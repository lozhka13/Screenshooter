import Foundation
import Testing

@testable import ScreenshooterCore

struct LibraryTests {
  func makeFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }

  @Test func uniqueDestinationNeverOverwrites() throws {
    let folder = try makeFolder()
    try Data().write(to: folder.appendingPathComponent("shot.png"))
    try Data().write(to: folder.appendingPathComponent("shot 2.png"))
    #expect(Library.uniqueDestination(named: "shot.png", in: folder).lastPathComponent == "shot 3.png")
  }

  @Test func moveCreatesFolderAndRenames() throws {
    let folder = try makeFolder()
    let file = folder.appendingPathComponent("a.png")
    try Data([1]).write(to: file)
    let moved = try Library.move(file, to: folder.appendingPathComponent("Sub"), name: "b.png")
    #expect(moved.lastPathComponent == "b.png")
    #expect(FileManager.default.fileExists(atPath: moved.path))
    #expect(!FileManager.default.fileExists(atPath: file.path))
  }

  @Test func metadataTravelsWithTheFile() throws {
    let folder = try makeFolder()
    let file = folder.appendingPathComponent("a.png")
    try Data([1]).write(to: file)
    ShotMetadata(appName: "Slack", text: "hello").write(to: file)
    let moved = try Library.move(file, to: folder.appendingPathComponent("Sub"))
    #expect(ShotMetadata.read(moved)?.appName == "Slack")
    ShotMetadata.update(moved) { $0.url = "https://x.com" }
    #expect(ShotMetadata.read(moved) == ShotMetadata(appName: "Slack", url: "https://x.com", text: "hello"))
  }

  @Test func cleanFolderNames() {
    #expect(Library.cleanFolderName("  Atlas / v2 ") == "Atlas - v2")
    #expect(Library.cleanFolderName(".hidden") == nil)
    #expect(Library.cleanFolderName("   ") == nil)
  }

  @Test func categoriesDecodeWithDefaults() throws {
    let json = #"[{"label":"Вёрстка","folder":"Verstka","subfolders":true},{"label":"Work","folder":"Work"}]"#
    let list = try #require(CategoryStore.decode(Data(json.utf8)))
    #expect(list.map(\.label) == ["Вёрстка", "Work"])
    #expect(list[1].hasSubfolders == false)
    #expect(list[0].keywords.isEmpty)
  }
}
