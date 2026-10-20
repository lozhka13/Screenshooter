// Listing, moving and resolving files inside ~/Screenshots.
import Foundation

public enum LibraryError: LocalizedError {
  case outside(String)
  case missing(String)

  public var errorDescription: String? {
    switch self {
    case .outside: "Only files inside \(base.path) are available"
    case .missing(let path): "No such file: \(path)"
    }
  }
}

public enum Library {
  static var rootPath: String { base.standardizedFileURL.resolvingSymlinksInPath().path + "/" }

  // Media files, newest first; recursive includes subfolders.
  public static func mediaFiles(in folder: URL, recursive: Bool = true) -> [URL] {
    let keys: [URLResourceKey] = [.creationDateKey, .isRegularFileKey]
    var urls: [URL] = []
    if recursive {
      let walker = FileManager.default.enumerator(
        at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants])
      while let url = walker?.nextObject() as? URL { urls.append(url) }
    } else {
      urls = (try? FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
    }
    return urls
      .filter { isMedia($0) && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
      .map { $0.standardizedFileURL.resolvingSymlinksInPath() }
      .sorted { creationDate($0) > creationDate($1) }
  }

  public static func creationDate(_ url: URL) -> Date {
    (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
  }

  public static func fileSize(_ url: URL) -> Int {
    (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
  }

  public static func subfolders(of url: URL) -> [String] {
    let items = (try? FileManager.default.contentsOfDirectory(
      at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
    return items
      .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
      .map(\.lastPathComponent)
      .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
  }

  // "name.png", then "name 2.png", "name 3.png"… — never overwrites.
  public static func uniqueDestination(named name: String, in folder: URL) -> URL {
    let ext = (name as NSString).pathExtension
    let stem = (name as NSString).deletingPathExtension
    var destination = folder.appendingPathComponent(name)
    var copy = 2
    while FileManager.default.fileExists(atPath: destination.path) {
      destination = folder.appendingPathComponent(ext.isEmpty ? "\(stem) \(copy)" : "\(stem) \(copy).\(ext)")
      copy += 1
    }
    return destination
  }

  // Moves a file into a folder (created if missing), optionally renaming it; returns where it landed.
  @discardableResult
  public static func move(_ url: URL, to folder: URL, name: String? = nil) throws -> URL {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let destination = uniqueDestination(named: name ?? url.lastPathComponent, in: folder)
    try FileManager.default.moveItem(at: url, to: destination)
    return destination
  }

  // A path relative to ~/Screenshots or absolute; must exist and stay inside ~/Screenshots.
  public static func resolve(_ path: String) throws -> URL {
    let expanded = (path as NSString).expandingTildeInPath
    let url = (expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : base.appendingPathComponent(expanded))
      .standardizedFileURL.resolvingSymlinksInPath()
    guard url.path.hasPrefix(rootPath) else { throw LibraryError.outside(path) }
    guard FileManager.default.fileExists(atPath: url.path) else { throw LibraryError.missing(path) }
    return url
  }

  public static func relativePath(_ url: URL) -> String {
    let path = url.standardizedFileURL.resolvingSymlinksInPath().path
    return path.hasPrefix(rootPath) ? String(path.dropFirst(rootPath.count)) : path
  }

  // Valid folder name: no slashes, not hidden, not empty.
  public static func cleanFolderName(_ name: String) -> String? {
    let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
    return cleaned.isEmpty || cleaned.hasPrefix(".") ? nil : cleaned
  }
}
