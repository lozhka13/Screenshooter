// Folders, file types and launch environment shared by the app and the MCP server.
import Foundation

public let launchEnvironment = ProcessInfo.processInfo.environment

// SCREENSHOOTER_DEMO=1: the window shows up in screenshots but never takes focus,
// keys or clicks — for README screenshots and tests.
public let demoMode = launchEnvironment["SCREENSHOOTER_DEMO"] != nil

// SCREENSHOOTER_HOME points everything at another folder (used for demos and tests).
public let base =
  launchEnvironment["SCREENSHOOTER_HOME"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
  ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Screenshots")
public let inbox = base.appendingPathComponent("Inbox")
public let stateFolder = base.appendingPathComponent(".screenshooter")  // learned suggestions

public let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic"]
public let videoExtensions: Set<String> = ["mov", "mp4"]
public let mediaExtensions = imageExtensions.union(videoExtensions)

public func isVideo(_ url: URL) -> Bool { videoExtensions.contains(url.pathExtension.lowercased()) }
public func isMedia(_ url: URL) -> Bool { mediaExtensions.contains(url.pathExtension.lowercased()) }

// Inside Screenshooter.app the script ships in Resources; a plain build uses ~/bin.
public let compressScript =
  Bundle.main.path(forResource: "screenshot-compress", ofType: "sh")
  ?? NSHomeDirectory() + "/bin/screenshot-compress.sh"
