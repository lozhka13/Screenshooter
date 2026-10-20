# Security scan report

| | |
|---|---|
| **Release** | v1.2.0 |
| **Date** | 2026-10-20 |
| **Scanner** | [Trivy](https://trivy.dev) 0.76.0, vulnerability DB updated 2026-10-20 07:17 UTC |
| **Result** | No vulnerabilities, secrets or license issues found |

## What was scanned

| Target | Scanners | Result |
|---|---|---|
| Repository (`trivy fs .`) | secret, license | Clean — no findings |
| Repository (`trivy fs .`) | vuln, misconfig | Not applicable — no dependency manifests or IaC files |
| `Screenshooter.app` (`trivy rootfs`) | vuln, secret | Clean for secrets; vulnerabilities not applicable — Trivy cannot analyze Swift binaries |
| `oxipng` binary (`trivy rootfs`) | vuln | Not applicable — built without embedded dependency metadata |

## Dependencies

Screenshooter has **no third-party code packages**: the app and the MCP server use only Apple frameworks (SwiftUI, AppKit, AVFoundation, ImageIO), and the compression script uses system tools plus two Homebrew formulae.

| Dependency | Source | Installed | Latest | Status |
|---|---|---|---|---|
| ffmpeg | Homebrew | 9.0.2 | 9.0.2_1 | Revision behind — run `brew upgrade ffmpeg` |
| oxipng | Homebrew | 10.2.1 | 10.2.1 | Up to date |

These are installed by Homebrew rather than bundled, so they are kept current with `brew upgrade` and don't ship inside the release.

## Manual review

Trivy can't see into Swift code, so the code was also reviewed by hand.

**MCP server (new in 1.2.0)**

- Every path from Claude is resolved (symlinks included) and must stay inside `~/Screenshots`; `../` escapes and absolute paths elsewhere are rejected. Verified with a request for `../../../../etc/hosts`.
- Subfolder names can't contain `/` or start with `.`.
- `move_screenshot` never overwrites: a name clash gets a ` 2`, ` 3`… suffix.
- No network access; the server talks to its client over stdio only.

**First-run setup (new in 1.2.0)**

- Only runs when the app is a real `.app` bundle and not in demo mode.
- Changes only: `~/Screenshots`, the `com.apple.screencapture` location, and `~/Library/LaunchAgents/com.screenshooter.sorter.plist`. The agent is rewritten only when the app has moved.

**File safety (fixed in 1.1.0)**

- Held keys don't sort several files; keys act only while the window is visible and focused.
- Video compression rewrites in place with a clone of the original kept until the write succeeds; an interrupted run restores the original and leaves no temporary files.

## Notes

- The app is **signed ad hoc, not notarized**: macOS asks for confirmation on first launch (see the [installation guide](INSTALL.md)). Building from source avoids running a prebuilt binary at all.
- The app and the MCP server read and write only inside `~/Screenshots` (or `SCREENSHOOTER_HOME`), run the bundled compression script, and make no network connections.

## Reproduce

```bash
brew install trivy
trivy fs --scanners vuln,secret,misconfig,license .
scripts/build-app.sh && trivy rootfs --scanners vuln,secret dist/Screenshooter.app
brew outdated ffmpeg oxipng
```
