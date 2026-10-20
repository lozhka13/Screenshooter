// Paths, categories and launch environment.
import Foundation

struct Category: Hashable, Decodable {
  let label: String
  let folder: String
  let hasSubfolders: Bool

  enum CodingKeys: String, CodingKey {
    case label, folder
    case hasSubfolders = "subfolders"
  }
}

let launchEnvironment = ProcessInfo.processInfo.environment

// SCREENSHOOTER_DEMO=1: the window shows up in screenshots but never takes focus,
// keys or clicks — for README screenshots and tests.
let demoMode = launchEnvironment["SCREENSHOOTER_DEMO"] != nil

// SCREENSHOOTER_HOME points the app at another folder (used for demos and tests).
let base =
  launchEnvironment["SCREENSHOOTER_HOME"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
  ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Screenshots")
let inbox = base.appendingPathComponent("Inbox")
let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic"]
let videoExtensions: Set<String> = ["mov", "mp4"]

let defaultCategories = [
  Category(label: "Work", folder: "Work", hasSubfolders: false),
  Category(label: "Projects", folder: "Projects", hasSubfolders: true),
  Category(label: "Personal", folder: "Personal", hasSubfolders: true),
]

// Up to 9 categories; the shortcut is the position in the list.
let categories: [Category] = {
  let file = base.appendingPathComponent("categories.json")
  guard let data = try? Data(contentsOf: file),
    let list = try? JSONDecoder().decode([Category].self, from: data), !list.isEmpty
  else { return defaultCategories }
  return Array(list.prefix(9))
}()
