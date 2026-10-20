// Checks GitHub Releases for a newer version — the only network request the app makes.
import Cocoa
import ScreenshooterCore

@MainActor
enum Updater {
  static let latestRelease = URL(string: "https://api.github.com/repos/lozhka13/Screenshooter/releases/latest")!

  static var currentVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
  }

  // Once a day when automatic checks are on.
  static func checkDaily() {
    let key = "lastUpdateCheck"
    let last = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
    guard Preferences.checkForUpdates, Date().timeIntervalSince(last) > 24 * 3600 else { return }
    UserDefaults.standard.set(Date(), forKey: key)
    Task { await check(userInitiated: false) }
  }

  static func check(userInitiated: Bool) async {
    var request = URLRequest(url: latestRelease)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    guard let (data, _) = try? await URLSession.shared.data(for: request),
      let release = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let tag = release["tag_name"] as? String, let page = (release["html_url"] as? String).flatMap(URL.init)
    else {
      if userInitiated { inform(L("Couldn't check for updates"), L("Check your internet connection and try again.")) }
      return
    }
    guard Versions.isNewer(tag, than: currentVersion) else {
      if userInitiated {
        inform(L("You're up to date"), String(format: L("Screenshooter %@ is the latest version."), currentVersion))
      }
      return
    }
    let alert = NSAlert()
    alert.messageText = String(format: L("Screenshooter %@ is available"), tag.trimmingCharacters(in: CharacterSet(charactersIn: "v")))
    alert.informativeText = String(format: L("You have %@. Download the new disk image and replace the app."), currentVersion)
    alert.addButton(withTitle: L("Download"))
    alert.addButton(withTitle: L("Later"))
    NSApp.activate(ignoringOtherApps: true)
    if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(page) }
  }

  static func inform(_ title: String, _ text: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = text
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
  }
}
