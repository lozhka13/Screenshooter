// Which app, page and window the user was looking at when a screenshot appeared.
import Cocoa
import ScreenshooterCore

enum Context {
  static func capture() -> ShotMetadata? {
    guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else { return nil }
    var metadata = ShotMetadata(appBundleID: app.bundleIdentifier, appName: app.localizedName)
    if let page = browserPage(app.bundleIdentifier) {
      metadata.url = page.url
      metadata.pageTitle = page.title
    }
    metadata.windowTitle = frontWindowTitle(of: app.processIdentifier)
    return metadata
  }

  // Asks the browser for the active tab (macOS asks the user once per browser).
  static let pageScripts: [String: String] = {
    let chromium = { (id: String) in "tell application id \"\(id)\" to tell active tab of front window to return {URL, title}" }
    return [
      "com.google.Chrome": chromium("com.google.Chrome"),
      "company.thebrowser.Browser": chromium("company.thebrowser.Browser"),
      "com.brave.Browser": chromium("com.brave.Browser"),
      "com.microsoft.edgemac": chromium("com.microsoft.edgemac"),
      "com.apple.Safari": "tell application id \"com.apple.Safari\" to tell current tab of front window to return {URL, name}",
    ]
  }()

  static func browserPage(_ bundleID: String?) -> (url: String, title: String)? {
    guard let bundleID, let source = pageScripts[bundleID] else { return nil }
    var error: NSDictionary?
    guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error), result.numberOfItems == 2,
      let url = result.atIndex(1)?.stringValue
    else { return nil }
    return (url, result.atIndex(2)?.stringValue ?? "")
  }

  // The frontmost window's title; macOS only reveals it with Screen Recording permission.
  static func frontWindowTitle(of pid: pid_t) -> String? {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
      as? [[String: Any]] ?? []
    let front = windows.first {
      ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
    }
    return (front?[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 }
  }
}
