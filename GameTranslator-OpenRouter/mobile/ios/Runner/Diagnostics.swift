// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import UIKit

/// Uygulama içi tanı kaydı (Ayarlar › Tanı kaydı): kaydedici (Core/DiagnosticRecorder) ile uygulamanın bağlantısı:
/// kayıt klasörü, oturum bilgisi, gizli değerler, kare kodlama, nabız ve paylaşım sayfası.
/// Kayıtlar Application Support/GameTranslator/tani/<zaman>/ altında, iCloud yedeğine girmez.
final class Diagnostics {
  static let shared = Diagnostics()

  let recorder: DiagnosticRecorder
  private let background = DispatchQueue(label: "gt.diag.export", qos: .userInitiated)
  private let pulseLock = NSLock()
  private var lastAddress: String??
  private var lastFrames = 0
  /// Paylaşım için hazırlanan zip'lerin geçici klasörü (uygulamanın kendi tmp'si; açılışta ve paylaşımdan sonra silinir).
  private let exportFolder = FileManager.default.temporaryDirectory.appendingPathComponent("tani-paylas", isDirectory: true)

  private init() {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let root = support.appendingPathComponent("GameTranslator", isDirectory: true).appendingPathComponent("tani", isDirectory: true)
    recorder = DiagnosticRecorder(root: root)
    recorder.frameGrabber = { () -> DiagnosticFrameEncoder? in
      // Kilit altında çağrılır: yalnız son karenin kopyası alınır (veri paylaşılır), kodlama kare kuyruğunda.
      guard let frame: Frame = Engine.shared.currentFrame() else { return nil }
      let encoder: DiagnosticFrameEncoder = { () -> Data? in Diagnostics.jpeg(frame) }
      return encoder
    }
    recorder.onPulse = { [weak self] in self?.pulse() }
    recorder.onChange = { Engine.shared.notifyChanged() }
    Diag.recorder = recorder
  }

  /// Açılışta: yarım kalan kayıtlar mühürlenir, eski paylaşım dosyaları silinir (arka planda).
  func bootstrap() {
    background.async {
      try? FileManager.default.removeItem(at: self.exportFolder)
      self.recorder.sealInterrupted()
      Engine.shared.notifyChanged()
    }
  }

  // MARK: - Köprü

  /// Kaydı başlatır. Dönüş: {"ok": true, "id"} ya da {"ok": false, "error": "busy"|"full"|"disk"|"io", "detail", "oldest"}.
  func start(replaceOldest: Bool) -> [String: Any] {
    let engine = Engine.shared
    let settings = Store.shared.settings
    recorder.secrets = Self.secrets(settings)
    pulseLock.lock()
    lastAddress = .some(Network.localAddress())
    lastFrames = engine.frameCount
    pulseLock.unlock()
    let result = recorder.start(version: Self.version, replaceOldest: replaceOldest, fields: sessionFields(settings))
    switch result {
    case .started(let id):
      engine.log(2, "tanı kaydı başladı: \(id)")
      return ["ok": true, "id": id]
    case .busy:
      return ["ok": false, "error": "busy", "detail": Lang.t("Zaten bir kayıt sürüyor.", "A recording is already running.")]
    case .full(let oldest):
      return ["ok": false, "error": "full", "oldest": oldest,
              "detail": Lang.t("En çok \(recorder.limits.maxSessions) kayıt saklanır; yenisi için en eskisi silinmeli.",
                               "At most \(recorder.limits.maxSessions) recordings are kept; the oldest must be deleted for a new one.")]
    case .lowDisk(let free):
      let mb: Int64 = max(0, free / (1024 * 1024))
      let need: Int64 = recorder.limits.minFreeBytes / (1024 * 1024)
      return ["ok": false, "error": "disk",
              "detail": Lang.t("Telefonda yeterli boş alan yok (\(mb) MB). En az \(need) MB gerekli.",
                               "Not enough free space on the phone (\(mb) MB). At least \(need) MB is needed.")]
    case .failed(let detail):
      engine.log(1, "tanı kaydı açılamadı: \(detail)")
      return ["ok": false, "error": "io", "detail": Lang.t("Kayıt dosyası açılamadı.", "The recording file could not be opened.")]
    }
  }

  func stop() {
    let wasRecording = recorder.isRecording
    recorder.stop(.manual)
    if wasRecording { Engine.shared.log(2, "tanı kaydı durduruldu") }
  }

  /// Uygulama kapanırken (kayıt düzgün kapansın).
  func terminate() { recorder.stop(.terminated) }

  /// Kayıt durumu ve saklanan kayıtlar (tanı sayfası).
  func status() -> [String: Any] {
    let s = recorder.status
    let list: [[String: Any]] = recorder.sessions().map { summary in
      ["id": summary.id, "version": summary.version, "startedAt": summary.startedAt, "seconds": summary.seconds,
       "events": summary.events, "frames": summary.frames, "bytes": summary.bytes, "reason": summary.reason,
       "interrupted": summary.interrupted]
    }
    let limits = recorder.limits
    return [
      "recording": s.recording,
      "id": s.id,
      "seconds": s.seconds,
      "events": s.events,
      "bytes": s.bytes,
      "frames": s.frames,
      "lastStop": s.lastStop?.rawValue ?? "",
      "stops": s.stops,
      "limits": ["seconds": limits.maxSeconds, "bytes": limits.maxBytes, "frames": limits.maxFrames,
                 "sessions": limits.maxSessions] as [String: Any],
      "sessions": list,
    ]
  }

  /// Ana ekrandaki gösterge için (EngineState.diagnostics; ucuz: yalnız bellekteki sayaçlar).
  func stateMap() -> [String: Any] {
    let s = recorder.status
    return ["recording": s.recording, "seconds": Int(s.seconds), "events": s.events, "bytes": s.bytes, "frames": s.frames,
            "lastStop": s.lastStop?.rawValue ?? "", "stops": s.stops]
  }

  @discardableResult
  func delete(_ id: String) -> Bool { recorder.delete(id) }

  /// Kaydı zip'e paketleyip iOS paylaşım sayfasını açar. [done]: ana iş parçacığında {"ok": Bool, "error"?: String}.
  func share(_ id: String, done: @escaping ([String: Any]) -> Void) {
    background.async {
      guard let folder = self.recorder.folder(for: id) else {
        return DispatchQueue.main.async { done(["ok": false, "error": Lang.t("Kayıt bulunamadı.", "Recording not found.")]) }
      }
      let version = self.recorder.summary(for: id).map(\.version).flatMap { $0.isEmpty ? nil : $0 } ?? Self.version
      let base = DiagnosticNames.exportBase(version: version, sessionId: id)
      let manager = FileManager.default
      try? manager.removeItem(at: self.exportFolder)
      let url = self.exportFolder.appendingPathComponent(base + ".zip")
      do {
        try manager.createDirectory(at: self.exportFolder, withIntermediateDirectories: true)
        let sink = try FileZipSink(url: url)
        defer { sink.close() }
        try DiagnosticExport.write(folder: folder, root: base, to: sink)
      } catch {
        try? manager.removeItem(at: url)
        Engine.shared.log(1, "tanı kaydı paketlenemedi: \(error)")
        return DispatchQueue.main.async {
          done(["ok": false, "error": Lang.t("Kayıt paketlenemedi.", "The recording could not be packed.")])
        }
      }
      DispatchQueue.main.async {
        guard self.present(url) else {
          try? manager.removeItem(at: url)
          return done(["ok": false, "error": Lang.t("Paylaşım sayfası açılamadı.", "The share sheet could not be opened.")])
        }
        done(["ok": true])
      }
    }
  }

  /// Ana iş parçacığında: paylaşım sayfası (iPad'de ekranın ortasına bağlı açılır pencere).
  private func present(_ url: URL) -> Bool {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let windows = scenes.flatMap { $0.windows }
    guard let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first, var top = window.rootViewController else { return false }
    while let presented = top.presentedViewController { top = presented }
    let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    if let popover = sheet.popoverPresentationController {
      popover.sourceView = top.view
      popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
      popover.permittedArrowDirections = []
    }
    sheet.completionWithItemsHandler = { _, _, _, _ in
      // Paylaşım bitti ya da vazgeçildi: geçici zip silinir (kayıt telefonda kalır).
      try? FileManager.default.removeItem(at: url)
    }
    top.present(sheet, animated: true)
    return true
  }

  // MARK: - Olay yardımcıları

  /// Ayar değişikliği: hangi alanlar değişti (gizli alanların değeri yazılmaz); gizli değer listesi yenilenir.
  func settingsChanged(before: Settings, after: Settings) {
    guard Diag.on else { return }
    recorder.secrets = Self.secrets(after)
    let old = before.toJson(), new = after.toJson()
    let changed = DiagnosticPrivacy.changes(before: old, after: new)
    guard !changed.isEmpty else { return }
    Diag.emit("engine") {
      ["what": .string("settings"), "changed": DiagValue.strings(changed),
       "values": .object(DiagnosticPrivacy.values(new, paths: changed))]
    }
  }

  /// Nabız (kayıt sürerken ~10 sn'de bir, yardımcı kuyrukta): durum özeti ve kare; /hello istek özeti; Wi-Fi adresi değişimi.
  private func pulse() {
    let engine = Engine.shared
    let address = Network.localAddress()
    pulseLock.lock()
    let previous = lastAddress
    lastAddress = .some(address)
    let framesBefore = lastFrames
    lastFrames = engine.frameCount
    pulseLock.unlock()
    let frames = engine.frameCount
    let hello = engine.server.takeHelloSummary()
    let health = engine.reader?.health ?? ReaderHealth()
    Diag.emit("pulse", frame: "pulse") {
      var fields: DiagFields = ["phase": .string(engine.phase), "running": .bool(engine.running), "demo": .bool(engine.demoActive)]
      fields["tvClients"] = DiagValue.int(engine.server.connectedClients)
      fields["serverReady"] = DiagValue.bool(engine.server.isReady)
      fields["framesTotal"] = DiagValue.int(frames)
      fields["framesSinceLastPulse"] = DiagValue.int(max(0, frames - framesBefore))
      fields["frameSize"] = DiagValue.array([.int(engine.frameWidth), .int(engine.frameHeight)])
      fields["lastOcrMs"] = DiagValue.int(health.lastReadMs)
      fields["stuckRecoveries"] = DiagValue.int(health.stuckRecoveries)
      fields["lastRead"] = DiagValue.string(engine.lastRead)
      fields["address"] = DiagValue.optional(address)
      return fields
    }
    if hello.count > 0 {
      Diag.emit("tv") {
        ["what": .string("hello"), "count": .int(hello.count), "seconds": .double(hello.seconds), "from": DiagValue.strings(hello.peers)]
      }
    }
    if let previous, previous != address {
      Diag.emit("engine") { ["what": .string("address"), "old": DiagValue.optional(previous), "new": DiagValue.optional(address)] }
    }
  }

  // MARK: - Oturum bilgisi

  static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }
  static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "" }

  /// Cihaz modeli kimliği ("iPhone15,2").
  static var deviceModel: String {
    var info = utsname()
    uname(&info)
    return withUnsafeBytes(of: &info.machine) { raw in
      String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
    }
  }

  private func sessionFields(_ settings: Settings) -> DiagFields {
    let engine = Engine.shared
    let store = Store.shared
    let os = ProcessInfo.processInfo.operatingSystemVersion
    var fields: DiagFields = ["app": .object(["version": .string(Self.version), "build": .string(Self.build)])]
    fields["os"] = DiagValue.object(["name": .string("iOS"), "version": .string("\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")])
    fields["device"] = DiagValue.string(Self.deviceModel)
    fields["frameSize"] = DiagValue.array([.int(engine.frameWidth), .int(engine.frameHeight)])
    fields["uiLanguage"] = DiagValue.object(["setting": .string(settings.uiLanguage), "effective": .string(Lang.provider())])
    fields["effectiveEngine"] = DiagValue.string(Engine.effectiveEngine(settings))
    let settingsJson: [String: Any] = settings.toJson()
    fields["settings"] = DiagnosticPrivacy.settings(settingsJson)
    // Çalışma anı denetimi: Settings'e izin listesinde olmayan alan eklendiyse değeri yazılmaz, burada adı listelenir.
    let unclassified: [String] = DiagnosticPrivacy.unclassifiedPaths(settingsJson)
    fields["unclassifiedSettings"] = DiagValue.strings(unclassified)
    if !unclassified.isEmpty {
      Engine.shared.log(1, "tanı kaydı: sınıflanmamış ayar alanları (değerleri yazılmadı): \(unclassified.joined(separator: ", "))")
    }
    let console = store.console
    fields["console"] = DiagValue.object(["paired": .bool(console != nil), "name": DiagValue.optional(console?.name),
                                 "host": DiagValue.optional(console?.host)])
    fields["psnAccount"] = DiagValue.object(["set": .bool(store.accountId != nil)])
    fields["engine"] = DiagValue.object(["phase": .string(engine.phase), "running": .bool(engine.running), "demo": .bool(engine.demoActive),
                                "tvClients": .int(engine.server.connectedClients), "serverReady": .bool(engine.server.isReady),
                                "address": DiagValue.optional(Network.localAddress())])
    fields["frameJpeg"] = DiagValue.object(["longEdge": .int(Self.jpegLongEdge), "quality": .double(Self.jpegQuality)])
    return fields
  }

  /// Satırlardan silinecek gizli değerler: API anahtarları, PSN hesap kimliği, PS5 kayıt anahtarları (her biçimiyle).
  private static func secrets(_ settings: Settings) -> [String] {
    var out = [settings.deepLKey, settings.geminiKey, settings.openRouterKey]
    let store = Store.shared
    if let account = store.accountId {
      out.append(account.base64EncodedString())
      out.append(account.map { String(format: "%02x", $0) }.joined())
      // Hesap kimliği sayı olarak da (küçük ve büyük uçlu 8 bayt).
      out.append(String(account.reversed().reduce(UInt64(0)) { $0 << 8 | UInt64($1) }))
      out.append(String(account.reduce(UInt64(0)) { $0 << 8 | UInt64($1) }))
    }
    if let console = store.console {
      out.append(console.registKey.base64EncodedString())
      out.append(console.morning.base64EncodedString())
      out.append(console.morning.map { String(format: "%02x", $0) }.joined())
      let end = console.registKey.firstIndex(of: 0) ?? console.registKey.endIndex
      if let text = String(data: console.registKey[console.registKey.startIndex..<end], encoding: .ascii) { out.append(text) }
    }
    var usable: [String] = []
    for value in out {
      let trimmed: String = value.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.count >= DiagnosticPrivacy.minSecretLength { usable.append(trimmed) }
    }
    return usable
  }

  // MARK: - Kare

  static let jpegLongEdge = 960
  static let jpegQuality = 0.5

  /// Kareyi uzun kenarı ~960 piksele küçültüp JPEG'e çevirir (kare kuyruğunda).
  static func jpeg(_ frame: Frame) -> Data? {
    guard frame.width > 0, frame.height > 0, let image = frame.cgImage() else { return nil }
    let scale = min(1, Double(jpegLongEdge) / Double(max(frame.width, frame.height)))
    let width = max(1, Int((Double(frame.width) * scale).rounded()))
    let height = max(1, Int((Double(frame.height) * scale).rounded()))
    let scaled = scale < 1 ? (VisionReader.resized(image, width: width, height: height) ?? image) : image
    return UIImage(cgImage: scaled).jpegData(compressionQuality: CGFloat(jpegQuality))
  }
}
