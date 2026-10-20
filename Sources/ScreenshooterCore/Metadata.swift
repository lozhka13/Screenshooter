// Where a screenshot came from and what text it shows, kept in an extended attribute
// so it travels with the file when it moves.
import Foundation

public struct ShotMetadata: Codable, Equatable, Sendable {
  public var appBundleID: String?
  public var appName: String?
  public var url: String?
  public var pageTitle: String?
  public var windowTitle: String?
  public var text: String?  // recognized text
  public var summary: String?  // short on-device AI title

  public init(
    appBundleID: String? = nil, appName: String? = nil, url: String? = nil, pageTitle: String? = nil,
    windowTitle: String? = nil, text: String? = nil, summary: String? = nil
  ) {
    self.appBundleID = appBundleID
    self.appName = appName
    self.url = url
    self.pageTitle = pageTitle
    self.windowTitle = windowTitle
    self.text = text
    self.summary = summary
  }

  public var host: String? {
    url.flatMap { URL(string: $0)?.host() }.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
  }

  // Words that describe the content — titles and text, not URL parts like "https".
  public var contentText: String {
    [pageTitle, windowTitle, text].compactMap { $0 }.joined(separator: "\n")
  }

  // Everything searchable in one lowercase string.
  public var searchableText: String {
    [appName, url, pageTitle, windowTitle, summary, text].compactMap { $0 }.joined(separator: "\n").lowercased()
  }

  static let attribute = "com.screenshooter.meta"
  static let maxTextLength = 32_000

  public static func read(_ file: URL) -> ShotMetadata? {
    let size = getxattr(file.path, attribute, nil, 0, 0, 0)
    guard size > 0 else { return nil }
    var data = Data(count: size)
    let read = data.withUnsafeMutableBytes { getxattr(file.path, attribute, $0.baseAddress, size, 0, 0) }
    guard read == size else { return nil }
    return try? JSONDecoder().decode(ShotMetadata.self, from: data)
  }

  public func write(to file: URL) {
    var copy = self
    if let text, text.count > Self.maxTextLength { copy.text = String(text.prefix(Self.maxTextLength)) }
    guard let data = try? JSONEncoder().encode(copy) else { return }
    _ = data.withUnsafeBytes { setxattr(file.path, Self.attribute, $0.baseAddress, data.count, 0, 0) }
  }

  // Merges new fields into what the file already has.
  public static func update(_ file: URL, _ change: (inout ShotMetadata) -> Void) {
    var metadata = read(file) ?? ShotMetadata()
    change(&metadata)
    metadata.write(to: file)
  }
}

// The transcript of a recording sits next to it: "Recording.mov" → "Recording.txt".
public func transcriptURL(for video: URL) -> URL {
  video.deletingPathExtension().appendingPathExtension("txt")
}
