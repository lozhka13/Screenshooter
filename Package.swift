// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Screenshooter",
  platforms: [.macOS("26.0")],
  targets: [
    // Shared by the app and the MCP server: paths, categories, metadata, OCR, suggestions, transcription.
    .target(name: "ScreenshooterCore"),
    .executableTarget(name: "Screenshooter", dependencies: ["ScreenshooterCore"]),
    .executableTarget(name: "screenshooter-mcp", dependencies: ["ScreenshooterCore"]),
    .testTarget(name: "ScreenshooterCoreTests", dependencies: ["ScreenshooterCore"]),
  ],
  swiftLanguageModes: [.v5]
)
