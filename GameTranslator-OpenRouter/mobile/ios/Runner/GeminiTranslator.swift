// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Google Gemini ile yapay zekâ çevirisi, kullanıcının kendi (ücretsiz alınabilen) anahtarıyla. İstek, yönerge ve yanıt
/// okuma bilgisayar sürümüyle aynı (windows/src/GameTranslator.Translation/AiTranslator.cs → AiRequest; model listesi
/// windows/src/GameTranslator.Core/Resources/ai-models.json). Son birkaç satır bağlam olarak gider.
/// Ücretsiz anahtarın dakikalık sınırı vardır: sınıra yaklaşınca ya da Gemini "çok istek" deyince bu çevirmen bir süre
/// nil döner ve hat yedek motora (Google) geçer; altyazı beklemez.
final class GeminiTranslator: TextTranslator {
  /// ai-models.json'daki ilk (önerilen) model: hızlı, ücretsiz katmanda dakikada 15 istek.
  static let defaultModel = GeminiModels.defaultId
  static let requestsPerMinute = 15
  static let keyPage = "https://aistudio.google.com/apikey"

  static let systemPrompt =
    "You translate English video game subtitles into natural, spoken Turkish, the way people really talk. " +
    "Characters address each other informally (use \"sen\", not \"siz\") unless the line is clearly formal. " +
    "Keep character names, place names and speaker labels such as \"ATREUS:\" exactly as they are. " +
    "Keep line breaks. Keep the meaning and tone; do not add or leave out anything. " +
    "Reply with only the translation, no explanations, notes or quotes."

  /// En son duraklatmanın bitişi (sistem sağlık ekranı için; tüm örnekler ortak, yeni örnek kurulunca sıfırlanır).
  private static let pauseLock = NSLock()
  private static var lastPauseEnd = Date.distantPast

  /// Gemini'nin yedek motora bırakıldığı kalan süre (sn); duraklatma yoksa 0.
  static var pausedSeconds: Int {
    pauseLock.lock(); defer { pauseLock.unlock() }
    return max(0, Int(lastPauseEnd.timeIntervalSinceNow.rounded(.up)))
  }

  private let key: String
  private let model: String
  private let log: (Int, String) -> Void
  private let lock = NSLock()
  private var sent: [Date] = []
  private var pausedUntil = Date.distantPast
  private var context: [(String, String)] = []
  private var warnedKey = false

  /// [model] verilmezse ayarlardaki `geminiModel` kullanılır; bilinmeyen değer varsayılana döner.
  init(key: String, model: String? = nil, log: @escaping (Int, String) -> Void) {
    self.key = key.trimmingCharacters(in: .whitespacesAndNewlines)
    self.model = GeminiModels.resolve(model ?? Store.shared.settings.geminiModel)
    self.log = log
    Self.pauseLock.lock()
    Self.lastPauseEnd = Date.distantPast
    Self.pauseLock.unlock()
  }

  func translate(_ text: String) -> String? { attempt(text).text }

  /// Zincir için deneme: hak dolu ya da duraklatılmışsa istek atılmaz ve `pause` döner (zincir sonraki motora geçer).
  func attempt(_ text: String) -> ChainOutcome {
    guard !key.isEmpty, let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else { return .failed }
    let previous: [(String, String)]
    switch reserve() {
    case .wait(let seconds): return .pause(EnginePause(seconds: seconds, reason: .busy))
    case .go(let context): previous = context
    }

    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6)
    request.httpMethod = "POST"
    request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let body: [String: Any] = [
      "systemInstruction": ["parts": [["text": GeminiStyleNote.compose(Self.systemPrompt, note: Store.shared.settings.geminiStyleNote)]]],
      "contents": [["role": "user", "parts": [["text": Self.userMessage([text], context: previous)]]]],
      "generationConfig": ["maxOutputTokens": 1024],
    ]
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)

    let semaphore = DispatchSemaphore(value: 0)
    var status = 0
    var data: Data?
    let task = URLSession.shared.dataTask(with: request) { d, response, _ in
      status = (response as? HTTPURLResponse)?.statusCode ?? 0
      data = d
      semaphore.signal()
    }
    task.resume()
    if semaphore.wait(timeout: .now() + 7) == .timedOut {
      task.cancel()
      return .unreachable
    }
    switch status {
    case 200:
      break
    case 0:
      return .unreachable
    case 429:
      // Dakikalık hak doldu: Gemini'nin söylediği süre (RetryInfo) kadar, günlük hak bittiyse bir saat yedek motor kullanılır.
      let decision = GeminiRateLimit.decide(data)
      let wait = Int(decision.seconds.rounded())
      pause(decision.seconds, decision.daily
        ? "Gemini günlük hakkı doldu; \(wait / 60) dakika yedek motor kullanılıyor (yarın ya da başka anahtarla yeniden denenir)"
        : "Gemini dakikalık sınırı doldu; \(wait) sn yedek motor kullanılıyor")
      return .pause(EnginePauseRule.gemini(decision))
    case 400, 401, 403:
      lock.lock()
      let first = !warnedKey
      warnedKey = true
      lock.unlock()
      if first { log(0, "Gemini anahtarı kabul edilmedi (HTTP \(status)); anahtarı Ayarlar'dan kontrol edin") }
      pause(300, nil)
      return .pause(EnginePauseRule.geminiKeyRejected)
    default:
      return .failed
    }
    guard let data, let reply = Self.replyText(data), let translated = Self.translations(reply, count: 1)?.first,
          !translated.isEmpty else { return .failed }
    remember(text, translated)
    return .translated(translated)
  }

  /// Ayarlardaki "Kaydet ve dene": anahtarı tek bir deneme çevirisiyle sınar. (başarılı mı, kullanıcıya gösterilecek metin)
  static func check(key: String, model: String? = nil) -> (Bool, String) {
    let model = GeminiModels.resolve(model ?? Store.shared.settings.geminiModel)
    let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
    if key.isEmpty { return (false, Lang.t("Önce anahtarı yapıştır.", "Paste the key first.")) }
    guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
      return (false, Lang.t("Gemini adresi kurulamadı.", "Could not build the Gemini address."))
    }
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
    request.httpMethod = "POST"
    request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let body: [String: Any] = [
      "systemInstruction": ["parts": [["text": GeminiStyleNote.compose(systemPrompt, note: Store.shared.settings.geminiStyleNote)]]],
      "contents": [["role": "user", "parts": [["text": userMessage(["Let's get out of here before they find us."], context: [])]]]],
      "generationConfig": ["maxOutputTokens": 1024],
    ]
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    let semaphore = DispatchSemaphore(value: 0)
    var status = 0
    var data: Data?
    let task = URLSession.shared.dataTask(with: request) { d, response, _ in
      status = (response as? HTTPURLResponse)?.statusCode ?? 0
      data = d
      semaphore.signal()
    }
    task.resume()
    if semaphore.wait(timeout: .now() + 12) == .timedOut {
      task.cancel()
      return (false, Lang.t("Gemini yanıt vermedi. İnternet bağlantını kontrol et.", "Gemini did not respond. Check your internet connection."))
    }
    switch status {
    case 200:
      if let data, let reply = replyText(data), let text = translations(reply, count: 1)?.first, !text.isEmpty {
        return (true, Lang.t("Anahtar çalışıyor. Deneme çevirisi: \(text)", "The key works. Test translation: \(text)"))
      }
      return (false, Lang.t("Gemini yanıt verdi ama çeviri okunamadı. Yeniden dene.", "Gemini replied but the translation could not be read. Try again."))
    case 400, 401, 403:
      return (false, Lang.t("Anahtar kabul edilmedi. Anahtarı eksiksiz kopyaladığından emin ol.", "The key was not accepted. Make sure you copied the whole key."))
    case 429:
      return (true, Lang.t("Anahtar doğru, ama şu an sınır dolu. Bir dakika sonra çeviride kullanılır.", "The key is valid, but the rate limit is full right now. It will be used for translation in a minute."))
    case 0:
      return (false, Lang.t("Gemini'ye ulaşılamadı. İnternet bağlantını kontrol et.", "Could not reach Gemini. Check your internet connection."))
    default:
      return (false, Lang.t("Gemini hata verdi (HTTP \(status)). Biraz sonra yeniden dene.", "Gemini returned an error (HTTP \(status)). Try again shortly."))
    }
  }

  // MARK: - Sınır ve bağlam

  private enum Reservation {
    case go([(String, String)])
    /// Duraklatma ya da dakikalık sınır: bu kadar saniye istek atılmaz.
    case wait(Double)
  }

  /// İstek hakkı varsa bağlamı döner; duraklatma ya da dakikalık sınır varsa kalan süreyi (yedek motora geçilir).
  private func reserve() -> Reservation {
    lock.lock(); defer { lock.unlock() }
    let now = Date()
    if now < pausedUntil { return .wait(max(1, pausedUntil.timeIntervalSince(now))) }
    sent.removeAll { now.timeIntervalSince($0) > 60 }
    if sent.count >= Self.requestsPerMinute {
      let oldest = sent.first ?? now
      return .wait(max(1, 60 - now.timeIntervalSince(oldest)))
    }
    sent.append(now)
    return .go(context)
  }

  private func pause(_ seconds: TimeInterval, _ message: String?) {
    lock.lock()
    let wasPaused = Date() < pausedUntil
    pausedUntil = Date().addingTimeInterval(seconds)
    let until = pausedUntil
    lock.unlock()
    Self.pauseLock.lock()
    Self.lastPauseEnd = until
    Self.pauseLock.unlock()
    if let message, !wasPaused { log(1, message) }
  }

  private func remember(_ source: String, _ translation: String) {
    lock.lock(); defer { lock.unlock() }
    context.append((source, translation))
    if context.count > 4 { context.removeFirst(context.count - 4) }
  }

  // MARK: - İstek ve yanıt (AiRequest ile aynı)

  /// Kullanıcı iletisi: önceki satırlar (yalnız bağlam) ve çevrilecek cümleler.
  static func userMessage(_ sentences: [String], context: [(String, String)]) -> String {
    var parts: [String] = []
    if !context.isEmpty {
      var lines = ["Previous subtitles, for context only (do not translate them again):"]
      for (source, translation) in context {
        lines.append("English: \(source)")
        lines.append("Turkish: \(translation)")
      }
      parts.append(lines.joined(separator: "\n"))
    }
    let list = (try? JSONSerialization.data(withJSONObject: sentences, options: [.withoutEscapingSlashes]))
      .map { String(decoding: $0, as: UTF8.self) } ?? "[]"
    parts.append("Translate each string in this JSON array into Turkish. Reply with only a JSON array of \(sentences.count) " +
                 "Turkish strings in the same order.\n\(list)")
    return parts.joined(separator: "\n\n")
  }

  /// candidates[0].content.parts[].text; "thought": true olan parçalar düşünmedir, alınmaz.
  static func replyText(_ data: Data) -> String? {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let candidates = root["candidates"] as? [[String: Any]],
          let content = candidates.first?["content"] as? [String: Any],
          let parts = content["parts"] as? [[String: Any]] else { return nil }
    let text = parts.filter { ($0["thought"] as? Bool) != true }.compactMap { $0["text"] as? String }.joined()
    return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
  }

  /// Yanıttaki JSON dizisi; tek cümlede model diziyi unutup düz metin dönerse o metin alınır.
  static func translations(_ text: String, count: Int) -> [String]? {
    var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("```") {
      trimmed = trimmed.split(separator: "\n", omittingEmptySubsequences: false).dropFirst()
        .filter { !$0.hasPrefix("```") }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let start = trimmed.firstIndex(of: "["), let end = trimmed.lastIndex(of: "]"), start < end,
       let array = try? JSONSerialization.jsonObject(with: Data(trimmed[start...end].utf8)) as? [Any],
       array.allSatisfy({ $0 is String }) {
      guard array.count == count else { return nil }
      return array.map { ($0 as! String).trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    guard count == 1 else { return nil }
    return [trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))]
  }
}

extension GeminiTranslator: ChainMember {
  var id: String { "gemini" }
}


/// OpenRouter translation provider for the existing GameTranslator iOS pipeline.
/// Preserves the original OCR, PS5 Remote Play, subtitle timing and TV sender.
final class OpenRouterTranslator: TextTranslator {
  static let defaultModel = "tencent/hy-mt2-30b-a3b"
  private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
  private let key: String
  private let model: String
  private let source: String
  private let target: String
  private let lock = NSLock()
  private var context: [(String, String)] = []

  init(key: String, model: String, source: String, target: String) {
    self.key = key.trimmingCharacters(in: .whitespacesAndNewlines)
    self.model = Self.validate(model)
    self.source = source
    self.target = target
  }

  func translate(_ text: String) -> String? { attempt(text).text }

  func attempt(_ text: String) -> ChainOutcome {
    guard !key.isEmpty, source == "en", target == "ar" else { return .failed }
    lock.lock()
    let previous = context
    lock.unlock()
    let userMessage = Self.prompt(text, previous: previous, shortContext: TranslationContext.current)
    guard let (status, data) = Self.call(key: key, model: model, user: userMessage, timeout: 5.5)
    else { return .unreachable }
    switch status {
    case 200:
      guard let value = Self.answer(data), Self.hasArabic(value) else { return .failed }
      lock.lock()
      context.append((text, value))
      if context.count > 4 { context.removeFirst(context.count - 4) }
      lock.unlock()
      return .translated(value)
    case 401, 403: return .pause(EnginePause(seconds: 300, reason: .key))
    case 402: return .pause(EnginePause(seconds: 600, reason: .quota))
    case 429: return .pause(EnginePause(seconds: 30, reason: .busy))
    case 500...599: return .unreachable
    default: return .failed
    }
  }

  private static func validate(_ model: String) -> String {
    switch model {
    case "tencent/hy-mt2-7b", "tencent/hy-mt2-30b-a3b": return model
    default: return defaultModel
    }
  }

  private static let systemPrompt = """
    You are an expert professional translator specializing in AAA video-game localization. \
    Translate from English into natural Modern Standard Arabic. \
    Preserve meaning, emotion, sarcasm, slang, and idioms, not literal word substitutions. \
    Keep speaker names and proper nouns consistent and never invent events or missing words. \
    Write concise cinematic Arabic subtitles, preferably one or two readable lines. \
    For context: 'You sold me out' may mean 'خنتني' or 'وشيت بي'; \
    'cover for you' means 'أتستر عليك'; sarcastic 'Oh, great' can mean 'يا للروعة'. \
    Return ONLY the Arabic translation with no labels, notes, quotation marks or markdown.
    """

  private static func prompt(_ text: String, previous: [(String, String)], shortContext: String?) -> String {
    var lines: [String] = []
    if !previous.isEmpty {
      lines.append("Previous game subtitles: CONTEXT ONLY; do not translate again.")
      for (english, arabic) in previous {
        lines.append("EN: \(english)")
        lines.append("AR: \(arabic)")
      }
    }
    if let shortContext, !shortContext.isEmpty {
      lines.append("Context only: \(String(shortContext.prefix(240)))")
    }
    lines.append("Translate this one subtitle from English into Modern Standard Arabic:")
    lines.append(text)
    return lines.joined(separator: "\n")
  }

  private static func call(key: String, model: String, user: String, timeout: TimeInterval) -> (Int, Data)? {
    var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
    request.httpMethod = "POST"
    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("GameTranslator-iOS", forHTTPHeaderField: "X-Title")
    let note = GeminiStyleNote.clean(Store.shared.settings.geminiStyleNote)
    let system = note.isEmpty ? systemPrompt : systemPrompt + "\nAdditional style preference: " + note
    let messages: [[String: String]] = [
      ["role": "system", "content": system],
      ["role": "user", "content": user]
    ]
    request.httpBody = try? JSONSerialization.data(withJSONObject: [
      "model": model, "messages": messages, "temperature": 0.2,
      "max_tokens": 180, "stream": false
    ] as [String: Any])
    let sem = DispatchSemaphore(value: 0)
    var resultCode = 0
    var resultData: Data?
    let task = URLSession.shared.dataTask(with: request) { data, response, _ in
      resultCode = (response as? HTTPURLResponse)?.statusCode ?? 0
      resultData = data
      sem.signal()
    }
    task.resume()
    if sem.wait(timeout: .now() + timeout + 0.5) == .timedOut {
      task.cancel()
      return nil
    }
    guard let resultData else { return nil }
    return (resultCode, resultData)
  }

  private static func hasArabic(_ text: String) -> Bool {
    text.unicodeScalars.contains {
      (0x0600...0x06FF).contains($0.value) || (0x0750...0x077F).contains($0.value)
    }
  }

  private static func answer(_ data: Data) -> String? {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let choices = root["choices"] as? [[String: Any]],
          let message = choices.first?["message"] as? [String: Any],
          let text = message["content"] as? String else { return nil }
    let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
    guard !result.isEmpty, result.count < 700, !result.hasPrefix("{") else { return nil }
    return result
  }

  /// Test button: one short Arabic translation. The secret is never logged.
  static func check(key: String, model: String) -> (Bool, String) {
    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return (false, "Enter your OpenRouter API key.") }
    let user = "Translate to Modern Standard Arabic: We need to leave before they find us."
    guard let (code, data) = call(key: trimmed, model: validate(model), user: user, timeout: 8)
    else { return (false, "OpenRouter request timed out.") }
    if code == 401 || code == 403 { return (false, "OpenRouter rejected the API key.") }
    if code == 402 { return (false, "Insufficient OpenRouter credits.") }
    if code == 429 { return (false, "Rate limit reached. Try again.") }
    guard code == 200, let text = answer(data), hasArabic(text) else {
      return (false, "OpenRouter returned HTTP \(code) or no Arabic translation.")
    }
    return (true, "OpenRouter connected. Test: \(text)")
  }
}
