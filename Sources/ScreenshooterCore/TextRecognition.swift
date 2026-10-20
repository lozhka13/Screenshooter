// On-device text recognition (Vision) for search, suggestions, file names and secret detection.
import CoreGraphics
import Foundation
import Vision

public struct TextLine: @unchecked Sendable {
  public let text: String
  public let box: CGRect  // normalized, origin at the top left
  let candidate: RecognizedText

  // Box of part of the line, e.g. just the password after "password:".
  public func box(for range: Range<String.Index>) -> CGRect {
    let part = text.distance(from: range.lowerBound, to: range.upperBound)
    guard let found = candidate.boundingBox(for: range).map({ flip($0.boundingBox.cgRect) }),
      part >= text.count || found.width < box.width * 0.95
    else { return estimate(range) }
    return found
  }

  // Vision sometimes can't box a substring — no box, or the whole line (seen in virtual machines);
  // then share the line by characters.
  func estimate(_ range: Range<String.Index>) -> CGRect {
    let total = CGFloat(max(text.count, 1))
    let start = CGFloat(text.distance(from: text.startIndex, to: range.lowerBound)) / total
    let length = CGFloat(text.distance(from: range.lowerBound, to: range.upperBound)) / total
    return CGRect(x: box.minX + box.width * start, y: box.minY, width: box.width * length, height: box.height)
  }
}

// Vision's normalized rects start at the bottom left.
func flip(_ rect: CGRect) -> CGRect {
  CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
}

public enum TextRecognizer {
  public static let languages = [Locale.Language(identifier: "ru-RU"), Locale.Language(identifier: "en-US")]

  public static func recognize(_ url: URL) async throws -> [TextLine] {
    try await recognize(Images.load(url, maxSize: isVideo(url) ? 1920 : nil))
  }

  public static func recognize(_ image: CGImage) async throws -> [TextLine] {
    var request = RecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = languages
    request.usesLanguageCorrection = true
    let observations = try await request.perform(on: image)
    return observations.compactMap { observation in
      guard let candidate = observation.topCandidates(1).first else { return nil }
      return TextLine(text: candidate.string, box: flip(observation.boundingBox.cgRect), candidate: candidate)
    }
  }

  // Recognized text stored with the file; recognized now if it isn't yet.
  public static func text(of url: URL) async -> String {
    if let text = ShotMetadata.read(url)?.text { return text }
    let text = ((try? await recognize(url)) ?? []).map(\.text).joined(separator: "\n")
    ShotMetadata.update(url) { $0.text = text }
    return text
  }
}
