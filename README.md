# Rec

Minimal native macOS menu-bar screen recorder: full screen or an area, 720p/1080p at 30/60 fps,
saved instantly with a one-click "Copy to clipboard".

- **WebM · AV1** (default): SVT-AV1 encoded live on the CPU, Opus audio, hand-written WebM muxer.
  Measured ~5× smaller than hardware H.264 at higher quality (`research/2026-10-10-encoder-bench.md`).
- **MP4 · H.264**: Apple Media Engine, near-zero CPU, plays everywhere. Also recorded alongside AV1
  so "Copy as MP4" is instant.

## Build

Requires macOS 26, Command Line Tools and Homebrew `svt-av1` + `opus` (build time only; the dylibs
are bundled into the app).

```sh
scripts/build.sh          # → out/Rec.app
open out/Rec.app
```

The app is signed with the local self-signed identity `Rec Local Signing` (login keychain) so the
Screen Recording permission survives rebuilds. Without it the script signs ad-hoc and macOS asks again
after every build.

## Layout

| Path | What |
|---|---|
| `Sources/Rec/Core` | Shared models, contracts (protocols), design tokens |
| `Sources/Rec/App` | Entry point, state machine, hotkeys, composition root |
| `Sources/Rec/UI` | Popover, settings, permission, toasts |
| `Sources/Rec/Overlay` | Area selection, countdown, recording HUD |
| `Sources/Rec/Capture` | ScreenCaptureKit recorder, hardware H.264 MP4 writer |
| `Sources/Rec/Encoding` | SVT-AV1 + Opus encoders, WebM muxer |
| `design/` | Pen design file (`screen-recorder.pen`) |
| `research/` | Encoder benchmark and script |

## Installed outside this folder

- `~/Applications/Rec.app` → symlink to `out/Rec.app`
- Recordings: `~/Movies/general/screen-recordings/` (configurable)
- Caches: `~/Library/Caches/local.tools.screen-recorder/`
- Keychain: certificate "Rec Local Signing" (login keychain)

Uninstall: quit Rec, remove the symlink and caches, delete the certificate in Keychain Access, delete this folder.
