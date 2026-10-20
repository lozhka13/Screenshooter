// Screenshots pinned on top of other windows, like a sticky note.
import Cocoa

@MainActor
enum Pins {
  static var panels: [NSPanel] = []

  static func pin(_ url: URL) {
    guard let image = NSImage(contentsOf: url) else { return }
    let scale = min(1, 520 / max(image.size.width, image.size.height))
    let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
    let panel = NSPanel(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel, .utilityWindow],
      backing: .buffered, defer: false)
    panel.title = url.lastPathComponent
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.isMovableByWindowBackground = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.contentAspectRatio = size
    panel.isReleasedWhenClosed = false
    let view = NSImageView(image: image)
    view.imageScaling = .scaleProportionallyUpOrDown
    panel.contentView = view
    // Cascade from the top right so several pins don't cover each other.
    if let screen = NSScreen.main?.visibleFrame {
      let offset = CGFloat(panels.count % 6) * 28
      panel.setFrameTopLeftPoint(NSPoint(x: screen.maxX - size.width - 24 - offset, y: screen.maxY - 24 - offset))
    }
    panel.orderFrontRegardless()
    panels.removeAll { !$0.isVisible }
    panels.append(panel)
  }
}
