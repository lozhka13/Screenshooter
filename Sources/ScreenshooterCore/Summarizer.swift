// Short titles for screenshots from their text, with Apple's on-device language model
// (Apple Intelligence). Nothing leaves the Mac; without Apple Intelligence it simply returns nil.
import Foundation
import FoundationModels

public enum Summarizer {
  public static var isAvailable: Bool { SystemLanguageModel.default.availability == .available }

  public static func title(for text: String, app: String?) async -> String? {
    guard isAvailable, Preferences.smartNames, text.count >= 20 else { return nil }
    let session = LanguageModelSession(
      instructions: """
        You name screenshot files. Reply with one short title of 2 to 6 words that says what the screen shows, \
        in the language of the text on it. No quotes, no file extension, no punctuation at the end.
        """)
    let prompt = "App: \(app ?? "unknown")\nText on the screen:\n\(text.prefix(1500))"
    guard let response = try? await session.respond(to: prompt) else { return nil }
    let title = response.content
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "\"'«»“”."))
    return title.isEmpty || title.count > 80 ? nil : title
  }
}
