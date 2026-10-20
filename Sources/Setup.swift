// First-run setup when Screenshooter.app is opened from Finder, and the status window.
import Cocoa

enum Setup {
  static let label = "com.screenshooter.sorter"
  static let agentURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/LaunchAgents/\(label).plist")

  static var isAppBundle: Bool { Bundle.main.bundleURL.pathExtension == "app" }

  // launchd sets XPC_SERVICE_NAME to the job label for processes it starts.
  static var launchedByAgent: Bool { launchEnvironment["XPC_SERVICE_NAME"] == label }

  static var mcpPath: String? { Bundle.main.path(forAuxiliaryExecutable: "screenshooter-mcp") }

  // Inbox, categories, screenshot location and the launch agent. Safe to run on every launch.
  static func run() {
    guard isAppBundle, !demoMode, launchEnvironment["SCREENSHOOTER_HOME"] == nil else { return }
    try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)

    let categoriesFile = base.appendingPathComponent("categories.json")
    if !FileManager.default.fileExists(atPath: categoriesFile.path),
      let example = Bundle.main.url(forResource: "categories.example", withExtension: "json")
    {
      try? FileManager.default.copyItem(at: example, to: categoriesFile)
    }

    if UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") != inbox.path {
      shell("/usr/bin/defaults", "write", "com.apple.screencapture", "location", inbox.path)
      shell("/usr/bin/killall", "SystemUIServer")
    }

    installAgent()
  }

  // Points the agent at this copy of the app; rewritten only when the app has moved.
  static func installAgent() {
    guard let executable = Bundle.main.executablePath else { return }
    let agent: [String: Any] = [
      "Label": label,
      "ProgramArguments": [executable],
      "WatchPaths": [inbox.path],
      "ThrottleInterval": 2,
      "StandardErrorPath": base.appendingPathComponent(".sorter.log").path,
    ]
    if let current = NSDictionary(contentsOf: agentURL), current.isEqual(to: agent) { return }
    try? FileManager.default.createDirectory(
      at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard (agent as NSDictionary).write(to: agentURL, atomically: true) else { return }
    let domain = "gui/\(getuid())"
    shell("/bin/launchctl", "bootout", "\(domain)/\(label)")
    shell("/bin/launchctl", "bootstrap", domain, agentURL.path)
  }

  // Shown when the app is opened by hand: what's set up and how to connect Claude.
  @MainActor static func showStatus() {
    let compressor = ["ffmpeg", "oxipng"].allSatisfy {
      FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/\($0)")
    }
    let mcpCommand = mcpPath.map { "claude mcp add --scope user screenshooter \"\($0)\"" }

    let alert = NSAlert()
    alert.icon = NSApp.applicationIconImage
    alert.messageText = "Screenshooter is ready"
    alert.informativeText = """
      Take a screenshot (⌘⇧3 / ⌘⇧4 / ⌘⇧5) and the sorting window opens.

      Screenshots: \(inbox.path)
      Categories: \(categories.map(\.label).joined(separator: ", ")) — edit categories.json to change them.
      Compression: \(compressor ? "on" : "off — run “brew install ffmpeg oxipng” to turn it on").

      Tip: ⌘⇧5 → Options → turn off “Show Floating Thumbnail”.
      """
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Edit Categories")
    if mcpCommand != nil { alert.addButton(withTitle: "Copy Claude MCP Command") }

    NSApp.activate(ignoringOtherApps: true)
    switch alert.runModal() {
    case .alertSecondButtonReturn:
      NSWorkspace.shared.open(base.appendingPathComponent("categories.json"))
    case .alertThirdButtonReturn:
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(mcpCommand ?? "", forType: .string)
    default:
      break
    }
  }

  @discardableResult
  static func shell(_ tool: String, _ arguments: String...) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return -1 }
    process.waitUntilExit()
    return process.terminationStatus
  }
}
