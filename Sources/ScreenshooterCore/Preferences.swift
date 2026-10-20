// Settings shared by the app and the MCP server (both run with the app's bundle identifier).
import Foundation

public enum Preferences {
  static let defaults = UserDefaults.standard

  static func flag(_ key: String, default value: Bool) -> Bool {
    defaults.object(forKey: key) as? Bool ?? value
  }

  public static var renameFiles: Bool {
    get { flag("renameFiles", default: true) }
    set { defaults.set(newValue, forKey: "renameFiles") }
  }
  public static var compress: Bool {
    get { flag("compress", default: true) }
    set { defaults.set(newValue, forKey: "compress") }
  }
  public static var suggestFolders: Bool {
    get { flag("suggestFolders", default: true) }
    set { defaults.set(newValue, forKey: "suggestFolders") }
  }
  public static var detectSecrets: Bool {
    get { flag("detectSecrets", default: true) }
    set { defaults.set(newValue, forKey: "detectSecrets") }
  }
  public static var transcribe: Bool {
    get { flag("transcribe", default: true) }
    set { defaults.set(newValue, forKey: "transcribe") }
  }
  // nil — pick from the system languages.
  public static var transcriptionLocale: String? {
    get { defaults.string(forKey: "transcriptionLocale").flatMap { $0.isEmpty ? nil : $0 } }
    set { defaults.set(newValue, forKey: "transcriptionLocale") }
  }
  public static var recordSystemAudio: Bool {
    get { flag("recordSystemAudio", default: true) }
    set { defaults.set(newValue, forKey: "recordSystemAudio") }
  }
  public static var recordMicrophone: Bool {
    get { flag("recordMicrophone", default: true) }
    set { defaults.set(newValue, forKey: "recordMicrophone") }
  }
  public static var checkForUpdates: Bool {
    get { flag("checkForUpdates", default: true) }
    set { defaults.set(newValue, forKey: "checkForUpdates") }
  }
}
