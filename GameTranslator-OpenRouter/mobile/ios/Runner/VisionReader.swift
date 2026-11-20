// SPDX-License-Identifier: AGPL-3.0-only
import CoreGraphics
import Foundation
import Vision

/// Karelerde altyazı bölgesini okuyan ve çeviri hattına veren [FrameReader] (Android'deki Engine.readFrame,
/// rows ve buildPipeline'ın karşılığı). Yazı tanıma ML Kit yerine Apple'ın Vision çatısıyla, cihaz üstünde.
final class VisionReader: FrameReader {
  private unowned let engine: Engine
  /// Okuma kuyruğu; okuyucu takılırsa yenisiyle değiştirilir (busyLock altında okunur/yazılır).
  private var queue = DispatchQueue(label: "gt.reader")
  private let translating = DispatchQueue(label: "gt.translate")
  private let busyLock = NSLock()
  private var busy = false
  /// Takılma kurtarmasında artar; eski (takılmış) okumanın bitişi yeni durumu bozmasın diye.
  private var generation = 0
  private var stuck = StuckDetector()
  private var retryLimiter = RetryLimiter()
  /// Son altyazının görüldüğü an (yalnız okuma kuyruğunda); boş ekranda gereksiz yeniden okumayı önler.
  private var lastSubtitleAt: Int64?
  private let scheduler = ReadScheduler()
  private var pipeline: SubtitlePipeline?
  /// Elle seçilen bölge; otomatik alan kapalıyken ya da şerit henüz bulunamadıyken okunan alan.
  private var region = Region()
  /// Otomatik altyazı alanı (ayar açıkken): arama ve kilit durumu yalnız okuma kuyruğunda değişir.
  private var autoEnabled = false
  private var finder = AutoRegionFinder()
  /// Kilitli şerit, durum bilgisi için (busyLock altında).
  private var lockedBand: AutoRegionBand?
  private var language = "en"
  /// Vision'a verilecek tanıma dili; nil: Vision kendi seçsin (kaynak dil bu iOS sürümünde desteklenmiyor).
  private var ocrLanguage: String? = "en-US"
  private var hideButtonHints = true
  /// "Yalnız altyazıyı çevir": tabela, gösterge ve menü yazısı blok seçiminden önce atılır (yalnız okuma kuyruğunda).
  private var subtitleOnly = true
  private var onlyFilter = SubtitleOnlyFilter()
  /// Tanı kaydı: son yazılan süzgeç kararının özeti (yalnız okuma kuyruğunda).
  private var diagLastFilterKey = ""
  /// Oyun altyazısının satır yüksekliği (yalnız okuma kuyruğunda); bölge ya da hat değişince sıfırlanır.
  private var lineTracker = LineHeightTracker()
  private var lastLines: [String] = []
  private var lastBox: TextBox?
  private var lastLineBoxes: [TextBox] = []
  private var ocrTimes: [Int] = []
  /// Sağlık ekranı için (busyLock altında): son okumanın süresi, kullanılan tanıma dili, takılma kurtarma sayısı.
  private var lastOcrMs = 0
  private var healthLanguage = ""
  private var stuckRecoveries = 0
  private let sink: ServerSink
  /// Tanı kaydı: son yazılan okumanın özeti (yalnız okuma kuyruğunda); okuma sonucu değişmedikçe yeniden yazılmaz.
  private var diagLastReadKey = ""

  init(engine: Engine) {
    self.engine = engine
    sink = ServerSink(server: engine.server)
  }

  // MARK: - FrameReader

  private func currentQueue() -> (queue: DispatchQueue, token: Int) {
    busyLock.lock(); defer { busyLock.unlock() }
    return (queue, generation)
  }

  /// [body]'yi, [token] hâlâ güncel nesilse busyLock altında çalıştırır; eski (takılmış) okuma ortak duruma dokunamaz.
  /// [body] içinde kilit alan ya da günlük yazan çağrı yapılmamalı.
  private func whenCurrent<T>(_ token: Int, _ body: () -> T) -> T? {
    busyLock.lock(); defer { busyLock.unlock() }
    return token == generation ? body() : nil
  }

  func rebuild(settings s: Settings) {
    let target = currentQueue()
    target.queue.async {
      // Takılan kuyruğa atılmış eski kurulum, kurtarmadan sonra geç çalışırsa yenisini ezmesin.
      guard self.isCurrent(target.token) else { return }
      self.pipeline?.reset()
      self.region = s.region
      self.resetAuto(enabled: s.autoRegion, token: target.token)
      self.language = s.sourceLanguage
      self.ocrLanguage = self.resolveOcrLanguage(s.sourceLanguage)
      let languageName = self.ocrLanguage ?? Lang.t("otomatik", "automatic")
      _ = self.whenCurrent(target.token) { self.healthLanguage = languageName }
      self.hideButtonHints = s.hideButtonHints
      self.resetSubtitleOnly(s.subtitleOnly)
      self.lineTracker.reset()
      self.sink.matchGameTextSize = s.matchGameTextSize
      self.sink.coverPlacement = s.style.placement == "cover"
      // Cihaz üstü çeviri (Apple) arka planda hazırlanır: internet koptuğunda yedek olur (Android'deki ML Kit gibi).
      let local = AppleTranslator(source: s.sourceLanguage, target: s.targetLanguage) { level, text in self.engine.log(level, text) }
      self.translating.async { _ = local.prepare() }
      // Kota dolunca motor değiştirme: seçili motor → anahtarı dolu diğer motor → Google (kapalıysa ya da zincir yoksa eski yol).
      let chainOrder = s.engine == "openrouter" ? [] : FailoverOrder.keyed(
        engine: s.engine,
        deepLKey: !s.deepLKey.trimmingCharacters(in: .whitespaces).isEmpty,
        geminiKey: !s.geminiKey.trimmingCharacters(in: .whitespaces).isEmpty,
        targetIsTurkish: s.targetLanguage == "tr",
        failover: s.engineFailover)
      EngineCooldowns.shared.configure(order: chainOrder)
      let online: TextTranslator?
      if !chainOrder.isEmpty {
        var members: [ChainMember] = chainOrder.map { (id: String) -> ChainMember in
          if id == "deepl" { return DeepLTranslator(key: s.deepLKey, source: s.sourceLanguage, target: s.targetLanguage) }
          return GeminiTranslator(key: s.geminiKey) { level, text in self.engine.log(level, text) }
        }
        members.append(PlainChainMember(id: "google", translator: GoogleGtxTranslator(source: s.sourceLanguage, target: s.targetLanguage)))
        online = FailoverTranslator(members: members, cooldowns: EngineCooldowns.shared)
      } else {
      switch s.engine {
      case "openrouter":
        let google = GoogleGtxTranslator(source: s.sourceLanguage, target: s.targetLanguage)
        online = s.openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          || s.sourceLanguage != "en" || s.targetLanguage != "ar"
          ? google
          : FallbackTranslator(
              OpenRouterTranslator(key: s.openRouterKey, model: s.openRouterModel,
                                   source: s.sourceLanguage, target: s.targetLanguage),
              google)
      case "deepl":
        online = s.deepLKey.trimmingCharacters(in: .whitespaces).isEmpty
          ? GoogleGtxTranslator(source: s.sourceLanguage, target: s.targetLanguage)
          : FallbackTranslator(DeepLTranslator(key: s.deepLKey, source: s.sourceLanguage, target: s.targetLanguage),
                               GoogleGtxTranslator(source: s.sourceLanguage, target: s.targetLanguage))
      case "gemini":
        let google = GoogleGtxTranslator(source: s.sourceLanguage, target: s.targetLanguage)
        online = s.geminiKey.trimmingCharacters(in: .whitespaces).isEmpty || s.targetLanguage != "tr"
          ? google
          : FallbackTranslator(GeminiTranslator(key: s.geminiKey) { level, text in self.engine.log(level, text) }, google)
      case "mlkit":
        online = nil
      default:
        online = GoogleGtxTranslator(source: s.sourceLanguage, target: s.targetLanguage)
      }
      }
      let engineTranslator: TextTranslator = online.map { FallbackTranslator($0, local, fallbackId: "apple") } ?? local
      // Sözlüğün ek kuralları Türkçeye göredir; bilgisayarda da yalnız İngilizce→Türkçe için çalışır.
      let glossary = s.sourceLanguage == "en" && s.targetLanguage == "tr" ? s.parsedGlossary() : Glossary.EMPTY
      if !glossary.isEmpty { self.engine.log(2, "terim sözlüğü: \(glossary.count) terim") }
      let withGlossary: TextTranslator = glossary.isEmpty ? engineTranslator : GlossaryTranslator(glossary, engineTranslator)
      // Baştaki konuşmacı işareti ("- ", ">>") motorlara gönderilmez; hangi motor çevirirse çevirsin korunur.
      // Konuşmacı adı ("ENZO: ", "MINE GUARD: ") çevrilmez: satırdan satıra tutarsız çıkıyordu.
      let translator = PrefixTranslator(SpeakerNameTranslator(withGlossary))
      let engine = self.engine
      let built = SubtitlePipeline(translator: translator, sink: self.sink, translateQueue: self.translating)
      // Gemini zincirde beklemedeyse satırı DeepL/Google çevireceği için hat Gemini kipinden çıkar.
      if chainOrder.contains("gemini") {
        built.geminiBypassed = { EngineCooldowns.shared.isPaused("gemini", now: Date()) }
      }
      built.onShown = { [weak self] source, translation, origin, replaces in
        // Önceki satırın düzeltilmiş hâliyse geçmişte yeni satır açılmaz, sonuncusu güncellenir.
        Engine.history.record(source: source, text: translation, engine: origin, replacesLast: replaces)
        self?.noteShown(source)
      }
      built.onPair = { source, translation in
        engine.noteTranslation(ok: true)
        engine.lastSource = source
        engine.lastTranslation = translation
        engine.translatedCount += 1
        engine.log(2, "çeviri: \"\(source.replacingOccurrences(of: "\n", with: " "))\" → \"\(translation)\"")
        engine.notifyChanged()
      }
      built.onTranslateFailed = { source in
        engine.noteTranslation(ok: false, error: Lang.t("Çeviri alınamadı (motor yanıt vermedi)", "Translation failed (the engine did not respond)"))
        engine.log(1, "çevrilemedi: \"\(source.replacingOccurrences(of: "\n", with: " "))\"")
      }
      // Oyun paketi: satır paketteyse motora gidilmez. Bulanık arama yalnız son tam eşleşmenin paketinde (oynanan oyun).
      if s.packsEnabled && PackTranslation.applies(s.sourceLanguage, s.targetLanguage) {
        let library = Packs.shared.library
        library.setPinned(s.packChoice.isEmpty ? nil : s.packChoice)
        // Paketler çeviri kuyruğunda ilk istekten önce açılır (~1 sn; okuma beklemez).
        self.translating.async {
          let started = DispatchTime.now().uptimeNanoseconds
          let infos = library.infos
          engine.log(2, "oyun paketleri: \(infos.count) paket, \(infos.reduce(0) { $0 + $1.entries }) satır (\((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000) ms)")
        }
        built.packLookup = { text in PackTranslation.match(library, text) }
        built.onPackHit = { source, match in
          engine.packHits += 1
          engine.packGame = library.scopeTitle ?? match.packId ?? ""
          engine.log(2, "paket (\(match.packId ?? "?")): \"\(source.replacingOccurrences(of: "\n", with: " "))\"")
        }
      }
      built.onReadText = { text in
        if text != engine.lastRead {
          engine.lastRead = text
          engine.notifyChanged()
        }
      }
      self.scheduler.reset()
      self.lastLines = []
      self.lastBox = nil
      self.lastLineBoxes = []
      self.pipeline = built
      self.diagLastReadKey = ""
      Diag.emit("engine") {
        var fields: DiagFields = ["what": .string("reader-rebuild"), "ocrLanguage": DiagValue.optional(self.ocrLanguage)]
        fields["chain"] = DiagValue.strings(chainOrder)
        fields["engine"] = DiagValue.string(s.engine)
        fields["effectiveEngine"] = DiagValue.string(Engine.effectiveEngine(s))
        fields["glossaryTerms"] = DiagValue.int(glossary.count)
        fields["packs"] = DiagValue.bool(s.packsEnabled && PackTranslation.applies(s.sourceLanguage, s.targetLanguage))
        fields["hideButtonHints"] = DiagValue.bool(s.hideButtonHints)
        fields["subtitleOnly"] = DiagValue.bool(s.subtitleOnly)
        fields["matchGameTextSize"] = DiagValue.bool(s.matchGameTextSize)
        fields["placement"] = DiagValue.string(s.style.placement)
        fields["autoRegion"] = DiagValue.bool(s.autoRegion)
        fields["region"] = DiagValue.box(TextBox(left: s.region.left, top: s.region.top, right: s.region.right, bottom: s.region.bottom))
        return fields
      }
    }
  }

  /// "Oyunun yazı boyuna uy" değişti: bir sonraki satırdan geçerli (hat yeniden kurulmaz).
  func setMatchGameTextSize(_ on: Bool) { sink.matchGameTextSize = on }

  /// TV yerleşimi değişti: satır kutuları (rows) yalnız örtme (cover) yerleşiminde gider; bir sonraki satırdan geçerli.
  func setCoverPlacement(_ on: Bool) { sink.coverPlacement = on }

  func reset(clearScreen: Bool) {
    let target = currentQueue()
    target.queue.async {
      guard self.isCurrent(target.token) else { return }
      let settings = Store.shared.settings
      self.region = settings.region
      self.resetAuto(enabled: settings.autoRegion, token: target.token)
      self.hideButtonHints = settings.hideButtonHints
      self.resetSubtitleOnly(settings.subtitleOnly)
      self.lineTracker.reset()
      self.sink.matchGameTextSize = settings.matchGameTextSize
      self.sink.coverPlacement = settings.style.placement == "cover"
      self.scheduler.reset()
      _ = self.whenCurrent(target.token) { self.retryLimiter.reset() }
      self.pipeline?.reset()
      self.diagLastReadKey = ""
      Diag.emit("engine") {
        ["what": .string("reader-reset"), "clearScreen": .bool(clearScreen), "hideButtonHints": .bool(settings.hideButtonHints),
         "autoRegion": .bool(settings.autoRegion), "matchGameTextSize": .bool(settings.matchGameTextSize),
         "subtitleOnly": DiagValue.bool(settings.subtitleOnly)]
      }
      // Durdurmada: sıfırlamadan önce biten çeviri TV'ye gitmiş olabilir; sıfırlamadan sonra hat eski satır göndermez.
      if clearScreen { self.sink.clear() }
    }
  }

  func offer(_ frame: Frame) {
    let now = SubtitleStabilizer.monotonicMillis()
    busyLock.lock()
    stuck.frame(at: now)
    var recovered: StuckDetector.Reason?
    if let reason = stuck.check(at: now) {
      // Takılan okuma bırakılır: yeni kuyruk, boş durum; eski okuma dönerse yeni durumu bozmaz (generation).
      generation += 1
      busy = false
      queue = DispatchQueue(label: "gt.reader.\(generation)")
      recovered = reason
      stuckRecoveries += 1
    }
    // Önceki kare hâlâ okunuyorsa bu kare atlanır; okuma kareleri biriktirmez.
    if busy { busyLock.unlock(); reportRecovery(recovered); return }
    busy = true
    stuck.readStarted(at: now)
    let token = generation
    let target = queue
    busyLock.unlock()
    reportRecovery(recovered)
    if recovered != nil {
      // Takılan kuyruğa atılmış ayar yeniden kurulumu hiç çalışmayabilir: güncel ayarlarla yeni kuyrukta yeniden kurulur
      // (bölge, dil, hat). Ardından oku işi aynı seri kuyrukta sıraya girer.
      rebuild(settings: Store.shared.settings)
      target.async {
        _ = self.whenCurrent(token) { self.retryLimiter.reset() }
        self.lastSubtitleAt = nil
      }
    }
    target.async {
      defer {
        self.busyLock.lock()
        if token == self.generation {
          self.busy = false
          self.stuck.readFinished(at: SubtitleStabilizer.monotonicMillis())
        }
        self.busyLock.unlock()
      }
      self.read(frame, token: token)
    }
  }

  private func reportRecovery(_ reason: StuckDetector.Reason?) {
    guard let reason else { return }
    let text: String
    switch reason {
    case .busyTooLong: text = "okuyucu takıldı (okuma çok uzun sürdü); sıfırlandı"
    case .noResult: text = "okuyucu takıldı (karelere sonuç gelmiyor); sıfırlandı"
    }
    engine.log(1, text)
  }

  /// Kaynak dil kodunu Vision'ın desteklediği bir kimliğe çevirir. Desteklenmiyorsa tek bir uyarı yazılır ve
  /// İngilizceye (o da yoksa Vision'ın kendi seçimine) dönülür; her karede hata verilmez.
  private func resolveOcrLanguage(_ code: String) -> String? {
    let probe = VNRecognizeTextRequest()
    probe.recognitionLevel = .accurate
    let supported = (try? probe.supportedRecognitionLanguages()) ?? []
    if supported.isEmpty { return LanguageCodes.visionCandidates(code).first }
    if let chosen = LanguageCodes.visionLanguage(code, supported: supported) { return chosen }
    let fallback = LanguageCodes.visionLanguage("en", supported: supported)
    engine.log(1, "yazı tanıma bu iOS sürümünde \"\(code)\" dilini desteklemiyor; \(fallback ?? "otomatik dil") kullanılıyor")
    return fallback
  }

  // MARK: - Demo, ek alan ve sağlık

  /// Okunmuş gibi satırları çeviri hattına verir (demo); sıra, gerçek okumayla aynı kuyruktadır.
  func feed(lines: [String], box: TextBox?) {
    let target = currentQueue()
    target.queue.async {
      guard self.isCurrent(target.token), let pipeline = self.pipeline else { return }
      pipeline.onRead(lines, box)
    }
  }

  var health: ReaderHealth {
    busyLock.lock(); defer { busyLock.unlock() }
    return ReaderHealth(lastReadMs: lastOcrMs, language: healthLanguage, stuckRecoveries: stuckRecoveries)
  }

  // MARK: - Otomatik altyazı alanı

  /// Kilitli şerit (yoksa nil); durum bilgisi için her iş parçacığından okunur.
  var autoRegion: AutoRegionBand? {
    busyLock.lock(); defer { busyLock.unlock() }
    return lockedBand
  }

  /// Okuma kuyruğunda: ayar değişti ya da akış sıfırlandı; öğrenilenler unutulur.
  private func resetAuto(enabled: Bool, token: Int) {
    autoEnabled = enabled
    finder.reset()
    let had: Bool = whenCurrent(token) { () -> Bool in
      let was = lockedBand != nil
      lockedBand = nil
      return was
    } ?? false
    if had { engine.notifyChanged() }
  }

  /// Okuma kuyruğunda: "Yalnız altyazıyı çevir" ayarı uygulanır; öğrenilen bant ve sabit yazılar unutulur, TV kutusu
  /// kararlılığı da baştan başlar.
  private func resetSubtitleOnly(_ enabled: Bool) {
    subtitleOnly = enabled
    onlyFilter.reset()
    diagLastFilterKey = ""
    sink.resetCover()
  }

  /// Hat bir satırı TV'ye gönderdi (hattın kilidi altında, herhangi bir kuyrukta): süzgece okuma kuyruğunda bildirilir.
  private func noteShown(_ source: String) {
    let target = currentQueue()
    target.queue.async {
      guard self.isCurrent(target.token), self.subtitleOnly else { return }
      let note = self.onlyFilter.noteShown(source, at: SubtitleStabilizer.monotonicMillis())
      let band: SubtitleBand? = self.onlyFilter.band
      if note.bandChanged {
        self.sink.setCoverBand(band)
        if note.learning == SubtitleOnlyShown.Learning.learned || note.learning == SubtitleOnlyShown.Learning.relearned {
          let verb = note.learning == SubtitleOnlyShown.Learning.learned ? "öğrenildi" : "yeniden öğrenildi"
          self.engine.log(2, "altyazı bandı \(verb): üst %\(Int(((band?.top ?? 0) * 100).rounded())), alt %\(Int(((band?.bottom ?? 0) * 100).rounded()))")
        }
      }
      Diag.emit("filter") {
        var f: DiagFields = ["what": DiagValue.string("shown-sample"), "source": DiagValue.string(source)]
        f["learning"] = DiagValue.string(SubtitleOnlyDiag.learning(note.learning))
        f["sample"] = DiagValue.box(note.sample)
        f["lineHeight"] = DiagValue.optional(note.lineHeight)
        f["outsideRun"] = DiagValue.int(note.outsideRun)
        f["bandChanged"] = DiagValue.bool(note.bandChanged)
        f["band"] = SubtitleOnlyDiag.band(band)
        return f
      }
    }
  }

  /// Okuma kuyruğunda: bulucunun kararı okunan alana, duruma ve günlüğe yansır.
  private func applyAuto(_ event: AutoRegionEvent, token: Int) {
    let band: AutoRegionBand?
    let text: String
    switch event {
    case .none:
      return
    case .locked(let found):
      band = found
      text = "otomatik altyazı alanı bulundu: \(Self.describe(found))"
    case .adjusted(let moved):
      band = moved
      text = "otomatik altyazı alanı güncellendi: \(Self.describe(moved))"
    case .unlocked:
      band = nil
      text = "otomatik altyazı alanı bırakıldı (uzun süredir altyazı okunmadı); yeniden aranıyor, o sürece elle seçilen bölge okunur"
    }
    // Alan değişti: bölge özeti önbelleği geçersiz olur.
    let applied: Bool? = whenCurrent(token) { () -> Bool in
      lockedBand = band
      scheduler.reset()
      return true
    }
    guard applied != nil else { return }
    engine.log(2, text)
    engine.notifyChanged()
  }

  private static func describe(_ band: AutoRegionBand) -> String {
    func percent(_ value: Double) -> Int { Int((value * 100).rounded()) }
    return "üst %\(percent(band.top)), alt %\(percent(band.bottom)), sol %\(percent(band.left)), sağ %\(percent(band.right))"
  }

  /// Okuma kuyruğunda, normal okumadan sonra: tam kare aralıklı (aranırken ~2 sn, kilitliyken ~15 sn) küçültülüp hızlı
  /// düzeyde okunur; satırlar bulucuya verilir. Okuyucu meşgulken kare zaten gelmez (offer atlar), bu yüzden ek bekleme yok.
  private func autoScan(_ frame: Frame, token: Int) {
    guard isCurrent(token) else { return }
    let now = SubtitleStabilizer.monotonicMillis()
    guard finder.scanDue(at: now) else { return }
    finder.markScan(at: now)
    guard let image = frame.cgImage() else { return }
    let size = AutoRegionFinder.scanSize(width: frame.width, height: frame.height)
    let scan: CGImage = (size.width == frame.width && size.height == frame.height) ? image
      : (Self.resized(image, width: size.width, height: size.height) ?? image)
    guard let found = recognizeFull(scan) else { return }
    guard isCurrent(token) else { return }
    let w = Double(scan.width), h = Double(scan.height)
    let lines = found.map { o in
      AutoRegionLine(text: o.text, left: Double(o.left) / w, top: Double(o.top) / h, right: Double(o.right) / w,
                     bottom: Double(o.bottom) / h, confidence: o.confidence)
    }
    applyAuto(finder.ingest(lines, at: SubtitleStabilizer.monotonicMillis()), token: token)
  }

  /// Tam kareyi hızlı düzeyde okur (alan bulma için doğruluk yetmez, hız gerekir). Parçalar görüntü pikselinde, sol üstten.
  private func recognizeFull(_ image: CGImage) -> [TextObservation]? {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .fast
    request.usesLanguageCorrection = false
    // Hızlı düzey her dili desteklemez; desteklenmiyorsa Vision'ın kendi seçimi kullanılır.
    if let ocrLanguage, ((try? request.supportedRecognitionLanguages()) ?? []).contains(ocrLanguage) {
      request.recognitionLanguages = [ocrLanguage]
    }
    do {
      try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
    } catch {
      engine.log(1, "otomatik alan taraması başarısız: \(error.localizedDescription)")
      return nil
    }
    return (request.results ?? []).compactMap { (observation) -> TextObservation? in
      guard let candidate = observation.topCandidates(1).first else { return nil }
      let text = candidate.string.trimmingCharacters(in: .whitespaces)
      if text.isEmpty { return nil }
      let b = observation.boundingBox
      let p = ReadingSelector.pixels(minX: Double(b.minX), minY: Double(b.minY), maxX: Double(b.maxX), maxY: Double(b.maxY),
                                     imageWidth: image.width, imageHeight: image.height, offsetX: 0, offsetY: 0, scale: 1)
      return TextObservation(text: text, confidence: Double(candidate.confidence),
                             left: p.left, top: p.top, right: p.right, bottom: p.bottom)
    }
  }

  /// Görüntüyü verilen boyuta küçültür.
  static func resized(_ image: CGImage, width: Int, height: Int) -> CGImage? {
    guard width > 0, height > 0 else { return nil }
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
    context.interpolationQuality = .medium
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
  }

  /// Ek alanı bir kez okur: yazı tanıma okuma kuyruğunda sıraya girer (asıl okuma ve kararlılık durumuna dokunmaz),
  /// çeviri çeviri kuyruğunda yapılır, sonuç ~8 sn'lik altyazı olarak TV'ye gider. Bloklar (en çok ~30 sn).
  func readExtra(_ frame: Frame, region r: ExtraRegion) -> ExtraReadResult {
    var failed = ExtraReadResult()
    let target = currentQueue()
    let semaphore = DispatchSemaphore(value: 0)
    let slot = ExtraSlot()
    let queued = DispatchTime.now().uptimeNanoseconds
    target.queue.async {
      defer { semaphore.signal() }
      guard self.isCurrent(target.token) else {
        slot.stale = true
        return
      }
      slot.waitedMs = Int((DispatchTime.now().uptimeNanoseconds - queued) / 1_000_000)
      slot.pipeline = self.pipeline
      slot.resets = self.pipeline?.resetCount ?? 0
      slot.lines = self.extraLines(frame, r, token: target.token)
    }
    /// Tanı kaydı: ek alan denemesinin kesildiği adım.
    func fail(_ step: String, _ detail: DiagFields = DiagFields()) {
      Diag.emit("extra") {
        var fields: DiagFields = ["what": .string("fail"), "step": .string(step), "region": .string(r.name)]
        for item in detail.items { fields[item.key] = item.value }
        fields["error"] = DiagValue.string(failed.error)
        return fields
      }
    }
    if semaphore.wait(timeout: .now() + 12) == .timedOut {
      failed.error = Lang.t("Okuma zaman aşımına uğradı; yeniden deneyin.", "Reading timed out; try again.")
      fail("ocr-timeout", ["seconds": .int(12)])
      return failed
    }
    guard let pipeline = slot.pipeline, let lines = slot.lines else {
      failed.error = Lang.t("Alan okunamadı; yeniden deneyin.", "The area could not be read; try again.")
      let step = slot.stale ? "reader-replaced" : slot.pipeline == nil ? "no-pipeline" : "ocr-failed"
      fail(step, ["waitedMs": .int(slot.waitedMs)])
      return failed
    }
    let source = ExtraRegion.joinLines(lines.map { OcrNoise.clean($0) })
    if source.isEmpty {
      failed.error = Lang.t("Bu alanda okunacak yazı bulunamadı.", "No text to read was found in this area.")
      fail("ocr-empty", ["lines": DiagValue.strings(lines)])
      return failed
    }
    failed.source = source
    let translateStarted = DispatchTime.now().uptimeNanoseconds
    let translated = pipeline.translateOnce(source)
    let translateMs = Int((DispatchTime.now().uptimeNanoseconds - translateStarted) / 1_000_000)
    guard let text = translated.text, !text.isEmpty else {
      failed.error = Lang.t("Çeviri alınamadı; bağlantıyı kontrol edin.", "Translation failed; check your connection.")
      fail("translate-empty", ["source": .string(source), "origin": .string(translated.origin), "ms": .int(translateMs)])
      return failed
    }
    // Ek alan çevirisi 8 sn kalır; kutu verilmez, TV kendi yerleşimini kullanır. Hat bu arada sıfırlandıysa
    // (durdurma, ayar değişimi) gönderilmez.
    guard let mark = pipeline.showAside(text, durationMs: Self.extraShowMs, unlessResetSince: slot.resets) else {
      failed.error = Lang.t("Çeviri bu arada durduruldu ya da yeniden kuruldu; yeniden deneyin.",
                            "Translation was stopped or restarted meanwhile; try again.")
      fail("pipeline-reset", ["source": .string(source), "text": .string(text)])
      return failed
    }
    Diag.emit("extra") {
      ["what": .string("shown"), "region": .string(r.name), "source": .string(source), "text": .string(text),
       "origin": .string(translated.origin), "translateMs": .int(translateMs), "tvClients": .int(engine.server.connectedClients),
       "showMs": .int(Self.extraShowMs)]
    }
    Engine.history.record(source: source, text: text, engine: translated.origin, aside: true)
    engine.log(2, "ek alan (\(r.name)): \"\(source)\" → \"\(text)\"")
    // Gösterim bitince TV'de oyunun hâlâ ekrandaki satırının çevirisi geri gelir (arada yeni satır, temizleme ya da
    // durdurma olduysa hat karar verir, bir şey gönderilmez).
    let resume = currentQueue()
    resume.queue.asyncAfter(deadline: .now() + .milliseconds(Self.extraShowMs)) {
      guard self.isCurrent(resume.token), self.pipeline === pipeline else {
        Diag.emit("extra") { ["what": .string("resume"), "resumed": .bool(false), "reason": .string("reader-rebuilt")] }
        return
      }
      pipeline.resumeAfterAside(mark)
    }
    return ExtraReadResult(ok: true, source: source, text: text, error: "")
  }

  /// Ek alan çevirisinin TV'de kalma süresi.
  private static let extraShowMs = 8000

  /// Okuma kuyruğunda: ek alanın satırları (yukarıdan aşağı). Okuma hatasında nil, yazı yoksa boş dizi.
  private func extraLines(_ frame: Frame, _ r: ExtraRegion, token: Int) -> [String]? {
    guard let image = frame.cgImage() else { return nil }
    let fullWidth = frame.width, fullHeight = frame.height
    let cropX = min(max(Int(r.left * Double(fullWidth)), 0), fullWidth - 2)
    let cropY = min(max(Int(r.top * Double(fullHeight)), 0), fullHeight - 2)
    let w = min(max(Int((r.right - r.left) * Double(fullWidth)), 1), fullWidth - cropX)
    let h = min(max(Int((r.bottom - r.top) * Double(fullHeight)), 1), fullHeight - cropY)
    guard let crop = image.cropping(to: CGRect(x: cropX, y: cropY, width: w, height: h)) else {
      Diag.emit("extra") { ["what": .string("fail-detail"), "step": .string("crop"), "crop": .array([.int(cropX), .int(cropY), .int(w), .int(h)])] }
      return nil
    }
    let started = DispatchTime.now().uptimeNanoseconds
    guard let found = recognize(crop, offsetX: 0, offsetY: 0, scale: 1, timed: false, token: token) else {
      Diag.emit("extra") { ["what": .string("fail-detail"), "step": .string("vision-error")] }
      return nil
    }
    guard isCurrent(token) else { return nil }
    let selected = ReadingSelector.select(found, width: w, height: h)
    let pieces: [Piece] = selected.map { Piece(text: $0.text, left: $0.left, top: $0.top, right: $0.right, bottom: $0.bottom) }
    let lines = Self.rows(pieces, cropX: cropX, cropY: cropY, fullWidth: fullWidth, fullHeight: fullHeight).0
    Diag.emit("extra") {
      var f: DiagFields = ["what": .string("ocr"), "region": .string(r.name),
                           "regionBox": DiagValue.box(TextBox(left: r.left, top: r.top, right: r.right, bottom: r.bottom))]
      f["crop"] = DiagValue.array([.int(cropX), .int(cropY), .int(w), .int(h)])
      f["frame"] = DiagValue.array([.int(fullWidth), .int(fullHeight)])
      f["ocrMs"] = DiagValue.int(Int((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000))
      f["ocrLanguage"] = DiagValue.optional(ocrLanguage)
      f["raw"] = DiagRead.observations(found, cropX: cropX, cropY: cropY, frameWidth: fullWidth, frameHeight: fullHeight)
      f["selection"] = DiagRead.selection(found, width: w, height: h)
      f["lines"] = DiagValue.strings(lines)
      return f
    }
    return lines
  }

  // MARK: - Okuma

  /// Takılma kurtarmasından sonra eski bir okumanın sonucu atılır (kilit altında kontrol edilir).
  private func isCurrent(_ token: Int) -> Bool {
    busyLock.lock(); defer { busyLock.unlock() }
    return token == generation
  }

  private func read(_ frame: Frame, token: Int) {
    guard isCurrent(token) else { return }
    if autoEnabled { applyAuto(finder.checkIdle(at: SubtitleStabilizer.monotonicMillis()), token: token) }
    readRegion(frame, token: token)
    if autoEnabled { autoScan(frame, token: token) }
  }

  /// Okunan alan: otomatik şerit kilitliyse o, değilse elle seçilen bölge (yalnız okuma kuyruğunda).
  private var activeRegion: Region {
    if autoEnabled, let band = finder.band { return Region(top: band.top, bottom: band.bottom, left: band.left, right: band.right) }
    return region
  }

  private func readRegion(_ frame: Frame, token: Int) {
    guard isCurrent(token) else { return }
    guard let pipeline, let image = frame.cgImage() else { return }
    let r = activeRegion
    let fullWidth = frame.width, fullHeight = frame.height
    let cropX = min(max(Int(r.left * Double(fullWidth)), 0), fullWidth - 2)
    let cropY = min(max(Int(r.top * Double(fullHeight)), 0), fullHeight - 2)
    let w = min(max(Int((r.right - r.left) * Double(fullWidth)), 1), fullWidth - cropX)
    let h = min(max(Int((r.bottom - r.top) * Double(fullHeight)), 1), fullHeight - cropY)
    guard let crop = image.cropping(to: CGRect(x: cropX, y: cropY, width: w, height: h)) else { return }

    if let signature = Self.signature(crop) {
      guard let reuse = whenCurrent(token, { scheduler.canReuse(signature) }) else { return }
      if reuse {
        if isCurrent(token) {
          // Kare değişmedi: son okumada görülen yazılar hâlâ ekranda (sabit yazı süresi işlemeye devam eder).
          if subtitleOnly { onlyFilter.touch(at: SubtitleStabilizer.monotonicMillis()) }
          pipeline.onRead(lastLines, lastBox, lineBoxes: lastLineBoxes)
        }
        return
      }
    }

    // İlk okuma tüm bölgede; sonuç yoksa ya da güvensizse sınırlı sıklıkta, ortalanmış bandı büyüterek bir kez daha.
    let diagOn = Diag.on
    let ocrStarted = diagOn ? DispatchTime.now().uptimeNanoseconds : 0
    guard let raw = recognize(crop, offsetX: 0, offsetY: 0, scale: 1, timed: true, token: token) else { return }
    let ocrMs = diagOn ? Int((DispatchTime.now().uptimeNanoseconds - ocrStarted) / 1_000_000) : 0
    guard isCurrent(token) else { return }
    // Tuş ipucu satırları ("Hold L2 to aim") altyazı bloğu seçilmeden önce atılır: ne çevrilir ne de kutuya girer
    // (yoksa ipucu bloğu altyazının yerine seçilebiliyor, çeviri kutusu ipucunu örtüyordu).
    let english = language == "en"
    let hinted: [TextObservation]
    var hintDrops: [(text: String, reason: String)] = []
    if hideButtonHints && diagOn {
      // Aynı hesap; tanı kaydı için atılan satırlar ve nedenleri de alınır.
      let explained = ButtonHints.dropHintRowsExplained(raw, english: english)
      hinted = explained.kept
      hintDrops = explained.dropped
    } else {
      hinted = hideButtonHints ? ButtonHints.dropHintRows(raw, english: english) : raw
    }
    // "Yalnız altyazıyı çevir": tabela, gösterge, görev metni ve menü yazısı blok seçiminden önce atılır; atılan parça ne
    // çevrilir ne de kutuya/satır yüksekliğine girer. Kapalıyken hiçbir şey değişmez.
    var first: [TextObservation] = hinted
    let onlyFrame = SubtitleOnlyFrame(cropX: cropX, cropY: cropY, width: fullWidth, height: fullHeight)
    if subtitleOnly {
      let outcome = onlyFilter.apply(hinted, frame: onlyFrame, at: SubtitleStabilizer.monotonicMillis(), track: true)
      first = outcome.kept
      if outcome.bandDropped {
        // Emniyet supabı: bant yanlış ya da eskimişti; TV kutusu da bant bilgisini bırakır.
        sink.setCoverBand(nil)
        engine.log(1, "altyazı bandı bırakıldı (bir süredir altyazı gibi yazılar atılıyordu); yeniden öğreniliyor")
        Diag.emit("filter") {
          ["what": DiagValue.string("band-dropped"), "afterMs": DiagValue.int(Int(SubtitleOnlyFilter.SAFETY_MS))]
        }
      }
      if diagOn { diagFilter(outcome, frame: onlyFrame) }
    }
    var selected = ReadingSelector.select(first, width: w, height: h)
    let clock = SubtitleStabilizer.monotonicMillis()
    let band = ReadingSelector.retryBand(width: w, height: h)
    var reread: DiagValue = .null
    // Boş ekranda yeniden okuma yok; büyütme genişliği sınırlı (çok geniş bölgede küçülür ya da atlanır).
    if ReadingSelector.shouldRetry(rawCount: first.count, selected: selected, lastSubtitleAt: lastSubtitleAt, now: clock),
       let scale = ReadingSelector.retryScale(bandWidth: band.width),
       whenCurrent(token, { retryLimiter.allow(at: clock) }) == true {
      if let part = image.cropping(to: CGRect(x: cropX + band.x, y: cropY + band.y, width: band.width, height: band.height)),
         let big = Self.upscaled(part, factor: scale),
         let rereadRaw = recognize(big, offsetX: band.x, offsetY: band.y, scale: scale, timed: false, token: token) {
        guard isCurrent(token) else { return }
        let unhinted = hideButtonHints ? ButtonHints.dropHintRows(rereadRaw, english: english) : rereadRaw
        // Yeniden okumada da aynı süzgeç; sabit yazı izleri ikinci kez sayılmaz.
        let again: [TextObservation] = subtitleOnly
          ? onlyFilter.apply(unhinted, frame: onlyFrame, at: SubtitleStabilizer.monotonicMillis(), track: false).kept
          : unhinted
        let retried = ReadingSelector.select(again, width: w, height: h)
        let better = ReadingSelector.isBetter(retried, than: selected)
        if better { selected = retried }
        if diagOn {
          reread = DiagValue.object(["done": .bool(true), "scale": .double(scale), "better": .bool(better),
                            "raw": DiagRead.observations(rereadRaw, cropX: cropX, cropY: cropY, frameWidth: fullWidth, frameHeight: fullHeight)])
        }
      } else if diagOn {
        reread = DiagValue.object(["done": .bool(false), "scale": .double(scale), "error": .string("büyütülmüş okuma yapılamadı")])
      }
    }
    let pieces: [Piece] = selected.map { Piece(text: $0.text, left: $0.left, top: $0.top, right: $0.right, bottom: $0.bottom) }
    var (lines, box, lineBoxes) = Self.rowsWithBoxes(pieces, cropX: cropX, cropY: cropY, fullWidth: fullWidth,
                                                     fullHeight: fullHeight)
    // Tanı kaydı için düğme yazısı atılmadan önceki satırlar (kapalıyken boş; kopya alınmaz).
    let rowLines: [String] = diagOn ? lines : []
    if hideButtonHints {
      // Oyun düğmesi yazıları ("RESUME BA", "SKIP") çeviriye karışmasın. Satır kutuları satırlarla birlikte süzülür.
      let stripped = lines.map(ButtonHints.strip)
      let rowCount = lineBoxes.count
      lineBoxes = stripped.indices.filter { !stripped[$0].isEmpty }.map { lineBoxes[$0] }
      lines = stripped.filter { !$0.isEmpty }
      if lines.isEmpty {
        box = nil
      } else if sink.coverPlacement && lineBoxes.count < rowCount && !lineBoxes.isEmpty {
        // Örtme yerleşimi: bütünüyle atılan düğme satırı ("Hold △ to skip") kutuda kalmasın (kutu altyazıdan taşıyordu).
        box = TurnRows.union(lineBoxes)
      }
    }
    if subtitleOnly { onlyFilter.rememberRead(lines: lines, selected: selected, frame: onlyFrame, at: clock) }
    var lineTrace: LineHeight.Trace?
    var tracked: Double?
    if let box, !pieces.isEmpty {
      // Satır yüksekliği: iki satırı ya da simgeyi kapsayan parçaya karşı sağlam tahmin, son okumaların ortancası;
      // güvenilir ölçüm yoksa gönderilmez (TV ayardaki boyu kullanır). Tanı kaydı açıkken aynı hesap ara değerleriyle
      // yapılır (explain(...).result == estimate(...)); kapalıyken iz kurulmaz.
      let estimate: Double?
      if diagOn {
        let trace: LineHeight.Trace = LineHeight.explain(selected, frameHeight: fullHeight)
        lineTrace = trace
        estimate = trace.result
      } else {
        estimate = LineHeight.estimate(selected, frameHeight: fullHeight)
      }
      let line = lineTracker.add(estimate)
      sink.remember(box, line: line, characters: lines.reduce(0) { $0 + $1.count })
      if diagOn { tracked = line }
    }
    // Kurtarmadan önce başlamış eski okumanın bayat satırları hatta ve ortak duruma gitmez.
    guard isCurrent(token) else { return }
    if !lines.isEmpty {
      lastSubtitleAt = clock
      if autoEnabled { finder.noteReading(at: clock) }
    }
    lastLines = lines
    lastBox = box
    lastLineBoxes = lineBoxes
    if diagOn {
      // Yalnız okuma sonucu (satırlar, kutu, izlenen satır yüksekliği) değiştiğinde; her karede yazılmaz.
      let key = lines.joined(separator: "\n") + "|" + DiagValue.box(box).json + "|" + DiagValue.optional(tracked).json
      if key != diagLastReadKey {
        diagLastReadKey = key
        let regionName = autoEnabled && finder.band != nil ? "auto" : "main"
        let match = sink.matchGameTextSize
        let window = lineTracker.window
        Diag.emit("read") {
          var f: DiagFields = ["region": .string(regionName),
                               "regionBox": DiagValue.box(TextBox(left: r.left, top: r.top, right: r.right, bottom: r.bottom))]
          f["crop"] = DiagValue.array([.int(cropX), .int(cropY), .int(w), .int(h)])
          f["frame"] = DiagValue.array([.int(fullWidth), .int(fullHeight)])
          f["ocrMs"] = DiagValue.int(ocrMs)
          f["raw"] = DiagRead.observations(raw, cropX: cropX, cropY: cropY, frameWidth: fullWidth, frameHeight: fullHeight)
          f["hideButtonHints"] = DiagValue.bool(hideButtonHints)
          f["hintRowsDropped"] = DiagValue.array(hintDrops.map { drop -> DiagValue in
            .object(["text": .string(drop.text), "reason": .string(drop.reason)])
          })
          f["selection"] = DiagRead.selection(first, width: w, height: h)
          f["reread"] = reread
          f["selected"] = DiagRead.observations(selected, cropX: cropX, cropY: cropY, frameWidth: fullWidth, frameHeight: fullHeight)
          f["rows"] = DiagValue.strings(rowLines)
          f["lines"] = DiagValue.strings(lines)
          f["lineBoxes"] = DiagRead.boxes(lineBoxes)
          f["box"] = DiagValue.box(box)
          var height: DiagFields = ["trackerWindow": DiagValue.doubles(window), "trackerMedian": DiagValue.optional(tracked)]
          height["calc"] = lineTrace.map { DiagRead.lineHeight($0) } ?? DiagValue.null
          height["matchGameTextSize"] = DiagValue.bool(match)
          height["toSend"] = DiagValue.optional(LineHeight.toSend(tracked, matchGameTextSize: match))
          f["lineHeight"] = DiagValue.object(height)
          return f
        }
      }
    }
    pipeline.onRead(lines, box, lineBoxes: lineBoxes)
  }

  /// Okuma kuyruğunda, yalnız tanı kaydı açıkken: süzgecin attığı her parça nedeniyle (karar değişmedikçe yeniden yazılmaz).
  private func diagFilter(_ outcome: SubtitleOnlyOutcome, frame: SubtitleOnlyFrame) {
    var key = outcome.pageFound ? "page|" : ""
    for drop in outcome.drops { key += drop.observation.text + "\u{1F}" + drop.reason.code + "\u{1E}" }
    guard key != diagLastFilterKey else { return }
    diagLastFilterKey = key
    let band = onlyFilter.band
    Diag.emit("filter") {
      var f: DiagFields = ["what": DiagValue.string("subtitle-only"), "pageFound": DiagValue.bool(outcome.pageFound)]
      f["dropped"] = SubtitleOnlyDiag.drops(outcome.drops, frame: frame)
      f["kept"] = DiagValue.int(outcome.kept.count)
      f["band"] = SubtitleOnlyDiag.band(band)
      return f
    }
  }

  /// Görüntüyü okur; her çağrıda taze bir istek kurulur. Parçalar bölge pikselinde (sol üstten) döner;
  /// [offsetX]/[offsetY]/[scale] büyütülmüş bir alt bandın bölgedeki yerini belirtir. Okuma hatasında nil.
  private func recognize(_ image: CGImage, offsetX: Int, offsetY: Int, scale: Double, timed: Bool, token: Int) -> [TextObservation]? {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    if let ocrLanguage { request.recognitionLanguages = [ocrLanguage] }
    do {
      let started = DispatchTime.now().uptimeNanoseconds
      try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
      if timed {
        // ocrTimes yalnız güncel nesilde ve kilit altında değişir; günlük kilit dışında yazılır.
        let elapsed = Int((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
        let report: String? = whenCurrent(token) { () -> String? in
          lastOcrMs = elapsed
          ocrTimes.append(elapsed)
          guard ocrTimes.count >= 100 else { return nil }
          let sorted = ocrTimes.sorted()
          ocrTimes.removeAll()
          return "ölçüm: yazı tanıma \(image.width)x\(image.height) ortanca \(sorted[sorted.count / 2]) ms, en çok \(sorted.last!) ms"
        } ?? nil
        if let report { engine.log(2, report) }
      }
    } catch {
      engine.log(1, "yazı tanıma başarısız: \(error.localizedDescription)")
      return nil
    }
    return (request.results ?? []).compactMap { (observation) -> TextObservation? in
      guard let candidate = observation.topCandidates(1).first else { return nil }
      let text = candidate.string.trimmingCharacters(in: .whitespaces)
      if text.isEmpty { return nil }
      // Vision kutusu 0–1 ve sol alttan; piksel ve sol üstten koordinata çevrilir.
      let b = observation.boundingBox
      let p = ReadingSelector.pixels(minX: Double(b.minX), minY: Double(b.minY), maxX: Double(b.maxX), maxY: Double(b.maxY),
                                     imageWidth: image.width, imageHeight: image.height,
                                     offsetX: offsetX, offsetY: offsetY, scale: scale)
      // Satırın eğimi: dörtgenin üst kenarı (piksel oranıyla; Vision koordinatı sol alttan, y yukarı).
      let dx = Double(observation.topRight.x - observation.topLeft.x) * Double(image.width)
      let dy = Double(observation.topRight.y - observation.topLeft.y) * Double(image.height)
      let angle: Double? = dx > 0 ? atan2(dy, dx) * 180 / Double.pi : nil
      return TextObservation(text: text, confidence: Double(candidate.confidence),
                             left: p.left, top: p.top, right: p.right, bottom: p.bottom, angle: angle)
    }
  }

  /// Görüntüyü [factor] kat büyütür (küçük yazı için yeniden okuma).
  static func upscaled(_ image: CGImage, factor: Double) -> CGImage? {
    let width = Int((Double(image.width) * factor).rounded()), height = Int((Double(image.height) * factor).rounded())
    guard width > 0, height > 0 else { return nil }
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
  }

  struct Piece {
    let text: String
    let left: Int, top: Int, right: Int, bottom: Int
  }

  /// Tanınan satırları yukarıdan aşağı sıralar, aynı hizadakileri birleştirir; yazının tüm ekrandaki yerini verir
  /// (Android'deki Engine.rows ile aynı kural).
  static func rows(_ input: [Piece], cropX: Int, cropY: Int, fullWidth: Int, fullHeight: Int) -> ([String], TextBox?) {
    let result = rowsWithBoxes(input, cropX: cropX, cropY: cropY, fullWidth: fullWidth, fullHeight: fullHeight)
    return (result.lines, result.box)
  }

  /// [rows] ve her satırın (aynı hizadaki parçaların) tüm ekrandaki kutusu; satırlarla aynı sıra ve sayıda.
  static func rowsWithBoxes(_ input: [Piece], cropX: Int, cropY: Int, fullWidth: Int,
                            fullHeight: Int) -> (lines: [String], box: TextBox?, lineBoxes: [TextBox]) {
    let pieces = input.sorted { $0.top < $1.top }
    guard !pieces.isEmpty else { return ([], nil, []) }
    func screen(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) -> TextBox {
      TextBox(left: Double(cropX + left) / Double(fullWidth), top: Double(cropY + top) / Double(fullHeight),
              right: Double(cropX + right) / Double(fullWidth), bottom: Double(cropY + bottom) / Double(fullHeight))
    }
    var grouped: [[Piece]] = []
    for piece in pieces {
      if let reference = grouped.last?.first,
         abs((piece.top + piece.bottom) / 2 - (reference.top + reference.bottom) / 2)
           < max(reference.bottom - reference.top, piece.bottom - piece.top) / 2 {
        grouped[grouped.count - 1].append(piece)
      } else {
        grouped.append([piece])
      }
    }
    let lines = grouped.map { row in row.sorted { $0.left < $1.left }.map(\.text).joined(separator: " ") }
    let left = pieces.map(\.left).min()!, top = pieces.map(\.top).min()!
    let right = pieces.map(\.right).max()!, bottom = pieces.map(\.bottom).max()!
    let box = screen(left, top, right, bottom)
    let lineBoxes = grouped.map { row in
      screen(row.map(\.left).min()!, row.map(\.top).min()!, row.map(\.right).max()!, row.map(\.bottom).max()!)
    }
    return (lines, box, lineBoxes)
  }

  /// Bölgenin 32×8 küçültülmüş parlaklık özeti; iki karenin aynı olup olmadığını anlamak için.
  static func signature(_ image: CGImage) -> [UInt8]? {
    let width = 32, height = 8
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
      guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
      context.interpolationQuality = .medium
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drawn else { return nil }
    return (0..<(width * height)).map { i in
      let r = Int(pixels[i * 4]), g = Int(pixels[i * 4 + 1]), b = Int(pixels[i * 4 + 2])
      return UInt8((r * 3 + g * 6 + b) / 10)
    }
  }
}

/// Ek alan okumasının okuma kuyruğundan çağırana taşıdığı sonuç.
private final class ExtraSlot: @unchecked Sendable {
  var pipeline: SubtitlePipeline?
  var resets = 0
  var lines: [String]?
  /// Okuma sırası gelince okuyucu takılma kurtarmasıyla değişmişti (tanı kaydı).
  var stale = false
  /// Okuma kuyruğunda bekleme süresi, ms (tanı kaydı).
  var waitedMs = 0
}

/// Çevirinin gittiği yer: TV sunucusu. Okunan yazının yeri ve satır yüksekliği de gider: TV "cover" yerleşiminde
/// çeviriyi oyunun altyazısının alanına, onun boyunda sığdırır ve alanı opak bantla örter.
private final class ServerSink: SubtitleSink {
  private let server: SubtitleServer
  private let lock = NSLock()
  /// Son okumaların kutusu → (satır yüksekliği, okunan İngilizce metnin karakter sayısı); hat aynı kutuyu çeviriyle
  /// birlikte geri verir.
  private var lines: [(box: TextBox, line: Double?, characters: Int)] = []
  private var matchesGameSize = true
  private var cover = true
  /// Örtme yerleşiminde kutu ve satır yüksekliği kararlılığı (kilit altında).
  private var keeper = CoverKeeper()

  init(server: SubtitleServer) { self.server = server }

  /// "Yalnız altyazıyı çevir"in öğrendiği altyazı bandı: yüksek kutu bununla kırpılır, satır yüksekliği sınırı tipik
  /// değerden alınır. Yoksa nil.
  func setCoverBand(_ band: SubtitleBand?) {
    lock.lock()
    keeper.bandTop = band?.top
    keeper.bandBottom = band?.bottom
    keeper.typicalLine = band?.lineHeight
    lock.unlock()
  }

  /// Akış ya da ayar değişti: örtme kutusu kararlılığı ve bant bilgisi unutulur.
  func resetCover() {
    lock.lock()
    keeper = CoverKeeper()
    lock.unlock()
  }

  /// Açıksa okunan satır yüksekliği TV'ye gider (yazı oyunun altyazısının boyuna yaklaşır); kapalıysa gitmez (ayardaki boy).
  var matchGameTextSize: Bool {
    get { lock.lock(); defer { lock.unlock() }; return matchesGameSize }
    set { lock.lock(); matchesGameSize = newValue; lock.unlock() }
  }

  /// TV yerleşimi örtme (cover) mi: satır kutuları (rows) yalnız bu yerleşimde anlamlıdır, yalnız o zaman gider.
  var coverPlacement: Bool {
    get { lock.lock(); defer { lock.unlock() }; return cover }
    set { lock.lock(); cover = newValue; lock.unlock() }
  }

  func remember(_ box: TextBox, line: Double?, characters: Int) {
    lock.lock(); defer { lock.unlock() }
    if let last = lines.last, last.box == box {
      // Aynı kutunun sonraki okuması: satır yüksekliği ilk okumada henüz ölçülemediyse sonradan gelen kullanılır.
      if last.line == nil, let line { lines[lines.count - 1].line = line }
      return
    }
    lines.append((box, line, characters))
    if lines.count > 32 { lines.removeFirst(lines.count - 32) }
  }

  func show(_ text: String, durationMs: Int, box: TextBox?, replaces: Bool) {
    show(text, durationMs: durationMs, box: box, replaces: replaces, rows: nil)
  }

  /// [rows]: hattın verdiği konuşma kutuları (yalnız örtme yerleşiminde ve üst düzey kutu varken gider); her satırın
  /// yüksekliği üstteki line ile aynıdır (aynı oyunun yazısı; ayar kapalıysa line hiç gitmez).
  func show(_ text: String, durationMs: Int, box: TextBox?, replaces: Bool, rows: [TextBox]?) {
    var line: Double?
    var outBox = box
    var source = box
    var sent: [SubtitleRow]?
    var diag: DiagFields?
    if let box {
      lock.lock()
      let known = lines.last(where: { $0.box == box })
      let match = matchesGameSize
      let covering = cover
      // Örtme yerleşimi: kutu, örtülen alan, satır yüksekliği ve satır kutuları kararlı tutulur (CoverKeeper). Diğer
      // yerleşimlerde 1.8.5'teki hesap olduğu gibi.
      var request: CoverRequest?
      var placed: CoverPlacement?
      if covering {
        var ratio: Double?
        if let known, known.characters > 0 { ratio = Double(text.count) / Double(known.characters) }
        let made = CoverRequest(text: text, box: box, line: LineHeight.toSend(known?.line, matchGameTextSize: match),
                                matchGameTextSize: match, widenRatio: ratio, rows: rows, replaces: replaces)
        request = made
        placed = keeper.place(made, at: SubtitleStabilizer.monotonicMillis())
      }
      lock.unlock()
      if let placed {
        outBox = placed.box
        source = placed.source
        line = placed.line
        sent = placed.rows
      } else {
        line = LineHeight.toSend(known?.line, matchGameTextSize: match)
        if let known, known.characters > 0 {
          source = Self.widened(box, ratio: Double(text.count) / Double(known.characters))
        }
      }
      if Diag.on {
        // Yazı boyu kararının girdileri: okumadan bilinen satır yüksekliği ve karakter sayısı, ayar, giden değer.
        var f: DiagFields = ["knownBox": .bool(known != nil), "knownLine": DiagValue.optional(known?.line)]
        f["knownCharacters"] = known.map { DiagValue.int($0.characters) } ?? DiagValue.null
        f["matchGameTextSize"] = DiagValue.bool(match)
        f["cover"] = DiagValue.bool(covering)
        if let known, known.characters > 0 { f["widenRatio"] = DiagValue.double(Double(text.count) / Double(known.characters)) }
        if let request, let placed { f["coverKeeper"] = CoverDiag.fields(request, placed) }
        diag = f
      }
    }
    if Diag.on {
      let base = diag ?? DiagFields()
      Diag.emit("tv", frame: "tv") {
        var f: DiagFields = ["what": .string("show"), "text": .string(text), "durationMs": .int(durationMs), "replaces": .bool(replaces)]
        f["box"] = DiagValue.box(outBox)
        f["source"] = DiagValue.box(source)
        f["line"] = DiagValue.optional(line)
        f["rowsIn"] = rows.map { DiagValue.int($0.count) } ?? DiagValue.null
        f["rowsSent"] = sent.map { DiagValue.int($0.count) } ?? DiagValue.null
        for item in base.items { f[item.key] = item.value }
        return f
      }
    }
    server.sendSubtitle(text, durationMs: durationMs, box: outBox, replaces: replaces, source: source, line: line, rows: sent)
  }

  /// Çeviri uzunluğuna göre genişletilmiş örtme alanı (hesap Core'da: CoverKeeper.widened; 1.8.5 ile aynı).
  static func widened(_ box: TextBox, ratio: Double) -> TextBox { CoverKeeper.widened(box, ratio: ratio) }

  func clear() { server.clear() }
}
