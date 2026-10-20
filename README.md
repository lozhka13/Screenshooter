# Screenshooter

Sort macOS screenshots and screen recordings into folders right after you take them — with one key.

Take a screenshot (`Cmd+Shift+3/4/5`) or a screen recording and a window opens with a large preview. Press `1`, `2` or `3` and the file goes to the right folder and gets compressed in the background. A burst of screenshots is sorted one after another in the same window, with `3 / 12` progress in the title bar.

![Screenshooter window with a screenshot of an analytics dashboard and Work, Projects and Personal buttons](docs/overview.png)

## A quick tour

**Sort with one key.** The window fits the screenshot's aspect ratio, so there are no empty bars around the preview. The progress counter and file name live in the title bar, and the bottom row holds the categories. `Work` has no subfolders, so `1` moves the file straight away. `Projects` and `Personal` have subfolders, which the chevron shows.

**Pick a subfolder.** Press `2` and the glass buttons morph into the second level: `1` keeps the file in `Projects` itself, `2…9` pick a subfolder, `N` creates a new one right from the window, and `Esc` goes back.

![Second level: Projects with Atlas, Halo and Orbit website subfolders and a New folder button](docs/subfolders.png)

**Read the small print.** Hover over the preview and a loupe magnifies the area under the cursor 2.5×, so you can tell which screenshot is which without opening it. Right-click toggles the loupe.

![Loupe magnifying chat text in a screenshot of a code editor](docs/loupe.png)

*The screenshots above show made-up apps rendered for this README.*

## Features

- **One window for the whole queue.** The image and the counter just change; there are no pop-up dialogs.
- **Categories and subfolders**, for example `Projects → Atlas`. Create folders right from the window.
- **Liquid Glass** (macOS 26): glass buttons that morph between levels over a blurred copy of the screenshot.
- **Loupe** on hover, toggled with the right mouse button or the loupe button.
- **Drag and drop**: drag the preview into Telegram, Slack or any app to send a copy of the file.
- **Hidden from screenshots and screen recordings**, even when you capture the whole screen.
- **Background compression**: PNG losslessly (`oxipng`), video to H.265 at visually lossless quality (`ffmpeg`). Creation date and Finder tags are kept, and the original video goes to the Trash.
- **Menu bar mode**: hide the window and keep a counter of waiting files in the menu bar.
- **Full screen width** with the green button or `F`.

## Keys

| Key | Action |
|---|---|
| `1` `2` `3` | Category. Without subfolders the file moves at once; with subfolders the second level opens |
| `1` (second level) | Into the category itself |
| `2`…`9` (second level) | Into a subfolder |
| `N` | New subfolder (type a name, then `Enter`) |
| `Esc` | Back |
| `Delete` | Move to Trash |
| `F` | Full screen width and back |
| Right mouse button | Loupe on/off |
| Yellow / red window button | Hide to the menu bar |

## Install

You need macOS 26 (Tahoe), Apple Silicon and [Homebrew](https://brew.sh), which installs `ffmpeg` and `oxipng`.

**From source** (needs Xcode Command Line Tools: `xcode-select --install`):

```bash
git clone https://github.com/lozhka13/Screenshooter.git
cd Screenshooter
./install.sh
```

**From a release**: download the archive from the [releases page](https://github.com/lozhka13/Screenshooter/releases), unzip it and run `./install.sh`. This installs the prebuilt binary.

The installer:

- puts the app and the compression script into `~/bin`;
- makes macOS save screenshots to `~/Screenshots/Inbox`;
- creates `~/Screenshots/categories.json` with example categories, unless it already exists;
- registers a launch agent (`~/Library/LaunchAgents/com.screenshooter.sorter.plist`). The app starts by itself when a file lands in Inbox and quits once everything is sorted.

Turn off the floating thumbnail: `Cmd+Shift+5` → Options → uncheck “Show Floating Thumbnail”. Otherwise a screenshot reaches Inbox only after the thumbnail disappears, and if you drag the thumbnail into a chat the file is never saved.

## Categories

Categories live in `~/Screenshots/categories.json`:

```json
[
  { "label": "Work", "folder": "Work", "subfolders": false },
  { "label": "Projects", "folder": "Projects", "subfolders": true },
  { "label": "Personal", "folder": "Personal", "subfolders": true }
]
```

`label` is the button text, `folder` is the folder inside `~/Screenshots`, and `subfolders` says whether to show the second level. The shortcut is the position in the list (up to 9). Changes apply the next time the window opens.

Subfolders come from disk: every folder inside `~/Screenshots/<folder>/` shows up on the second level in alphabetical order.

## How it works

| File | What it does |
|---|---|
| `Sources/Config.swift` | Paths, categories, launch environment |
| `Sources/SorterModel.swift` | Watches Inbox, queues files once they stop growing, moves and deletes files, handles keys |
| `Sources/SorterView.swift` | The window content: preview, loupe, glass buttons |
| `Sources/FlowLayout.swift` | Wraps the buttons onto rows |
| `Sources/AppDelegate.swift` | Window, menu bar item, keyboard and mouse monitors |
| `scripts/screenshot-compress.sh` | Compresses one file in place; the app runs it after each move, one file at a time, at low priority |

A launchd `WatchPaths` agent starts the app whenever Inbox changes. Errors are logged to `~/Screenshots/.sorter.log`.

For demos and tests, `SCREENSHOOTER_HOME=/some/folder` points the app at another folder, and `SCREENSHOOTER_DEMO=1` makes the window visible to screenshots without taking focus, keys or clicks.

## Security

The [security report](docs/security-report.md) covers the Trivy scan and the manual review for the current release.

## Limitations

- The window is hidden from the system capture (`screencapture`, `Cmd+Shift+3/4/5`). Apps with their own capture (Zoom, Google Meet, OBS) may still show it on recent macOS versions.
- Video compression is not strictly lossless: H.265 CRF 22, SSIM ≈ 0.998. You can't see the difference, and screen recordings get 5–7× smaller.
- The built-in macOS screen recording captures the microphone only, not system audio.

## Uninstall

```bash
./uninstall.sh
```

This removes the app and the launch agent and sends screenshots back to the Desktop. `~/Screenshots` with your sorted files stays.
