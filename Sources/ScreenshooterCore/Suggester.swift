// Suggests a folder from where a screenshot was taken and what it shows,
// learning from where similar screenshots went before.
import Foundation

public struct Suggestion: Equatable, Sendable {
  public let category: SortCategory
  public let subfolder: String?
  public let score: Double

  public var label: String { [category.label, subfolder].compactMap { $0 }.joined(separator: " › ") }
}

public struct Example: Codable, Equatable, Sendable {
  public var host: String?
  public var app: String?
  public var words: [String]
  public var folder: String  // relative to ~/Screenshots, e.g. "Verstka/Atlas"
  public var file: String  // where the screenshot went, so an undo can forget it
}

public final class Suggester {
  public static let threshold = 4.0
  static let maxExamples = 500
  static let browsers: Set<String> = [
    "com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser", "org.mozilla.firefox",
    "com.microsoft.edgemac", "com.brave.Browser",
  ]

  let fileURL: URL
  public private(set) var examples: [Example]

  public init(fileURL: URL = stateFolder.appendingPathComponent("learned.json")) {
    self.fileURL = fileURL
    examples = (try? JSONDecoder().decode([Example].self, from: Data(contentsOf: fileURL))) ?? []
  }

  public func suggest(_ metadata: ShotMetadata, categories: [SortCategory]) -> Suggestion? {
    let words = Set(Self.keywords(in: metadata.contentText))
    var scores: [String: Double] = [:]

    for example in examples {
      var score = 0.0
      if let host = metadata.host, host == example.host { score += 6 }
      if let app = metadata.appBundleID, app == example.app {
        score += Self.browsers.contains(app) ? 0.5 : 2  // a browser alone says little
      }
      // The same screen again shares most of its words; a few common ones mean nothing.
      let shared = words.intersection(example.words).count
      if shared >= 3 { score += 6 * Double(shared) / Double(max(1, min(words.count, example.words.count))) }
      scores[example.folder] = max(scores[example.folder] ?? 0, score)
    }
    // Keywords set on a category in categories.json.
    let haystack = metadata.searchableText
    for category in categories where category.keywords.contains(where: { haystack.contains($0.lowercased()) }) {
      scores[category.folder] = max(scores[category.folder] ?? 0, 5)
    }

    for (folder, score) in scores.sorted(by: { $0.value > $1.value }) where score >= Self.threshold {
      let parts = folder.split(separator: "/", maxSplits: 1).map(String.init)
      guard let category = categories.first(where: { $0.folder == parts[0] }) else { continue }
      let subfolder = parts.count > 1 && category.hasSubfolders ? parts[1] : nil
      if let subfolder, !FileManager.default.fileExists(atPath: category.url.appendingPathComponent(subfolder).path) {
        continue
      }
      return Suggestion(category: category, subfolder: subfolder, score: score)
    }
    return nil
  }

  public func learn(_ metadata: ShotMetadata, folder: String, file: String) {
    examples.append(
      Example(
        host: metadata.host, app: metadata.appBundleID, words: Self.keywords(in: metadata.contentText),
        folder: folder, file: file))
    if examples.count > Self.maxExamples { examples.removeFirst(examples.count - Self.maxExamples) }
    save()
  }

  public func forget(file: String) {
    examples.removeAll { $0.file == file }
    save()
  }

  func save() {
    try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? JSONEncoder().encode(examples).write(to: fileURL, options: .atomic)
  }

  // The 30 most frequent words of four or more letters.
  public static func keywords(in text: String) -> [String] {
    var counts: [String: Int] = [:]
    for word in text.lowercased().split(whereSeparator: { !$0.isLetter }) where word.count >= 4 {
      counts[String(word), default: 0] += 1
    }
    return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(30).map(\.key)
  }
}
