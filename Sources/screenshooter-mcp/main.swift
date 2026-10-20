// MCP server for Claude: list, search, view and file the screenshots in ~/Screenshots,
// and read transcripts of screen recordings. JSON-RPC 2.0 over stdio, one message per line.
// Reads and writes only inside ~/Screenshots.
// Register: claude mcp add --scope user screenshooter /Applications/Screenshooter.app/Contents/MacOS/screenshooter-mcp
import Foundation
import ScreenshooterCore
import UniformTypeIdentifiers

let serverVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
let defaultImageSize = 1568  // long edge Claude handles without downscaling

struct ToolError: LocalizedError {
  let errorDescription: String?
  init(_ message: String) { errorDescription = message }
}

let dateFormatter: DateFormatter = {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.dateFormat = "yyyy-MM-dd HH:mm"
  return formatter
}()

func describe(_ url: URL) -> String {
  let size = ByteCountFormatter.string(fromByteCount: Int64(Library.fileSize(url)), countStyle: .file)
  var line = "\(Library.relativePath(url)) — \(dateFormatter.string(from: Library.creationDate(url))), \(size)"
  if let metadata = ShotMetadata.read(url), let source = metadata.pageTitle ?? metadata.appName {
    line += " · \(source)"
  }
  if isVideo(url) && FileManager.default.fileExists(atPath: transcriptURL(for: url).path) { line += " · transcript" }
  return line
}

// "Inbox", a category, and optionally a subfolder → folder on disk; nothing → everything.
func folder(category name: String?, subfolder: String?) throws -> URL {
  guard let name, !name.isEmpty else { return base }
  var url: URL
  if name.lowercased() == "inbox" {
    url = inbox
  } else if let category = CategoryStore.find(name) {
    url = category.url
  } else {
    let known = CategoryStore.load().map(\.label).joined(separator: ", ")
    throw ToolError("Unknown category “\(name)”. Known: \(known), Inbox")
  }
  if let subfolder, !subfolder.isEmpty { url.appendPathComponent(subfolder) }
  guard FileManager.default.fileExists(atPath: url.path) else { throw ToolError("No such folder: \(url.path)") }
  return url
}

func imageContent(_ url: URL, maxSize: Int) async throws -> [String: Any] {
  let image = try await Images.load(url, maxSize: maxSize)
  let data = try Images.encode(image, as: .jpeg)
  return ["type": "image", "data": data.base64EncodedString(), "mimeType": "image/jpeg"]
}

func text(_ string: String) -> [String: Any] { ["type": "text", "text": string] }

func listed(_ urls: [URL], limit: Int) -> [[String: Any]] {
  guard !urls.isEmpty else { return [text("Nothing found.")] }
  let shown = urls.prefix(limit).map(describe).joined(separator: "\n")
  return [text(shown + (urls.count > limit ? "\n…and \(urls.count - limit) more" : ""))]
}

// MARK: - Tools

var categoryHint: String {
  "Category label or folder (\(CategoryStore.load().map(\.label).joined(separator: ", "))) or Inbox"
}

func schema(_ properties: [String: [String: Any]], required: [String] = []) -> [String: Any] {
  ["type": "object", "properties": properties, "required": required]
}

let pathProperty: [String: Any] = ["type": "string", "description": "Path from a listing, relative to ~/Screenshots"]
let categoryProperty: [String: Any] = ["type": "string", "description": categoryHint]
let subfolderProperty: [String: Any] = ["type": "string", "description": "Subfolder inside the category"]
let limitProperty: [String: Any] = ["type": "integer", "description": "Max results (default 20)"]

let tools: [[String: Any]] = [
  [
    "name": "list_categories",
    "description": "List the screenshot categories, their subfolders and how many files each holds, plus Inbox (not sorted yet).",
    "inputSchema": schema([:]),
  ],
  [
    "name": "list_screenshots",
    "description": "List screenshots and screen recordings, newest first. Paths are relative to ~/Screenshots.",
    "inputSchema": schema([
      "category": categoryProperty, "subfolder": subfolderProperty,
      "since": ["type": "string", "description": "Only files created on or after this date (YYYY-MM-DD)"],
      "limit": limitProperty,
    ]),
  ],
  [
    "name": "search_screenshots",
    "description": "Find screenshots and recordings by the text they show, page title, address, app, file name or transcript. All words must match. Text is recognized on this Mac the first time a file is searched.",
    "inputSchema": schema(
      ["query": ["type": "string", "description": "Words to find"], "category": categoryProperty, "limit": limitProperty],
      required: ["query"]),
  ],
  [
    "name": "get_screenshot",
    "description": "Show a screenshot as an image (first frame for a screen recording), with where it was taken.",
    "inputSchema": schema(
      ["path": pathProperty, "max_size": ["type": "integer", "description": "Long edge in pixels (default \(defaultImageSize))"]],
      required: ["path"]),
  ],
  [
    "name": "latest_screenshot",
    "description": "Show the most recent screenshot, optionally within a category or subfolder.",
    "inputSchema": schema(["category": categoryProperty, "subfolder": subfolderProperty]),
  ],
  [
    "name": "move_screenshot",
    "description": "File a screenshot into a category (and subfolder, created if missing). It's compressed in the background afterwards.",
    "inputSchema": schema(
      ["path": pathProperty, "category": categoryProperty, "subfolder": subfolderProperty], required: ["path", "category"]),
  ],
  [
    "name": "list_recordings",
    "description": "List screen recordings, newest first, and whether each has a transcript.",
    "inputSchema": schema(["category": categoryProperty, "limit": limitProperty]),
  ],
  [
    "name": "get_transcript",
    "description": "Read the transcript of a screen recording as timestamped lines. Transcribes on this Mac if there isn't one yet, which takes a fraction of the recording's length.",
    "inputSchema": schema(["path": pathProperty], required: ["path"]),
  ],
]

func callTool(_ name: String, _ arguments: [String: Any]) async throws -> [[String: Any]] {
  let string = { (key: String) in (arguments[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
  let limit = max(1, arguments["limit"] as? Int ?? 20)

  switch name {
  case "list_categories":
    var lines = ["Inbox — \(Library.mediaFiles(in: inbox).count) files (not sorted yet)"]
    for (index, category) in CategoryStore.load().enumerated() {
      var line = "\(category.label) [key \(index + 1), folder \(category.folder)] — \(Library.mediaFiles(in: category.url).count) files"
      let subfolders = Library.subfolders(of: category.url)
      if !subfolders.isEmpty {
        line += "; subfolders: "
          + subfolders.map { "\($0) (\(Library.mediaFiles(in: category.url.appendingPathComponent($0)).count))" }
          .joined(separator: ", ")
      }
      lines.append(line)
    }
    return [text(lines.joined(separator: "\n"))]

  case "list_screenshots":
    var found = Library.mediaFiles(in: try folder(category: string("category"), subfolder: string("subfolder")))
    if let since = string("since") {
      guard let day = try? Date(since, strategy: .iso8601.year().month().day()) else {
        throw ToolError("“since” must look like 2026-10-20")
      }
      found = found.filter { Library.creationDate($0) >= day }
    }
    return listed(found, limit: limit)

  case "search_screenshots":
    guard let query = string("query") else { throw ToolError("“query” is required") }
    let words = query.lowercased().split(separator: " ").map(String.init)
    var matches: [URL] = []
    for url in Library.mediaFiles(in: try folder(category: string("category"), subfolder: nil)) {
      var haystack = url.lastPathComponent.lowercased() + "\n" + (ShotMetadata.read(url)?.searchableText ?? "")
      if !isVideo(url) && ShotMetadata.read(url)?.text == nil {
        haystack += "\n" + (await TextRecognizer.text(of: url)).lowercased()
      }
      if isVideo(url), let transcript = try? String(contentsOf: transcriptURL(for: url), encoding: .utf8) {
        haystack += "\n" + transcript.lowercased()
      }
      if words.allSatisfy(haystack.contains) { matches.append(url) }
      if matches.count >= limit { break }
    }
    return listed(matches, limit: limit)

  case "get_screenshot":
    guard let path = string("path") else { throw ToolError("“path” is required") }
    let url = try Library.resolve(path)
    let image = try await imageContent(url, maxSize: arguments["max_size"] as? Int ?? defaultImageSize)
    var info = describe(url)
    if let metadata = ShotMetadata.read(url) {
      if let address = metadata.url { info += "\nPage: \(address)" }
      if let window = metadata.windowTitle { info += "\nWindow: \(window)" }
    }
    return [text(info), image]

  case "latest_screenshot":
    guard let latest = Library.mediaFiles(in: try folder(category: string("category"), subfolder: string("subfolder"))).first
    else { return [text("Nothing found.")] }
    return [text(describe(latest)), try await imageContent(latest, maxSize: defaultImageSize)]

  case "move_screenshot":
    guard let path = string("path"), let categoryName = string("category") else {
      throw ToolError("“path” and “category” are required")
    }
    let source = try Library.resolve(path)
    guard let category = CategoryStore.find(categoryName) else { throw ToolError("Unknown category “\(categoryName)”") }
    var target = category.url
    if let sub = string("subfolder") {
      guard let clean = Library.cleanFolderName(sub), clean == sub else { throw ToolError("Invalid subfolder name") }
      target.appendPathComponent(clean)
    }
    let destination = try Library.move(source, to: target)
    let transcript = transcriptURL(for: source)
    if FileManager.default.fileExists(atPath: transcript.path) {
      try? FileManager.default.moveItem(at: transcript, to: transcriptURL(for: destination))
    }
    if Preferences.compress {
      let compressor = Process()
      compressor.executableURL = URL(fileURLWithPath: "/usr/bin/nice")
      compressor.arguments = ["-n", "15", compressScript, destination.path]
      try? compressor.run()
    }
    return [text("Moved to \(Library.relativePath(destination))")]

  case "list_recordings":
    let recordings = Library.mediaFiles(in: try folder(category: string("category"), subfolder: nil)).filter(isVideo)
    return listed(recordings, limit: limit)

  case "get_transcript":
    guard let path = string("path") else { throw ToolError("“path” is required") }
    let url = try Library.resolve(path)
    guard isVideo(url) else { throw ToolError("Not a recording: \(path)") }
    let file = try await Transcriber.transcribeNextTo(url)
    let transcript = try String(contentsOf: file, encoding: .utf8)
    return [text(transcript.isEmpty ? "No speech found in the recording." : transcript)]

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
      send(["jsonrpc": "2.0", "id": id, "result": ["content": [text(error.localizedDescription)], "isError": true]])
    }
  default:
    send(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found"]])
  }
}
