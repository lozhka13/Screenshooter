// Window, menu bar item, key and mouse monitors.
import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  var window: NSWindow!
  var statusItem: NSStatusItem!
  var scanTimer: Timer?
  let model = MainActor.assumeIsolated { SorterModel() }
  var large = UserDefaults.standard.bool(forKey: "large") {
    didSet { UserDefaults.standard.set(large, forKey: "large") }
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    Setup.run()
    // Opened from Finder rather than by the launch agent — show what's set up.
    if Setup.isAppBundle && !Setup.launchedByAgent && !demoMode {
      MainActor.assumeIsolated { Setup.showStatus() }
    }

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
    statusItem.button?.target = self
    statusItem.button?.action = #selector(statusClicked)
    statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

    MainActor.assumeIsolated {
      model.onLayout = { [weak self] in self?.fitPreview() }
      model.onToggleLarge = { [weak self] in self?.toggleLarge() }
      model.onCount = { [weak self] count in
        self?.statusItem.button?.title = count > 0 ? " \(count)" : ""
      }
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
    scanTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      guard let model = self?.model else { return }
      MainActor.assumeIsolated { model.scan() }
    }
  }

  // The window resizes for every image — keep it from running off screen.
  func windowDidResize(_ notification: Notification) {
    guard let visible = window.screen?.visibleFrame else { return }
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
    let maxWidth = large ? visible.width - 40 : min(1300, visible.width * 0.9 - 40)
    let maxHeight = (large ? visible.height : visible.height * 0.92) - 140  // title bar, buttons, padding
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

  // The red and yellow buttons hide the window to the menu bar; the rest waits in Inbox.
  func windowShouldClose(_ sender: NSWindow) -> Bool {
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

  @objc func statusClicked() {
    guard NSApp.currentEvent?.type == .rightMouseUp else {
      window.isVisible ? hideToTray() : showFromTray()
      return
    }
    let menu = NSMenu()
    menu.addItem(withTitle: "Show", action: #selector(showFromTray), keyEquivalent: "").target = self
    menu.addItem(.separator())
    menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q").target = self
    statusItem.menu = menu
    statusItem.button?.performClick(nil)
    statusItem.menu = nil
  }

  // Quit: the rest waits in Inbox until the next screenshot; a started compression is finished.
  @objc func quit() {
    scanTimer?.invalidate()  // new screenshots no longer open the window
    window.orderOut(nil)
    NSStatusBar.system.removeStatusItem(statusItem)
    let compressor = MainActor.assumeIsolated { model.compressor }
    DispatchQueue.global().async {
      compressor.waitUntilAllOperationsAreFinished()
      DispatchQueue.main.async { NSApp.terminate(nil) }
    }
  }
}
