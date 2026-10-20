# Installing Screenshooter

This guide takes about five minutes. You need:

- macOS 26 (Tahoe) or later on an Apple Silicon Mac;
- [Homebrew](https://brew.sh) — only for background compression (`ffmpeg`, `oxipng`). Without it everything else works.

## 1. Install compression tools

Open Terminal and run:

```bash
brew install ffmpeg oxipng
```

Skip this step if you don't need files compressed.

## 2. Install the app

### Option A — disk image (recommended)

1. Download `Screenshooter-1.2.0.dmg` from the [latest release](https://github.com/lozhka13/Screenshooter/releases/latest).
2. Open it and drag **Screenshooter** onto **Applications**.
3. Open **Applications** and double-click **Screenshooter**.

The app is signed ad hoc but not notarized by Apple, so on the first launch macOS says it can't verify the developer:

1. Click **Done** (not *Move to Trash*).
2. Open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to Screenshooter.
3. Confirm with **Open** and your password.

You only do this once. Alternatively, remove the quarantine flag in Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/Screenshooter.app
```

### Option B — build from source

Needs Xcode Command Line Tools (`xcode-select --install`):

```bash
git clone https://github.com/lozhka13/Screenshooter.git
cd Screenshooter
./install.sh
```

The script installs the Homebrew tools, builds `Screenshooter.app`, copies it to `/Applications` (or `~/Applications` if that isn't writable) and opens it. A locally built app doesn't trigger the Gatekeeper warning.

## 3. First launch

When you open Screenshooter from Finder it sets itself up and shows a status window:

- creates `~/Screenshots/Inbox` and makes macOS save screenshots and screen recordings there;
- creates `~/Screenshots/categories.json` with example categories;
- registers a launch agent (`~/Library/LaunchAgents/com.screenshooter.sorter.plist`), so the app starts by itself whenever a file lands in Inbox and quits once everything is sorted.

There is no Dock icon and nothing to keep running — the app appears only when there is something to sort.

## 4. Turn off the floating thumbnail

Press `Cmd+Shift+5` → **Options** → uncheck **Show Floating Thumbnail**.

With the thumbnail on, a screenshot reaches Inbox only after the thumbnail slides away, and if you drag the thumbnail into a chat the file is never saved.

## 5. Try it

Press `Cmd+Shift+4` and select an area. The sorting window opens:

- `1` `2` `3` choose a category; categories with subfolders open a second level (`1` — the category itself, `2…9` — subfolders, `N` — new folder);
- `Delete` moves the file to the Trash;
- drag the preview into any chat to send a copy.

See the [key reference](../README.md#keys) for everything else.

## 6. Set up your categories

Click **Edit Categories** in the status window (open the app from Applications to see it again), or edit `~/Screenshots/categories.json`:

```json
[
  { "label": "Work", "folder": "Work", "subfolders": false },
  { "label": "Projects", "folder": "Projects", "subfolders": true },
  { "label": "Personal", "folder": "Personal", "subfolders": true }
]
```

- `label` — button text;
- `folder` — folder inside `~/Screenshots`;
- `subfolders` — show the second level with the folders inside it.

Up to 9 categories; the key is the position in the list. Changes apply the next time the window opens.

## 7. Connect Claude (optional)

Screenshooter includes an MCP server, so Claude can list, view and file your screenshots. Click **Copy Claude MCP Command** in the status window and run it in Terminal, or run:

```bash
claude mcp add --scope user screenshooter /Applications/Screenshooter.app/Contents/MacOS/screenshooter-mcp
```

Then ask Claude things like *“what's on my latest screenshot?”* or *“move today's screenshots of the dashboard to Projects → Atlas”*. The server can only read and write inside `~/Screenshots`.

For Claude Desktop, add this to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "screenshooter": {
      "command": "/Applications/Screenshooter.app/Contents/MacOS/screenshooter-mcp"
    }
  }
}
```

## Updating

Download the new disk image and replace the app in Applications, or run `git pull && ./install.sh`. Open the app once afterwards so it updates the launch agent.

## Uninstalling

```bash
./uninstall.sh
```

Or by hand:

```bash
launchctl bootout gui/$(id -u)/com.screenshooter.sorter
rm ~/Library/LaunchAgents/com.screenshooter.sorter.plist
rm -rf /Applications/Screenshooter.app
defaults delete com.apple.screencapture location && killall SystemUIServer
claude mcp remove --scope user screenshooter
```

Your sorted files stay in `~/Screenshots`.

## Troubleshooting

| Problem | Fix |
|---|---|
| The window doesn't open after a screenshot | Open the app from Applications once — it re-registers the launch agent. Check `~/Screenshots/.sorter.log`. |
| Screenshots still land on the Desktop | `Cmd+Shift+5` → Options → Save to → Other Location → `~/Screenshots/Inbox`, or reopen the app. |
| The window opens only a few seconds later | Turn off the floating thumbnail (step 4). |
| Files aren't getting smaller | Install the tools: `brew install ffmpeg oxipng`. The status window shows whether compression is on. |
| “Screenshooter can't be opened” | See the Gatekeeper steps in [Option A](#option-a--disk-image-recommended). |
| Claude doesn't see the tools | Run `claude mcp list`; the `screenshooter` server should be listed. Restart Claude after adding it. |
