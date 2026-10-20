// Screen recording with system audio and the microphone (ScreenCaptureKit), saved to Inbox.
import AVFoundation
import Cocoa
import ScreenCaptureKit
import ScreenshooterCore

@MainActor
final class Recorder: NSObject, ObservableObject {
  @Published private(set) var startedAt: Date?
  private var stream: SCStream?
  private var output: SCRecordingOutput?
  private var file: URL?

  var isRecording: Bool { startedAt != nil }

  var elapsed: String {
    let seconds = Int(Date().timeIntervalSince(startedAt ?? Date()))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
  }

  func toggle() {
    Task { isRecording ? await stop() : await start() }
  }

  // The display under the mouse, without Screenshooter's own windows.
  func start() async {
    do {
      let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
      let mouse = NSEvent.mouseLocation
      let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
      let displayID = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
      guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
        return
      }
      let ownApp = content.applications.filter { $0.processID == getpid() }
      let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])

      let configuration = SCStreamConfiguration()
      let scale = screen?.backingScaleFactor ?? 2
      configuration.width = Int(CGFloat(display.width) * scale)
      configuration.height = Int(CGFloat(display.height) * scale)
      configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
      configuration.showsCursor = true
      configuration.capturesAudio = Preferences.recordSystemAudio
      configuration.excludesCurrentProcessAudio = true
      configuration.captureMicrophone = Preferences.recordMicrophone

      // Hidden while recording so the sorter doesn't pick up a growing file.
      try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
      let file = inbox.appendingPathComponent(".recording-\(UUID().uuidString).mov")
      let outputConfiguration = SCRecordingOutputConfiguration()
      outputConfiguration.outputURL = file
      outputConfiguration.outputFileType = .mov
      outputConfiguration.videoCodecType = .hevc

      let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
      let output = SCRecordingOutput(configuration: outputConfiguration, delegate: self)
      try stream.addRecordingOutput(output)
      try await stream.startCapture()
      self.stream = stream
      self.output = output
      self.file = file
      startedAt = Date()
    } catch {
      showPermissionHelp(error)
    }
  }

  func stop() async {
    guard let stream else { return }
    try? await stream.stopCapture()
    self.stream = nil
    output = nil
    startedAt = nil
  }

  // Gives the finished file its real name so the sorter shows it.
  nonisolated func finish() {
    Task { @MainActor in
      guard let file, FileManager.default.fileExists(atPath: file.path) else { return }
      self.file = nil
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
      let name = "Screen Recording \(formatter.string(from: Library.creationDate(file))).mov"
      try? FileManager.default.moveItem(at: file, to: Library.uniqueDestination(named: name, in: inbox))
    }
  }

  func showPermissionHelp(_ error: Error) {
    let alert = NSAlert()
    alert.messageText = L("Can't start recording")
    alert.informativeText =
      L("Allow Screenshooter in System Settings → Privacy & Security → Screen & System Audio Recording, then try again.")
      + "\n\n" + error.localizedDescription
    alert.addButton(withTitle: L("Open System Settings"))
    alert.addButton(withTitle: L("Cancel"))
    NSApp.activate(ignoringOtherApps: true)
    if alert.runModal() == .alertFirstButtonReturn {
      NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
  }
}

extension Recorder: SCRecordingOutputDelegate {
  nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
    finish()
  }

  nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
    finish()
  }
}
