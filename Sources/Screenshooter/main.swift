// Screenshooter: a menu bar app that sorts screenshots and screen recordings from ~/Screenshots/Inbox.
// A window opens for every new file: preview, folder suggestion, glass buttons (Liquid Glass, macOS 26).
//   1/2/3 — category; inside a category with subfolders 1 — the category itself, 2…9 — subfolder,
//   N — new folder, Esc — back, Return — take the suggestion, Delete — Trash, ⌘Z — undo,
//   C — copy, E — edit (arrows, boxes, text, blur), R — blur detected secrets, F — full width.
// Categories come from ~/Screenshots/categories.json, subfolders from disk.
// After a move recordings are transcribed and files compressed in the background.
// Build: scripts/build-app.sh
import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
