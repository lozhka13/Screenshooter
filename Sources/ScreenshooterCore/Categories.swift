// Categories from ~/Screenshots/categories.json.
import Foundation

public struct SortCategory: Hashable, Codable, Identifiable, Sendable {
  public var label: String
  public var folder: String
  public var hasSubfolders: Bool
  public var keywords: [String]  // words in a URL, title or the text that point to this category

  public var id: String { folder }

  public init(label: String, folder: String, hasSubfolders: Bool, keywords: [String] = []) {
    self.label = label
    self.folder = folder
    self.hasSubfolders = hasSubfolders
    self.keywords = keywords
  }

  enum CodingKeys: String, CodingKey {
    case label, folder, keywords
    case hasSubfolders = "subfolders"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    label = try container.decode(String.self, forKey: .label)
    folder = try container.decode(String.self, forKey: .folder)
    hasSubfolders = try container.decodeIfPresent(Bool.self, forKey: .hasSubfolders) ?? false
    keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(label, forKey: .label)
    try container.encode(folder, forKey: .folder)
    try container.encode(hasSubfolders, forKey: .hasSubfolders)
    if !keywords.isEmpty { try container.encode(keywords, forKey: .keywords) }
  }

  public var url: URL { base.appendingPathComponent(folder) }
}

public enum CategoryStore {
  public static let maxCount = 9  // one digit key each
  public static var fileURL: URL { base.appendingPathComponent("categories.json") }

  public static let defaults = [
    SortCategory(label: "Work", folder: "Work", hasSubfolders: false),
    SortCategory(label: "Projects", folder: "Projects", hasSubfolders: true),
    SortCategory(label: "Personal", folder: "Personal", hasSubfolders: true),
  ]

  public static func load() -> [SortCategory] {
    guard let data = try? Data(contentsOf: fileURL) else { return defaults }
    return decode(data) ?? defaults
  }

  public static func decode(_ data: Data) -> [SortCategory]? {
    guard let list = try? JSONDecoder().decode([SortCategory].self, from: data), !list.isEmpty else { return nil }
    return Array(list.prefix(maxCount))
  }

  public static func save(_ categories: [SortCategory]) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    try encoder.encode(Array(categories.prefix(maxCount))).write(to: fileURL, options: .atomic)
  }

  // A category by its label or folder, case-insensitive.
  public static func find(_ name: String, in categories: [SortCategory] = load()) -> SortCategory? {
    let key = name.lowercased()
    return categories.first { $0.label.lowercased() == key || $0.folder.lowercased() == key }
  }
}
