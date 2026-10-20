import CoreGraphics
import Foundation
import Testing

@testable import ScreenshooterCore

struct NamerTests {
  let english = URL(fileURLWithPath: "/tmp/Screenshot 2026-10-20 at 9.42.15.png")
  let russian = URL(fileURLWithPath: "/tmp/Снимок экрана — 2026-10-20 в 14.30.29.png")

  @Test func timestampFromMacOSNames() {
    #expect(Namer.timestamp(for: english) == "2026-10-20 09.42.15")
    #expect(Namer.timestamp(for: russian) == "2026-10-20 14.30.29")
  }

  @Test func pageTitleWins() {
    let metadata = ShotMetadata(pageTitle: "Grafana: CPU usage / prod", windowTitle: "Chrome")
    #expect(Namer.name(for: english, metadata: metadata, headline: "Ignored") == "2026-10-20 09.42.15 — Grafana CPU usage prod.png")
  }

  @Test func headlineWhenNoTitle() {
    #expect(Namer.name(for: russian, metadata: nil, headline: "Q3 Overview") == "2026-10-20 14.30.29 — Q3 Overview.png")
  }

  @Test func appNameWhenNothingBetter() {
    #expect(Namer.name(for: english, metadata: ShotMetadata(appName: "Ghostty"), headline: nil) == "2026-10-20 09.42.15 — Ghostty.png")
  }

  @Test func singleWordIsNotAHeadline() {
    #expect(Namer.headline(from: [("dasdasda", CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1))]) == nil)
  }

  @Test func keepsNameWithoutAnyTitle() {
    #expect(Namer.name(for: english, metadata: ShotMetadata(), headline: "  42 ") == english.lastPathComponent)
  }

  @Test func longTitlesAreCut() {
    let title = String(repeating: "word ", count: 30)
    let name = Namer.name(for: english, metadata: ShotMetadata(pageTitle: title), headline: nil)
    #expect(name.hasSuffix("….png"))
    #expect(name.count < 90)
  }

  @Test func headlinePicksBiggestTopText() {
    let lines: [(text: String, box: CGRect)] = [
      ("Overview", CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.03)),
      ("Q3 Overview", CGRect(x: 0.2, y: 0.12, width: 0.3, height: 0.05)),
      ("Huge footer text", CGRect(x: 0.1, y: 0.9, width: 0.5, height: 0.08)),
    ]
    #expect(Namer.headline(from: lines) == "Q3 Overview")
  }
}
