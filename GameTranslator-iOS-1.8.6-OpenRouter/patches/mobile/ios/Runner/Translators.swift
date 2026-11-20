// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Bloklayan HTTP isteği (çeviri iş parçacığında çağrılır). Zaman aşımında ya da hatada nil.
private func fetch(_ request: URLRequest) -> (Int, Data)? {
  let semaphore = DispatchSemaphore(value: 0)
  var result: (Int, Data)?
  let task = URLSession.shared.dataTask(with: request) { data, response, _ in
    if let data, let http = response as? HTTPURLResponse { result = (http.statusCode, data) }
    semaphore.signal()
  }
  task.resume()
  if semaphore.wait(timeout: .now() + request.timeoutInterval + 1) == .timedOut {
    task.cancel()
    return nil
  }
  return result
}

/// Google'ın anahtarsız çeviri ucu (Android'deki GoogleGtxTranslator ve Windows'taki GoogleGtxTranslator ile aynı).
/// Bir uç yanıt vermezse ya da hız sınırına takılırsa sıradaki yedek uç denenir; hiçbiri çevirmezse nil döner.
final class GoogleGtxTranslator: TextTranslator {
  private let source: String
  private let target: String

  init(source: String, target: String) {
    self.source = LanguageCodes.google(source)
    self.target = LanguageCodes.google(target)
  }

  /// Kısa satırın önceki satırı bağlam olarak hat tarafından konduysa ("###" ayraçlı birleşik çeviri) kullanılır.
  func translate(_ text: String) -> String? {
    ContextSplit.translate(text, context: TranslationContext.current) { translateOne($0) }
  }

  private func translateOne(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return "" }
    // Java'daki URLEncoder gibi: yalnız ASCII harf/rakam ve "-._*" olduğu gibi kalır (Türkçe harfler kodlanır).
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._*")
    guard let query = trimmed.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
    let endpoints = [
      "https://translate.googleapis.com/translate_a/single?client=gtx&sl=\(source)&tl=\(target)&dt=t&q=\(query)",
      "https://translate.googleapis.com/translate_a/single?client=dict-chrome-ex&sl=\(source)&tl=\(target)&dt=t&q=\(query)",
      "https://clients5.google.com/translate_a/t?client=dict-chrome-ex&sl=\(source)&tl=\(target)&q=\(query)",
    ]
    for endpoint in endpoints {
      guard let url = URL(string: endpoint) else { continue }
      // Üç uç sırayla denenebildiği için süreler kısa tutulur: altyazı ekrandan gitmeden yedeğe geçilsin.
      var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 3.5)
      request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                       forHTTPHeaderField: "User-Agent")
      guard let (status, data) = fetch(request), status == 200, let translated = Self.parse(data), !translated.isEmpty else { continue }
      return translated
    }
    return nil
  }

  /// İki yanıt biçimi vardır: `[[["çeviri","kaynak",...],...],...]` (cümle parçaları birleştirilir) ve yedek uçtaki
  /// `["çeviri"]`.
  static func parse(_ data: Data) -> String? {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [Any], let first = root.first else { return nil }
    let text: String
    if let sentences = first as? [Any] {
      text = sentences.compactMap { ($0 as? [Any])?.first as? String }.filter { $0 != "null" }.joined()
        .trimmingCharacters(in: .whitespacesAndNewlines)
    } else {
      text = (first as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    return text.isEmpty ? nil : decodeEntities(text)
  }

  /// Yanıttaki HTML varlıkları (&amp;, &#39; ...) düz metne çevrilir (Android'deki Html.fromHtml karşılığı).
  static func decodeEntities(_ text: String) -> String {
    guard text.contains("&") else { return text }
    let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}"]
    var out = ""
    var index = text.startIndex
    while index < text.endIndex {
      if text[index] == "&", let semicolon = text[index...].prefix(10).firstIndex(of: ";") {
        let name = String(text[text.index(after: index)..<semicolon])
        var replacement: String?
        if name.hasPrefix("#x") || name.hasPrefix("#X"), let code = UInt32(name.dropFirst(2), radix: 16), let scalar = Unicode.Scalar(code) {
          replacement = String(Character(scalar))
        } else if name.hasPrefix("#"), let code = UInt32(name.dropFirst()), let scalar = Unicode.Scalar(code) {
          replacement = String(Character(scalar))
        } else {
          replacement = named[name]
        }
        if let replacement {
          out += replacement
          index = text.index(after: semicolon)
          continue
        }
      }
      out.append(text[index])
      index = text.index(after: index)
    }
    return out
  }
}

/// DeepL API (kullanıcının kendi anahtarıyla). ":fx" ile biten anahtar ücretsiz uca gider.
final class DeepLTranslator: TextTranslator {
  private let key: String
  private let source: String?
  private let target: String?

  init(key: String, source: String, target: String) {
    self.key = key.trimmingCharacters(in: .whitespacesAndNewlines)
    self.source = LanguageCodes.deepLSource(source)
    self.target = LanguageCodes.deepLTarget(target)
  }

  func translate(_ text: String) -> String? { attempt(text).text }

  /// Zincir için deneme: durum kodu (456 kota dolu, 403 anahtar reddedildi, 429 çok istek) bekleme olarak bildirilir.
  /// Ağ hatası, zaman aşımı ve boş cevap yalnız `failed` döner.
  func attempt(_ text: String) -> ChainOutcome {
    // DeepL bu dili desteklemiyorsa istek atılmaz; hat Google'a düşer.
    guard let source, let target else { return .failed }
    let host = key.hasSuffix(":fx") ? "api-free.deepl.com" : "api.deepl.com"
    guard let url = URL(string: "https://\(host)/v2/translate") else { return .failed }
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6)
    request.httpMethod = "POST"
    request.setValue("DeepL-Auth-Key \(key)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    var body: [String: Any] = ["text": [text], "source_lang": source, "target_lang": target]
    // Kısa satırın önceki satırı: DeepL `context` parametresi çevrilmez ve faturalandırılmaz (API belgesi).
    if let context = TranslationContext.current, !context.isEmpty { body["context"] = context }
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    guard let (status, data) = fetch(request) else { return .unreachable }
    if let pause = EnginePauseRule.deepL(status: status) { return .pause(pause) }
    guard status == 200,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let translations = json["translations"] as? [[String: Any]],
          let translated = translations.first?["text"] as? String,
          !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .failed }
    return .translated(translated)
  }

  /// Ayardaki "Kaydet ve dene": `GET /v2/usage` ile anahtarı sınar (çeviri yapmaz, kota harcamaz).
  /// (başarılı mı, kullanıcıya gösterilecek metin)
  static func check(key: String) -> (Bool, String) {
    let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
    if key.isEmpty { return DeepLCheck.emptyKey }
    let host = key.hasSuffix(":fx") ? "api-free.deepl.com" : "api.deepl.com"
    guard let url = URL(string: "https://\(host)/v2/usage") else { return DeepLCheck.unreachable }
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
    request.httpMethod = "GET"
    request.setValue("DeepL-Auth-Key \(key)", forHTTPHeaderField: "Authorization")
    guard let (status, data) = fetch(request) else { return DeepLCheck.unreachable }
    return DeepLCheck.outcome(status: status, body: data)
  }
}

extension DeepLTranslator: ChainMember {
  var id: String { "deepl" }
}

#if canImport(Translation)
import Translation
#endif

/// Cihaz üstünde çeviri: Apple'ın Translation çatısı (Android'deki ML Kit'in karşılığı). İnternetsiz çalışır.
/// iOS 26+ gerekir ve dil modelleri telefonda indirilmiş olmalı (Ayarlar › Uygulamalar › Çeviri › İndirilen Diller);
/// uygulama ekran açmadan modeli indiremez. Kullanılamıyorsa her çağrı nil döner.
final class AppleTranslator: TextTranslator {
  private let source: String
  private let target: String
  private let lock = NSLock()
  private var session: AnyObject?
  private var checked = false
  private var usable = false
  private let log: (Int, String) -> Void

  init(source: String, target: String, log: @escaping (Int, String) -> Void) {
    self.source = LanguageCodes.apple(source)
    self.target = LanguageCodes.apple(target)
    self.log = log
  }

  /// Dil çifti indirilmiş mi, oturum kurulabiliyor mu (bloklar; ilk çağrıda bir kez bakılır).
  func prepare() -> Bool {
    lock.lock(); defer { lock.unlock() }
    if checked { return usable }
    checked = true
    #if canImport(Translation)
    if #available(iOS 26.0, *) {
      let from = Locale.Language(identifier: source)
      let to = Locale.Language(identifier: target)
      let semaphore = DispatchSemaphore(value: 0)
      var status: LanguageAvailability.Status = .unsupported
      Task.detached {
        status = await LanguageAvailability().status(from: from, to: to)
        semaphore.signal()
      }
      _ = semaphore.wait(timeout: .now() + 10)
      switch status {
      case .installed:
        session = TranslationSession(installedSource: from, target: to)
        usable = true
        log(2, "cihaz üstü çeviri hazır (Apple, \(source)→\(target))")
      case .supported:
        log(1, "cihaz üstü çeviri için dil indirilmemiş: Ayarlar › Uygulamalar › Çeviri › İndirilen Diller'den \(source) ve \(target) indirilmeli")
      default:
        log(1, "cihaz üstü çeviri bu dil çiftini desteklemiyor: \(source)→\(target)")
      }
    } else {
      log(1, "cihaz üstü çeviri iOS 26 ister")
    }
    #endif
    return usable
  }

  func translate(_ text: String) -> String? {
    ContextSplit.translate(text, context: TranslationContext.current) { translateOne($0) }
  }

  private func translateOne(_ text: String) -> String? {
    guard prepare() else { return nil }
    #if canImport(Translation)
    if #available(iOS 26.0, *), let session = session as? TranslationSession {
      let semaphore = DispatchSemaphore(value: 0)
      var result: String?
      Task.detached {
        result = try? await session.translate(text).targetText
        semaphore.signal()
      }
      if semaphore.wait(timeout: .now() + 8) == .timedOut { return nil }
      let trimmed = result?.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed?.isEmpty == false ? trimmed : nil
    }
    #endif
    return nil
  }
}


// OpenRouter is an opt-in translation engine. It does not alter PS5 capture, OCR,
// subtitle layout or TV transport. Only the original subtitle text is sent.
final class OpenRouterTranslator: TextTranslator, ChainMember {
  static let model = "tencent/hy-mt2-30b-a3b"
  var id: String { "openrouter" }
  private let key: String
  private let source: String
  private let target: String
  private let memoryLock = NSLock()
  private var previous: [(String, String)] = []
  private var previousAt = Date.distantPast

  init(key: String, source: String, target: String) {
    self.key = key.trimmingCharacters(in: .whitespacesAndNewlines)
    self.source = source
    self.target = target
  }

  func translate(_ text: String) -> String? { attempt(text).text }

  func attempt(_ text: String) -> ChainOutcome {
    guard !key.isEmpty, source == "en", target == "ar",
          let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") else { return .failed }
    memoryLock.lock()
    if Date().timeIntervalSince(previousAt) > 90 { previous.removeAll() }
    let prior = previous.suffix(6).map { "English: \($0.0)\nArabic: \($0.1)" }.joined(separator: "\n")
    memoryLock.unlock()
    let context = (prior.isEmpty ? (TranslationContext.current ?? "") : prior).prefix(1600)
    let instruction = """
      Translate English video-game dialogue into polished, natural Modern Standard Arabic,
      using the quality and clarity expected of professional Arabic game localization.
      Preserve the speaker's emotions, sarcasm, intent, and idiomatic meanings;
      never translate English idioms literally. Do not invent information, speakers, or events.
      Preserve the identity of character names and in-game terminology.
      Keep Arabic subtitles concise and readable without losing essential meaning.
      Treat previous lines as context ONLY; translate the CURRENT line ONLY.
      Output only the Arabic subtitle, with no notes, markdown, or labels.
      """
    let prompt = context.isEmpty
      ? "CURRENT ENGLISH SUBTITLE:\n\(text)"
      : "PREVIOUS DIALOGUE (context only):\n\(context)\n\nCURRENT ENGLISH SUBTITLE:\n\(text)"
    let body: [String: Any] = [
      "model": Self.model,
      "messages": [
        ["role": "system", "content": instruction],
        ["role": "user", "content": prompt],
      ],
      "temperature": 0.15,
      "max_tokens": 260,
      "stream": false,
    ]
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6)
    request.httpMethod = "POST"
    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("GameTranslator-iOS-1.8.6", forHTTPHeaderField: "X-Title")
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    guard let (status, data) = fetch(request) else { return .unreachable }
    switch status {
    case 401, 403: return .pause(EnginePause(seconds: 300, reason: .key))
    case 402: return .pause(EnginePause(seconds: 300, reason: .quota))
    case 429: return .pause(EnginePause(seconds: 60, reason: .busy))
    case 200: break
    default: return .failed
    }
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let choices = root["choices"] as? [[String: Any]],
          let message = choices.first?["message"] as? [String: Any],
          let output = message["content"] as? String else { return .failed }
    let translated = output.trimmingCharacters(in: .whitespacesAndNewlines)
    let hasArabic = translated.unicodeScalars.contains { (0x0600...0x06FF).contains(Int($0.value)) }
    guard !translated.isEmpty, hasArabic else { return .failed }
    memoryLock.lock()
    previous.append((String(text.prefix(500)), String(translated.prefix(500))))
    if previous.count > 6 { previous.removeFirst(previous.count - 6) }
    previousAt = Date()
    memoryLock.unlock()
    return .translated(translated)
  }

  // Test uses one short, billable inference call. The raw API key is never logged.
  static func check(key: String) -> (Bool, String) {
    let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { return (false, "Enter an OpenRouter API key.") }
    switch OpenRouterTranslator(key: cleaned, source: "en", target: "ar").attempt("He betrayed me!") {
    case .translated:
      return (true, "OpenRouter works. Your key is stored securely on this iPhone.")
    case .pause(let pause):
      return (false, pause.reason == .quota ? "OpenRouter credit is unavailable." :
        pause.reason == .key ? "OpenRouter rejected the API key." : "OpenRouter rate limit reached.")
    case .unreachable:
      return (false, "OpenRouter connection timed out.")
    case .failed:
      return (false, "OpenRouter did not return a valid Arabic translation.")
    }
  }
}
