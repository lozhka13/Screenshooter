// MCP server for Claude: list, view and file the screenshots Screenshooter keeps in ~/Screenshots.
// Speaks JSON-RPC 2.0 over stdio, one message per line. Reads and writes only inside ~/Screenshots.
// Build and install: ./install.sh
// Register: claude mcp add --scope user screenshooter /Applications/Screenshooter.app/Contents/MacOS/screenshooter-mcp
import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

let serverVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
let defaultImageSize = 1568  // long edge Claude handles without downscaling

struct ToolError: Error {
  let message: String
  init(_ message: String) { self.message = message }
}

// MARK: - Files

struct Shot {
  let url: URL
  let date: Date
  let size: Int

  var relativePath: String { String(url.path.dropFirst(rootPath.count)) }
}

let rootPath = base.standardizedFileURL.resolvingSymlinksInPath().path + "/"
let mediaExtensions = imageExtensions.union(videoExtensions)

func shot(_ url: URL) -> Shot? {
  guard mediaExtensions.contains(url.pathExtension.lowercased()),
    let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey, .isRegularFileKey]),
    values.isRegularFile == true
  else { return nil }
  return Shot(url: url.standardizedFileURL.resolvingSymlinksInPath(), date: values.creationDate ?? .distantPast,
    size: values.fileSize ?? 0)
}

// Newest first. Without a subfolder the whole category is searched, subfolders included.
func shots(in folder: URL) -> [Shot] {
  guard let walker = FileManager.default.enumerator(
    at: folder, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey, .isRegularFileKey],
    options: [.skipsHiddenFiles, .skipsPackageDescendants])
  else { return [] }
  return walker.compactMap { ($0 as? URL).flatMap(shot) }.sorted { $0.date > $1.date }
}

func category(named name: String) throws -> Category {
  let key = name.lowercased()
  guard let match = categories.first(where: { $0.label.lowercased() == key || $0.folder.lowercased() == key })
  else {
    throw ToolError("Unknown category “\(name)”. Known: \(categories.map(\.label).joined(separator: ", ")), Inbox")
  }
  return match
}

// "Inbox", a category, and optionally a subfolder → folder on disk.
func folder(category name: String?, subfolder: String?) throws -> URL {
  guard let name, !name.isEmpty else { return base }
  var url = name.lowercased() == "inbox" ? inbox : base.appendingPathComponent(try category(named: name).folder)
  if let subfolder, !subfolder.isEmpty { url.appendPathComponent(subfolder) }
  guard FileManager.default.fileExists(atPath: url.path) else { throw ToolError("No such folder: \(url.path)") }
  return url
}

func subfolders(of url: URL) -> [String] {
  let items = (try? FileManager.default.contentsOfDirectory(
    at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
  return items
    .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    .map(\.lastPathComponent)
    .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
}

// A path from Claude, relative to ~/Screenshots or absolute, that must stay inside ~/Screenshots.
func resolve(_ path: String) throws -> URL {
  let expanded = (path as NSString).expandingTildeInPath
  let url = (expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : base.appendingPathComponent(expanded))
    .standardizedFileURL.resolvingSymlinksInPath()
  guard url.path.hasPrefix(rootPath) else { throw ToolError("Only files inside \(base.path) are available") }
  guard FileManager.default.fileExists(atPath: url.path) else { throw ToolError("No such file: \(path)") }
  return url
}

let dateFormatter: DateFormatter = {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.dateFormat = "yyyy-MM-dd HH:mm"
  return formatter
}()

func describe(_ shot: Shot) -> String {
  let date = dateFormatter.string(from: shot.date)
  let size = ByteCountFormatter.string(fromByteCount: Int64(shot.size), countStyle: .file)
  return "\(shot.relativePath) — \(date), \(size)"
}

// MARK: - Images

// JPEG with the long edge scaled down to `maxSize`; video → first frame.
func imageContent(_ url: URL, maxSize: Int) async throws -> [String: Any] {
  let frame: CGImage
  if videoExtensions.contains(url.pathExtension.lowercased()) {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: maxSize, height: maxSize)
    frame = try await generator.image(at: .zero).image
  } else {
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxSize,
    ]
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else { throw ToolError("Can't read image: \(url.lastPathComponent)") }
    frame = image
  }
  let data = NSMutableData()
  guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
  else { throw ToolError("Can't encode image") }
  CGImageDestinationAddImage(destination, frame, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
  guard CGImageDestinationFinalize(destination) else { throw ToolError("Can't encode image") }
  return ["type": "image", "data": (data as Data).base64EncodedString(), "mimeType": "image/jpeg"]
}

func text(_ string: String) -> [String: Any] { ["type": "text", "text": string] }

// MARK: - Tools

let categoryHint = "Category label or folder (\(categories.map(\.label).joined(separator: ", "))) or Inbox"

let tools: [[String: Any]] = [
  [
    "name": "list_categories",
    "description": "List the screenshot categories, their subfolders and how many files each holds, plus Inbox (not sorted yet).",
    "inputSchema": ["type": "object", "properties": [String: Any]()],
  ],
  [
    "name": "list_screenshots",
    "description": "List screenshots and screen recordings, newest first. Returns paths relative to ~/Screenshots.",
    "inputSchema": [
      "type": "object",
      "properties": [
        "category": ["type": "string", "description": categoryHint + ". Omit to search everything."],
        "subfolder": ["type": "string", "description": "Subfolder inside the category"],
        "since": ["type": "string", "description": "Only files created on or after this date (YYYY-MM-DD)"],
        "limit": ["type": "integer", "description": "Max files to return (default 20)"],
      ],
    ],
  ],
  [
    "name": "get_screenshot",
    "description": "Show a screenshot as an image (first frame for a screen recording).",
    "inputSchema": [
      "type": "object",
      "properties": [
        "path": ["type": "string", "description": "Path from list_screenshots, relative to ~/Screenshots"],
        "max_size": ["type": "integer", "description": "Long edge in pixels (default \(defaultImageSize))"],
      ],
      "required": ["path"],
    ],
  ],
  [
    "name": "latest_screenshot",
    "description": "Show the most recent screenshot, optionally within a category or subfolder.",
    "inputSchema": [
      "type": "object",
      "properties": [
        "category": ["type": "string", "description": categoryHint],
        "subfolder": ["type": "string", "description": "Subfolder inside the category"],
      ],
    ],
  ],
  [
    "name": "move_screenshot",
    "description": "File a screenshot into a category (and subfolder, created if missing). The file is then compressed in the background.",
    "inputSchema": [
      "type": "object",
      "properties": [
        "path": ["type": "string", "description": "Path from list_screenshots, relative to ~/Screenshots"],
        "category": ["type": "string", "description": "Category label or folder"],
        "subfolder": ["type": "string", "description": "Subfolder inside the category"],
      ],
      "required": ["path", "category"],
    ],
  ],
]

func callTool(_ name: String, _ arguments: [String: Any]) async throws -> [[String: Any]] {
  let string = { (key: String) in (arguments[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
  switch name {
  case "list_categories":
    var lines = ["Inbox — \(shots(in: inbox).count) files (not sorted yet)"]
    for (index, item) in categories.enumerated() {
      let url = base.appendingPathComponent(item.folder)
      var line = "\(item.label) [key \(index + 1), folder \(item.folder)] — \(shots(in: url).count) files"
      let subs = subfolders(of: url)
      if !subs.isEmpty {
        line += "; subfolders: "
          + subs.map { "\($0) (\(shots(in: url.appendingPathComponent($0)).count))" }.joined(separator: ", ")
      }
      lines.append(line)
    }
    return [text(lines.joined(separator: "\n"))]

  case "list_screenshots":
    var found = shots(in: try folder(category: string("category"), subfolder: string("subfolder")))
    if let since = string("since") {
      guard let day = try? Date(since, strategy: .iso8601.year().month().day()) else {
        throw ToolError("“since” must look like 2026-10-20")
      }
      found = found.filter { $0.date >= day }
    }
    let limit = max(1, arguments["limit"] as? Int ?? 20)
    guard !found.isEmpty else { return [text("No screenshots found.")] }
    let shown = found.prefix(limit).map(describe).joined(separator: "\n")
    let more = found.count > limit ? "\n…and \(found.count - limit) more" : ""
    return [text(shown + more)]

  case "get_screenshot":
    guard let path = string("path") else { throw ToolError("“path” is required") }
    let url = try resolve(path)
    let image = try await imageContent(url, maxSize: arguments["max_size"] as? Int ?? defaultImageSize)
    return [text(shot(url).map(describe) ?? path), image]

  case "latest_screenshot":
    guard let latest = shots(in: try folder(category: string("category"), subfolder: string("subfolder"))).first
    else { return [text("No screenshots found.")] }
    return [text(describe(latest)), try await imageContent(latest.url, maxSize: defaultImageSize)]

  case "move_screenshot":
    guard let path = string("path"), let categoryName = string("category") else {
      throw ToolError("“path” and “category” are required")
    }
    let source = try resolve(path)
    var target = base.appendingPathComponent(try category(named: categoryName).folder)
    if let sub = string("subfolder") {
      guard !sub.contains("/"), !sub.hasPrefix(".") else { throw ToolError("Invalid subfolder name") }
      target.appendPathComponent(sub)
    }
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    var destination = target.appendingPathComponent(source.lastPathComponent)
    var copy = 2
    while FileManager.default.fileExists(atPath: destination.path) {
      destination = target.appendingPathComponent(
        "\(source.deletingPathExtension().lastPathComponent) \(copy).\(source.pathExtension)")
      copy += 1
    }
    try FileManager.default.moveItem(at: source, to: destination)
    // Same background compression the app runs after a move.
    let compressor = Process()
    compressor.executableURL = URL(fileURLWithPath: "/usr/bin/nice")
    compressor.arguments = ["-n", "15", compressScript, destination.path]
    try? compressor.run()
    return [text("Moved to \(shot(destination)?.relativePath ?? destination.path)")]

  default:
    throw ToolError("Unknown tool: \(name)")
  }
}

// MARK: - JSON-RPC over stdio

func send(_ message: [String: Any]) {
  guard var data = try? JSONSerialization.data(withJSONObject: message) else { return }
  data.append(0x0A)
  FileHandle.standardOutput.write(data)
}

while let line = readLine() {
  guard let message = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
    let id = message["id"]  // notifications (no id) need no reply
  else { continue }
  let params = message["params"] as? [String: Any] ?? [:]

  switch message["method"] as? String {
  case "initialize":
    send([
      "jsonrpc": "2.0", "id": id,
      "result": [
        "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
        "capabilities": ["tools": [String: Any]()],
        "serverInfo": ["name": "screenshooter", "version": serverVersion],
      ],
    ])
  case "ping":
    send(["jsonrpc": "2.0", "id": id, "result": [String: Any]()])
  case "tools/list":
    send(["jsonrpc": "2.0", "id": id, "result": ["tools": tools]])
  case "tools/call":
    let name = params["name"] as? String ?? ""
    let arguments = params["arguments"] as? [String: Any] ?? [:]
    do {
      send(["jsonrpc": "2.0", "id": id, "result": ["content": try await callTool(name, arguments)]])
    } catch {
      let reason = (error as? ToolError)?.message ?? error.localizedDescription
      send(["jsonrpc": "2.0", "id": id, "result": ["content": [text(reason)], "isError": true]])
    }
  default:
    send(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found"]])
  }
}
