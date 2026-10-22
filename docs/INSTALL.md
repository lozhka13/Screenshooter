# Installing Screenshooter

About five minutes. You need macOS 26 (Tahoe) or later on an Apple Silicon Mac.

## 1. Install

### Homebrew (recommended)

```bash
brew install --cask lozhka13/tap/screenshooter
brew install ffmpeg oxipng   # optional: background compression
```

### Disk image

1. Download `Screenshooter-2.2.1.dmg` from the [latest release](https://github.com/lozhka13/Screenshooter/releases/latest).
2. Open it and drag **Screenshooter** onto **Applications**.
3. Optional: `brew install ffmpeg oxipng` for compression.

### From source

Needs Xcode or the Command Line Tools (`xcode-select --install`):

```bash
git clone https://github.com/lozhka13/Screenshooter.git
cd Screenshooter
./install.sh
```

## 2. First launch

Open **Screenshooter** from Applications.

The app is signed ad hoc but not notarized, so macOS may say it can't verify the developer the first time:

1. Click **Done** (not *Move to Trash*).
2. Open **System Settings → Privacy & Security**, scroll down, click **Open Anyway** next to Screenshooter and confirm.

Or in Terminal: `xattr -dr com.apple.quarantine /Applications/Screenshooter.app`.

On first launch Screenshooter:

- creates `~/Screenshots/Inbox` and makes macOS save screenshots and screen recordings there;
- creates `~/Screenshots/categories.json` with example categories;
- adds itself to **Login Items** so it starts with your Mac (turn off in Settings → General);
- shows a welcome message and lives in the menu bar from then on — the 🖼 icon with a count of waiting files.

If you used Screenshooter 1.x, the old launch agent is removed automatically.

## 3. Turn off the floating thumbnail

`Cmd+Shift+5` → **Options** → uncheck **Show Floating Thumbnail**. Otherwise a screenshot reaches Inbox only after the thumbnail slides away.

## 4. Permissions

macOS asks for each of these the first time a feature needs it. All are optional.

| Permission | Asked when | Used for |
|---|---|---|
| Screen & System Audio Recording | You start a recording | Recording the screen and call audio; also lets suggestions see window titles |
| Microphone | You start a recording with the microphone on | Your voice in recordings |
| Speech Recognition | A Russian (or other non-English) recording is transcribed | On-device transcription |
| Automation → your browser | You take a screenshot of a browser | Reading the tab's address and title for suggestions and file names |

Settings → Recording has buttons that open the right System Settings pages.

## 5. Try it

Press `Cmd+Shift+4` and select an area. The sorting window opens:

- `1` `2` `3` choose a category; categories with subfolders open a second level;
- after a few sorted screenshots of the same app or page, a suggestion appears — press `Return`;
- `E` marks it up, `R` blurs detected secrets, `C` copies, `T` copies the text, `P` pins it, `B` styles it, `Delete` trashes, `⌘Z` undoes.

Search everything you captured with `⌃⌥⌘F`.

Record the screen with `⌃⌥⌘R` (or **Record Screen** in the menu bar), press it again to stop. The recording is sorted like a screenshot and transcribed into a `.txt` next to it.

## 6. Categories

**Settings → Categories** (menu bar icon → Settings…): label, folder, whether it has subfolders, and keywords that suggest it. Or edit `~/Screenshots/categories.json`. Up to 9; the key is the position in the list.

## 7. Connect Claude (optional)

**Settings → Claude → Copy Command**, then run it in Terminal:

```bash
claude mcp add --scope user screenshooter /Applications/Screenshooter.app/Contents/MacOS/screenshooter-mcp
```

For Claude Desktop, **Copy Configuration** gives the block for `~/Library/Application Support/Claude/claude_desktop_config.json`.

Then ask Claude *“what's on my latest screenshot?”*, *“find screenshots with ‘invoice’ from this week”* or *“read the transcript of today's recording and list the action items”*.

## Updating

Screenshooter checks GitHub for a new version once a day (Settings → About). With Homebrew: `brew upgrade --cask screenshooter`. Or download the new disk image and replace the app.

## Uninstalling

```bash
brew uninstall --cask screenshooter   # or quit from the menu bar and delete the app
./uninstall.sh                        # puts screenshots back on the Desktop, removes the Claude registration
```

Your files stay in `~/Screenshots`.

## Troubleshooting

| Problem | Fix |
|---|---|
| No window after a screenshot | Is the 🖼 icon in the menu bar? If not, open the app. Check that screenshots go to `~/Screenshots/Inbox` (`Cmd+Shift+5` → Options → Save to). |
| Window opens a few seconds late | Turn off the floating thumbnail (step 3). |
| No folder suggestions | They appear after a few screenshots of the same page or app are filed, or add keywords to a category. Settings → General must have suggestions on. |
| “Can't start recording” | Allow Screenshooter in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen it. |
| No transcript | Settings → Recording → Transcription on; for Russian allow Speech Recognition. English models download on first use. |
| Files aren't getting smaller | `brew install ffmpeg oxipng`. |
| Claude doesn't see the tools | `claude mcp list` should list `screenshooter`; restart Claude after adding it. |
| Logs | `log stream --predicate 'process == "Screenshooter"'` |
