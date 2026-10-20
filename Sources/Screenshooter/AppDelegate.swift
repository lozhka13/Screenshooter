// Window, menu bar item, recording shortcut, key and mouse monitors.
import Carbon
import Cocoa
import ScreenshooterCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
  var window: NSWindow!
  var settingsWindow: NSWindow?
  var libraryWindow: NSWindow?
  var statusItem: NSStatusItem!
  var scanTimer: Timer?
  var recordingShortcut: HotKey?
  var searchShortcut: HotKey?
  let model = MainActor.assumeIsolated { SorterModel() }
  let recorder = MainActor.assumeIsolated { Recorder() }
  var large = UserDefaults.standard.bool(forKey: "large") {
    didSet { UserDefaults.standard.set(large, forKey: "large") }
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    // One copy at a time: a second launch just brings up the first one's settings.
    if Setup.isAppBundle, let id = Bundle.main.bundleIdentifier,
      NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1
    {
      DistributedNotificationCenter.default().postNotificationName(.init("\(id).reopen"), object: nil)
      NSApp.terminate(nil)
      return
    }
    if let id = Bundle.main.bundleIdentifier {
      DistributedNotificationCenter.default().addObserver(
        self, selector: #selector(openSettings), name: .init("\(id).reopen"), object: nil)
    }
    Setup.run()

    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    window.titlebarAppearsTransparent = true
    window.title = "Screenshooter"
    window.level = .floating
    window.animationBehavior = .none
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .darkAqua)
    window.delegate = self
    // Excluded from screenshots and screen recordings, except in demo mode.
    window.sharingType = demoMode ? .readOnly : .none
    window.ignoresMouseEvents = demoMode

    let hosting = NSHostingView(rootView: SorterView(model: model))
    hosting.sizingOptions = [.minSize, .maxSize]  // window = preview size + buttons
    window.contentView = hosting
    window.collectionBehavior = [.fullScreenNone]

    // Yellow — hide to the menu bar, green — full screen width.
    window.standardWindowButton(.miniaturizeButton)?.target = self
    window.standardWindowButton(.miniaturizeButton)?.action = #selector(hideToTray)
    window.standardWindowButton(.zoomButton)?.target = self
    window.standardWindowButton(.zoomButton)?.action = #selector(toggleLarge)

    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.image = NSImage(
      systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: "Screenshooter")
    statusItem.button?.imagePosition = .imageLeading
    let menu = NSMenu()
    menu.delegate = self
    statusItem.menu = menu

    MainActor.assumeIsolated {
      model.onLayout = { [weak self] in self?.fitPreview() }
      model.onToggleLarge = { [weak self] in self?.toggleLarge() }
      model.onCount = { [weak self] _ in self?.updateStatusItem() }
      model.onShow = { [weak self] in
        guard let self, let window = self.window, !window.isVisible,
          !MainActor.assumeIsolated({ self.model.hiddenByUser })
        else { return }
        if demoMode {
          window.orderFrontRegardless()  // visible, but focus stays where it was
        } else {
          window.makeKeyAndOrderFront(nil)
          NSApp.activate(ignoringOtherApps: true)
        }
        DispatchQueue.main.async { window.center() }  // once the window has taken its new size
      }
      model.onHide = { [weak self] in self?.window.orderOut(nil) }
      model.onTitle = { [weak self] title in self?.window.title = title }
      model.scan()
    }

    // Keys only while the window is on screen and focused, otherwise files would be sorted blind.
    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, event.window === self.window, self.window.isVisible else { return event }
      return MainActor.assumeIsolated { self.model.handleKey(event) } ? nil : event
    }
    // Right mouse button in the window toggles the loupe.
    NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
      guard let self, event.window === self.window else { return event }
      MainActor.assumeIsolated { self.model.loupeEnabled.toggle() }
      return nil
    }
    // Common modes: keeps scanning while a menu or an alert is open.
    let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
      guard let self else { return }
      MainActor.assumeIsolated { self.model.scan() }
      self.updateStatusItem()
    }
    RunLoop.main.add(timer, forMode: .common)
    scanTimer = timer

    // SCREENSHOOTER_DEMO_LIBRARY="query" — open the library with a search, for README screenshots.
    if demoMode, launchEnvironment["SCREENSHOOTER_DEMO_LIBRARY"] != nil { openLibrary() }
    if !demoMode {
      recordingShortcut = HotKey(keyCode: kVK_ANSI_R, modifiers: cmdKey | optionKey | controlKey, id: 1) { [weak self] in
        self?.toggleRecording()
      }
      searchShortcut = HotKey(keyCode: kVK_ANSI_F, modifiers: cmdKey | optionKey | controlKey, id: 2) { [weak self] in
        self?.openLibrary()
      }
      MainActor.assumeIsolated {
        if Setup.isAppBundle && !Setup.welcomed {
          Setup.welcome { openSettings() }
        }
        Updater.checkDaily()
      }
    }
  }

  // Opening the app again from Finder shows the settings.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    openSettings()
    return false
  }

  // MARK: Menu bar

  func updateStatusItem() {
    let (waiting, recording, elapsed) = MainActor.assumeIsolated {
      (model.waiting, recorder.isRecording, recorder.elapsed)
    }
    statusItem.button?.title = recording ? " ● \(elapsed)" : waiting > 0 ? " \(waiting)" : ""
    statusItem.button?.contentTintColor = recording ? .systemRed : nil
  }

  // Rebuilt every time it opens, so counts and recording state are current.
  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    let (waiting, recording, canUndo) = MainActor.assumeIsolated {
      (model.waiting, recorder.isRecording, !model.history.isEmpty)
    }
    if waiting > 0 {
      item(menu, String(format: L("Show %d Waiting"), waiting), #selector(showFromTray))
    }
    let record = item(menu, recording ? L("Stop Recording") : L("Record Screen"), #selector(toggleRecording), "r")
    record.keyEquivalentModifierMask = [.command, .option, .control]
    let search = item(menu, L("Search Screenshots…"), #selector(openLibrary), "f")
    search.keyEquivalentModifierMask = [.command, .option, .control]
    if canUndo { item(menu, L("Undo Last Sort"), #selector(undo)) }
    menu.addItem(.separator())
    item(menu, L("Open Screenshots Folder"), #selector(openFolder))
    item(menu, L("Settings…"), #selector(openSettings), ",")
    item(menu, L("Check for Updates…"), #selector(checkForUpdates))
    menu.addItem(.separator())
    item(menu, L("Quit Screenshooter"), #selector(quit), "q")
  }

  @discardableResult
  func item(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
    let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
    item.target = self
    return item
  }

  @objc func toggleRecording() {
    MainActor.assumeIsolated { recorder.toggle() }
  }

  @objc func undo() {
    MainActor.assumeIsolated { model.undo() }
  }

  @objc func openFolder() {
    NSWorkspace.shared.open(base)
  }

  @objc func checkForUpdates() {
    Task { await Updater.check(userInitiated: true) }
  }

  @objc func openLibrary() {
    if libraryWindow == nil {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
        styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
      window.title = L("Screenshot Library")
      window.isReleasedWhenClosed = false
      window.contentView = NSHostingView(rootView: LibraryView(initialQuery: launchEnvironment["SCREENSHOOTER_DEMO_LIBRARY"] ?? ""))
      window.setFrameAutosaveName("Library")
      if !window.setFrameUsingName("Library") { window.center() }
      libraryWindow = window
    }
    if demoMode {
      libraryWindow?.orderFrontRegardless()
      return
    }
    libraryWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc func openSettings() {
    if settingsWindow == nil {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 640, height: 480), styleMask: [.titled, .closable],
        backing: .buffered, defer: false)
      window.title = L("Screenshooter Settings")
      window.isReleasedWhenClosed = false
      window.contentView = NSHostingView(rootView: SettingsView())
      window.center()
      settingsWindow = window
    }
    settingsWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  // MARK: Sorting window

  // The window resizes for every image — keep it from running off screen.
  func windowDidResize(_ notification: Notification) {
    guard let window, notification.object as? NSWindow === window, let visible = window.screen?.visibleFrame else {
      return
    }
    var origin = window.frame.origin
    origin.x = min(max(origin.x, visible.minX), visible.maxX - window.frame.width)
    origin.y = min(max(origin.y, visible.minY), visible.maxY - window.frame.height)
    if origin != window.frame.origin { window.setFrameOrigin(origin) }
  }

  // Preview follows the image aspect ratio: up to 1300 pt wide, never larger than the screen.
  @MainActor func fitPreview() {
    guard let image = model.preview else { return }
    let rep = image.representations.first
    let aspect =
      (rep?.pixelsWide ?? 0) > 0
      ? CGFloat(rep!.pixelsWide) / CGFloat(max(rep!.pixelsHigh, 1))
      : image.size.width / max(image.size.height, 1)
    let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let sidebar = model.showsSidebar ? sidebarColumn + 16 : 0  // thumbnails column and its gap
    let maxWidth = (large ? visible.width - 40 : min(1300, visible.width * 0.9 - 40)) - sidebar
    let maxHeight = (large ? visible.height : visible.height * 0.92) - 160  // title bar, buttons, padding
    var size = CGSize(width: maxWidth, height: maxWidth / aspect)
    if size.height > maxHeight {
      size = CGSize(width: maxHeight * aspect, height: maxHeight)
    }
    model.previewSize = CGSize(width: size.width.rounded(), height: size.height.rounded())
  }

  @objc func toggleLarge() {
    large.toggle()
    MainActor.assumeIsolated { fitPreview() }
    DispatchQueue.main.async { [weak self] in self?.window.center() }
  }

  // The red and yellow buttons hide the sorting window to the menu bar; the rest waits in Inbox.
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard sender === window else { return true }
    hideToTray()
    return false
  }

  @objc func hideToTray() {
    MainActor.assumeIsolated { model.hiddenByUser = true }
    window.orderOut(nil)
  }

  @objc func showFromTray() {
    let hasFile = MainActor.assumeIsolated {
      model.hiddenByUser = false
      return model.current != nil
    }
    guard hasFile else { return }
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  // Finishes a recording and background work, then quits; unsorted files wait in Inbox.
  @objc func quit() {
    scanTimer?.invalidate()
    window.orderOut(nil)
    Task { @MainActor in
      await recorder.stop()
      await model.pipeline.waitUntilIdle()
      NSApp.terminate(nil)
    }
  }
}
