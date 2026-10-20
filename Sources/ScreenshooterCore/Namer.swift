// Readable file names: "2026-10-20 10.42.15 — Grafana · CPU usage.png" instead of "Screenshot …".
import CoreGraphics
import Foundation

public enum Namer {
  static let maxTitleLength = 60
  static let datePattern = try! NSRegularExpression(pattern: #"(\d{4}-\d{2}-\d{2})\D+?(\d{1,2}[.:]\d{2}[.:]\d{2})"#)

  public static func name(for url: URL, metadata: ShotMetadata?, headline: String?) -> String {
    let title = [metadata?.pageTitle, metadata?.windowTitle, metadata?.summary, headline, metadata?.appName]
      .compactMap { $0.flatMap(clean) }
      .first
    guard let title else { return url.lastPathComponent }
    let ext = url.pathExtension
    return "\(timestamp(for: url)) — \(title)" + (ext.isEmpty ? "" : ".\(ext)")
  }

  // Date and time from the macOS file name, or the creation date.
  static func timestamp(for url: URL) -> String {
    let name = url.deletingPathExtension().lastPathComponent
    if let match = datePattern.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
      let day = Range(match.range(at: 1), in: name), let time = Range(match.range(at: 2), in: name)
    {
      let parts = name[time].split(whereSeparator: { $0 == "." || $0 == ":" })
      return "\(name[day]) " + parts.map { $0.count == 1 ? "0\($0)" : String($0) }.joined(separator: ".")
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
    return formatter.string(from: Library.creationDate(url))
  }

  // Safe for a file name: no slashes or colons, single spaces, trimmed to a sensible length.
  static func clean(_ title: String) -> String? {
    var text = title.replacingOccurrences(of: #"[/:\\\n\r\t]"#, with: " ", options: .regularExpression)
      .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet.whitespaces.union(.punctuationCharacters))
    guard text.count >= 3, text.contains(where: \.isLetter) else { return nil }
    if text.count > maxTitleLength {
      text = String(text.prefix(maxTitleLength))
      if let space = text.lastIndex(of: " "), text.distance(from: text.startIndex, to: space) > maxTitleLength / 2 {
        text = String(text[..<space])
      }
      text += "…"
    }
    return text
  }

  // The biggest text in the top part of the screen, usually a heading or window title.
  public static func headline(from lines: [(text: String, box: CGRect)]) -> String? {
    lines
      .filter { line in
        let words = line.text.split(separator: " ").filter { $0.contains(where: \.isLetter) }
        return line.box.minY < 0.5 && words.count >= 2 && line.text.count <= 80  // one stray word isn't a heading
      }
      .max { $0.box.height < $1.box.height }?
      .text
  }
}
