import Testing

@testable import ScreenshooterCore

struct VersionsTests {
  @Test func comparesNumerically() {
    #expect(Versions.isNewer("2.10.0", than: "2.9.1"))
    #expect(Versions.isNewer("v2.0.1", than: "2.0"))
    #expect(!Versions.isNewer("2.0.0", than: "2.0"))
    #expect(!Versions.isNewer("1.9", than: "2.0.0"))
  }
}
