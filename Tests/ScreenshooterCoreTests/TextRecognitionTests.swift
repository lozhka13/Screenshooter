import AppKit
import Testing

@testable import ScreenshooterCore

struct TextRecognitionTests {
  // A white image with a few lines of black text, like a tiny screenshot.
  func render(_ lines: [String]) -> CGImage {
    let size = NSSize(width: 1200, height: 120 + lines.count * 70)
    let image = NSImage(size: size, flipped: true) { rect in
      NSColor.white.setFill()
      rect.fill()
      for (index, line) in lines.enumerated() {
        (line as NSString).draw(
          at: NSPoint(x: 40, y: 50 + index * 70),
          withAttributes: [.font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.black])
      }
      return true
    }
    return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
  }

  @Test func recognizesTextAndFindsTheSecret() async throws {
    let lines = try await TextRecognizer.recognize(render(["Monitoring dashboard", "admin Gjqa3PFC3DqMYc3u3TXCS7ft"]))
    #expect(lines.contains { $0.text.contains("Monitoring") })
    let boxes = SecretDetector.boxes(in: lines)
    #expect(boxes.count == 1)
    // The box covers the token in the lower line. (OCR in CI VMs sometimes glues "admin" to the token,
    // so the box may start at the line's left edge.)
    let box = try #require(boxes.first)
    #expect(box.minY > 0.4)
    #expect(box.maxX > 0.5)
  }

  @Test func recognizesRussian() async throws {
    let lines = try await TextRecognizer.recognize(render(["Пароль от сервера"]))
    #expect(lines.map(\.text).joined().lowercased().contains("пароль"))
  }
}
