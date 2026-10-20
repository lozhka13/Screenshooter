# Security scan report

| | |
|---|---|
| **Release** | v2.0.0 |
| **Date** | 2026-10-20 |
| **Scanner** | [Trivy](https://trivy.dev) 0.76.0, vulnerability DB updated 2026-10-20 07:17 UTC |
| **Result** | No vulnerabilities, secrets, misconfigurations or license issues found |

## What was scanned

| Target | Scanners | Result |
|---|---|---|
| Repository (`trivy fs .`) | vuln, secret, misconfig, license | Clean. No dependency lock files: the package has no third-party dependencies |
| GitHub Actions workflows (`trivy config .github`) | misconfig | Clean |
| `Screenshooter.app` (`trivy rootfs`) | vuln, secret | Clean for secrets; Trivy can't analyze Swift binaries for vulnerabilities |

## Dependencies

`Package.swift` declares **no third-party packages**. The app and the MCP server use only Apple frameworks: SwiftUI, AppKit, ScreenCaptureKit, AVFoundation, Vision, Speech, ImageIO, CoreImage, ServiceManagement, Carbon (hot key).

Compression uses two Homebrew formulae installed separately, not shipped in the app:

| Dependency | Installed | Latest | Status |
|---|---|---|---|
| ffmpeg | 9.0.2 | 9.0.2_1 | Revision behind — run `brew upgrade ffmpeg` |
| oxipng | 10.2.1 | 10.2.1 | Up to date |

## Permissions and data

| What | Why | Where data goes |
|---|---|---|
| Files in `~/Screenshots` | Sorting, metadata, learned suggestions | Stays there; metadata is an extended attribute on each file, suggestions in `.screenshooter/learned.json` |
| Screen & System Audio Recording | Screen recordings; window titles for suggestions | Recordings saved to Inbox |
| Microphone | Voice in recordings | Inside the recording file |
| Speech Recognition | On-device transcription for languages the new Speech API lacks (e.g. Russian) | `requiresOnDeviceRecognition` — audio never leaves the Mac |
| Automation (browsers) | Address and title of the tab you captured | Stored in the file's metadata |
| Network | Daily check of `api.github.com/repos/lozhka13/Screenshooter/releases/latest`; first-use download of Apple's speech models | Only a GET request; can be turned off in Settings → About |

Text recognition (Vision) and transcription (Speech) run on the device.

## Manual review

Trivy can't see into Swift code, so the code was reviewed by hand, with unit tests for the risky parts (`swift test`, 33 tests).

**Secret detection (new in 2.0.0)** — passwords after a label, known token formats (GitHub, OpenAI, Anthropic, Slack, AWS, Google, JWT, private keys), credentials in URLs, Luhn-valid card numbers and high-entropy tokens. Handles OCR reading Latin letters as Cyrillic twins. Blurring pixelates the area in the file (not reversible from the image); the original goes to the Trash so the edit can be undone — empty the Trash to get rid of it.

**Undo and file safety** — moves never overwrite (`name 2.png`…); background transcription and compression start 8 seconds after a move and skip files that were moved back; undo refuses while a file is being compressed. Video compression rewrites in place with a clone of the original kept until the write succeeds.

**MCP server** — every path is resolved (symlinks included) and must stay inside `~/Screenshots`; subfolder names can't contain `/` or start with `.`; no network access.

**Setup** — touches only `~/Screenshots`, the `com.apple.screencapture` location, the app's login item, and removes the 1.x launch agent.

## Notes

- The app is **signed ad hoc, not notarized** (no Apple Developer account yet). `scripts/notarize.sh` signs with a Developer ID, notarizes and staples once one is available.
- Ad-hoc signatures change with every build, so macOS may ask for Screen Recording permission again after an update.

## Reproduce

```bash
brew install trivy
trivy fs --scanners vuln,secret,misconfig,license .
trivy config .github
scripts/build-app.sh && trivy rootfs --scanners vuln,secret dist/Screenshooter.app
swift test
```
