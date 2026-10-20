// First-run setup when Screenshooter.app starts, and the welcome window.
import Cocoa
import ScreenshooterCore
import ServiceManagement

enum Setup {
  // Versions before 2.0 started on demand from this launch agent.
  static let legacyLabel = "com.screenshooter.sorter"
  static let legacyAgent = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/LaunchAgents/\(legacyLabel).plist")

  static var isAppBundle: Bool { Bundle.main.bundleURL.pathExtension == "app" }
  static var launchedByLegacyAgent: Bool { launchEnvironment["XPC_SERVICE_NAME"] == legacyLabel }
  static var mcpPath: String? { Bundle.main.path(forAuxiliaryExecutable: "screenshooter-mcp") }

  static var welcomed: Bool {
    get { UserDefaults.standard.bool(forKey: "welcomed") }
    set { UserDefaults.standard.set(newValue, forKey: "welcomed") }
  }

  // Inbox, categories, screenshot location, login item. Safe to run on every launch.
  static func run() {
    guard isAppBundle, !demoMode, launchEnvironment["SCREENSHOOTER_HOME"] == nil else { return }
    try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)

    if !FileManager.default.fileExists(atPath: CategoryStore.fileURL.path),
      let example = Bundle.main.url(forResource: "categories.example", withExtension: "json")
    {
      try? FileManager.default.copyItem(at: example, to: CategoryStore.fileURL)
    }

    if UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") != inbox.path {
      shell("/usr/bin/defaults", "write", "com.apple.screencapture", "location", inbox.path)
      shell("/usr/bin/killall", "SystemUIServer")
    }

    removeLegacyAgent()
    if !welcomed { try? SMAppService.mainApp.register() }
  }

  static func removeLegacyAgent() {
    guard FileManager.default.fileExists(atPath: legacyAgent.path) else { return }
    // Unloading the agent we were started by would quit us; the file alone is enough then.
    if !launchedByLegacyAgent { shell("/bin/launchctl", "bootout", "gui/\(getuid())/\(legacyLabel)") }
    try? FileManager.default.removeItem(at: legacyAgent)
  }

  // Shown once, on the first launch.
  @MainActor static func welcome(openSettings: () -> Void) {
    welcomed = true
    let alert = NSAlert()
    alert.icon = NSApp.applicationIconImage
    alert.messageText = L("Screenshooter is ready")
    alert.informativeText = String(
      format: L(
        "Take a screenshot (⌘⇧3 / ⌘⇧4 / ⌘⇧5) and the sorting window opens. Record the screen with sound from the menu bar or with ⌃⌥⌘R.\n\nScreenshots go to %@. Screenshooter lives in the menu bar and opens at login.\n\nTip: ⌘⇧5 → Options → turn off “Show Floating Thumbnail”."
      ), inbox.path)
    alert.addButton(withTitle: L("OK"))
    alert.addButton(withTitle: L("Settings…"))
    NSApp.activate(ignoringOtherApps: true)
    if alert.runModal() == .alertSecondButtonReturn { openSettings() }
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
