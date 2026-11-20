// SPDX-License-Identifier: AGPL-3.0-only
// Tanı kaydının (Ayarlar › Tanı kaydı) saf parçaları: olay JSON'u, gizli alan süzme, sınırlar ve yarım kayıt okuma.
// Yalnız iOS'ta; Kotlin karşılığı yok. Yalnız Foundation.
import Foundation

/// Tanı kaydındaki bir JSON değeri. Nesne alanlarının sırası korunur (çıktı kararlı ve okunur).
/// `indirect`: dizi ve nesne durumları kutulanır; DiagValue ↔ DiagFields özyinelemesi tip yerleşiminde döngü kurmasın.
indirect enum DiagValue {
  case null
  case bool(Bool)
  case int(Int)
  case double(Double)
  case string(String)
  case array([DiagValue])
  case object(DiagFields)

  /// Bu uzunluğu (UTF-8 bayt) aşan metin kısaltılır: tek bir dev günlük satırı dosyayı şişirmesin.
  static let maxStringBytes = 8192

  /// Kutu: [sol, üst, sağ, alt] (0–1, dört basamak); yoksa null.
  static func box(_ b: TextBox?) -> DiagValue {
    guard let b else { return DiagValue.null }
    let edges: [DiagValue] = [DiagValue.double(b.left), DiagValue.double(b.top), DiagValue.double(b.right),
                              DiagValue.double(b.bottom)]
    return DiagValue.array(edges)
  }

  static func strings(_ list: [String]) -> DiagValue {
    var items: [DiagValue] = []
    for text in list { items.append(DiagValue.string(text)) }
    return DiagValue.array(items)
  }

  static func doubles(_ list: [Double]) -> DiagValue {
    var items: [DiagValue] = []
    for number in list { items.append(DiagValue.double(number)) }
    return DiagValue.array(items)
  }

  static func optional(_ value: Double?) -> DiagValue {
    guard let value else { return DiagValue.null }
    return DiagValue.double(value)
  }

  static func optional(_ value: String?) -> DiagValue {
    guard let value else { return DiagValue.null }
    return DiagValue.string(value)
  }

  /// JSON metni.
  var json: String {
    var out = ""
    write(to: &out)
    return out
  }

  func write(to out: inout String) {
    switch self {
    case .null: out += "null"
    case .bool(let value): out += value ? "true" : "false"
    case .int(let value): out += String(value)
    case .double(let value): out += DiagValue.number(value)
    case .string(let value): out += SubtitleWire.jsonString(DiagValue.clip(value))
    case .array(let items):
      out += "["
      for (index, item) in items.enumerated() {
        if index > 0 { out += "," }
        item.write(to: &out)
      }
      out += "]"
    case .object(let fields): fields.write(to: &out)
    }
  }

  /// Dört basamağa yuvarlanmış sayı, sondaki sıfırlar atılır; sonlu değilse null (JSON'da NaN yok).
  static func number(_ value: Double) -> String {
    guard value.isFinite else { return "null" }
    var text = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value)
    if text.contains(".") {
      while text.hasSuffix("0") { text.removeLast() }
      if text.hasSuffix(".") { text.removeLast() }
    }
    return text == "-0" ? "0" : text
  }

  static func clip(_ text: String) -> String {
    guard text.utf8.count > maxStringBytes else { return text }
    var kept = ""
    var bytes = 0
    for character in text {
      bytes += String(character).utf8.count
      if bytes > maxStringBytes - 16 { break }
      kept.append(character)
    }
    return kept + "…[kısaltıldı]"
  }
}

/// Nesnenin bir alanı.
struct DiagField {
  let key: String
  var value: DiagValue
}

/// Sıralı nesne alanları. `["what": .string("send"), "count": .int(2)]` biçiminde yazılır.
struct DiagFields: ExpressibleByDictionaryLiteral {
  // İlişkili tipler açık: çıkarıma bırakılınca DiagValue ile karşılıklı başvuru tip denetleyicide döngü oluyordu.
  typealias Key = String
  typealias Value = DiagValue

  private(set) var items: [DiagField] = []

  init() {}

  init(dictionaryLiteral elements: (String, DiagValue)...) {
    var collected: [DiagField] = []
    for element in elements { collected.append(DiagField(key: element.0, value: element.1)) }
    items = collected
  }

  var isEmpty: Bool { items.isEmpty }

  private func index(of key: String) -> Int? {
    for (position, item) in items.enumerated() where item.key == key { return position }
    return nil
  }

  /// Alan ekler; aynı ad varsa değeri değiştirir; nil atanırsa alanı siler.
  subscript(key: String) -> DiagValue? {
    get {
      guard let position = index(of: key) else { return nil }
      return items[position].value
    }
    set {
      if let position = index(of: key) {
        if let newValue {
          items[position].value = newValue
        } else {
          items.remove(at: position)
        }
      } else if let newValue {
        items.append(DiagField(key: key, value: newValue))
      }
    }
  }

  func write(to out: inout String) {
    out += "{"
    for (index, item) in items.enumerated() {
      if index > 0 { out += "," }
      out += SubtitleWire.jsonString(item.key)
      out += ":"
      item.value.write(to: &out)
    }
    out += "}"
  }

  var json: String {
    var out = ""
    write(to: &out)
    return out
  }
}

/// events.jsonl'deki bir satır: `{"seq":12,"t":3400,"type":"read",...}` ve satır sonu. [t]: kaydın başından ms.
enum DiagnosticLine {
  static let reserved: Set<String> = ["seq", "t", "type"]

  static func encode(seq: Int, t: Int, type: String, fields: DiagFields) -> String {
    var out = "{\"seq\":\(seq),\"t\":\(t),\"type\":" + SubtitleWire.jsonString(type)
    for item in fields.items where !reserved.contains(item.key) {
      out += ","
      out += SubtitleWire.jsonString(item.key)
      out += ":"
      item.value.write(to: &out)
    }
    out += "}\n"
    return out
  }
}

/// Hat adımlarının tanı izi (kayıt açıkken kurulur; kapalıyken hiç oluşmaz).
final class DiagTrace {
  var steps: [String] = []
  var calls = 0
  var raw: String?
  var names: [String] = []
}

/// Gizli bilgilerin kayda girmemesi. Ayar dökümü İZİN listesiyle yazılır: yalnız bilinen güvenli alanların değeri
/// yazılır; anahtarlar ve listede olmayan (ileride eklenecek) her alan yalnız "dolu/boş" olarak, sözlük yalnız sayılarla.
/// Ayrıca bilinen gizli değerler ve URL/üst bilgi anahtarları her olayın DİZGE DEĞERLERİNDEN silinir.
enum DiagnosticPrivacy {
  /// Değeri olduğu gibi yazılan ayar yolları ("style.fontSize"; dizideki nesnelerin alanları "extraRegions.name").
  static let safeSettingPaths: Set<String> = [
    "sourceLanguage", "targetLanguage", "engine", "geminiModel", "openRouterModel", "geminiStyleNote", "engineFailover", "autoWake",
    "packsEnabled", "hideButtonHints", "subtitleOnly", "matchGameTextSize", "packChoice", "autoRegion", "uiLanguage",
    "region.top", "region.bottom", "region.left", "region.right",
    "style.fontSize", "style.bottomPercent", "style.placement", "style.background", "style.bold", "style.textColor",
    "style.displayMode", "style.stackPrevious", "style.speakerColor", "style.speakerColorsEnabled", "style.subtitleFont",
    "style.subtitleFontUsed",
    "extraRegions.top", "extraRegions.bottom", "extraRegions.left", "extraRegions.right", "extraRegions.name",
  ]
  /// İçine girilen (nesne ya da nesne dizisi) ayar yolları.
  static let containerSettingPaths: Set<String> = ["region", "style", "extraRegions"]
  /// İçeriği değil yalnız büyüklüğü yazılan alanlar.
  static let summarizedSettingPaths: Set<String> = ["glossary"]
  /// Bilinen gizli alanlar: yalnız {"set": dolu mu}.
  static let secretSettingPaths: Set<String> = ["deepLKey", "geminiKey", "openRouterKey"]
  /// Bundan kısa "gizli" değer silinmez: "1234", "true", "text" gibi her yerde geçen dizgeler bozulmasın.
  static let minSecretLength = 8
  static let masked = "[gizli]"

  /// Yolun bilinen sınıfı var mı (güvenli, kapsayıcı, özet ya da gizli).
  static func isClassified(_ path: String) -> Bool {
    safeSettingPaths.contains(path) || containerSettingPaths.contains(path) || summarizedSettingPaths.contains(path)
      || secretSettingPaths.contains(path)
  }

  /// Bilinen yolların son bileşenleri ("fontSize", "region"...): kaynak metinden çıkarılan anahtar adları bunlarla denetlenir.
  static var classifiedNames: Set<String> {
    let all: Set<String> = safeSettingPaths.union(containerSettingPaths).union(summarizedSettingPaths).union(secretSettingPaths)
    var names = Set<String>()
    for path in all {
      let parts: [Substring] = path.split(separator: ".")
      if let last = parts.last { names.insert(String(last)) } else { names.insert(path) }
    }
    return names
  }

  /// Ayar JSON'unda hiçbir sınıfa girmeyen yollar (yeni eklenmiş alan): kayıtta değeri yazılmaz, oturum olayında listelenir.
  static func unclassifiedPaths(_ json: [String: Any], prefix: String = "") -> [String] {
    var out: [String] = []
    for key in json.keys.sorted() {
      let path: String = prefix.isEmpty ? key : prefix + "." + key
      let value: Any = json[key] as Any
      if containerSettingPaths.contains(path) {
        if let map = value as? [String: Any] {
          out.append(contentsOf: unclassifiedPaths(map, prefix: path))
        } else if let list = value as? [Any] {
          for item in list {
            if let map = item as? [String: Any] { out.append(contentsOf: unclassifiedPaths(map, prefix: path)) }
          }
        }
      } else if !isClassified(path) {
        out.append(path)
      }
    }
    var seen = Set<String>()
    return out.filter { (path: String) -> Bool in seen.insert(path).inserted }
  }

  /// Ayar JSON'u (Settings.toJson) izin listesine göre; alanlar alfabetik.
  static func settings(_ json: [String: Any]) -> DiagValue { DiagValue.object(redactedObject(json, prefix: "")) }

  /// Değişen ayar yolları ("engine", "style.fontSize"); alfabetik. Değerler karşılaştırılır, yazılmaz.
  static func changes(before: [String: Any], after: [String: Any]) -> [String] {
    var old: [String: String] = [:]
    var new: [String: String] = [:]
    for (path, value) in flatten(before, prefix: "") { old[path] = convert(value).json }
    for (path, value) in flatten(after, prefix: "") { new[path] = convert(value).json }
    let keys: Set<String> = Set(old.keys).union(new.keys)
    return keys.filter { (path: String) -> Bool in old[path] != new[path] }.sorted()
  }

  /// [paths] yollarındaki yeni değerler, izin listesine göre (ayar değişikliği olayı için).
  static func values(_ json: [String: Any], paths: [String]) -> DiagFields {
    var flat: [String: Any] = [:]
    for (path, value) in flatten(json, prefix: "") where flat[path] == nil { flat[path] = value }
    var out = DiagFields()
    for path in paths {
      guard let value = flat[path] else {
        out[path] = DiagValue.null
        continue
      }
      out[path] = redacted(path: path, value)
    }
    return out
  }

  /// Olay alanlarındaki DİZGE DEĞERLERİNDEN gizli değerleri siler (iç içe nesne ve diziler dahil). Alan adlarına,
  /// sayılara ve yapıya dokunulmaz; çıktı her zaman geçerli JSON'dur.
  static func scrub(fields: DiagFields, secrets: [String]) -> DiagFields {
    let forms: [String] = usableSecrets(secrets)
    return scrubFields(fields, forms)
  }

  /// Tek bir metinden (dizge değeri) bilinen gizli değerleri ve URL/üst bilgi anahtarlarını [masked] ile değiştirir.
  /// [minSecretLength]'ten kısa "gizli" değer yok sayılır.
  static func scrub(_ text: String, secrets: [String]) -> String {
    scrubText(text, usableSecrets(secrets))
  }

  /// `?key=...`, `&key=...`, `DeepL-Auth-Key ...`, `x-goog-api-key: ...`, `Bearer ...`.
  private static let patterns: [NSRegularExpression] = [
    "(?i)([?&](?:key|api_key|apikey|auth_key|token)=)[^&\\s\"\\\\]+",
    "(?i)(DeepL-Auth-Key\\s+)[^\\s\"\\\\]+",
    "(?i)(x-goog-api-key\\s*[:=]\\s*)[^\\s\"\\\\]+",
    "(?i)(Bearer\\s+)[^\\s\"\\\\]+",
  ].compactMap { (pattern: String) -> NSRegularExpression? in try? NSRegularExpression(pattern: pattern) }

  /// Silinecek biçimler: kırpılmış değer ve (farklıysa) JSON'a kaçışlı yazılmış hali (gömülü JSON metinleri için,
  /// ör. TV çerçevesi). Uzundan kısaya: biri ötekini içeriyorsa önce uzunu silinsin.
  private static func usableSecrets(_ secrets: [String]) -> [String] {
    var forms: [String] = []
    for secret in secrets {
      let value: String = secret.trimmingCharacters(in: .whitespacesAndNewlines)
      guard value.count >= minSecretLength else { continue }
      forms.append(value)
      let quoted: String = SubtitleWire.jsonString(value)
      let escaped: String = String(quoted.dropFirst().dropLast())
      if escaped != value { forms.append(escaped) }
    }
    return forms.sorted { (a: String, b: String) -> Bool in a.count > b.count }
  }

  private static func scrubText(_ text: String, _ forms: [String]) -> String {
    var out: String = text
    for form in forms where out.contains(form) { out = out.replacingOccurrences(of: form, with: masked) }
    for pattern in patterns {
      let range = NSRange(out.startIndex..., in: out)
      out = pattern.stringByReplacingMatches(in: out, options: [], range: range, withTemplate: "$1" + masked)
    }
    return out
  }

  private static func scrubFields(_ fields: DiagFields, _ forms: [String]) -> DiagFields {
    var out = DiagFields()
    for item in fields.items { out[item.key] = scrubValue(item.value, forms) }
    return out
  }

  private static func scrubValue(_ value: DiagValue, _ forms: [String]) -> DiagValue {
    switch value {
    case .string(let text):
      return DiagValue.string(scrubText(text, forms))
    case .array(let items):
      return DiagValue.array(items.map { (item: DiagValue) -> DiagValue in scrubValue(item, forms) })
    case .object(let inner):
      return DiagValue.object(scrubFields(inner, forms))
    default:
      return value
    }
  }

  // MARK: - Dönüştürme

  private static func redactedObject(_ json: [String: Any], prefix: String) -> DiagFields {
    var out = DiagFields()
    for key in json.keys.sorted() {
      let path: String = prefix.isEmpty ? key : prefix + "." + key
      out[key] = redacted(path: path, json[key] as Any)
    }
    return out
  }

  /// Yolun sınıfına göre: özet, kapsayıcı (içine girilir), güvenli (değer) ya da gizli/bilinmeyen (yalnız dolu mu).
  private static func redacted(path: String, _ value: Any) -> DiagValue {
    if summarizedSettingPaths.contains(path) { return glossarySummary(value as? String ?? "") }
    if containerSettingPaths.contains(path) {
      if let map = value as? [String: Any] { return DiagValue.object(redactedObject(map, prefix: path)) }
      if let list = value as? [Any] {
        var items: [DiagValue] = []
        for item in list {
          if let map = item as? [String: Any] {
            items.append(DiagValue.object(redactedObject(map, prefix: path)))
          } else {
            items.append(hidden(item, known: false))
          }
        }
        return DiagValue.array(items)
      }
      return hidden(value, known: false)
    }
    if safeSettingPaths.contains(path) { return convert(value) }
    return hidden(value, known: secretSettingPaths.contains(path))
  }

  /// Değeri yazılmayan alan: {"set": dolu mu}; bilinen gizli alan değilse "unclassified": true da eklenir.
  private static func hidden(_ value: Any, known: Bool) -> DiagValue {
    let filled: Bool
    if let text = value as? String {
      filled = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    } else if let map = value as? [String: Any] {
      filled = !map.isEmpty
    } else if let list = value as? [Any] {
      filled = !list.isEmpty
    } else {
      filled = !(value is NSNull)
    }
    var fields: DiagFields = ["set": DiagValue.bool(filled)]
    if !known { fields["unclassified"] = DiagValue.bool(true) }
    return DiagValue.object(fields)
  }

  /// Sözlüğün içeriği değil yalnız büyüklüğü: satır, terim ve korunan terim sayısı.
  static func glossarySummary(_ text: String) -> DiagValue {
    let trimmed: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let lineCount: Int = trimmed.isEmpty ? 0 : trimmed.split(separator: "\n", omittingEmptySubsequences: true).count
    var fields: DiagFields = ["set": DiagValue.bool(!trimmed.isEmpty)]
    fields["lines"] = DiagValue.int(lineCount)
    if let data = trimmed.data(using: .utf8), let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
      let terms: Int = (root["terms"] as? [String: Any])?.count ?? 0
      let keep: Int = (root["keep"] as? [Any])?.count ?? 0
      fields["terms"] = DiagValue.int(terms)
      fields["keep"] = DiagValue.int(keep)
    } else if !trimmed.isEmpty {
      fields["valid"] = DiagValue.bool(false)
    }
    return DiagValue.object(fields)
  }

  /// Süzme olmadan düz dönüşüm (yalnız karşılaştırma ve güvenli değerler için).
  static func convert(_ value: Any) -> DiagValue {
    if JsonNumber.isBoolean(value), let flag = value as? Bool { return DiagValue.bool(flag) }
    if let text = value as? String { return DiagValue.string(text) }
    if type(of: value) == Int.self, let number = value as? Int { return DiagValue.int(number) }
    if type(of: value) == Double.self, let number = value as? Double { return DiagValue.double(number) }
    if let number = value as? NSNumber {
      let isFloat: Bool = CFNumberIsFloatType(number as CFNumber)
      return isFloat ? DiagValue.double(number.doubleValue) : DiagValue.int(number.intValue)
    }
    if let map = value as? [String: Any] {
      var out = DiagFields()
      for key in map.keys.sorted() { out[key] = convert(map[key] as Any) }
      return DiagValue.object(out)
    }
    if let list = value as? [Any] {
      var items: [DiagValue] = []
      for item in list { items.append(convert(item)) }
      return DiagValue.array(items)
    }
    return DiagValue.null
  }

  private static func flatten(_ json: [String: Any], prefix: String) -> [(String, Any)] {
    var out: [(String, Any)] = []
    for key in json.keys.sorted() {
      let path: String = prefix.isEmpty ? key : prefix + "." + key
      if let map = json[key] as? [String: Any] {
        out.append(contentsOf: flatten(map, prefix: path))
      } else {
        out.append((path, json[key] as Any))
      }
    }
    return out
  }
}

/// Kaydın sınırları: biri dolunca kayıt kendiliğinden durur.
struct DiagnosticLimits: Equatable {
  var maxSeconds: Double = 15 * 60
  var maxBytes = 40 * 1024 * 1024
  var maxFrames = 600
  /// Boş alan bunun altındaysa kayıt başlamaz (kayıt + paylaşılacak zip kopyası + pay).
  var minFreeBytes: Int64 = 200 * 1024 * 1024
  /// Telefonda en çok bu kadar kayıt durur; yenisi için eskisi silinmeli.
  var maxSessions = 3
  /// Nabız (durum özeti ve kare) aralığı, sn.
  var pulseSeconds: Double = 10
}

/// Kaydın neden durduğu.
enum DiagnosticStop: String {
  case manual, duration, size, frames, failed, terminated
}

/// Kayıt sürerken sayaçlar ve sınır denetimi (saf; saat dışarıdan).
struct DiagnosticBudget {
  let limits: DiagnosticLimits
  let startedAt: Double
  private(set) var bytes = 0
  private(set) var frames = 0
  private(set) var events = 0

  init(limits: DiagnosticLimits, startedAt: Double) {
    self.limits = limits
    self.startedAt = startedAt
  }

  mutating func addEvent(bytes count: Int) {
    events += 1
    bytes += count
  }

  mutating func addFrame(bytes count: Int) {
    frames += 1
    bytes += count
  }

  /// Bu boyda bir kare boyut sınırını aşmadan yazılabilir mi.
  func fitsFrame(bytes count: Int) -> Bool { bytes + count <= limits.maxBytes }

  /// Kare kotası dolmadı mı.
  func acceptsFrame(reserved: Int) -> Bool { reserved < limits.maxFrames }

  /// Dolan ilk sınır; yoksa nil.
  func exceeded(now: Double) -> DiagnosticStop? {
    if now - startedAt >= limits.maxSeconds { return .duration }
    if bytes >= limits.maxBytes { return .size }
    if frames >= limits.maxFrames { return .frames }
    return nil
  }
}

/// events.jsonl okuma: yalnız satır sonuyla biten ve çözülebilen satırlar sayılır; yarım kalan son satır yok sayılır.
enum DiagnosticReader {
  static func events(_ data: Data) -> (events: [[String: Any]], skipped: Int) {
    var events: [[String: Any]] = []
    var skipped = 0
    var start = data.startIndex
    while start < data.endIndex {
      guard let end = data[start...].firstIndex(of: 0x0A) else {
        skipped += 1  // satır sonu yok: uygulama yazarken kapandı
        break
      }
      let line = data[start..<end]
      if !line.isEmpty {
        if let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] {
          events.append(object)
        } else {
          skipped += 1
        }
      }
      start = data.index(after: end)
    }
    return (events, skipped)
  }

  /// Dosyanın sağlam kısmının uzunluğu: son satır sonuna kadar (yarım son satır atılınca kalacak bayt).
  static func completeLength(_ data: Data) -> Int {
    guard let last = data.lastIndex(of: 0x0A) else { return 0 }
    return data.distance(from: data.startIndex, to: last) + 1
  }

  /// Tam satır sayısı (satır sonları).
  static func lineCount(_ data: Data) -> Int {
    var count = 0
    for byte: UInt8 in data where byte == 0x0A { count += 1 }
    return count
  }

  /// Son tam satır (çözülebiliyorsa).
  static func lastEvent(_ data: Data) -> [String: Any]? {
    let length = completeLength(data)
    guard length > 0 else { return nil }
    let body: Data = data.prefix(length - 1)
    var start: Data.Index = body.startIndex
    if let newline = body.lastIndex(of: 0x0A) { start = body.index(after: newline) }
    return try? JSONSerialization.jsonObject(with: Data(body[start...])) as? [String: Any]
  }

  /// İlk satır (oturum bilgisi).
  static func firstEvent(_ data: Data) -> [String: Any]? {
    guard let end = data.firstIndex(of: 0x0A) else { return nil }
    return try? JSONSerialization.jsonObject(with: Data(data[data.startIndex..<end])) as? [String: Any]
  }
}

/// Okuma adımlarının tanı biçimi (VisionReader'ın kullandığı saf yapılar).
enum DiagRead {
  /// Vision gözlemi: metin, güven, kutu (tüm karede 0–1: sol, üst, sağ, alt) ve okunan alandaki piksel boyu.
  /// [cropX]/[cropY]: alanın karedeki yeri (piksel).
  static func observation(_ o: TextObservation, cropX: Int, cropY: Int, frameWidth: Int, frameHeight: Int) -> DiagValue {
    let w: Double = Double(max(frameWidth, 1))
    let h: Double = Double(max(frameHeight, 1))
    let box = TextBox(left: Double(cropX + o.left) / w, top: Double(cropY + o.top) / h,
                      right: Double(cropX + o.right) / w, bottom: Double(cropY + o.bottom) / h)
    let pixels: [DiagValue] = [DiagValue.int(o.left), DiagValue.int(o.top), DiagValue.int(o.right), DiagValue.int(o.bottom)]
    var fields = DiagFields()
    fields["text"] = DiagValue.string(o.text)
    fields["conf"] = DiagValue.double(o.confidence)
    fields["box"] = DiagValue.box(box)
    fields["px"] = DiagValue.array(pixels)
    fields["h"] = DiagValue.int(o.height)
    return DiagValue.object(fields)
  }

  static func observations(_ list: [TextObservation], cropX: Int, cropY: Int, frameWidth: Int, frameHeight: Int) -> DiagValue {
    var items: [DiagValue] = []
    for o in list { items.append(observation(o, cropX: cropX, cropY: cropY, frameWidth: frameWidth, frameHeight: frameHeight)) }
    return DiagValue.array(items)
  }

  /// Seçim adımları: güven elemesi, kesik kenar elemesi, bloklar ve puanları, seçilen bloğun sırası (ReadingSelector.select
  /// ile aynı hesap).
  static func selection(_ input: [TextObservation], width: Int, height: Int) -> DiagValue {
    let confident: [TextObservation] = ReadingSelector.filterConfidence(input)
    let uncut: [TextObservation] = ReadingSelector.dropEdgeCut(confident, width: width)
    let blocks: [[TextObservation]] = ReadingSelector.blocks(uncut)
    var best = -1
    var bestScore: Double = -Double.infinity
    var list: [DiagValue] = []
    for (index, block) in blocks.enumerated() {
      let score: Double = ReadingSelector.score(block, width: width, height: height)
      // pickBlock: tek blok puansız seçilir; birden çokta ilk en yüksek puan.
      if blocks.count == 1 || score > bestScore {
        best = index
        bestScore = score
      }
      var entry = DiagFields()
      entry["texts"] = DiagValue.strings(texts(block))
      entry["score"] = DiagValue.double(score)
      list.append(DiagValue.object(entry))
    }
    var lowConfidence: [String] = []
    for o in input where !confident.contains(o) { lowConfidence.append(o.text) }
    var edgeCut: [String] = []
    for o in confident where !uncut.contains(o) { edgeCut.append(o.text) }
    var fields = DiagFields()
    fields["lowConfidence"] = DiagValue.strings(lowConfidence)
    fields["edgeCut"] = DiagValue.strings(edgeCut)
    fields["blocks"] = DiagValue.array(list)
    fields["chosenBlock"] = DiagValue.int(best)
    return DiagValue.object(fields)
  }

  private static func texts(_ list: [TextObservation]) -> [String] {
    var out: [String] = []
    for o in list { out.append(o.text) }
    return out
  }

  /// Satır yüksekliği hesabının ara değerleri.
  static func lineHeight(_ t: LineHeight.Trace) -> DiagValue {
    var pieces: [DiagValue] = []
    for p in t.pieces {
      var piece = DiagFields()
      piece["text"] = DiagValue.string(p.text)
      piece["chars"] = DiagValue.int(p.characters)
      piece["hPx"] = DiagValue.int(p.heightPx)
      piece["wPx"] = DiagValue.int(p.widthPx)
      piece["ratio"] = DiagValue.optional(p.ratio)
      piece["lines"] = DiagValue.optional(p.linesGuess)
      piece["perLine"] = DiagValue.double(p.perLine)
      pieces.append(DiagValue.object(piece))
    }
    var fields = DiagFields()
    fields["frameHeight"] = DiagValue.int(t.frameHeight)
    fields["onlyLong"] = DiagValue.bool(t.onlyLong)
    fields["pieces"] = DiagValue.array(pieces)
    fields["typical"] = DiagValue.double(t.typical)
    fields["single"] = DiagValue.doubles(t.single)
    fields["upperMedianPx"] = DiagValue.double(t.upper)
    fields["ratio"] = DiagValue.double(t.ratio)
    fields["inRange"] = DiagValue.bool(t.inRange)
    fields["min"] = DiagValue.double(LineHeight.MIN_RATIO)
    fields["max"] = DiagValue.double(LineHeight.MAX_RATIO)
    fields["estimate"] = DiagValue.optional(t.result)
    return DiagValue.object(fields)
  }

  static func boxes(_ list: [TextBox]) -> DiagValue {
    var items: [DiagValue] = []
    for b in list { items.append(DiagValue.box(b)) }
    return DiagValue.array(items)
  }
}

/// Kayıt ve paylaşım dosyası adları.
enum DiagnosticNames {
  /// Kayıt klasörü: yyyyMMdd-HHmmss (yerel saat).
  static func sessionId(_ date: Date, timeZone: TimeZone = .current) -> String {
    stamp(date, "yyyyMMdd-HHmmss", timeZone)
  }

  /// gametranslator-tani-<sürüm>-<yyyyMMdd-HHmm>; sürümdeki dosya adına uygun olmayan karakterler atılır.
  static func exportBase(version: String, sessionId: String) -> String {
    var cleanVersion = ""
    for scalar in version.unicodeScalars where isFileNameScalar(scalar) { cleanVersion.unicodeScalars.append(scalar) }
    let minute: String = sessionId.count >= 13 ? String(sessionId.prefix(13)) : sessionId
    let shown: String = cleanVersion.isEmpty ? "0" : cleanVersion
    return "gametranslator-tani-" + shown + "-" + minute
  }

  /// Dosya adında kalan karakter: ASCII harf, rakam, ".", "-", "_".
  private static func isFileNameScalar(_ scalar: Unicode.Scalar) -> Bool {
    let v: UInt32 = scalar.value
    let digit: Bool = v >= 48 && v <= 57
    let upper: Bool = v >= 65 && v <= 90
    let lower: Bool = v >= 97 && v <= 122
    return digit || upper || lower || v == 46 || v == 45 || v == 95
  }

  /// Kayıt kimliği yalnız rakam ve tireden oluşmalı (klasör dışına çıkılmasın).
  static func isValidId(_ id: String) -> Bool {
    guard !id.isEmpty, id.count <= 32 else { return false }
    for scalar in id.unicodeScalars {
      let v: UInt32 = scalar.value
      let digit: Bool = v >= 48 && v <= 57
      if !digit && v != 45 { return false }
    }
    return true
  }

  private static func stamp(_ date: Date, _ format: String, _ timeZone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = timeZone
    formatter.dateFormat = format
    return formatter.string(from: date)
  }
}
