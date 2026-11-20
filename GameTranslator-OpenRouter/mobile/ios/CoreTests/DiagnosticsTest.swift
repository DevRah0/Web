// SPDX-License-Identifier: AGPL-3.0-only
// Tanı kaydı testleri: Core/DiagnosticFormat.swift (olay JSON'u, gizli alan süzme, sınırlar, yarım kayıt okuma),
// Core/DiagnosticRecorder.swift (kayıt, sınırlarda durma, mühürleme) ve Core/StoredZip.swift (CRC-32, ZIP düzeni).
// Kotlin karşılığı yok.
import Foundation

/// Testlerin sahte saati (kuyruktan da okunur; yalnız testte).
private final class DiagTestClock {
  var now = 1000.0
}

private func tempRoot() -> URL {
  URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gt-diag-\(UUID().uuidString)", isDirectory: true)
}

private func le16(_ data: Data, _ at: Int) -> Int {
  let low: Int = Int(data[data.startIndex + at])
  let high: Int = Int(data[data.startIndex + at + 1])
  return low | (high << 8)
}

private func le32(_ data: Data, _ at: Int) -> UInt32 {
  var value: UInt32 = 0
  for i in 0..<4 {
    let byte: UInt32 = UInt32(data[data.startIndex + at + i])
    value |= byte << UInt32(8 * i)
  }
  return value
}

private func text(_ url: URL) -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }

private func events(_ folder: URL) -> [[String: Any]] {
  DiagnosticReader.events((try? Data(contentsOf: folder.appendingPathComponent("events.jsonl"))) ?? Data()).events
}

/// ZIP'i merkezî dizinden okur (test için küçük okuyucu): ad → veri. Bozuksa nil.
private func unzip(_ zip: Data) -> [String: Data]? {
  guard zip.count >= 22 else { return nil }
  let end = zip.count - 22
  guard le32(zip, end) == 0x0605_4B50 else { return nil }
  let count = le16(zip, end + 10)
  var at = Int(le32(zip, end + 16))
  var out: [String: Data] = [:]
  for _ in 0..<count {
    guard le32(zip, at) == 0x0201_4B50 else { return nil }
    let crc = le32(zip, at + 16)
    let size = Int(le32(zip, at + 20))
    let nameLength = le16(zip, at + 28)
    let extra = le16(zip, at + 30)
    let comment = le16(zip, at + 32)
    let local = Int(le32(zip, at + 42))
    let name = String(decoding: zip[(zip.startIndex + at + 46)..<(zip.startIndex + at + 46 + nameLength)], as: UTF8.self)
    guard le32(zip, local) == 0x0403_4B50, le16(zip, local + 8) == 0 else { return nil }
    let dataStart = local + 30 + le16(zip, local + 26) + le16(zip, local + 28)
    let body = Data(zip[(zip.startIndex + dataStart)..<(zip.startIndex + dataStart + size)])
    guard ZipChecksum.of(body) == crc else { return nil }
    out[name] = body
    at += 46 + nameLength + extra + comment
  }
  return out
}

enum DiagnosticFormatTest {
  static func run() {
    TestRun.test("DiagnosticFormatTest.escapesSpecialCharacters") {
      let original = "a\"b\\c\nd\te\u{01}é—😀"
      let line = DiagnosticLine.encode(seq: 3, t: 1500, type: "log", fields: ["text": .string(original)])
      assertEquals("{\"seq\":3,\"t\":1500,\"type\":\"log\",\"text\":\"a\\\"b\\\\c\\nd\\te\\u0001é—😀\"}\n", line)
      // Geri okunur ve metin aynen döner.
      let parsed = DiagnosticReader.events(Data(line.utf8))
      assertEquals(1, parsed.events.count)
      assertEquals(0, parsed.skipped)
      assertEquals(original, parsed.events.first?["text"] as? String ?? "")
    }
    TestRun.test("DiagnosticFormatTest.reservedKeysAndOrder") {
      let line = DiagnosticLine.encode(seq: 1, t: 0, type: "tv", fields: ["seq": .int(99), "b": .int(1), "a": .bool(true), "type": .string("x")])
      assertEquals("{\"seq\":1,\"t\":0,\"type\":\"tv\",\"b\":1,\"a\":true}\n", line)
      var fields: DiagFields = ["x": .null]
      fields["y"] = DiagValue.array([.int(1), .string("z")])
      fields["x"] = DiagValue.double(0.5)
      assertEquals("{\"x\":0.5,\"y\":[1,\"z\"]}", fields.json)
    }
    TestRun.test("DiagnosticFormatTest.numbers") {
      assertEquals("0.875", DiagValue.number(0.875))
      assertEquals("1", DiagValue.number(1.0))
      assertEquals("100", DiagValue.number(100))
      assertEquals("12.3457", DiagValue.number(12.34567))
      assertEquals("0", DiagValue.number(-0.00001))
      assertEquals("-2.5", DiagValue.number(-2.5))
      assertEquals("null", DiagValue.number(Double.nan))
      assertEquals("null", DiagValue.number(Double.infinity))
      assertEquals("[0.25,0.5,0.75,1]", DiagValue.box(TextBox(left: 0.25, top: 0.5, right: 0.75, bottom: 1)).json)
      assertEquals("null", DiagValue.box(nil).json)
    }
    TestRun.test("DiagnosticFormatTest.longTextIsClipped") {
      let json = DiagValue.string(String(repeating: "a", count: 20000)).json
      assertTrue(json.utf8.count < DiagValue.maxStringBytes + 40, "\(json.utf8.count)")
      assertTrue(json.hasSuffix("…[kısaltıldı]\""))
    }
    TestRun.test("DiagnosticFormatTest.readerSkipsTruncatedTail") {
      let data = Data("{\"seq\":1,\"t\":0,\"type\":\"session\"}\n{\"seq\":2,\"t\":5,\"type\":\"log\"}\n{\"seq\":3,\"t\":9,\"ty".utf8)
      let parsed = DiagnosticReader.events(data)
      assertEquals(2, parsed.events.count)
      assertEquals(1, parsed.skipped)
      assertEquals(2, DiagnosticReader.lineCount(data))
      assertEquals(data.count - "{\"seq\":3,\"t\":9,\"ty".utf8.count, DiagnosticReader.completeLength(data))
      assertEquals("log", DiagnosticReader.lastEvent(data)?["type"] as? String ?? "")
      assertEquals("session", DiagnosticReader.firstEvent(data)?["type"] as? String ?? "")
      // Ortadaki bozuk satır da atlanır, sonrakiler okunur.
      let broken = DiagnosticReader.events(Data("{\"a\":1}\nnot json\n{\"b\":2}\n".utf8))
      assertEquals(2, broken.events.count)
      assertEquals(1, broken.skipped)
    }
    TestRun.test("DiagnosticFormatTest.lineHeightTraceMatchesEstimate") {
      // İki satırı kapsayan tek parça: 85 px, 400 px genişlik, 51 karakter → oran 85 / (400/51) = 10,8375;
      // √(10,8375 / 2,6) ≈ 2,04 → 2 satır, satır başına 42,5 px → 0,0425 (LineHeightTest ile aynı örnek).
      let piece = TextObservation(text: "We need to leave right now before they find us here", confidence: 0.9,
                                  left: 300, top: 860, right: 700, bottom: 945)
      let trace = LineHeight.explain([piece], frameHeight: 1000)
      assertEquals(1, trace.pieces.count)
      assertEquals(85, trace.pieces[0].heightPx)
      assertEquals(51, trace.pieces[0].characters)
      assertEquals(10.8375, trace.pieces[0].ratio ?? 0, accuracy: 1e-9)
      assertEquals(2, trace.pieces[0].linesGuess ?? 0, accuracy: 0)
      assertEquals(42.5, trace.pieces[0].perLine, accuracy: 1e-9)
      assertTrue(trace.onlyLong)
      assertTrue(trace.inRange)
      assertEquals(0.0425, trace.result ?? 0, accuracy: 1e-9)
      assertEquals(LineHeight.estimate([piece], frameHeight: 1000) ?? -1, trace.result ?? -2, accuracy: 0)
      let json = DiagRead.lineHeight(trace).json
      assertTrue(json.contains("\"ratio\":10.8375,\"lines\":2,\"perLine\":42.5"), json)
      assertTrue(json.contains("\"estimate\":0.0425"), json)
      // Güvenilmez tahmin: aralık dışı, sonuç yok.
      let tall = LineHeight.explain([TextObservation(text: "OK", confidence: 0.9, left: 450, top: 700, right: 550, bottom: 900)], frameHeight: 1000)
      assertFalse(tall.inRange)
      assertNull(tall.result)
      assertEquals(0.2, tall.ratio, accuracy: 1e-9)
      // Sıcak yoldaki estimate ile tanıdaki explain ayrı yazılı: LineHeightTest'in bütün örneklerinde sonuçlar aynı.
      func o(_ text: String, _ l: Int, _ t: Int, _ r: Int, _ b: Int) -> TextObservation {
        TextObservation(text: text, confidence: 0.9, left: l, top: t, right: r, bottom: b)
      }
      let line1 = "We need to leave right now"
      let samples: [[TextObservation]] = [
        [o(line1, 300, 900, 700, 940)],
        [o(line1, 300, 850, 700, 890), o(line1, 300, 900, 700, 940)],
        [o("We need to leave right now before they find us here", 300, 860, 700, 945)],
        [o("Hey", 450, 820, 550, 860), o("Hey you", 430, 870, 570, 950)],
        [o(line1, 300, 800, 700, 838), o(line1, 300, 850, 700, 890), o(line1, 300, 900, 700, 942)],
        [o(line1, 300, 800, 700, 840), o(line1, 300, 850, 700, 890), o("OK", 480, 700, 520, 820)],
        [o(line1, 300, 850, 700, 890), o(line1, 300, 900, 700, 944)],
        [o(line1, 300, 800, 700, 840), o(line1, 300, 860, 700, 944)],
        [o(line1, 300, 900, 700, 944), o("me", 490, 950, 510, 963)],
        [o(line1, 300, 900, 700, 944), o("Go now", 460, 950, 540, 984)],
        [], [o("OK", 450, 700, 550, 900)], [o("OK", 450, 900, 550, 905)], [o("", 0, 0, 0, 0)],
      ]
      for (index, sample) in samples.enumerated() {
        for height in [1000, 1080, 0] {
          let fast: Double? = LineHeight.estimate(sample, frameHeight: height)
          let traced: Double? = LineHeight.explain(sample, frameHeight: height).result
          assertEquals(fast ?? -1, traced ?? -1, accuracy: 0, "örnek \(index), yükseklik \(height)")
        }
      }
    }
    TestRun.test("DiagnosticFormatTest.hintDropsAreExplained") {
      func o(_ text: String, _ top: Int) -> TextObservation {
        TextObservation(text: text, confidence: 0.9, left: 300, top: top, right: 600, bottom: top + 25)
      }
      let input = [o("Where are you going?", 100), o("SKIP RESUME BA", 200), o("● ○ ○", 300), o("Hold L2 to aim", 400)]
      let explained = ButtonHints.dropHintRowsExplained(input, english: true)
      assertEquals(ButtonHints.dropHintRows(input, english: true), explained.kept)
      assertEquals(["Where are you going?"], explained.kept.map(\.text))
      assertEquals(["SKIP RESUME BA", "● ○ ○", "Hold L2 to aim"], explained.dropped.map(\.text))
      assertEquals("only-buttons", explained.dropped.first?.reason ?? "")
      assertEquals("no-letters", explained.dropped.dropFirst().first?.reason ?? "")
    }
    TestRun.test("DiagnosticFormatTest.names") {
      var utc = Calendar(identifier: .gregorian)
      utc.timeZone = TimeZone(identifier: "UTC")!
      let date = utc.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 14, minute: 30, second: 42))!
      let id = DiagnosticNames.sessionId(date, timeZone: TimeZone(identifier: "UTC")!)
      assertEquals("20261119-143042", id)
      assertEquals("gametranslator-tani-1.8.4-20261119-1430", DiagnosticNames.exportBase(version: "1.8.4", sessionId: id))
      assertEquals("gametranslator-tani-184-20261119-1430", DiagnosticNames.exportBase(version: "1/8 4", sessionId: id))
      assertTrue(DiagnosticNames.isValidId(id))
      assertTrue(DiagnosticNames.isValidId(id + "-2"))
      assertFalse(DiagnosticNames.isValidId("../x"))
      assertFalse(DiagnosticNames.isValidId(""))
      assertFalse(DiagnosticNames.isValidId("20261119.143042"))
    }
  }
}

enum DiagnosticPrivacyTest {
  static let deepL = "dl-SECRET-1234:fx"
  static let gemini = "AIzaSyGEMINISECRET99"

  static func settingsJson(geminiKey: String? = nil, fontSize: Int = 46) -> [String: Any] {
    let key: String = geminiKey ?? DiagnosticPrivacyTest.gemini
    return [
      "deepLKey": deepL, "geminiKey": key, "engine": "gemini", "geminiStyleNote": "samimi konuş",
      "glossary": "{\"terms\":{\"Foo\":\"GLOSSSECRET\"},\"keep\":[\"KEEPSECRET\"]}",
      "region": ["top": 0.62, "bottom": 0.97] as [String: Double],
      "style": ["fontSize": fontSize, "bold": false, "placement": "cover"] as [String: Any],
      "extraRegions": [["name": "Görev", "top": 0.1] as [String: Any]],
      "accountId": "ACCOUNTSECRET", "registKeyHex": "abcd",
    ]
  }

  static func run() {
    TestRun.test("DiagnosticPrivacyTest.secretsNeverInSettingsOutput") {
      let out = DiagnosticPrivacy.settings(settingsJson()).json
      for secret in [deepL, "dl-SECRET", gemini, "GEMINISECRET", "GLOSSSECRET", "KEEPSECRET", "ACCOUNTSECRET", "abcd"] {
        assertFalse(out.contains(secret), "gizli değer çıktıda: \(secret)")
      }
      assertTrue(out.contains("\"deepLKey\":{\"set\":true}"), out)
      assertTrue(out.contains("\"geminiKey\":{\"set\":true}"), out)
      // OpenRouter is now a registered secret, never an unknown field.
      var withOpenRouter = settingsJson()
      withOpenRouter["openRouterKey"] = "sk-or-SENSITIVE-KEY-12345"
      let maskedOpenRouter = DiagnosticPrivacy.settings(withOpenRouter).json
      assertTrue(maskedOpenRouter.contains("\"openRouterKey\":{\"set\":true}"), maskedOpenRouter)
      assertFalse(maskedOpenRouter.contains("SENSITIVE-KEY"), maskedOpenRouter)
      // İzin listesinde olmayan alanın değeri yazılmaz; yalnız dolu olduğu ve sınıflanmadığı.
      assertTrue(out.contains("\"accountId\":{\"set\":true,\"unclassified\":true}"), out)
      assertTrue(out.contains("\"registKeyHex\":{\"set\":true,\"unclassified\":true}"), out)
      assertTrue(out.contains("\"glossary\":{\"set\":true,\"lines\":1,\"terms\":1,\"keep\":1}"), out)
      // Kullanıcının kendi üslup notu gizli değil.
      assertTrue(out.contains("\"geminiStyleNote\":\"samimi konuş\""), out)
      assertTrue(out.contains("\"style\":{\"bold\":false,\"fontSize\":46,\"placement\":\"cover\"}"), out)
      assertTrue(out.contains("\"region\":{\"bottom\":0.97,\"top\":0.62}"), out)
      assertTrue(out.contains("\"extraRegions\":[{\"name\":\"Görev\",\"top\":0.1}]"), out)
      var empty = settingsJson()
      empty["deepLKey"] = "  "
      empty["glossary"] = ""
      let blank = DiagnosticPrivacy.settings(empty).json
      assertTrue(blank.contains("\"deepLKey\":{\"set\":false}"), blank)
      assertTrue(blank.contains("\"glossary\":{\"set\":false,\"lines\":0}"), blank)
    }
    TestRun.test("DiagnosticPrivacyTest.unknownFieldsAreHiddenByDefault") {
      // İleride eklenecek bir alan (ör. yeni bir anahtar) izin listesinde olmadığı için değeri hiçbir zaman yazılmaz.
      var json = settingsJson()
      json["futureProviderKey"] = "sk-or-FUTURESECRET42"
      json["style"] = ["fontSize": 46, "outlineToken": "STYLESECRET77"] as [String: Any]
      json["extraRegions"] = [["name": "Görev", "apiHint": "REGIONSECRET9"] as [String: Any]]
      let out = DiagnosticPrivacy.settings(json).json
      for secret in ["FUTURESECRET42", "STYLESECRET77", "REGIONSECRET9"] { assertFalse(out.contains(secret), secret) }
      assertTrue(out.contains("\"futureProviderKey\":{\"set\":true,\"unclassified\":true}"), out)
      assertTrue(out.contains("\"style\":{\"fontSize\":46,\"outlineToken\":{\"set\":true,\"unclassified\":true}}"), out)
      assertEquals(["accountId", "extraRegions.apiHint", "futureProviderKey", "registKeyHex", "style.outlineToken"],
                   DiagnosticPrivacy.unclassifiedPaths(json).sorted())
      // Değişiklik olayında da aynı kural.
      let values = DiagValue.object(DiagnosticPrivacy.values(json, paths: ["futureProviderKey", "style.outlineToken"])).json
      assertFalse(values.contains("SECRET"), values)
    }
    TestRun.test("DiagnosticPrivacyTest.everySettingsKeyIsClassified") {
      // Core'daki gerçek tür: ek okuma alanının bütün alanları izin listesinde.
      assertEquals([], DiagnosticPrivacy.unclassifiedPaths(["extraRegions": [ExtraRegion().toJson()]]))
      // Settings Runner'da (Store.swift; Security/UIKit'e bağlı dosya, burada derlenmez): Settings.toJson gövdesindeki
      // bütün anahtar adları kaynak metinden çıkarılır; her biri izin, kapsayıcı, özet ya da gizli listesinde olmalı.
      // Yeni bir alan eklenince bu test kırılır ve alanın sınıfına karar vermeye zorlar.
      guard let dir = ProcessInfo.processInfo.environment["GT_RUNNER_DIR"] else {
        return TestRun.fail("GT_RUNNER_DIR ayarlı değil (run.sh ayarlar)", #fileID, #line)
      }
      let source = (try? String(contentsOf: URL(fileURLWithPath: dir).appendingPathComponent("Store.swift"), encoding: .utf8)) ?? ""
      guard let start = source.range(of: "func toJson() -> [String: Any] {"),
            let end = source.range(of: "func toJsonString()", range: start.upperBound..<source.endIndex) else {
        return TestRun.fail("Store.swift içinde Settings.toJson bulunamadı", #fileID, #line)
      }
      let body = String(source[start.upperBound..<end.lowerBound])
      guard let pattern = try? NSRegularExpression(pattern: "\"([A-Za-z][A-Za-z0-9]*)\"\\s*:") else {
        return TestRun.fail("desen kurulamadı", #fileID, #line)
      }
      var names: [String] = []
      for match in pattern.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
        if let range = Range(match.range(at: 1), in: body) { names.append(String(body[range])) }
      }
      // Kaynak okuması sağlam mı: bilinen alanlar bulundu.
      assertTrue(names.count >= 30, "\(names.count) anahtar")
      for known in ["deepLKey", "geminiKey", "glossary", "fontSize", "extraRegions", "uiLanguage"] {
        assertTrue(names.contains(known), known)
      }
      let classified = DiagnosticPrivacy.classifiedNames
      for name in names { assertTrue(classified.contains(name), "Settings.toJson'daki \"\(name)\" alanı sınıflanmamış") }
    }
    TestRun.test("DiagnosticPrivacyTest.changedFieldsWithoutSecretValues") {
      let before = settingsJson()
      let after = settingsJson(geminiKey: "AIzaSyNEWSECRET77", fontSize: 50)
      let changed = DiagnosticPrivacy.changes(before: before, after: after)
      assertEquals(["geminiKey", "style.fontSize"], changed)
      let values = DiagValue.object(DiagnosticPrivacy.values(after, paths: changed)).json
      assertEquals("{\"geminiKey\":{\"set\":true},\"style.fontSize\":50}", values)
      assertFalse(values.contains("NEWSECRET"))
      assertEquals([], DiagnosticPrivacy.changes(before: before, after: before))
    }
    TestRun.test("DiagnosticPrivacyTest.scrubRemovesKnownSecretsAndUrlKeys") {
      let text = "GET https://x/v1?key=AIzaOTHER123&alt=json \(deepL) Authorization: DeepL-Auth-Key abc-777 ab"
      let out = DiagnosticPrivacy.scrub(text, secrets: [deepL, "ab", "   "])
      assertFalse(out.contains("AIzaOTHER123"), out)
      assertFalse(out.contains(deepL), out)
      assertFalse(out.contains("abc-777"), out)
      assertTrue(out.contains("?key=[gizli]&alt=json"), out)
      assertTrue(out.contains("DeepL-Auth-Key [gizli]"), out)
      // 8 karakterden kısa "gizli" değer silinmez.
      assertTrue(out.hasSuffix(" ab"), out)
      // JSON'a kaçışlı yazılmış gizli değer de silinir (gömülü JSON metni, ör. TV çerçevesi).
      assertFalse(DiagnosticPrivacy.scrub("data: {\"t\":\"se\\\"cret/1\"}", secrets: ["se\"cret/1"]).contains("cret/1"))
    }
    TestRun.test("DiagnosticPrivacyTest.scrubKeepsKeysNumbersAndStructure") {
      // Kısa ya da sözcük benzeri "anahtar": alan adları, sayılar ve true/null dokunulmaz; satır geçerli JSON kalır.
      let fields: DiagFields = ["durationMs": .int(1234), "text": .string("text true null 1234 durationMs"), "ok": .bool(true),
                                "n": .null]
      let clean = DiagnosticPrivacy.scrub(fields: fields, secrets: ["1234", "true", "null", "text", "durationMs"])
      let line = DiagnosticLine.encode(seq: 1, t: 0, type: "x", fields: clean)
      assertEquals("{\"seq\":1,\"t\":0,\"type\":\"x\",\"durationMs\":1234,\"text\":\"text true null 1234 [gizli]\",\"ok\":true,\"n\":null}\n", line)
      let parsed = DiagnosticReader.events(Data(line.utf8))
      assertEquals(1, parsed.events.count)
      assertEquals(0, parsed.skipped)
    }
    TestRun.test("DiagnosticPrivacyTest.scrubRemovesLongSecretEverywhere") {
      let secret = "AIzaSyLONGSECRET1234567"
      let quoted = "ab\"cdEFGH12"
      var fields: DiagFields = ["a": .string("k=" + secret)]
      fields["nested"] = DiagValue.object(["b": .array([.string("x " + secret + " y"), .int(5)])])
      fields["wire"] = DiagValue.string("data: {\"text\":\"?key=" + secret + "\",\"t\":\"ab\\\"cdEFGH12\"}")
      fields["plain"] = DiagValue.string("önce " + quoted + " sonra")
      let clean = DiagnosticPrivacy.scrub(fields: fields, secrets: [secret, quoted])
      let line = DiagnosticLine.encode(seq: 1, t: 0, type: "x", fields: clean)
      assertFalse(line.contains("LONGSECRET"), line)
      assertFalse(line.contains("cdEFGH12"), line)
      assertTrue(line.contains("\"b\":[\"x [gizli] y\",5]"), line)
      let parsed = DiagnosticReader.events(Data(line.utf8))
      assertEquals(1, parsed.events.count, "geçerli JSON")
      assertEquals(0, parsed.skipped)
    }
  }
}

enum DiagnosticRecorderTest {
  private static func make(_ clock: DiagTestClock, limits: DiagnosticLimits = DiagnosticLimits(),
                           free: Int64? = 10_000_000_000,
                           output: ((URL) -> DiagnosticOutput?)? = nil) -> DiagnosticRecorder {
    let now: () -> Double = { () -> Double in clock.now }
    let space: (URL) -> Int64? = { (_: URL) -> Int64? in free }
    let recorder = DiagnosticRecorder(root: tempRoot(), limits: limits, clock: now, freeSpace: space, openOutput: output)
    Diag.recorder = recorder
    return recorder
  }

  /// İlk [allowed] yazımı kabul edip sonra yazamayan hedef (disk dolu benzeri).
  private final class LimitedOutput: DiagnosticOutput {
    private var allowed: Int
    init(allowed: Int) { self.allowed = allowed }
    func write(_ data: Data) -> Bool {
      if allowed <= 0 { return false }
      allowed -= 1
      return true
    }
    func sync() {}
    func close() {}
  }

  /// Kare sınırı senaryosu (3 kare): olayların hepsi, karelerin hepsi yazılır ve kayıt "frames" ile durur.
  private static func runFrameLimit(_ round: Int) {
    let clock = DiagTestClock()
    var limits = DiagnosticLimits()
    limits.maxFrames = 3
    let r = make(clock, limits: limits)
    defer { finish(r) }
    let encoder: DiagnosticFrameEncoder = { () -> Data? in Data(repeating: 0xFF, count: 100) }
    r.frameGrabber = { () -> DiagnosticFrameEncoder? in encoder }
    let id = startedId(r.start(version: "1"))
    for index in 0..<6 {
      Diag.emit("tv", frame: "tv") { ["what": .string("show"), "index": .int(index)] }
      r.waitIdle()
    }
    assertFalse(r.isRecording, "tur \(round)")
    assertEquals(DiagnosticStop.frames, r.status.lastStop, "tur \(round)")
    let framesDir = folder(r, id).appendingPathComponent("frames").path
    let names: [String] = ((try? FileManager.default.contentsOfDirectory(atPath: framesDir)) ?? []).sorted()
    assertEquals(["0001.jpg", "0002.jpg", "0003.jpg"], names, "tur \(round)")
    let list = events(folder(r, id))
    let written: [[String: Any]] = list.filter { (event: [String: Any]) -> Bool in event["type"] as? String == "frame" && event["ok"] as? Bool == true }
    assertEquals(3, written.count, "tur \(round)")
    // Kareyi isteyen üç olayın üçü de yazıldı (sınırı dolduran kareyi isteyen dahil) ve her biri karesinden önce.
    let shows: [[String: Any]] = list.filter { (event: [String: Any]) -> Bool in event["type"] as? String == "tv" }
    assertEquals(["0001.jpg", "0002.jpg", "0003.jpg"], shows.compactMap { (event: [String: Any]) -> String? in event["frame"] as? String },
                 "tur \(round)")
    for name in ["0001.jpg", "0002.jpg", "0003.jpg"] {
      let show: [String: Any]? = shows.first(where: { (event: [String: Any]) -> Bool in event["frame"] as? String == name })
      let frame: [String: Any]? = written.first(where: { (event: [String: Any]) -> Bool in event["name"] as? String == name })
      let showSeq: Int = (show?["seq"] as? Int) ?? Int.max
      let frameSeq: Int = (frame?["seq"] as? Int) ?? -1
      assertTrue(showSeq < frameSeq, "tur \(round): \(name) olayı karesinden önce")
    }
    assertEquals(3, r.sessions().first?.frames ?? 0, "tur \(round)")
  }

  private static func finish(_ recorder: DiagnosticRecorder) {
    recorder.stop()
    try? FileManager.default.removeItem(at: recorder.root)
    Diag.recorder = nil
    Diag.on = false
  }

  private static func startedId(_ result: DiagnosticRecorder.StartResult) -> String {
    if case .started(let id) = result { return id }
    TestRun.fail("kayıt başlamadı: \(result)", #fileID, #line)
    return ""
  }

  private static func folder(_ recorder: DiagnosticRecorder, _ id: String) -> URL {
    recorder.root.appendingPathComponent(id, isDirectory: true)
  }

  static func run() {
    TestRun.test("DiagnosticRecorderTest.recordsSessionEventsAndStop") {
      let clock = DiagTestClock()
      let r = make(clock)
      defer { finish(r) }
      assertFalse(Diag.on)
      let id = startedId(r.start(version: "1.8.4", fields: ["device": .string("iPhone15,2")]))
      assertTrue(Diag.on)
      assertTrue(r.isRecording)
      clock.now += 2.5
      Diag.emit("log") { ["level": .int(2), "text": .string("merhaba")] }
      r.waitIdle()
      r.stop()
      assertFalse(Diag.on)
      // Kayıt kapalıyken olay yazılmaz; kapanış hiç çalışmaz.
      var built = false
      Diag.emit("log") {
        built = true
        return ["text": .string("yazılmamalı")]
      }
      assertFalse(built, "kayıt kapalıyken alanlar kurulmamalı")
      let list = events(folder(r, id))
      assertEquals(["session", "log", "stop"], list.map { (event: [String: Any]) -> String in event["type"] as? String ?? "" })
      assertEquals("1.8.4", list[0]["version"] as? String ?? "")
      assertEquals("iPhone15,2", list[0]["device"] as? String ?? "")
      assertEquals(2500, list[1]["t"] as? Int ?? -1)
      assertEquals("manual", list[2]["reason"] as? String ?? "")
      let summary = r.sessions().first
      assertEquals(id, summary?.id ?? "")
      assertEquals("manual", summary?.reason ?? "")
      assertFalse(summary?.interrupted ?? true)
      assertEquals(3, summary?.events ?? 0)
      assertEquals(DiagnosticStop.manual, r.status.lastStop)
      assertEquals(1, r.status.stops)
    }
    TestRun.test("DiagnosticRecorderTest.durationLimitStops") {
      let clock = DiagTestClock()
      var limits = DiagnosticLimits()
      limits.maxSeconds = 900
      let r = make(clock, limits: limits)
      defer { finish(r) }
      _ = startedId(r.start(version: "1"))
      clock.now += 899
      r.tick()
      assertTrue(r.isRecording)
      clock.now += 1
      r.tick()
      assertFalse(r.isRecording)
      assertFalse(Diag.on)
      assertEquals(DiagnosticStop.duration, r.status.lastStop)
    }
    TestRun.test("DiagnosticRecorderTest.sizeLimitStops") {
      let clock = DiagTestClock()
      var limits = DiagnosticLimits()
      limits.maxBytes = 2000
      let r = make(clock, limits: limits)
      defer { finish(r) }
      let id = startedId(r.start(version: "1"))
      for _ in 0..<100 where r.isRecording {
        Diag.emit("log") { ["text": .string(String(repeating: "x", count: 150))] }
        r.waitIdle()
      }
      assertFalse(r.isRecording)
      assertEquals(DiagnosticStop.size, r.status.lastStop)
      let size = (try? Data(contentsOf: folder(r, id).appendingPathComponent("events.jsonl")))?.count ?? 0
      // Sınır dolunca durur: en çok bir satır ve kapanış satırı kadar aşar.
      assertTrue(size >= 2000 && size < 2600, "\(size)")
    }
    TestRun.test("DiagnosticRecorderTest.frameLimitStops") {
      // Olay kare kodlamasından önce seri kuyruğa girer; karenin yazımı kodlamadan sonra aynı kuyruğa girdiği için
      // olaydan önce olamaz. Sıra zamanlamaya bağlı değil: senaryo 25 kez aynı sonucu vermeli.
      for round in 1...25 { runFrameLimit(round) }
    }
    TestRun.test("DiagnosticRecorderTest.frameSkippedWhenNoImage") {
      let clock = DiagTestClock()
      let r = make(clock)
      defer { finish(r) }
      r.frameGrabber = { () -> DiagnosticFrameEncoder? in nil }
      let id = startedId(r.start(version: "1"))
      Diag.emit("extra", frame: "extra") { ["what": .string("pressed")] }
      r.waitIdle()
      r.stop()
      let extra = events(folder(r, id)).first(where: { (event: [String: Any]) -> Bool in event["type"] as? String == "extra" })
      assertNotNull(extra)
      assertNull(extra?["frame"] as? String, "kare yoksa olay karesiz yazılır")
    }
    TestRun.test("DiagnosticRecorderTest.busyFullAndLowDisk") {
      let clock = DiagTestClock()
      let r = make(clock)
      defer { finish(r) }
      _ = startedId(r.start(version: "1"))
      assertEquals(DiagnosticRecorder.StartResult.busy, r.start(version: "1"))
      r.stop()
      // Üç kayıt varken yenisi için en eskisi silinmeli.
      let manager = FileManager.default
      for id in ["20200101-000000", "20200102-000000"] {
        try? manager.createDirectory(at: folder(r, id), withIntermediateDirectories: true)
      }
      let ids = r.sessions().map(\.id)
      assertEquals(3, ids.count)
      assertEquals(DiagnosticRecorder.StartResult.full(oldest: "20200101-000000"), r.start(version: "1"))
      let replaced = startedId(r.start(version: "1", replaceOldest: true))
      r.stop()
      assertFalse(manager.fileExists(atPath: folder(r, "20200101-000000").path))
      assertTrue(manager.fileExists(atPath: folder(r, replaced).path))
      assertEquals(3, r.sessions().count)
      let low = DiagnosticRecorder(root: tempRoot(), clock: { () -> Double in clock.now },
                                   freeSpace: { (_: URL) -> Int64? in 10 })
      assertEquals(DiagnosticRecorder.StartResult.lowDisk(10), low.start(version: "1"))
      assertFalse(low.isRecording)
      try? manager.removeItem(at: low.root)
    }
    TestRun.test("DiagnosticRecorderTest.interruptedSessionIsSealedAndReadable") {
      let clock = DiagTestClock()
      let r = make(clock)
      defer { finish(r) }
      let id = "20200101-120000"
      let dir = folder(r, id)
      let manager = FileManager.default
      try? manager.createDirectory(at: dir.appendingPathComponent("frames"), withIntermediateDirectories: true)
      let body = "{\"seq\":1,\"t\":0,\"type\":\"session\",\"version\":\"1.8.4\",\"startedAt\":1577880000000}\n"
        + "{\"seq\":2,\"t\":4200,\"type\":\"log\",\"text\":\"x\"}\n{\"seq\":3,\"t\":4300,\"type\":\"lo"
      try? Data(body.utf8).write(to: dir.appendingPathComponent("events.jsonl"))
      try? Data([0xFF, 0xD8]).write(to: dir.appendingPathComponent("frames/0001.jpg"))
      let summary = r.sessions().first
      assertEquals(id, summary?.id ?? "")
      assertTrue(summary?.interrupted ?? false)
      assertEquals("interrupted", summary?.reason ?? "")
      assertEquals("1.8.4", summary?.version ?? "")
      assertEquals(Int64(1_577_880_000_000), summary?.startedAt ?? 0)
      assertEquals(4.2, summary?.seconds ?? 0, accuracy: 0.0001)
      assertEquals(3, summary?.events ?? 0)
      assertEquals(1, summary?.frames ?? 0)
      // Yarım satır kesildi, mühür satırı eklendi; dosya baştan sona okunur.
      let data = (try? Data(contentsOf: dir.appendingPathComponent("events.jsonl"))) ?? Data()
      let parsed = DiagnosticReader.events(data)
      assertEquals(0, parsed.skipped)
      assertEquals(["session", "log", "recovered"], parsed.events.map { (event: [String: Any]) -> String in event["type"] as? String ?? "" })
      assertEquals(3, parsed.events.last?["seq"] as? Int ?? 0)
      assertEquals(UInt8(0x0A), data.last ?? 0)
      // İkinci kez mühürlenmez (özet dosyası var).
      _ = r.sessions()
      assertEquals(3, DiagnosticReader.lineCount((try? Data(contentsOf: dir.appendingPathComponent("events.jsonl"))) ?? Data()))
    }
    TestRun.test("DiagnosticRecorderTest.secretsAreScrubbedFromEveryLine") {
      let clock = DiagTestClock()
      let r = make(clock)
      defer { finish(r) }
      let secret = "AIzaSECRETKEY123"
      r.secrets = [secret, DiagnosticPrivacyTest.deepL]
      let id = startedId(r.start(version: "1", fields: ["settings": DiagnosticPrivacy.settings(DiagnosticPrivacyTest.settingsJson())]))
      Diag.emit("log") { ["text": .string("istek: https://g/v1?key=\(secret) ve \(secret) ve \(DiagnosticPrivacyTest.deepL)")] }
      r.waitIdle()
      r.stop()
      let content = text(folder(r, id).appendingPathComponent("events.jsonl"))
      assertFalse(content.isEmpty)
      for value in [secret, DiagnosticPrivacyTest.deepL, DiagnosticPrivacyTest.gemini, "GLOSSSECRET", "ACCOUNTSECRET"] {
        assertFalse(content.contains(value), "gizli değer kayıtta: \(value)")
      }
    }
    TestRun.test("DiagnosticRecorderTest.unwritableSessionLineDoesNotStart") {
      let clock = DiagTestClock()
      let r = make(clock, output: { (_: URL) -> DiagnosticOutput? in LimitedOutput(allowed: 0) })
      defer { finish(r) }
      let result = r.start(version: "1")
      if case .failed = result {} else { TestRun.fail("başarısız dönmeliydi: \(result)", #fileID, #line) }
      assertFalse(Diag.on, "bayrak açılmamalı")
      assertFalse(r.isRecording)
      assertFalse(r.status.recording)
      assertEquals(0, r.status.stops, "açılmayan kayıt 'durdu' sayılmaz")
      assertEquals(0, r.sessions().count, "yarım klasör kalmamalı")
      // Olay gelirse yazılmaz (kayıt yok).
      Diag.emit("log") { ["text": .string("x")] }
      r.waitIdle()
      assertFalse(r.isRecording)
    }
    TestRun.test("DiagnosticRecorderTest.writeFailureWhileRecordingStops") {
      let clock = DiagTestClock()
      let r = make(clock, output: { (_: URL) -> DiagnosticOutput? in LimitedOutput(allowed: 1) })
      defer { finish(r) }
      let id = startedId(r.start(version: "1"))
      assertTrue(Diag.on)
      Diag.emit("log") { ["text": .string("yazılamayacak")] }
      r.waitIdle()
      assertFalse(r.isRecording)
      assertFalse(Diag.on)
      assertEquals(DiagnosticStop.failed, r.status.lastStop)
      assertEquals("failed", r.summary(for: id)?.reason ?? "")
    }
    TestRun.test("DiagnosticRecorderTest.unsavedSealIsDoneOnlyOnce") {
      let clock = DiagTestClock()
      let r = make(clock)
      defer { finish(r) }
      let id = "20200101-130000"
      let dir = folder(r, id)
      let manager = FileManager.default
      try? manager.createDirectory(at: dir, withIntermediateDirectories: true)
      let events = dir.appendingPathComponent("events.jsonl")
      try? Data("{\"seq\":1,\"t\":0,\"type\":\"session\",\"version\":\"1.8.5\"}\n{\"seq\":2,\"t\":9,\"ty".utf8).write(to: events)
      // summary.json yerinde bir klasör var: özet yazılamaz (disk dolu benzeri), okunamaz.
      try? manager.createDirectory(at: dir.appendingPathComponent("summary.json/engel"), withIntermediateDirectories: true)
      for _ in 0..<3 {
        let summary = r.sessions().first
        assertEquals(id, summary?.id ?? "")
        assertTrue(summary?.interrupted ?? false)
        assertEquals(2, summary?.events ?? 0)
      }
      // Mühür satırı bir kez eklendi; dosya her yoklamada yeniden onarılmadı.
      let data: Data = (try? Data(contentsOf: events)) ?? Data()
      assertEquals(2, DiagnosticReader.lineCount(data))
      assertEquals(["session", "recovered"], DiagnosticReader.events(data).events.map { (event: [String: Any]) -> String in
        event["type"] as? String ?? ""
      })
    }
    TestRun.test("DiagnosticRecorderTest.deleteAndExport") {
      let clock = DiagTestClock()
      let r = make(clock)
      defer { finish(r) }
      let jpeg: DiagnosticFrameEncoder = { () -> Data? in Data([0xFF, 0xD8, 0xFF, 0xD9]) }
      r.frameGrabber = { () -> DiagnosticFrameEncoder? in jpeg }
      let id = startedId(r.start(version: "1.8.4"))
      assertFalse(r.delete(id), "süren kayıt silinmez")
      assertNull(r.folder(for: id), "süren kayıt paylaşılmaz")
      Diag.emit("pulse", frame: "pulse") { ["phase": .string("idle")] }
      r.waitIdle()
      r.stop()
      guard let dir = r.folder(for: id) else { return TestRun.fail("klasör yok", #fileID, #line) }
      let sink = DataZipSink()
      let base = DiagnosticNames.exportBase(version: "1.8.4", sessionId: id)
      try DiagnosticExport.write(folder: dir, root: base, to: sink)
      guard let files = unzip(sink.data) else { return TestRun.fail("zip okunamadı", #fileID, #line) }
      assertEquals([base + "/events.jsonl", base + "/frames/0001.jpg", base + "/summary.json"], files.keys.sorted())
      assertEquals(Data([0xFF, 0xD8, 0xFF, 0xD9]), files[base + "/frames/0001.jpg"] ?? Data())
      assertEquals((try? Data(contentsOf: dir.appendingPathComponent("events.jsonl"))) ?? Data(), files[base + "/events.jsonl"] ?? Data([1]))
      assertNull(r.folder(for: "../\(id)"))
      assertTrue(r.delete(id))
      assertFalse(FileManager.default.fileExists(atPath: dir.path))
    }
  }
}

enum StoredZipTest {
  static func run() {
    TestRun.test("StoredZipTest.crc32KnownValues") {
      assertEquals(UInt32(0xCBF4_3926), ZipChecksum.of(Data("123456789".utf8)))
      assertEquals(UInt32(0x3610_A686), ZipChecksum.of(Data("hello".utf8)))
      assertEquals(UInt32(0), ZipChecksum.of(Data()))
      var running = CRC32()
      ZipChecksum.add(&running, Data("1234".utf8))
      ZipChecksum.add(&running, Data("56789".utf8))
      assertEquals(UInt32(0xCBF4_3926), running.value, "parça parça hesap")
      assertEquals(UInt32(0), CRC32().value, "boş hesap")
    }
    TestRun.test("StoredZipTest.dosTime") {
      var utc = Calendar(identifier: .gregorian)
      utc.timeZone = TimeZone(identifier: "UTC")!
      let date = utc.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 14, minute: 30, second: 42))!
      let dos = StoredZipWriter.dosTime(date, timeZone: TimeZone(identifier: "UTC")!)
      // 14<<11 | 30<<5 | 42/2 = 28672 + 960 + 21; (2026-1980)<<9 | 11<<5 | 19 = 23552 + 352 + 19.
      assertEquals(UInt16(29653), dos.time)
      assertEquals(UInt16(23923), dos.date)
    }
    TestRun.test("StoredZipTest.layoutIsValid") {
      let sink = DataZipSink()
      let writer = StoredZipWriter(sink: sink)
      let date = Date(timeIntervalSince1970: 1_800_000_000)
      let dos = StoredZipWriter.dosTime(date)
      try writer.add(name: "a.txt", data: Data("hello".utf8), modified: date)
      try writer.add(name: "d/b.txt", data: Data("123456789".utf8), modified: date)
      try writer.finish()
      let zip = sink.data
      // Yerel başlıklar 30+5+5 ve 30+7+9 = 86; merkezî dizin 46+5 ve 46+7 = 104; dizin sonu 22: toplam 212.
      assertEquals(212, zip.count)
      assertEquals(UInt32(0x0403_4B50), le32(zip, 0))
      assertEquals(20, le16(zip, 4))
      assertEquals(0x0800, le16(zip, 6))
      assertEquals(0, le16(zip, 8), "stored")
      assertEquals(Int(dos.time), le16(zip, 10))
      assertEquals(Int(dos.date), le16(zip, 12))
      assertEquals(UInt32(0x3610_A686), le32(zip, 14))
      assertEquals(UInt32(5), le32(zip, 18))
      assertEquals(UInt32(5), le32(zip, 22))
      assertEquals(5, le16(zip, 26))
      assertEquals(0, le16(zip, 28))
      assertEquals("a.txt", String(decoding: zip[30..<35], as: UTF8.self))
      assertEquals("hello", String(decoding: zip[35..<40], as: UTF8.self))
      assertEquals(UInt32(0x0403_4B50), le32(zip, 40))
      assertEquals(UInt32(0xCBF4_3926), le32(zip, 54))
      assertEquals(UInt32(9), le32(zip, 58))
      assertEquals(7, le16(zip, 66))
      assertEquals("d/b.txt", String(decoding: zip[70..<77], as: UTF8.self))
      assertEquals("123456789", String(decoding: zip[77..<86], as: UTF8.self))
      // Merkezî dizin 86'da.
      assertEquals(UInt32(0x0201_4B50), le32(zip, 86))
      assertEquals(UInt32(0x3610_A686), le32(zip, 102))
      assertEquals(UInt32(5), le32(zip, 106))
      assertEquals(5, le16(zip, 114))
      assertEquals(UInt32(0), le32(zip, 128), "ilk yerel başlığın yeri")
      assertEquals("a.txt", String(decoding: zip[132..<137], as: UTF8.self))
      assertEquals(UInt32(0x0201_4B50), le32(zip, 137))
      assertEquals(7, le16(zip, 165))
      assertEquals(UInt32(40), le32(zip, 179), "ikinci yerel başlığın yeri")
      // Dizin sonu 190'da: 2 kayıt, dizin boyu 104, yeri 86.
      assertEquals(UInt32(0x0605_4B50), le32(zip, 190))
      assertEquals(2, le16(zip, 198))
      assertEquals(2, le16(zip, 200))
      assertEquals(UInt32(104), le32(zip, 202))
      assertEquals(UInt32(86), le32(zip, 206))
      assertEquals(0, le16(zip, 210))
      assertEquals(["a.txt": Data("hello".utf8), "d/b.txt": Data("123456789".utf8)], unzip(zip) ?? [:])
    }
    TestRun.test("StoredZipTest.fileEntriesAreCopiedInChunks") {
      let dir = tempRoot()
      defer { try? FileManager.default.removeItem(at: dir) }
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      // Parça boyundan büyük dosya: iki geçişte CRC ve kopya.
      var bytes: [UInt8] = []
      let total: Int = StoredZipWriter.chunkSize * 2 + 123
      bytes.reserveCapacity(total)
      for index in 0..<total { bytes.append(UInt8(truncatingIfNeeded: index &* 31)) }
      let big = Data(bytes)
      let url = dir.appendingPathComponent("big.bin")
      try big.write(to: url)
      let sink = DataZipSink()
      let writer = StoredZipWriter(sink: sink)
      try writer.add(name: "big.bin", file: url, modified: Date())
      try writer.finish()
      assertEquals(big, unzip(sink.data)?["big.bin"] ?? Data())
      // Dosyaya yazan hedef de aynı baytları üretir.
      let out = dir.appendingPathComponent("out.zip")
      let file = try FileZipSink(url: out)
      let second = StoredZipWriter(sink: file)
      try second.add(name: "big.bin", file: url, modified: Date())
      try second.finish()
      file.close()
      assertEquals(big, unzip((try? Data(contentsOf: out)) ?? Data())?["big.bin"] ?? Data())
    }
  }
}
