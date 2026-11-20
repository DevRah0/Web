// SPDX-License-Identifier: AGPL-3.0-only
import Flutter
import Foundation
import UIKit

/// Flutter arayüzü ile [Engine] arasındaki köprü: "gt/bridge" yöntem kanalı ve "gt/events" durum akışı
/// (Android'deki MainActivity ile aynı yöntemler ve dönüş biçimleri).
final class BridgeChannel: NSObject, FlutterStreamHandler {
  private static var instance: BridgeChannel?
  private let background = DispatchQueue(label: "gt.bridge", attributes: .concurrent)

  static func attach(_ messenger: FlutterBinaryMessenger) {
    let bridge = BridgeChannel()
    instance = bridge
    FlutterMethodChannel(name: "gt/bridge", binaryMessenger: messenger).setMethodCallHandler(bridge.handle)
    FlutterEventChannel(name: "gt/events", binaryMessenger: messenger).setStreamHandler(bridge)
    TvChannel.attach(messenger)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    Engine.shared.onChanged = { state in events(Self.plain(state)) }
    events(Self.plain(Engine.shared.state()))
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    Engine.shared.onChanged = nil
    return nil
  }

  /// Flutter kanalı nil değerleri NSNull olarak bekler.
  static func plain(_ map: [String: Any?]) -> [String: Any] { map.mapValues { $0 ?? NSNull() } }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let store = Store.shared
    let engine = Engine.shared
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "getState": result(Self.plain(engine.state()))
    case "getSetup": result(Self.plain(setup(store)))
    case "getSettings": result(store.settings.toJsonString())
    case "setSettings":
      guard var settings = Settings.fromJsonString(call.arguments as? String) else {
        return result(FlutterError(code: "bad_settings", message: Lang.t("Ayarlar okunamadı", "Could not read the settings"), details: nil))
      }
      // Yalnız yerelin türettiği bayrak: Dart'ın eski kopyası onu silmesin (Quicksand → Standart dönüşünde TV standarda dönsün).
      settings.style.subtitleFontUsed = SubtitleFonts.usedFlag(incoming: settings.style, stored: store.settings.style)
      store.settings = settings
      engine.applySettings()
      result(nil)
    case "setAccountId":
      guard let bytes = (call.arguments as? String).flatMap({ Data(base64Encoded: $0) }), bytes.count == 8 else {
        return result(FlutterError(code: "bad_account", message: Lang.t("Hesap kimliği 8 bayt olmalı", "The account ID must be 8 bytes"), details: nil))
      }
      store.accountId = bytes
      result(nil)
    case "forgetAccount":
      store.accountId = nil
      store.console = nil
      result(nil)
    case "setIntroSeen":
      store.introSeen = call.arguments as? Bool ?? true
      result(nil)
    case "forgetConsole":
      store.console = nil
      result(nil)
    case "discover":
      let hosts = args?["hosts"] as? [String] ?? []
      let timeout = args?["timeoutMs"] as? Int ?? 3000
      background.async {
        let found = engine.discover(hosts: hosts, timeoutMs: timeout)
        DispatchQueue.main.async { result(found) }
      }
    case "register":
      let host = (args?["host"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      let pin = args?["pin"] as? Int ?? -1
      if host.isEmpty || pin < 0 {
        return result(FlutterError(code: "bad_arguments", message: Lang.t("Adres ve kod gerekli", "Address and code are required"), details: nil))
      }
      background.async {
        let outcome = engine.register(host: host, pin: pin)
        DispatchQueue.main.async { result(outcome) }
      }
    case "start":
      engine.start()
      result(nil)
    case "stop":
      engine.stop()
      result(nil)
    case "snapshot":
      let width = call.arguments as? Int ?? 960
      background.async {
        let jpeg = engine.snapshot(width: width)
        DispatchQueue.main.async { result(jpeg.map { FlutterStandardTypedData(bytes: $0) }) }
      }
    case "testSubtitle":
      engine.sendTestSubtitle()
      result(nil)
    case "logs": result(engine.logLines())
    case "history":
      // En yeniden en eskiye: [{"at": ms, "source", "text", "engine"}].
      background.async {
        let list = Engine.history.list()
        DispatchQueue.main.async { result(list) }
      }
    case "clearHistory":
      background.async {
        Engine.history.clear()
        DispatchQueue.main.async { result(nil) }
      }
    case "resetSettings":
      // Ayarlar varsayılana döner; PSN hesabı, PS5 kaydı, DeepL/Gemini anahtarı ve tanıtım bilgisi kalır.
      let fresh = store.resetSettings()
      engine.applySettings()
      result(fresh.toJsonString())
    case "lastCrash": result(CrashLog.last())
    case "clearCrash":
      CrashLog.clear()
      result(nil)
    case "health":
      background.async {
        let report = engine.health()
        DispatchQueue.main.async { result(report) }
      }
    case "demoStart":
      engine.demoStart()
      result(nil)
    case "demoStop":
      engine.demoStop()
      result(nil)
    case "readExtra":
      // Bağımsız değişken: alan sırası (Int) ya da {"index": Int}.
      let index = call.arguments as? Int ?? args?["index"] as? Int ?? -1
      background.async {
        let outcome = engine.readExtra(index: index)
        DispatchQueue.main.async { result(outcome) }
      }
    case "packList":
      // Oyun seçimi listesi: yüklü paketler (gömülü + inen); ilk çağrıda paketler açılır (~1 sn).
      background.async {
        let list = Packs.shared.library.infos
          .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
          .map { ["id": $0.id, "title": $0.title, "entries": $0.entries] as [String: Any] }
        DispatchQueue.main.async { result(list) }
      }
    case "updatePatches":
      background.async {
        let (ok, detail) = Packs.shared.updateCommunityPatches { level, text in engine.log(level, text) }
        DispatchQueue.main.async { result(["ok": ok, "detail": detail]) }
      }
    case "checkOpenRouter":
      let map = call.arguments as? [String: Any]
      let key = map?["key"] as? String ?? ""
      let model = map?["model"] as? String ?? OpenRouterTranslator.defaultModel
      background.async {
        let (ok, detail) = OpenRouterTranslator.check(key: key, model: model)
        DispatchQueue.main.async { result(["ok": ok, "detail": detail]) }
      }
    case "checkGemini":
      // Bağımsız değişken: anahtar metni ya da {"key": ..., "model": ...}; model yoksa ayarlardaki seçilir.
      let map = call.arguments as? [String: Any]
      let key = map?["key"] as? String ?? call.arguments as? String ?? ""
      let model = map?["model"] as? String
      background.async {
        let (ok, detail) = GeminiTranslator.check(key: key, model: model)
        DispatchQueue.main.async { result(["ok": ok, "detail": detail]) }
      }
    case "checkDeepL":
      // Bağımsız değişken: anahtar metni ya da {"key": ...}.
      let map = call.arguments as? [String: Any]
      let key = map?["key"] as? String ?? call.arguments as? String ?? ""
      background.async {
        let (ok, detail) = DeepLTranslator.check(key: key)
        DispatchQueue.main.async { result(["ok": ok, "detail": detail]) }
      }
    case "diagStatus":
      background.async {
        let status = Diagnostics.shared.status()
        DispatchQueue.main.async { result(status) }
      }
    case "diagStart":
      // Bağımsız değişken: {"replaceOldest": Bool} (en eski kayıt silinip yenisi açılır).
      let replace = args?["replaceOldest"] as? Bool ?? false
      background.async {
        let outcome = Diagnostics.shared.start(replaceOldest: replace)
        DispatchQueue.main.async { result(outcome) }
      }
    case "diagStop":
      background.async {
        Diagnostics.shared.stop()
        let status = Diagnostics.shared.status()
        DispatchQueue.main.async { result(status) }
      }
    case "diagDelete":
      let id = args?["id"] as? String ?? call.arguments as? String ?? ""
      background.async {
        let ok = Diagnostics.shared.delete(id)
        DispatchQueue.main.async { result(ok) }
      }
    case "diagShare":
      // Kayıt zip'e paketlenir ve paylaşım sayfası açılır; dönüş {"ok": Bool, "error"?: String}.
      let id = args?["id"] as? String ?? call.arguments as? String ?? ""
      Diagnostics.shared.share(id) { outcome in result(outcome) }
    case "openUrl":
      // Yalnız https adresleri (ör. Gemini anahtar sayfası) Safari'de açılır.
      guard let text = call.arguments as? String, let url = URL(string: text), url.scheme == "https" else { return result(false) }
      UIApplication.shared.open(url) { opened in result(opened) }
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func setup(_ store: Store) -> [String: Any?] {
    let console = store.console
    return [
      "hasAccount": store.accountId != nil,
      "accountId": store.accountId?.base64EncodedString(),
      "consoleHost": console?.host,
      "consoleName": console?.name,
      "introSeen": store.introSeen,
      "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
    ]
  }
}

/// Telefondan TV uygulaması kurma sihirbazının "gt/tv" kanalı. iPhone'dan kurulum henüz yok: adres yardımcıları ve
/// kayıtlı TV çalışır, arama boş döner, kurulum anlaşılır bir hatayla biter.
final class TvChannel: NSObject, FlutterStreamHandler {
  private static var instance: TvChannel?
  private let defaults = UserDefaults.standard

  static func attach(_ messenger: FlutterBinaryMessenger) {
    let channel = TvChannel()
    instance = channel
    FlutterMethodChannel(name: "gt/tv", binaryMessenger: messenger).setMethodCallHandler(channel.handle)
    FlutterEventChannel(name: "gt/tv/events", binaryMessenger: messenger).setStreamHandler(channel)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? { nil }
  func onCancel(withArguments arguments: Any?) -> FlutterError? { nil }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "bundled": result([String: String]())
    case "phoneAddress": result(Network.localAddress())
    case "saved": result(defaults.dictionary(forKey: "tv"))
    case "forget":
      defaults.removeObject(forKey: "tv")
      result(nil)
    case "normalize": result(Self.normalize(call.arguments as? String ?? ""))
    case "find": result([Any]())
    case "check": result(["ready": false, "keyServer": false, "hasKey": false])
    case "install":
      result(["ok": false, "error": "IOS_UNSUPPORTED",
              "detail": Lang.t("TV uygulamasını iPhone'dan kurma henüz yok; şimdilik bilgisayardan ya da Android telefondan kurun.",
                               "Installing the TV app from an iPhone is not available yet; for now install it from a computer or an Android phone.")])
    case "cancel": result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }

  /// Elle yazılan TV adresi (Android'deki ManualAddress.normalize ile aynı kurallar): "192.168.1.5:3000",
  /// "http://192.168.1.5", sonda boşluk ya da Türkçe sayı klavyesindeki "192,168,1,5" temizlenir; adres değilse nil.
  static func normalize(_ input: String) -> String? {
    var text = input.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
    if let scheme = text.range(of: "://") { text = String(text[scheme.upperBound...]) }
    if let end = text.firstIndex(where: { "/?#".contains($0) }) { text = String(text[..<end]) }
    let parts = text.split(separator: ":", omittingEmptySubsequences: false)
    // Tek iki nokta port ayırır; daha fazlası IPv6'dır (TV'ler IPv4 adresiyle eşleşir).
    if parts.count == 2 {
      if parts[1].isEmpty || !parts[1].allSatisfy({ ("0"..."9").contains($0) }) { return nil }
      text = String(parts[0])
    } else if parts.count > 2 {
      return nil
    }
    if text.hasSuffix(".") { text.removeLast() }
    if text.isEmpty { return nil }
    if text.allSatisfy({ ("0"..."9").contains($0) || $0 == "." }) { return ipv4(text) }
    return isHostName(text) ? text.lowercased() : nil
  }

  private static func ipv4(_ text: String) -> String? {
    let octets = text.split(separator: ".", omittingEmptySubsequences: false)
    guard octets.count == 4 else { return nil }
    var values: [Int] = []
    for octet in octets {
      guard (1...3).contains(octet.count), let value = Int(octet), value <= 255 else { return nil }
      values.append(value)
    }
    return values.map(String.init).joined(separator: ".")
  }

  /// Harf, rakam ve tireden oluşan, en az bir harf içeren etiketler (RFC 1123).
  private static func isHostName(_ text: String) -> Bool {
    func letter(_ c: Character) -> Bool { ("a"..."z").contains(c) || ("A"..."Z").contains(c) }
    return text.count <= 253 && text.contains(where: letter) &&
      text.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
        (1...63).contains(label.count) && label.first != "-" && label.last != "-" &&
          label.allSatisfy { letter($0) || ("0"..."9").contains($0) || $0 == "-" }
      }
  }
}
