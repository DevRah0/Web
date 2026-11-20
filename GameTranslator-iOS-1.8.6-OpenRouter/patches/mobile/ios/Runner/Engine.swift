// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import UIKit

/// Uygulamanın çekirdeği (Android'deki Engine.kt'nin iOS karşılığı): PS5 Remote Play oturumunu açar, gelen kareleri
/// tutar ve altyazı sunucusunu yönetir. Yazı okuma ve çeviri hattı [FrameReader] üzerinden bağlanır.
final class Engine: Native.Listener {
  static let shared = Engine()

  /// Yazı tanıma için saniyede en çok bu kadar kare verilir. Android'de 5; iPhone'da Vision bölgeyi ~70–100 ms'de
  /// okuyor ve çeviri ~80 ms sürüyor, gecikmenin çoğu kareler arası beklemeydi (kararlılık iki kare ister).
  /// Bölge değişmedikçe okuma yeniden kullanıldığı için yük yalnız altyazı değişirken artar.
  static let maxFps = 10
  private static let logLimit = 300

  /// idle, starting, waking, connecting, streaming, reconnecting, stopping, failed
  private(set) var phase = "idle"
  private(set) var message = ""
  /// Son durum metninin (Türkçe, İngilizce) çifti; arayüz dili değişince mesaj yeniden üretilir.
  private var messagePair: (tr: String, en: String)?
  /// Gerçek akış istendi (start → stop; bağlanma, yeniden bağlanma beklemesi ve hata sonrası yeniden deneme dahil).
  /// Yalnız denetim kuyruğunda değişir; her değişimde TV'ye /hello'da bildirilen "active" güncellenir.
  private(set) var running = false {
    didSet { updateServerActive() }
  }
  var lastSource = ""
  var lastTranslation = ""
  var lastRead = ""
  private(set) var frameCount = 0
  private(set) var frameWidth = 0
  private(set) var frameHeight = 0
  var translatedCount = 0
  var packHits = 0
  var packGame = ""

  let server = SubtitleServer()

  /// Durum değişince ana iş parçacığında çağrılır.
  var onChanged: (([String: Any?]) -> Void)?

  /// Gelen her karenin okunması (yazı tanıma + çeviri). Verilmediyse kareler yalnız saklanır.
  var reader: FrameReader?

  /// Durum değişkenleri, oturum ve sunucu işleri bu kuyrukta sıralanır (Android'deki gt-control iş parçacığı).
  private let control = DispatchQueue(label: "gt.control")
  private let logLock = NSLock()
  private var logs: [String] = []
  private var notifyPending = false
  private(set) var settings = Settings()
  private var openRouterKeySeen = ""
  private var session: Native.Session?
  private var retry: DispatchWorkItem?
  /// Yeniden bağlanma beklemesi (üstel artış); yalnız denetim kuyruğunda kullanılır.
  private var reconnect = ReconnectPolicy()
  /// Tek tek satır çevirilerinin diskteki önbelleği (Application Support/TranslationCache/translation-cache.json).
  static let translationCache: DiskTranslationCache = {
    // Yedekten hariç tutma işareti dosyaya değil klasöre konur: dosya her yazımda yeniden oluşur (atomik yazma).
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    var folder = support.appendingPathComponent("TranslationCache", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var excluded = URLResourceValues()
    excluded.isExcludedFromBackup = true
    try? folder.setResourceValues(excluded)
    let url = folder.appendingPathComponent("translation-cache.json")
    return DiskTranslationCache(storage: FileCacheStorage(url: url))
  }()
  /// Gösterilen altyazıların geçmişi (Application Support/History/history.json; son 200 satır, yedeğe gitmez).
  static let history: SubtitleHistoryLog = {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    var folder = support.appendingPathComponent("History", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var excluded = URLResourceValues()
    excluded.isExcludedFromBackup = true
    try? folder.setResourceValues(excluded)
    return SubtitleHistoryLog(storage: FileCacheStorage(url: folder.appendingPathComponent("history.json")))
  }()

  /// Ayarlardaki motorun fiilen çalışan karşılığı: anahtarsız deepl/gemini seçimi Google çalıştırır.
  static func effectiveEngine(_ s: Settings) -> String {
    let usesGemini = s.engine == "gemini" && s.targetLanguage == "tr"
      && !s.geminiKey.trimmingCharacters(in: .whitespaces).isEmpty
    let usesDeepL = s.engine == "deepl" && !s.deepLKey.trimmingCharacters(in: .whitespaces).isEmpty
    if s.engine == "openrouter" {
      return !Store.shared.openRouterKey.isEmpty && s.sourceLanguage == "en" && s.targetLanguage == "ar"
        ? "openrouter" : "google"
    }
    return s.engine == "gemini" ? (usesGemini ? "gemini" : "google")
      : s.engine == "deepl" ? (usesDeepL ? "deepl" : "google") : s.engine
  }

  /// Çeviri kurallarının sürümü: kurallar (ör. sözlük) değişince eski önbellek kayıtları kullanılmaz.
  private static let rulesVersion = "r2"
  private let stopLock = NSLock()
  private var _stopRequested = false
  /// Durdurma istendi ama denetim kuyruğu henüz işlemedi (uyandırma beklemesini keser).
  private var stopRequested: Bool {
    get { stopLock.lock(); defer { stopLock.unlock() }; return _stopRequested }
    set { stopLock.lock(); _stopRequested = newValue; stopLock.unlock() }
  }

  /// Konsolsuz deneme (demo) zamanlayıcısı; yalnız denetim kuyruğunda değişir.
  private var demoTimer: DispatchSourceTimer?
  private var demoScript = DemoScript()
  private let demoLock = NSLock()
  private var _demo = false
  /// Demo çalışıyor mu (her iş parçacığından okunur; yalnız denetim kuyruğunda yazılır).
  var demoActive: Bool {
    get { demoLock.lock(); defer { demoLock.unlock() }; return _demo }
    set {
      demoLock.lock(); _demo = newValue; demoLock.unlock()
      updateServerActive()
    }
  }

  /// TV'ye /hello yanıtında bildirilen "çeviri çalışıyor": gerçek akış ya da demo. [running] ve [demoActive]'in her
  /// yazımından sonra çağrılır; ikisinin dışında bir yerden ayarlanmaz, böylece bayrak durumdan ayrı kalamaz.
  private func updateServerActive() { server.active = running || demoActive }

  /// Sistem sağlığı için: okumaya verilen karelerin hızı ve son çeviri sonucu (kilit altında).
  private let healthLock = NSLock()
  private var frameRate = RateMeter(window: 5)
  private var translatorOk = true
  private var translatorError = ""

  /// Son kare (BGRA). Okuma ve önizleme kopyasını alır.
  private let frameLock = NSLock()
  private var frame: Frame?

  private init() {
    // Her yeni çeviri hattı ayarlardan seçeneklerini alır: Türkçe satırı atlama ve diskteki çeviri önbelleği.
    SubtitlePipeline.optionsProvider = {
      let s = Store.shared.settings
      var options = PipelineOptions()
      options.skipTurkishSource = s.targetLanguage == "tr"
      options.cache = Engine.translationCache
      // Anahtarsız deepl/gemini seçimi fiilen Google çalıştırır; önbellek anahtarı gerçek motoru göstersin.
      let usesGemini = s.engine == "gemini" && s.targetLanguage == "tr"
        && !s.geminiKey.trimmingCharacters(in: .whitespaces).isEmpty
      options.engineId = Engine.effectiveEngine(s)
      // Talimat değişince eski üslupla saklanmış çeviriler gelmesin: kararlı kısa özet modele eklenir (boşsa eklenmez).
      let noteTag = GeminiStyleNote.cacheTag(s.geminiStyleNote)
      options.model = options.engineId == "openrouter" ? OpenRouterTranslator.model :
        (usesGemini ? GeminiModels.resolve(s.geminiModel) + (noteTag.isEmpty ? "" : "+" + noteTag) : "")
      options.sourceLanguage = s.sourceLanguage
      options.targetLanguage = s.targetLanguage
      let glossary = s.sourceLanguage == "en" && s.targetLanguage == "tr" ? s.glossary : ""
      options.rulesVersion = Engine.rulesVersion + "-" + DiskTranslationCache.stableHash(glossary)
      // Ad koruması kullanıcı sözlüğündeki terimlere dokunmaz.
      if !glossary.isEmpty { options.glossary = s.parsedGlossary() }
      return options
    }
    // Uygulama arka plandan dönünce (çeviri kapalıyken iOS uygulamayı askıya almış olabilir) dinleyici bozulmuş olabilir;
    // TV "bekleniyor"da kalıyordu, çeviriyi kapatıp açmak düzeltiyordu. Dönüşte sunucu yeniden kurulur.
    NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { [weak self] _ in
      Diag.emit("engine") { ["what": .string("app"), "state": .string("foreground")] }
      self?.onControl {
        guard let self else { return }
        if !self.running || !self.server.isReady {
          self.log(2, "uygulama önde: altyazı sunucusu yeniden kuruluyor")
          self.server.restart()
          self.server.sendStyle(Store.shared.settings.style)
        }
      }
    }
    // Geçmişin bekleyen yazımı arka plana giderken diske iner (iOS uygulamayı sonra askıya alabilir).
    NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
      Diag.emit("engine") {
        ["what": .string("app"), "state": .string("background"), "running": .bool(self?.running ?? false)]
      }
      Engine.history.flush()
    }
    NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { _ in
      Diag.emit("engine") { ["what": .string("app"), "state": .string("active")] }
    }
    NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: nil) { _ in
      Diag.emit("engine") { ["what": .string("app"), "state": .string("inactive")] }
    }
    // Uygulama kapanırken süren tanı kaydı düzgün kapanır (öldürülürse bir sonraki açılışta mühürlenir).
    NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: nil) { _ in
      Diagnostics.shared.terminate()
    }
    server.onChanged = { [weak self] in self?.notifyChanged() }
    server.onLog = { [weak self] level, text in self?.log(level, text) }
    if let url = Bundle.main.url(forResource: "obs-overlay", withExtension: "html") {
      server.overlayPage = try? Data(contentsOf: url)
    }
  }

  // MARK: - Durum

  func state() -> [String: Any?] {
    [
      "phase": phase,
      "message": message,
      "running": running,
      "tvClients": server.connectedClients,
      "serverPort": server.boundPort,
      "localAddress": Network.localAddress(),
      "lastSource": lastSource,
      "lastTranslation": lastTranslation,
      "lastRead": lastRead,
      "frames": frameCount,
      "frameWidth": frameWidth,
      "frameHeight": frameHeight,
      "translated": translatedCount,
      "packHits": packHits,
      "packGame": packGame,
      "nativeAvailable": Native.available,
      "demo": demoActive,
      // Otomatik alan kilitliyse bulunan şerit (0–1 oranlar); değilse nil.
      "autoRegion": reader?.autoRegion.map { ["top": $0.top, "bottom": $0.bottom, "left": $0.left, "right": $0.right] as [String: Double] },
      // Tanı kaydı (yalnız iOS): kayıt sürüyor mu, sayaçlar, son duruşun nedeni.
      "diagnostics": Diagnostics.shared.stateMap(),
    ]
  }

  /// Çeviri sonucu bildirimi (sağlık ekranı): başarılıysa hata temizlenir.
  func noteTranslation(ok: Bool, error: String = "") {
    healthLock.lock()
    translatorOk = ok
    translatorError = ok ? "" : error
    healthLock.unlock()
  }

  /// Sistem sağlığı özeti ("health" yöntemi). Ucuzdur: yalnız bellekteki sayaçlara bakar (çeviri önbelleği sayısı ilk
  /// çağrıda dosyayı yükleyebilir). Kullanılamayan değerler nötr döner.
  func health() -> [String: Any] {
    let store = Store.shared
    let s = store.settings
    let console = store.console
    let address = Network.localAddress()
    healthLock.lock()
    let fps = frameRate.rate(at: ProcessInfo.processInfo.systemUptime)
    let ok = translatorOk
    let error = translatorError
    healthLock.unlock()
    let readerHealth = reader?.health ?? ReaderHealth()
    let port = server.boundPort
    let consoleInfo: [String: Any] = ["registered": console != nil, "host": console?.host ?? "", "state": phase]
    let streamInfo: [String: Any] = ["running": phase == "streaming", "fps": fps]
    let readerInfo: [String: Any] = ["lastReadMs": readerHealth.lastReadMs, "language": readerHealth.language,
                                     "stuckRecoveries": readerHealth.stuckRecoveries]
    let chain = EngineCooldowns.shared.snapshot(now: Date())
    let pausedEngines: [[String: Any]] = chain.paused.map { ["engine": $0.engine, "seconds": $0.seconds, "reason": $0.reason.rawValue] }
    let translatorInfo: [String: Any] = ["engine": Engine.effectiveEngine(s), "lastOk": ok, "lastError": error,
                                         "geminiPausedSeconds": GeminiTranslator.pausedSeconds,
                                         "failover": ["active": chain.active, "current": chain.current, "paused": pausedEngines] as [String: Any]]
    let tvInfo: [String: Any] = ["clients": server.connectedClients, "port": port == 0 ? Int(SubtitleServer.defaultPort) : port]
    let packInfo: [String: Any] = ["enabled": s.packsEnabled, "game": packGame]
    let cacheInfo: [String: Any] = ["entries": Engine.translationCache.count]
    return [
      "network": address != nil,
      "phoneAddress": address ?? "",
      "console": consoleInfo,
      "stream": streamInfo,
      "reader": readerInfo,
      "translator": translatorInfo,
      "tv": tvInfo,
      "packs": packInfo,
      "cache": cacheInfo,
    ]
  }

  func logLines() -> [String] {
    logLock.lock(); defer { logLock.unlock() }
    return logs
  }

  func log(_ level: Int, _ text: String) {
    let line = "\(level == 0 ? "E" : level == 1 ? "W" : "I") \(text)"
    NSLog("GameTranslator %@", line)
    Diag.emit("log") { ["level": .int(level), "text": .string(text)] }
    logLock.lock()
    logs.append(line)
    if logs.count > Self.logLimit { logs.removeFirst(logs.count - Self.logLimit) }
    logLock.unlock()
  }

  private func setPhase(_ value: String, _ text: String = "", logText: String? = nil) {
    phase = value
    message = text
    messagePair = nil
    Diag.emit("engine") {
      ["what": .string("phase"), "phase": .string(value), "message": .string(logText ?? text), "running": .bool(running),
       "tvClients": .int(server.connectedClients)]
    }
    log(value == "failed" ? 0 : 2, "durum: \(value) \(logText ?? text)".trimmingCharacters(in: .whitespaces))
    notifyChanged()
  }

  /// Arayüzde görünen durum metni dile göre seçilir; günlüğe her zaman Türkçesi yazılır.
  private func setPhase(_ value: String, tr: String, en: String) {
    setPhase(value, Lang.t(tr, en), logText: tr)
    messagePair = (tr, en)
  }

  /// Arayüze en çok ~10 Hz bildirim: kare sayacı her karede değişir.
  func notifyChanged() {
    DispatchQueue.main.async {
      if self.notifyPending { return }
      self.notifyPending = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        self.notifyPending = false
        self.onChanged?(self.state())
      }
    }
  }

  /// Denetim kuyruğunda çalıştırır.
  private func onControl(_ block: @escaping () -> Void) { control.async(execute: block) }

  // MARK: - Başlat / durdur

  /// Uygulama açılınca: altyazı sunucusu çeviri başlamadan da açık olur; TV telefonu hemen bulur.
  func openServer() {
    onControl {
      self.settings = Store.shared.settings
      self.server.start()
      self.server.sendStyle(self.settings.style)
      self.log(2, "altyazı sunucusu: \(Network.localAddress() ?? "?"):\(SubtitleServer.defaultPort)")
    }
  }

  func start() {
    stopRequested = false
    onControl {
      if self.running { return }
      let store = Store.shared
      self.settings = store.settings
      if !Native.available { return self.setPhase("failed", tr: "Yerel kütüphane yüklenemedi", en: "Native library could not be loaded") }
      if store.accountId == nil || store.console == nil {
        return self.setPhase("failed", tr: "Önce PSN girişi ve PS5 eşleştirmesi gerekli", en: "Sign in to PSN and pair your PS5 first")
      }
      // Gerçek akış başlarken demo durur.
      if self.demoTimer != nil { self.stopDemoLocked() }
      self.running = true
      self.reconnect.reset()
      self.frameCount = 0
      self.healthLock.lock(); self.frameRate.reset(); self.healthLock.unlock()
      self.translatedCount = 0
      self.packHits = 0
      self.packGame = ""
      self.setPhase("starting")
      // Ekran kilitliyken de sürsün diye uygulama sessiz bir ses akışıyla arka planda canlı tutulur.
      BackgroundKeeper.shared.log = { [weak self] level, text in self?.log(level, text) }
      BackgroundKeeper.shared.start()
      self.server.start()
      self.log(2, "altyazı sunucusu: \(Network.localAddress() ?? "?"):\(SubtitleServer.defaultPort)")
      self.server.sendStyle(self.settings.style)
      if self.reader == nil { self.reader = VisionReader(engine: self) }
      if self.settings.packsEnabled { Packs.shared.refresh { [weak self] level, text in self?.log(level, text) } }
      self.reader?.rebuild(settings: self.settings)
      self.connect()
    }
  }

  func stop() {
    stopRequested = true
    // Oturumun kapanması birkaç saniye sürebilir; arayüz bu sırada "durduruluyor" gösterir.
    if running || session != nil { setPhase("stopping") }
    onControl {
      if !self.running && self.session == nil { return self.setPhase("idle") }
      self.running = false
      self.retry?.cancel()
      self.retry = nil
      Engine.translationCache.flush()
      Engine.history.flush()
      self.closeSession()
      // Okuma kuyruğundaki sıfırlamadan önce biten çeviri TV'ye gidebilir: sıfırlamanın ardından TV bir kez daha temizlenir.
      self.reader?.reset(clearScreen: true)
      // Sunucu açık kalır: TV bağlı kalsın, çeviri yeniden başlayınca altyazılar hemen gitsin.
      self.server.clear()
      self.frameLock.lock(); self.frame = nil; self.frameLock.unlock()
      BackgroundKeeper.shared.stop()
      self.setPhase("idle")
    }
  }

  /// Ayarlar değişti: görünüm hemen TV'ye gider; dil, motor ya da bölge değiştiyse okuma hattı yenilenir.
  func applySettings() {
    onControl {
      let before = self.settings
      let now = Store.shared.settings
      self.settings = now
      let openRouterKey = Store.shared.openRouterKey
      let openRouterKeyChanged = openRouterKey != self.openRouterKeySeen
      self.openRouterKeySeen = openRouterKey
      Diagnostics.shared.settingsChanged(before: before, after: now)
      if now.uiLanguage != before.uiLanguage, let pair = self.messagePair {
        self.message = Lang.t(pair.tr, pair.en)
        self.notifyChanged()
      }
      if now.style != before.style, self.server.isStarted { self.server.sendStyle(now.style) }
      // Yazı boyu seçimi bir sonraki satırdan geçerli; hat yeniden kurulmaz.
      if now.matchGameTextSize != before.matchGameTextSize {
        (self.reader as? VisionReader)?.setMatchGameTextSize(now.matchGameTextSize)
      }
      if now.style.placement != before.style.placement {
        (self.reader as? VisionReader)?.setCoverPlacement(now.style.placement == "cover")
      }
      guard self.running || self.demoTimer != nil else { return }
      if openRouterKeyChanged || now.engine != before.engine || now.deepLKey != before.deepLKey || now.geminiKey != before.geminiKey || now.geminiModel != before.geminiModel || now.geminiStyleNote != before.geminiStyleNote || now.engineFailover != before.engineFailover || now.sourceLanguage != before.sourceLanguage
        || now.targetLanguage != before.targetLanguage || now.glossary != before.glossary || now.packsEnabled != before.packsEnabled
        || now.packChoice != before.packChoice {
        Diag.emit("engine") { ["what": .string("settings-apply"), "action": .string("rebuild")] }
        self.reader?.rebuild(settings: now)
      } else if now.region != before.region || now.hideButtonHints != before.hideButtonHints
        || now.autoRegion != before.autoRegion || now.subtitleOnly != before.subtitleOnly {
        Diag.emit("engine") { ["what": .string("settings-apply"), "action": .string("reset")] }
        self.reader?.reset()
      }
    }
  }

  /// TV'de deneme altyazısı; sunucu kapalıysa açılır (TV telefonu bulsun diye açık kalır).
  func sendTestSubtitle() {
    onControl {
      // self.settings'e yazılmaz: applySettings farkı ona göre hesaplar, bekleyen ayar değişikliği yutulmasın.
      let s = Store.shared.settings
      if !self.server.isStarted {
        self.server.start()
        self.log(2, "altyazı sunucusu: \(Network.localAddress() ?? "?"):\(SubtitleServer.defaultPort)")
      }
      self.server.sendStyle(s.style)
      let r = s.region
      self.server.sendSubtitle(Lang.t("Bu bir deneme altyazısıdır. Oyunun üstünde görüyor musunuz?", "This is a test subtitle. Can you see it over the game?"), durationMs: 8000,
                               box: TextBox(left: 0.3, top: r.bottom - 0.1, right: 0.7, bottom: r.bottom - 0.03))
    }
  }

  // MARK: - Demo (konsolsuz deneme)

  /// Demo: birkaç saniyede bir örnek İngilizce satırı gerçek çeviri hattından geçirip TV'ye gönderir. Akış sürerken
  /// başlamaz; akış başlayınca kendiliğinden durur.
  func demoStart() {
    onControl { self.startDemoLocked() }
  }

  func demoStop() {
    onControl { self.stopDemoLocked() }
  }

  /// Denetim kuyruğunda.
  private func startDemoLocked() {
    if running {
      log(1, "demo: akış sürerken başlatılamaz")
      notifyChanged()
      return
    }
    if demoTimer != nil { return }
    settings = Store.shared.settings
    if !server.isStarted { server.start() }
    server.sendStyle(settings.style)
    if reader == nil { reader = VisionReader(engine: self) }
    reader?.rebuild(settings: settings)
    demoScript = DemoScript()
    demoActive = true
    let timer = DispatchSource.makeTimerSource(queue: control)
    timer.schedule(deadline: .now() + 0.8, repeating: DemoScript.intervalSeconds)
    timer.setEventHandler { [weak self] in self?.demoTick() }
    timer.resume()
    demoTimer = timer
    log(2, "demo başladı")
    notifyChanged()
  }

  /// Denetim kuyruğunda.
  private func stopDemoLocked() {
    guard let timer = demoTimer else { return }
    timer.cancel()
    demoTimer = nil
    demoActive = false
    reader?.reset(clearScreen: true)
    server.clear()
    log(2, "demo durdu")
    notifyChanged()
  }

  /// Denetim kuyruğunda: sıradaki örnek satır okunmuş gibi hatta verilir (kararlılık için iki kare).
  private func demoTick() {
    guard !running, demoTimer != nil else { return }
    let line = demoScript.next()
    let r = settings.region
    let box = TextBox(left: 0.25, top: max(0, r.bottom - 0.1), right: 0.75, bottom: max(0.1, r.bottom - 0.04))
    reader?.feed(lines: [line], box: box)
    reader?.feed(lines: [line], box: box)
  }

  // MARK: - Ek okuma alanı

  /// Ek alanı son karede bir kez okuyup çevirir ve TV'ye gönderir (bloklar; arka plan iş parçacığında çağrılır).
  func readExtra(index: Int) -> [String: Any] {
    let regions = Store.shared.settings.extraRegions
    // Tanı kaydı: basıldı; o anki kare de kaydedilir (okunacak olan kare).
    Diag.emit("extra", frame: "extra") {
      var fields: DiagFields = ["what": .string("pressed"), "index": .int(index), "running": .bool(running), "phase": .string(phase)]
      fields["hasReader"] = DiagValue.bool(reader != nil)
      fields["hasFrame"] = DiagValue.bool(currentFrame() != nil)
      fields["frames"] = DiagValue.int(frameCount)
      fields["regionCount"] = DiagValue.int(regions.count)
      if index >= 0, index < regions.count {
        let r = regions[index]
        fields["region"] = DiagValue.string(r.name)
        fields["regionBox"] = DiagValue.box(TextBox(left: r.left, top: r.top, right: r.right, bottom: r.bottom))
      }
      fields["tvClients"] = DiagValue.int(server.connectedClients)
      return fields
    }
    func failure(_ step: String, _ message: String) -> [String: Any] {
      Diag.emit("extra") { ["what": .string("fail"), "step": .string(step), "error": .string(message)] }
      return ["ok": false, "source": "", "text": "", "error": message]
    }
    guard running, phase == "streaming", let reader = reader else {
      return failure("no-stream", Lang.t("Akış çalışmıyor; önce çeviriyi başlatın.", "The stream is not running; start translation first."))
    }
    guard index >= 0, index < regions.count else { return failure("bad-region", Lang.t("Geçersiz okuma alanı.", "Invalid reading area.")) }
    guard let frame = currentFrame() else {
      return failure("no-frame", Lang.t("Henüz görüntü gelmedi; biraz bekleyin.", "No image has arrived yet; wait a moment."))
    }
    let outcome = reader.readExtra(frame, region: regions[index])
    return ["ok": outcome.ok, "source": outcome.source, "text": outcome.text, "error": outcome.error]
  }

  // MARK: - PS5 oturumu

  /// [relocated]: adres bu denemede zaten yenilendi; ağ ikinci kez taranmaz.
  private func connect(relocated: Bool = false) {
    guard running else { return }
    let store = Store.shared
    guard let console = store.console else { return setPhase("failed", tr: "PS5 eşleştirmesi yok", en: "No PS5 is paired") }
    guard let account = store.accountId else { return setPhase("failed", tr: "PSN hesabı yok", en: "No PSN account") }
    setPhase("connecting", console.host)

    // PS5 açık mı? Kapalıysa (dinlenme modu) ayara göre uyandırılır.
    switch probe(console.host) {
    case true?:
      break
    case false?:
      guard settings.autoWake, let credential = console.wakeCredential else {
        setPhase("failed", tr: "PS5 dinlenme modunda", en: "The PS5 is in rest mode")
        return scheduleRetry()
      }
      setPhase("waking", console.host)
      Native.wake(host: console.host, credential: credential)
      let deadline = Date().addingTimeInterval(60)
      var awake = false
      while !stopRequested && !awake && Date() < deadline { awake = probe(console.host) == true }
      if stopRequested { return }
      if !awake {
        setPhase("failed", tr: "PS5 uyanmadı", en: "The PS5 did not wake up")
        return scheduleRetry()
      }
      setPhase("connecting", console.host)
    case nil:
      // Modem PS5'e yeni adres vermiş olabilir: ağ taranır, aynı adlı konsol bulunursa kayıt güncellenir.
      let moved = relocated ? nil : relocate(console)
      if stopRequested { return }
      if let moved {
        log(2, "PS5 yeni adreste bulundu: \(console.host) → \(moved)")
        store.console = Console(host: moved, name: console.name, registKey: console.registKey, morning: console.morning)
        return connect(relocated: true)
      }
      setPhase("failed", tr: "PS5 ağda bulunamadı (\(console.host))", en: "PS5 not found on the network (\(console.host))")
      return scheduleRetry()
    }

    log(2, "PS5 oturumu: \(console.name) \(console.host)")
    session = Native.startSession(host: console.host, registKey: console.registKey, morning: console.morning,
                                  accountId: account, maxFps: Self.maxFps, listener: self)
    if session == nil {
      setPhase("failed", tr: "Oturum başlatılamadı", en: "Could not start the session")
      scheduleRetry()
    }
  }

  /// Kayıtlı adres yanıt vermiyorsa konsolu ağda arar. Aynı adlı tek konsol varsa adresini döner; yoksa ya da
  /// birden çok aday varsa nil (başka bir PS5'in adresi kayda yazılmasın).
  private func relocate(_ console: Console) -> String? {
    let sameName = discover(hosts: [], timeoutMs: 2500).filter { $0["host"] as? String != console.host && $0["name"] as? String == console.name }
    return sameName.count == 1 ? sameName[0]["host"] as? String : nil
  }

  /// true: açık, false: dinlenme modunda, nil: yanıt yok.
  private func probe(_ host: String) -> Bool? {
    let lock = NSLock()
    var result: Bool?
    Native.discover(targets: [host], timeoutMs: 1500) { _, _, awake in
      lock.lock()
      if result != true { result = awake }
      lock.unlock()
    }
    lock.lock(); defer { lock.unlock() }
    return result
  }

  private func closeSession() {
    let current = session
    session = nil
    current?.stop()
  }

  /// Yeniden bağlanma: 2, 4, 8, 16, 30 sn (üst sınır 30); "başka cihazda kullanımda" en az 8 sn; akış 60 sn kararlı
  /// sürmüşse ya da elle başlatılmışsa sayaç başa döner (ReconnectPolicy). Denetim kuyruğunda çağrılır.
  private func scheduleRetry(_ reason: ReconnectPolicy.Reason = .generic) {
    guard running else { return }
    let seconds = reconnect.nextDelay(reason, at: ProcessInfo.processInfo.systemUptime)
    Diag.emit("engine") { ["what": .string("retry"), "attempt": .int(reconnect.attempt), "seconds": .double(seconds)] }
    log(2, "yeniden bağlanma \(reconnect.attempt). deneme, \(Int(seconds)) sn sonra")
    retry?.cancel()
    let item = DispatchWorkItem { [weak self] in
      guard let self, self.running, self.session == nil else { return }
      self.connect()
    }
    retry = item
    control.asyncAfter(deadline: .now() + seconds, execute: item)
  }

  // MARK: - Native.Listener (libchiaki'nin iş parçacıklarından)

  func onLog(_ level: Int, _ message: String) {
    // Bilgi satırları (her 5 sn'de kalp atışı, paket dökümleri) günlüğü doldurur; hata ve uyarılar tutulur.
    if level < 2 || message.hasPrefix("Session") || message.hasPrefix("Starting") || message.hasPrefix("Switched") {
      log(level, "chiaki: \(message)")
    }
  }

  func onEvent(_ event: Int32, quitReason: Int32, reasonText: String?) {
    Diag.emit("engine") {
      ["what": .string("session-event"), "event": .int(Int(event)), "quitReason": .int(Int(quitReason)),
       "reasonText": DiagValue.optional(reasonText)]
    }
    switch event {
    case Native.eventConnected:
      onControl {
        self.reconnect.streamStarted(at: ProcessInfo.processInfo.systemUptime)
        self.setPhase("streaming")
      }
    case Native.eventLoginPin:
      onControl {
        self.closeSession()
        self.running = false
        self.setPhase("failed", tr: "PS5 kullanıcısının giriş şifresi var; şifresiz bir kullanıcı kullanın", en: "This PS5 user has a login passcode; use a user without one")
      }
    case Native.eventQuit:
      onControl {
        // Oturum kendi iş parçacığından kapatılamaz; denetim kuyruğunda bırakılır.
        self.closeSession()
        guard self.running else { return }
        switch quitReason {
        case Native.quitStopped:
          break
        case Native.quitInUse:
          self.setPhase("failed", tr: "Remote Play başka bir cihazda kullanılıyor", en: "Remote Play is in use on another device")
          self.scheduleRetry(.inUse)
        case Native.quitRefused:
          self.running = false
          self.setPhase("failed", tr: "PS5 bağlantıyı reddetti; yeniden eşleştirin", en: "The PS5 refused the connection; pair again")
        default:
          self.setPhase("reconnecting", tr: reasonText ?? "bağlantı koptu", en: reasonText ?? "connection lost")
          self.scheduleRetry()
        }
      }
    default:
      break
    }
  }

  func onFrame(base: UnsafePointer<UInt8>, width: Int, height: Int, stride: Int) {
    let copy = Frame(width: width, height: height, stride: stride, pixels: Data(bytes: base, count: stride * height))
    frameLock.lock()
    frame = copy
    frameLock.unlock()
    frameWidth = width
    frameHeight = height
    frameCount += 1
    healthLock.lock()
    frameRate.record(at: ProcessInfo.processInfo.systemUptime)
    healthLock.unlock()
    if frameCount % Self.maxFps == 1 { notifyChanged() }
    reader?.offer(copy)
  }

  /// Son karenin kopyası; kare yoksa nil.
  func currentFrame() -> Frame? {
    frameLock.lock(); defer { frameLock.unlock() }
    return frame
  }

  // MARK: - Arayüz için yardımcılar

  /// Son karenin JPEG görüntüsü (bölge ayarı ve önizleme için); kare yoksa nil.
  func snapshot(width maxWidth: Int) -> Data? {
    guard let frame = currentFrame(), let image = frame.cgImage() else { return nil }
    let width = min(maxWidth, frame.width)
    let height = frame.height * width / frame.width
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: {
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      format.opaque = true
      return format
    }())
    return renderer.jpegData(withCompressionQuality: 0.8) { _ in
      UIImage(cgImage: image).draw(in: CGRect(x: 0, y: 0, width: width, height: height))
    }
  }

  /// Aramada sorulacak adresler: yayın adresleri ve /24 ağlardaki tüm adresler. iOS yayın paketlerini ayrı bir
  /// izin olmadan göndermez; tek tek adres taraması her ağda çalışır.
  private func discoveryTargets(_ extra: [String]) -> [String] {
    var targets: [String] = ["255.255.255.255"]
    func add(_ value: String) { if !value.isEmpty && !targets.contains(value) { targets.append(value) } }
    extra.forEach(add)
    for network in Network.ipv4Networks() {
      add(network.broadcast)
      if network.prefixLength >= 24 {
        for i in 1...254 { add(network.prefix24 + String(i)) }
      }
    }
    return targets
  }

  /// Ağdaki PS5'leri arar (bloklar). [hosts]: elle girilen adresler.
  func discover(hosts: [String], timeoutMs: Int) -> [[String: Any]] {
    guard Native.available else { return [] }
    let lock = NSLock()
    var order: [String] = []
    var found: [String: [String: Any]] = [:]
    Native.discover(targets: discoveryTargets(hosts), timeoutMs: timeoutMs) { host, name, awake in
      lock.lock()
      if found[host] == nil { order.append(host) }
      found[host] = ["host": host, "name": name, "awake": awake]
      lock.unlock()
    }
    lock.lock(); defer { lock.unlock() }
    return order.compactMap { found[$0] }
  }

  /// PS5'in "Cihaz Eşleştir" koduyla kayıt (bloklar, en çok ~30 sn). Başarılıysa kaydı saklar.
  func register(host: String, pin: Int) -> [String: Any] {
    let store = Store.shared
    guard let account = store.accountId else { return ["ok": false, "detail": Lang.t("Önce PSN girişi gerekli", "Sign in to PSN first")] }
    guard Native.available else { return ["ok": false, "detail": Lang.t("Yerel kütüphane yüklenemedi", "Native library could not be loaded")] }
    let errorLock = NSLock()
    var errors: [String] = []
    log(2, "PS5 kaydı başlıyor: \(host)")
    let outcome = Native.register(host: host, accountId: account, pin: UInt32(pin)) { [weak self] level, message in
      self?.log(level, "chiaki: \(message)")
      if level == 0 { errorLock.lock(); errors.append(message); errorLock.unlock() }
    }
    guard outcome.result == 0, let registered = outcome.registered else {
      let code = outcome.reason
      errorLock.lock()
      let seen = errors
      errorLock.unlock()
      let detail: String
      let logDetail: String  // Destek günlüğü arayüz dilinden bağımsız Türkçe kalır.
      if code == 0x80108b02 {
        logDetail = "PS5 bu PSN hesabını tanımadı. PS5'te oturum açık olan kullanıcıyla aynı hesapla giriş yapın."
        detail = Lang.t(logDetail, "The PS5 did not recognise this PSN account. Sign in with the same account as the user signed in on the PS5.")
      } else if code == 0x80108b09 || code == 0x80108b12 {
        logDetail = "Kod yanlış ya da süresi dolmuş. PS5'te Cihaz Eşleştir'i yeniden açıp yeni kodu girin."
        detail = Lang.t(logDetail, "The code is wrong or has expired. Reopen Add Device on the PS5 and enter the new code.")
      } else if outcome.result == 2 {
        logDetail = "İptal edildi"
        detail = Lang.t(logDetail, "Cancelled")
      } else if seen.contains(where: { $0.range(of: "search", options: .caseInsensitive) != nil }) {
        // PS5 "Cihaz Eşleştir" ekranında değilken kayıt aramasını reddeder ya da hiç yanıtlamaz.
        logDetail = "PS5 eşleştirmeye hazır değil. PS5'te Ayarlar › Sistem › Uzaktan Oynatma › Cihaz Eşleştir ekranını açık tutup yeniden deneyin."
        detail = Lang.t(logDetail, "The PS5 is not ready to pair. Keep Settings › System › Remote Play › Link Device open on the PS5 and try again.")
      } else if let first = seen.first {
        logDetail = first
        detail = first
      } else {
        logDetail = "PS5 yanıt vermedi. Konsolun açık ve Cihaz Eşleştir ekranında olduğunu kontrol edin."
        detail = Lang.t(logDetail, "The PS5 did not respond. Check that the console is on and showing the Link Device screen.")
      }
      log(0, "PS5 kaydı başarısız: \(logDetail)")
      return ["ok": false, "reason": Int(Int32(bitPattern: code)), "detail": detail]
    }
    let name = registered.name.trimmingCharacters(in: .whitespaces).isEmpty ? "PS5" : registered.name
    store.console = Console(host: host, name: name, registKey: registered.registKey, morning: registered.morning)
    log(2, "PS5 kaydı tamam: \(name)")
    return ["ok": true, "name": name, "host": host]
  }
}

/// Çözülmüş bir kare (BGRA, satır başına [stride] bayt).
struct Frame {
  let width: Int
  let height: Int
  let stride: Int
  let pixels: Data

  func cgImage() -> CGImage? {
    guard let provider = CGDataProvider(data: pixels as CFData) else { return nil }
    let info = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue)
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: stride,
                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info, provider: provider, decode: nil,
                   shouldInterpolate: true, intent: .defaultIntent)
  }
}

/// Gelen kareleri okuyan hat (yazı tanıma + çeviri); Engine yalnız bu arayüzü bilir.
protocol FrameReader: AnyObject {
  /// Ayarlara göre hattı yeniden kurar (denetim kuyruğunda).
  func rebuild(settings: Settings)
  /// Bölge ya da oturum değişti: geçmiş unutulur. [clearScreen]: sıfırlamadan sonra TV de temizlenir (durdurma).
  func reset(clearScreen: Bool)
  /// Yeni kare; okuma sürüyorsa kare atlanabilir (libchiaki iş parçacığından).
  func offer(_ frame: Frame)
  /// Okunmuş gibi satırları doğrudan çeviri hattına verir (demo).
  func feed(lines: [String], box: TextBox?)
  /// Ek alanı verilen karede bir kez okuyup çevirir ve TV'ye gönderir (bloklar); asıl okumayı bozmaz.
  func readExtra(_ frame: Frame, region: ExtraRegion) -> ExtraReadResult
  /// Sağlık ekranı için okuyucu sayaçları.
  var health: ReaderHealth { get }
  /// Otomatik altyazı alanı kilitliyse bulunan şerit; değilse nil.
  var autoRegion: AutoRegionBand? { get }
}

extension FrameReader {
  func reset() { reset(clearScreen: false) }
}

/// Ek alan okumasının sonucu.
struct ExtraReadResult {
  var ok = false
  var source = ""
  var text = ""
  var error = ""
}

/// Okuyucunun sağlık sayaçları (yoksa nötr değerler).
struct ReaderHealth {
  var lastReadMs = 0
  var language = ""
  var stuckRecoveries = 0
}

/// Ağ yardımcıları.
enum Network {
  struct IPv4 {
    let address: String
    let broadcast: String
    let prefixLength: Int
    /// "192.168.1." biçiminde ilk üç bayt.
    let prefix24: String
  }

  /// Telefonun yerel ağdaki IPv4 adresi (Wi-Fi, yani en0, öncelikli).
  static func localAddress() -> String? {
    let networks = ipv4Networks(includeCellular: false)
    return networks.first(where: { $0.name == "en0" })?.network.address ?? networks.first?.network.address
  }

  /// Açık, geri döngü olmayan IPv4 arayüzleri. Hücresel (pdp_ip) ve VPN arayüzleri TV'ye ve PS5'e ulaşmaz.
  static func ipv4Networks() -> [IPv4] { ipv4Networks(includeCellular: false).map(\.network) }

  private static func ipv4Networks(includeCellular: Bool) -> [(name: String, network: IPv4)] {
    var result: [(String, IPv4)] = []
    var list: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&list) == 0, let first = list else { return [] }
    defer { freeifaddrs(list) }
    for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
      let entry = pointer.pointee
      let flags = Int32(entry.ifa_flags)
      guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET), let mask = entry.ifa_netmask,
            flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
      let name = String(cString: entry.ifa_name)
      if !includeCellular, name.hasPrefix("pdp_ip") || name.hasPrefix("utun") || name.hasPrefix("ipsec") { continue }
      let ip = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
      let netmask = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
      func text(_ value: UInt32) -> String { "\(value >> 24 & 0xff).\(value >> 16 & 0xff).\(value >> 8 & 0xff).\(value & 0xff)" }
      let prefix = "\(ip >> 24 & 0xff).\(ip >> 16 & 0xff).\(ip >> 8 & 0xff)."
      result.append((name, IPv4(address: text(ip), broadcast: text(ip | ~netmask), prefixLength: netmask.nonzeroBitCount, prefix24: prefix)))
    }
    return result
  }
}
