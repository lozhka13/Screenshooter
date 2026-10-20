// On-device transcription of screen recordings (Speech framework, macOS 26).
// SpeechTranscriber where the language is supported, DictationTranscriber otherwise (e.g. Russian).
import AVFoundation
import Foundation
import Speech

public enum TranscriberError: LocalizedError {
  case unsupported(String)
  case noAudio
  case notAuthorized

  public var errorDescription: String? {
    switch self {
    case .unsupported(let locale): "Transcription isn't available for \(locale) on this Mac"
    case .noAudio: "The recording has no audio"
    case .notAuthorized: "Allow Screenshooter in System Settings → Privacy & Security → Speech Recognition"
    }
  }
}

public enum Transcriber {
  // Languages this Mac can transcribe, by identifier.
  public static func supportedLocales() async -> [Locale] {
    let speech = await SpeechTranscriber.supportedLocales
    let dictation = await DictationTranscriber.supportedLocales
    var seen = Set<String>()
    return (speech + dictation)
      .filter { seen.insert($0.identifier(.bcp47)).inserted }
      .sorted { $0.identifier < $1.identifier }
  }

  // The chosen language, or the first system language this Mac can transcribe.
  public static func preferredLocale() async -> Locale {
    let supported = await supportedLocales()
    if let chosen = Preferences.transcriptionLocale,
      let match = supported.first(where: { $0.identifier(.bcp47) == chosen })
    {
      return match
    }
    for language in Locale.preferredLanguages {
      let code = Locale(identifier: language).language.languageCode
      if let match = supported.first(where: { $0.identifier(.bcp47) == language })
        ?? supported.first(where: { $0.language.languageCode == code })
      {
        return match
      }
    }
    return Locale(identifier: "en-US")
  }

  // "[00:01:23] text" lines.
  public static func transcribe(_ recording: URL, locale: Locale? = nil) async throws -> String {
    let chosen: Locale
    if let locale { chosen = locale } else { chosen = await preferredLocale() }
    let audio = try await mixedAudio(of: recording)
    defer { try? FileManager.default.removeItem(at: audio) }
    let file = try AVAudioFile(forReading: audio)

    let speechLocale = await SpeechTranscriber.supportedLocale(equivalentTo: chosen)
    if let speechLocale {
      let module = SpeechTranscriber(locale: speechLocale, preset: .timeIndexedProgressiveTranscription)
      return try await run(module, file: file, results: module.results.map { ($0.text, $0.range, $0.isFinal) })
    }
    if let dictationLocale = await DictationTranscriber.supportedLocale(equivalentTo: chosen) {
      let module = DictationTranscriber(locale: dictationLocale, preset: .timeIndexedLongDictation)
      do {
        return try await run(module, file: file, results: module.results.map { ($0.text, $0.range, $0.isFinal) })
      } catch {
        // Some languages' dictation models can't be installed this way; the older recognizer still works offline.
      }
    }
    return try await recognize(audio, locale: chosen)
  }

  // On-device SFSpeechRecognizer, e.g. for Russian; needs Speech Recognition permission.
  static func recognize(_ audio: URL, locale: Locale) async throws -> String {
    guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition else {
      throw TranscriberError.unsupported(locale.identifier)
    }
    guard await requestPermission() else { throw TranscriberError.notAuthorized }
    let request = SFSpeechURLRecognitionRequest(url: audio)
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = false
    request.addsPunctuation = true
    let segments: [SFTranscriptionSegment] = try await withCheckedThrowingContinuation { continuation in
      var finished = false
      recognizer.recognitionTask(with: request) { result, error in
        guard !finished else { return }
        if let error {
          finished = true
          continuation.resume(throwing: error)
        } else if let result, result.isFinal {
          finished = true
          continuation.resume(returning: result.bestTranscription.segments)
        }
      }
    }
    return lines(from: segments)
  }

  // A new line after a pause of more than a second or every 25 words.
  static func lines(from segments: [SFTranscriptionSegment]) -> String {
    var lines: [String] = []
    var words: [String] = []
    var start = 0.0
    var end = 0.0
    for segment in segments {
      if !words.isEmpty && (segment.timestamp - end > 1.0 || words.count >= 25) {
        lines.append("[\(clock(CMTime(seconds: start, preferredTimescale: 1)))] " + words.joined(separator: " "))
        words = []
      }
      if words.isEmpty { start = segment.timestamp }
      words.append(segment.substring)
      end = segment.timestamp + segment.duration
    }
    if !words.isEmpty { lines.append("[\(clock(CMTime(seconds: start, preferredTimescale: 1)))] " + words.joined(separator: " ")) }
    return lines.joined(separator: "\n")
  }

  // Asks once; true when transcription with SFSpeechRecognizer is allowed.
  public static func requestPermission() async -> Bool {
    switch SFSpeechRecognizer.authorizationStatus() {
    case .authorized: return true
    case .notDetermined:
      return await withCheckedContinuation { continuation in
        SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
      }
    default: return false
    }
  }

  static func run<Results: AsyncSequence & Sendable>(
    _ module: any SpeechModule, file: AVAudioFile, results: Results
  ) async throws -> String where Results.Element == (AttributedString, CMTimeRange, Bool) {
    // Language models are downloaded on first use; a locale must be reserved before that.
    if await AssetInventory.status(forModules: [module]) != .installed {
      let reserved = await AssetInventory.reservedLocales
      for locale in (module as? any LocaleDependentSpeechModule)?.selectedLocales ?? [] where !reserved.contains(locale) {
        _ = try await AssetInventory.reserve(locale: locale)
      }
      if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
        try await request.downloadAndInstall()
      }
    }
    let analyzer = SpeechAnalyzer(modules: [module])
    async let lines: [String] = {
      var lines: [String] = []
      for try await (text, range, isFinal) in results where isFinal {
        let words = String(text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        if !words.isEmpty { lines.append("[\(clock(range.start))] \(words)") }
      }
      return lines
    }()
    if let end = try await analyzer.analyzeSequence(from: file) {
      try await analyzer.finalizeAndFinish(through: end)
    } else {
      await analyzer.cancelAndFinishNow()
    }
    return try await lines.joined(separator: "\n")
  }

  static func clock(_ time: CMTime) -> String {
    let seconds = max(0, Int(time.seconds.isFinite ? time.seconds : 0))
    return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
  }

  // All audio tracks (system audio and microphone) mixed into one M4A file.
  static func mixedAudio(of recording: URL) async throws -> URL {
    let asset = AVURLAsset(url: recording)
    let tracks = try await asset.loadTracks(withMediaType: .audio)
    guard !tracks.isEmpty else { throw TranscriberError.noAudio }
    let composition = AVMutableComposition()
    let duration = try await asset.load(.duration)
    for track in tracks {
      let target = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
      try target?.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
    }
    let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
    guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
      throw TranscriberError.noAudio
    }
    try await export.export(to: output, as: .m4a)
    return output
  }

  // Transcribes a recording next to it ("Recording.txt") unless that's already done.
  @discardableResult
  public static func transcribeNextTo(_ recording: URL) async throws -> URL {
    let target = transcriptURL(for: recording)
    if FileManager.default.fileExists(atPath: target.path) { return target }
    let text = try await transcribe(recording)
    try text.write(to: target, atomically: true, encoding: .utf8)
    return target
  }
}
