// Finds passwords, tokens, keys and card numbers in recognized text so they can be blurred.
import Foundation

public enum SecretDetector {
  // Text right after one of these words is treated as a secret.
  static let labelled = try! NSRegularExpression(
    pattern:
      #"(?i)\b(?:password|passwd|pwd|pass|passcode|пароль|token|токен|secret|api[ _-]?key|ключ|pin)\b(?:\s*[:=]\s*|\s+)([^\s"',;]{4,})"#)

  // Well-known token formats.
  static let formats = try! NSRegularExpression(
    pattern: [
      #"gh[pousr]_[A-Za-z0-9]{20,}"#,
      #"github_pat_[A-Za-z0-9_]{20,}"#,
      #"sk-(?:ant-|proj-)?[A-Za-z0-9_-]{20,}"#,
      #"xox[abpr]-[A-Za-z0-9-]{10,}"#,
      #"AKIA[0-9A-Z]{16}"#,
      #"AIza[0-9A-Za-z_-]{35}"#,
      #"eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"#,
      #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#,
    ].joined(separator: "|"))

  // user:password@host in URLs.
  static let urlCredentials = try! NSRegularExpression(pattern: #"[a-z][a-z0-9+.-]*://[^\s/:@]+:([^\s@/]+)@"#)

  static let cardNumber = try! NSRegularExpression(pattern: #"(?<!\d)(?:\d[ -]?){12,18}\d(?!\d)"#)

  // No "/" so URL paths don't count. Cyrillic is allowed because mixed-language OCR
  // reads some Latin letters of a token as their Cyrillic twins.
  static let longToken = try! NSRegularExpression(pattern: #"[A-Za-z0-9+_=\-А-Яа-яЁё]{20,}"#)

  static let latinTwins: [Character: Character] = [
    "А": "A", "В": "B", "Е": "E", "К": "K", "М": "M", "Н": "H", "О": "O", "Р": "P", "С": "C", "Т": "T",
    "Х": "X", "У": "Y", "З": "3", "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "у": "y", "х": "x",
    "к": "k", "и": "u", "п": "n", "г": "r", "т": "t", "м": "m",
  ]

  public static func secrets(in text: String) -> [Range<String.Index>] {
    var found: [Range<String.Index>] = []
    let whole = NSRange(text.startIndex..., in: text)

    for match in labelled.matches(in: text, range: whole) {
      if let range = Range(match.range(at: 1), in: text), looksLikePassword(text[range]) { found.append(range) }
    }
    for match in urlCredentials.matches(in: text, range: whole) {
      if let range = Range(match.range(at: 1), in: text) { found.append(range) }
    }
    for match in formats.matches(in: text, range: whole) {
      if let range = Range(match.range, in: text) { found.append(range) }
    }
    for match in cardNumber.matches(in: text, range: whole) {
      if let range = Range(match.range, in: text), luhn(text[range]) { found.append(range) }
    }
    for match in longToken.matches(in: text, range: whole) {
      guard let range = Range(match.range, in: text) else { continue }
      let token = Substring(String(text[range].map { latinTwins[$0] ?? $0 }))
      if token.contains(where: \.isASCII), looksRandom(token) { found.append(range) }
    }
    return merge(found)
  }

  // "Rotated" after "Password" is a word; "hunter2!" or "Qwerty123" is a password.
  static func looksLikePassword(_ token: Substring) -> Bool {
    token.contains { $0.isNumber || !$0.isLetter } || token.dropFirst().contains(where: \.isUppercase)
  }

  // Mixed case and digits with high entropy: generated passwords and keys, not words or hashes in prose.
  static func looksRandom(_ token: Substring) -> Bool {
    guard token.contains(where: \.isUppercase), token.contains(where: \.isLowercase),
      token.contains(where: \.isNumber)
    else { return false }
    var counts: [Character: Int] = [:]
    for character in token { counts[character, default: 0] += 1 }
    let length = Double(token.count)
    let entropy = counts.values.reduce(0.0) { sum, count in
      let p = Double(count) / length
      return sum - p * log2(p)
    }
    return entropy >= 3.5
  }

  static func luhn(_ number: Substring) -> Bool {
    let digits = number.compactMap(\.wholeNumberValue)
    guard (13...19).contains(digits.count) else { return false }
    let sum = digits.reversed().enumerated().reduce(0) { sum, item in
      let (index, digit) = item
      guard index % 2 == 1 else { return sum + digit }
      let doubled = digit * 2
      return sum + (doubled > 9 ? doubled - 9 : doubled)
    }
    return sum % 10 == 0
  }

  // Overlapping matches (a labelled token that also looks random) count once.
  static func merge(_ ranges: [Range<String.Index>]) -> [Range<String.Index>] {
    var merged: [Range<String.Index>] = []
    for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
      if let last = merged.last, range.lowerBound <= last.upperBound {
        merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
      } else {
        merged.append(range)
      }
    }
    return merged
  }

  // Boxes (normalized, top-left origin) of every secret in the recognized lines.
  public static func boxes(in lines: [TextLine]) -> [CGRect] {
    lines.flatMap { line in secrets(in: line.text).map { line.box(for: $0) } }
  }
}
