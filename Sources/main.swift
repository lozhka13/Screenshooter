// One window for sorting screenshots and screen recordings from ~/Screenshots/Inbox.
// Preview, m / n progress, glass buttons (Liquid Glass, macOS 26):
//   1/2/3 — category; inside a category with subfolders 1 — the category itself, 2…9 — subfolder,
//   N — new folder, Esc — back; Delete — move to Trash.
// Categories come from ~/Screenshots/categories.json, subfolders from disk.
// After a move the file is compressed in the background (~/bin/screenshot-compress.sh).
// Build and install: ./install.sh
// Launched by launchd (com.screenshooter.sorter) whenever Inbox changes.
import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
