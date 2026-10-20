// Inbox queue, sorting actions and keyboard handling.
import AVFoundation
import Cocoa
import SwiftUI

@MainActor
final class SorterModel: ObservableObject {
  @Published var current: URL?
  @Published var preview: NSImage?
  @Published var queue: [URL] = []
  @Published var done = 0
  @Published var opened: Category?  // category whose subfolders are shown
  @Published var subfolders: [String] = []
  @Published var naming = false
  @Published var newName = ""
  @Published var previewSize = CGSize(width: 1200, height: 750)  // the window follows it
  @Published var loupeEnabled = !UserDefaults.standard.bool(forKey: "loupeOff") {  // right mouse button
    didSet { UserDefaults.standard.set(!loupeEnabled, forKey: "loupeOff") }
  }

  var lastSizes: [URL: Int] = [:]  // a file is queued once its size stops changing
  var onShow: () -> Void = {}
  var onHide: () -> Void = {}
  var onTitle: (String) -> Void = { _ in }
  var onCount: (Int) -> Void = { _ in }
  var onLayout: () -> Void = {}
  var onToggleLarge: () -> Void = {}
  var hiddenByUser = false  // hidden to the menu bar — new screenshots don't reopen the window
  var demoOpen = launchEnvironment["SCREENSHOOTER_DEMO_OPEN"].flatMap { Int($0) }  // open a category on start
  let compressor: OperationQueue = {
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    return queue
  }()

  var progress: String { "\(done + 1) / \(done + 1 + queue.count)" }

  // Progress and file name go to the window title.
  func updateTitle() {
    onTitle(current.map { "\(progress)  ·  \($0.lastPathComponent)" } ?? "Screenshooter")
    onCount((current == nil ? 0 : 1) + queue.count)
  }

  func candidates() -> [URL] {
    let urls = (try? FileManager.default.contentsOfDirectory(
      at: inbox, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])) ?? []
    let all = imageExtensions.union(videoExtensions)
    return urls
      .filter { all.contains($0.pathExtension.lowercased()) }
      .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
  }

  func scan() {
    if let url = current, !FileManager.default.fileExists(atPath: url.path) {
      current = nil  // the file was removed from Inbox by hand
    }
    let files = candidates()
    if files.isEmpty && current == nil && compressor.operationCount == 0 {
      NSApp.terminate(nil)
      return
    }
    lastSizes = lastSizes.filter { files.contains($0.key) }  // forget files that are gone
    for url in files where url != current && !queue.contains(url) {
      let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
      if lastSizes[url] == size {
        queue.append(url)
      } else {
        lastSizes[url] = size
      }
    }
    if current == nil { showNext() }
    updateTitle()
  }

  func showNext() {
    queue.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
    opened = nil
    naming = false
    guard !queue.isEmpty else {
      current = nil
      preview = nil
      done = 0
      onHide()
      return
    }
    let url = queue.removeFirst()
    current = url
    updateTitle()
    guard videoExtensions.contains(url.pathExtension.lowercased()) else {
      preview = NSImage(contentsOf: url)
      onLayout()
      onShow()
      if let index = demoOpen, categories.indices.contains(index - 1) {
        demoOpen = nil
        pick(categories[index - 1])
      }
      return
    }
    // Grab the video frame asynchronously so the window doesn't stall.
    preview = nil
    onShow()
    Task {
      let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
      generator.appliesPreferredTrackTransform = true
      guard let (frame, _) = try? await generator.image(at: .zero), current == url else { return }
      preview = NSImage(cgImage: frame, size: .zero)
      onLayout()
    }
  }

  func folderURL(_ category: Category) -> URL {
    base.appendingPathComponent(category.folder)
  }

  func listSubfolders(_ category: Category) -> [String] {
    let urls = (try? FileManager.default.contentsOfDirectory(
      at: folderURL(category), includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles])) ?? []
    return urls
      .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
      .map(\.lastPathComponent)
      .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
  }

  // MARK: Actions

  func pick(_ category: Category) {
    guard current != nil else { return }
    guard category.hasSubfolders else {
      move(to: folderURL(category))
      return
    }
    subfolders = listSubfolders(category)
    withAnimation(.bouncy) { opened = category }
  }

  func pickSubfolder(_ name: String?) {
    guard let category = opened else { return }
    let folder = folderURL(category)
    move(to: name.map { folder.appendingPathComponent($0) } ?? folder)
  }

  func back() {
    withAnimation(.bouncy) {
      if naming {
        naming = false
      } else {
        opened = nil
      }
    }
  }

  func startNaming() {
    guard opened != nil else { return }
    newName = ""
    withAnimation(.bouncy) { naming = true }
  }

  func createFolder() {
    let name = newName
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "/", with: "-")
    guard let category = opened, !name.isEmpty, !name.hasPrefix(".") else {
      NSSound.beep()
      return
    }
    try? FileManager.default.createDirectory(
      at: folderURL(category).appendingPathComponent(name), withIntermediateDirectories: true)
    pickSubfolder(name)
  }

  func move(to folder: URL) {
    guard let url = current else { return }
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var destination = folder.appendingPathComponent(url.lastPathComponent)
    var copy = 2
    while FileManager.default.fileExists(atPath: destination.path) {
      let name = "\(url.deletingPathExtension().lastPathComponent) \(copy).\(url.pathExtension)"
      destination = folder.appendingPathComponent(name)
      copy += 1
    }
    do {
      try FileManager.default.moveItem(at: url, to: destination)
    } catch {
      NSSound.beep()
      return
    }
    compress(destination)
    finishCurrent()
  }

  func deleteCurrent() {
    guard let url = current else { return }
    do {
      try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    } catch {
      NSSound.beep()
      return
    }
    finishCurrent()
  }

  func finishCurrent() {
    guard let url = current else { return }
    lastSizes[url] = nil
    current = nil
    done += 1
    showNext()
  }

  // Background compression, one file at a time, at low priority.
  func compress(_ url: URL) {
    compressor.addOperation {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/nice")
      process.arguments = ["-n", "15", NSHomeDirectory() + "/bin/screenshot-compress.sh", url.path]
      try? process.run()
      process.waitUntilExit()
    }
  }

  // Returns true if the key was handled.
  func handleKey(_ event: NSEvent) -> Bool {
    guard current != nil else { return false }
    if naming {
      if event.keyCode == 53 {
        back()
        return true
      }
      return false  // everything else goes to the text field
    }
    // Auto-repeat of a held key would sort several files in a row.
    if event.isARepeat { return true }
    switch event.keyCode {
    case 51, 117:  // Delete, Fn+Delete
      deleteCurrent()
      return true
    case 53:  // Esc
      guard opened != nil else { return false }
      back()
      return true
    case 45:  // N (any keyboard layout)
      guard opened != nil else { return false }
      startNaming()
      return true
    case 3:  // F — full screen width and back
      onToggleLarge()
      return true
    default:
      break
    }
    guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
      let digit = event.charactersIgnoringModifiers.flatMap({ Int($0) })
    else { return false }
    if opened != nil {
      // 1 — the category itself, 2…9 — subfolders.
      if digit == 1 {
        pickSubfolder(nil)
        return true
      }
      if digit >= 2 && digit - 2 < subfolders.count {
        pickSubfolder(subfolders[digit - 2])
        return true
      }
    } else if (1...categories.count).contains(digit) {
      pick(categories[digit - 1])
      return true
    }
    return false
  }
}
