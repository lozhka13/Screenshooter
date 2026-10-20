// Turns a screen recording into a GIF next to it (ffmpeg from Homebrew).
import Foundation

public enum ConverterError: LocalizedError {
  case noFFmpeg
  case failed

  public var errorDescription: String? {
    switch self {
    case .noFFmpeg: "GIF export needs ffmpeg: brew install ffmpeg"
    case .failed: "Couldn't make a GIF from this recording"
    }
  }
}

public enum Converter {
  static let ffmpeg = "/opt/homebrew/bin/ffmpeg"

  // 12 fps, at most 1280 px wide, with a palette tuned to the clip so text stays readable.
  public static func gif(from video: URL) async throws -> URL {
    guard FileManager.default.isExecutableFile(atPath: ffmpeg) else { throw ConverterError.noFFmpeg }
    let output = Library.uniqueDestination(
      named: video.deletingPathExtension().lastPathComponent + ".gif", in: video.deletingLastPathComponent())
    let filter = "fps=12,scale='min(1280,iw)':-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a"
    let status = await run(ffmpeg, ["-nostdin", "-loglevel", "error", "-y", "-i", video.path, "-vf", filter, "-loop", "0", output.path])
    guard status == 0, FileManager.default.fileExists(atPath: output.path) else {
      try? FileManager.default.removeItem(at: output)
      throw ConverterError.failed
    }
    return output
  }

  static func run(_ tool: String, _ arguments: [String]) async -> Int32 {
    await withCheckedContinuation { continuation in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: tool)
      process.arguments = arguments
      process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
      if (try? process.run()) == nil { continuation.resume(returning: -1) }
    }
  }
}
