// Inbox queue, sorting, undo, text analysis, suggestions, secrets and the editor.
import AVFoundation
import Cocoa
import ScreenshooterCore
import SwiftUI

enum UndoRecord {
  case moved(from: URL, to: URL)
  case deleted(from: URL, trashed: URL)
  case edited(file: URL, backup: URL, metadata: ShotMetadata?)
}

@MainActor
final class SorterModel: ObservableObject {
  @Published var categories = CategoryStore.load()
  @Published var current: URL?
  @Published var preview: NSImage?
  @Published var queue: [URL] = []
  @Published var done = 0
  @Published var opened: SortCategory?  // category whose subfolders are shown
  @Published var subfolders: [String] = []
  @Published var naming = false
  @Published var newName = ""
  @Published var previewSize = CGSize(width: 1200, height: 750)  // the window follows it
  @Published var loupeEnabled = !UserDefaults.standard.bool(forKey: "loupeOff") {  // right mouse button
    didSet { UserDefaults.standard.set(!loupeEnabled, forKey: "loupeOff") }
  }
  @Published var suggestion: Suggestion?
  @Published var secrets: [CGRect] = []  // normalized, top-left origin
  @Published var analyzing = false
  @Published var editing = false
  @Published var tool = Tool.arrow
  @Published var marks: [Mark] = []
  @Published var textPoint: CGPoint?  // where a text mark is being typed
  @Published var allDone = false  // "All sorted" with a chance to undo
  @Published var toast: String?
  @Published var history: [UndoRecord] = []

  var lastSizes: [URL: Int] = [:]  // a file is queued once its size stops changing
  var headline: String?
  var onShow: () -> Void = {}
  var onHide: () -> Void = {}
  var onTitle: (String) -> Void = { _ in }
  var onCount: (Int) -> Void = { _ in }
  var onLayout: () -> Void = {}
  var onToggleLarge: () -> Void = {}
  var hiddenByUser = false  // hidden to the menu bar — new screenshots don't reopen the window
  var demoOpen = launchEnvironment["SCREENSHOOTER_DEMO_OPEN"].flatMap { Int($0) }  // open a category on start
  let suggester = Suggester()
  let pipeline = Pipeline()
  var analysis: Task<Void, Never>?
  var toastTask: Task<Void, Never>?

  var progress: String { "\(done + 1) / \(done + 1 + queue.count)" }
  var waiting: Int { (current == nil ? 0 : 1) + queue.count }

  // Progress and file name go to the window title.
  func updateTitle() {
    onTitle(current.map { "\(progress)  ·  \($0.lastPathComponent)" } ?? "Screenshooter")
    onCount(waiting)
  }

  func candidates() -> [URL] {
    let urls = (try? FileManager.default.contentsOfDirectory(
      at: inbox, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])) ?? []
    return urls
      .filter(isMedia)
      .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
  }

  func scan() {
    if let url = current, !FileManager.default.fileExists(atPath: url.path) {
      current = nil  // the file was removed from Inbox by hand
    }
    let files = candidates()
    lastSizes = lastSizes.filter { files.contains($0.key) }  // forget files that are gone
    for url in files where url != current && !queue.contains(url) {
      let size = Library.fileSize(url)
      if lastSizes[url] == nil { captureContext(url) }
      if lastSizes[url] == size {
        queue.append(url)
      } else {
        lastSizes[url] = size
      }
    }
    if current == nil && (!allDone || !queue.isEmpty) { showNext() }
    updateTitle()
  }

  // Which app and page the screenshot came from — only for files that just appeared.
  func captureContext(_ url: URL) {
    guard Date().timeIntervalSince(Library.creationDate(url)) < 20, let context = Context.capture() else { return }
    ShotMetadata.update(url) {
      $0.appBundleID = context.appBundleID
      $0.appName = context.appName
      $0.url = context.url
      $0.pageTitle = context.pageTitle
      $0.windowTitle = context.windowTitle
    }
  }

  func showNext() {
    queue.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
    guard !queue.isEmpty else {
      current = nil
      preview = nil
      resetFileState()
      if done > 0 && !history.isEmpty && !demoMode {
        allDone = true  // stays a moment so the last sort can be undone
        Task {
          try? await Task.sleep(for: .seconds(4))
          guard allDone, queue.isEmpty, current == nil else { return }
          finishBatch()
        }
      } else {
        finishBatch()
      }
      return
    }
    show(queue.removeFirst())
  }

  func finishBatch() {
    allDone = false
    done = 0
    hiddenByUser = false
    onHide()
    updateTitle()
  }

  func show(_ url: URL) {
    allDone = false
    resetFileState()
    current = url
    categories = CategoryStore.load()
    updateTitle()
    if isVideo(url) {
      preview = nil
      Task {
        guard let frame = try? await Images.load(url, maxSize: 2560), current == url else { return }
        preview = NSImage(cgImage: frame, size: .zero)
        onLayout()
      }
    } else {
      preview = NSImage(contentsOf: url)
      onLayout()
    }
    onShow()
    analyze(url)
    if let index = demoOpen, categories.indices.contains(index - 1) {
      demoOpen = nil
      pick(categories[index - 1])
    }
    // SCREENSHOOTER_DEMO_EDIT=1 — open the editor with a few sample marks, for README screenshots.
    if demoMode, launchEnvironment["SCREENSHOOTER_DEMO_EDIT"] != nil {
      editing = true
      marks = [
        Mark(tool: .box, start: CGPoint(x: 0.045, y: 0.61), end: CGPoint(x: 0.36, y: 0.72)),
        Mark(tool: .arrow, start: CGPoint(x: 0.5, y: 0.5), end: CGPoint(x: 0.37, y: 0.62)),
        Mark(tool: .text, start: CGPoint(x: 0.42, y: 0.43), end: CGPoint(x: 0.42, y: 0.43), text: "Make these buttons bigger"),
        Mark(blur: CGRect(x: 0.755, y: 0.69, width: 0.09, height: 0.065)),
      ]
    }
  }

  func resetFileState() {
    opened = nil
    naming = false
    editing = false
    marks = []
    textPoint = nil
    suggestion = nil
    secrets = []
    headline = nil
    analysis?.cancel()
  }

  // Text, secrets and a folder suggestion, in the background.
  func analyze(_ url: URL) {
    analysis?.cancel()
    analyzing = true
    analysis = Task {
      let lines = await Task.detached(priority: .userInitiated) { (try? await TextRecognizer.recognize(url)) ?? [] }.value
      guard current == url, !Task.isCancelled else { return }
      analyzing = false
      ShotMetadata.update(url) { $0.text = lines.map(\.text).joined(separator: "\n") }
      headline = Namer.headline(from: lines.map { ($0.text, $0.box) })
      if Preferences.detectSecrets && !isVideo(url) {
        secrets = SecretDetector.boxes(in: lines)
      }
      if Preferences.suggestFolders, let metadata = ShotMetadata.read(url) {
        withAnimation(.bouncy) { suggestion = suggester.suggest(metadata, categories: categories) }
      }
    }
  }

  func subfolderList(_ category: SortCategory) -> [String] { Library.subfolders(of: category.url) }

  // MARK: Actions

  func pick(_ category: SortCategory) {
    guard current != nil, !editing else { return }
    guard category.hasSubfolders else {
      move(to: category.url)
      return
    }
    subfolders = subfolderList(category)
    withAnimation(.bouncy) { opened = category }
  }

  func pickSubfolder(_ name: String?) {
    guard let category = opened else { return }
    move(to: name.map { category.url.appendingPathComponent($0) } ?? category.url)
  }

  func acceptSuggestion() {
    guard let suggestion, !editing else { return }
    let folder = suggestion.category.url
    move(to: suggestion.subfolder.map { folder.appendingPathComponent($0) } ?? folder)
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
    guard let category = opened, let name = Library.cleanFolderName(newName) else {
      NSSound.beep()
      return
    }
    try? FileManager.default.createDirectory(
      at: category.url.appendingPathComponent(name), withIntermediateDirectories: true)
    pickSubfolder(name)
  }

  func move(to folder: URL) {
    guard let url = current else { return }
    let metadata = ShotMetadata.read(url)
    let name = Preferences.renameFiles ? Namer.name(for: url, metadata: metadata, headline: headline) : nil
    let destination: URL
    do {
      destination = try Library.move(url, to: folder, name: name)
    } catch {
      NSSound.beep()
      return
    }
    if let metadata {
      suggester.learn(metadata, folder: Library.relativePath(folder), file: Library.relativePath(destination))
    }
    record(.moved(from: url, to: destination))
    pipeline.process(destination)
    finishCurrent()
  }

  func deleteCurrent() {
    guard let url = current else { return }
    var trashed: NSURL?
    do {
      try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
    } catch {
      NSSound.beep()
      return
    }
    if let trashed = trashed as URL? { record(.deleted(from: url, trashed: trashed)) }
    finishCurrent()
  }

  func finishCurrent() {
    guard let url = current else { return }
    lastSizes[url] = nil
    current = nil
    done += 1
    showNext()
  }

  func record(_ action: UndoRecord) {
    history.append(action)
    if history.count > 20 { history.removeFirst() }
  }

  // Puts the last sorted, deleted or edited file back.
  func undo() {
    guard let action = history.popLast() else {
      NSSound.beep()
      return
    }
    do {
      switch action {
      case .moved(let from, let to):
        guard !pipeline.isBusy(with: to) else {
          history.append(action)
          flash(L("Still compressing — try again in a moment"))
          return
        }
        let back = Library.uniqueDestination(named: from.lastPathComponent, in: from.deletingLastPathComponent())
        try FileManager.default.moveItem(at: to, to: back)
        try? FileManager.default.removeItem(at: transcriptURL(for: to))
        suggester.forget(file: Library.relativePath(to))
        reopen(back)
      case .deleted(let from, let trashed):
        let back = Library.uniqueDestination(named: from.lastPathComponent, in: from.deletingLastPathComponent())
        try FileManager.default.moveItem(at: trashed, to: back)
        reopen(back)
      case .edited(let file, let backup, let metadata):
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: backup, to: file)
        metadata?.write(to: file)
        if current == file { show(file) } else { reopen(file) }
      }
      flash(L("Undone"))
    } catch {
      NSSound.beep()
    }
  }

  func reopen(_ url: URL) {
    if let current, current != url { queue.insert(current, at: 0) }
    if done > 0 { done -= 1 }
    hiddenByUser = false
    show(url)
  }

  // Image and file on the clipboard, ready to paste into a chat.
  func copyCurrent() {
    guard let url = current else { return }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    var objects: [NSPasteboardWriting] = [url as NSURL]
    if !isVideo(url), let image = NSImage(contentsOf: url) { objects.append(image) }
    pasteboard.writeObjects(objects)
    flash(L("Copied"))
  }

  func flash(_ message: String) {
    toastTask?.cancel()
    withAnimation { toast = message }
    toastTask = Task {
      try? await Task.sleep(for: .seconds(1.6))
      guard !Task.isCancelled else { return }
      withAnimation { toast = nil }
    }
  }

  // MARK: Editor

  func startEditing() {
    guard let url = current, !isVideo(url) else {
      NSSound.beep()
      return
    }
    opened = nil
    withAnimation(.bouncy) { editing = true }
  }

  func cancelEditing() {
    withAnimation(.bouncy) {
      editing = false
      marks = []
      textPoint = nil
    }
  }

  func saveEdits() {
    let pending = marks
    cancelEditing()
    guard !pending.isEmpty else { return }
    apply(pending)
  }

  // Blurs every detected secret, with a little padding.
  func redactSecrets() {
    guard !secrets.isEmpty else { return }
    apply(secrets.map { Mark(blur: $0.insetBy(dx: -0.004, dy: -0.006)) })
    flash(L("Secrets blurred"))
  }

  // Draws marks into the file; the original goes to the Trash so the edit can be undone.
  func apply(_ marks: [Mark]) {
    guard let url = current else { return }
    Task {
      do {
        let image = try await Images.load(url)
        guard let result = Renderer.render(image, marks: marks) else { throw ImageError.unencodable }
        let metadata = ShotMetadata.read(url)
        let copy = url.deletingLastPathComponent().appendingPathComponent(".original-\(UUID().uuidString).\(url.pathExtension)")
        try FileManager.default.copyItem(at: url, to: copy)
        var trashed: NSURL?
        try FileManager.default.trashItem(at: copy, resultingItemURL: &trashed)
        try Images.write(result, to: url)
        metadata?.write(to: url)
        if let backup = trashed as URL? { record(.edited(file: url, backup: backup, metadata: metadata)) }
        if current == url { show(url) }
      } catch {
        NSSound.beep()
      }
    }
  }

  // MARK: Keys

  // Returns true if the key was handled.
  func handleKey(_ event: NSEvent) -> Bool {
    let command = event.modifierFlags.contains(.command)
    if command && event.keyCode == 6 {  // ⌘Z
      if editing, !marks.isEmpty { marks.removeLast() } else { undo() }
      return true
    }
    guard current != nil else { return false }
    if naming || textPoint != nil {
      if event.keyCode == 53 {
        if textPoint != nil { textPoint = nil } else { back() }
        return true
      }
      return false  // everything else goes to the text field
    }
    // Auto-repeat of a held key would sort several files in a row.
    if event.isARepeat { return true }
    guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
    if editing { return handleEditorKey(event) }

    switch event.keyCode {
    case 51, 117:  // Delete, Fn+Delete
      deleteCurrent()
    case 53:  // Esc
      guard opened != nil else { return false }
      back()
    case 36, 76:  // Return, Enter — take the suggestion
      guard suggestion != nil, opened == nil else { return false }
      acceptSuggestion()
    case 45:  // N (any keyboard layout)
      guard opened != nil else { return false }
      startNaming()
    case 3: onToggleLarge()  // F
    case 8: copyCurrent()  // C
    case 14: startEditing()  // E
    case 15: redactSecrets()  // R
    default:
      return handleDigit(event)
    }
    return true
  }

  func handleDigit(_ event: NSEvent) -> Bool {
    guard let digit = event.charactersIgnoringModifiers.flatMap({ Int($0) }) else { return false }
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

  func handleEditorKey(_ event: NSEvent) -> Bool {
    switch event.keyCode {
    case 53: cancelEditing()  // Esc
    case 36, 76: saveEdits()  // Return
    case 51, 117: if !marks.isEmpty { marks.removeLast() }  // Delete
    case 0: tool = .arrow  // A
    case 11: tool = .box  // B
    case 17: tool = .text  // T
    case 35: tool = .blur  // P
    default: break
    }
    return true
  }
}

// Background work after a move: transcribe recordings, then compress — one file at a time.
// Starts after a short delay so an undo right after sorting doesn't race with it.
@MainActor
final class Pipeline {
  private var tail: Task<Void, Never>?
  private var busy: Set<String> = []
  private(set) var pending = 0

  func isBusy(with url: URL) -> Bool { busy.contains(url.path) }

  func process(_ url: URL) {
    pending += 1
    let previous = tail
    tail = Task {
      try? await Task.sleep(for: .seconds(8))
      await previous?.value
      defer { pending -= 1 }
      guard FileManager.default.fileExists(atPath: url.path) else { return }  // undone
      busy.insert(url.path)
      defer { busy.remove(url.path) }
      if isVideo(url) && Preferences.transcribe {
        _ = try? await Transcriber.transcribeNextTo(url)
      }
      if Preferences.compress {
        await run("/usr/bin/nice", ["-n", "15", compressScript, url.path])
      }
    }
  }

  func waitUntilIdle() async { await tail?.value }

  private func run(_ tool: String, _ arguments: [String]) async {
    await withCheckedContinuation { continuation in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: tool)
      process.arguments = arguments
      process.terminationHandler = { _ in continuation.resume() }
      if (try? process.run()) == nil { continuation.resume() }
    }
  }
}
