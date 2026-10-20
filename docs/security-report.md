# Security scan report

| | |
|---|---|
| **Release** | v1.1.0 |
| **Date** | 2026-10-20 |
| **Scanner** | [Trivy](https://trivy.dev) 0.76.0, vulnerability DB updated 2026-10-20 07:17 UTC |
| **Result** | No vulnerabilities, secrets or license issues found |

## What was scanned

| Target | Scanners | Result |
|---|---|---|
| Repository (`trivy fs .`) | secret, license | Clean — no findings |
| Repository (`trivy fs .`) | vuln, misconfig | Not applicable — no dependency manifests or IaC files |
| App binary `screenshot-sorter` (`trivy rootfs`) | vuln, secret | Not applicable — Trivy cannot analyze Swift binaries |
| `oxipng` binary (`trivy rootfs`) | vuln | Not applicable — built without embedded dependency metadata |

## Dependencies

Screenshooter has **no third-party code packages**: the app uses only Apple frameworks (SwiftUI, AppKit, AVFoundation), and the scripts use system tools plus two Homebrew formulae installed at runtime.

| Dependency | Source | Installed | Latest | Status |
|---|---|---|---|---|
| ffmpeg | Homebrew | 9.0.2 | 9.0.2_1 | Revision behind — run `brew upgrade ffmpeg` |
| oxipng | Homebrew | 10.2.1 | 10.2.1 | Up to date |

Because these are installed by Homebrew rather than bundled, they are kept current with `brew upgrade` and do not ship inside the release archive.

## Manual review

Trivy cannot see into Swift code, so the code was also reviewed by hand for file-safety issues. Fixed in this release:

- Holding a key no longer sorts several files in a row (key auto-repeat is ignored).
- Keys act only while the window is visible and focused, never on a file hidden in the menu bar.
- Video compression rewrites the file in place with a clone of the original kept until the write succeeds; an interrupted run restores the original and leaves no temporary files.
- Quitting stops the scanner so new screenshots don't reopen the window.

## Notes

- The release binary is **not code-signed or notarized**. `install.sh` removes the quarantine attribute; building from source avoids running a prebuilt binary at all.
- The app only reads and writes inside `~/Screenshots` (or `SCREENSHOOTER_HOME`) and runs `~/bin/screenshot-compress.sh`. It makes no network connections.

## Reproduce

```bash
brew install trivy
trivy fs --scanners vuln,secret,misconfig,license .
brew outdated ffmpeg oxipng
```
