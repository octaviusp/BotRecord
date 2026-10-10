# BotRecord

A native macOS menu-bar screen recorder and meeting notetaker that transcribes on your Mac, live, with no cloud.

## Features

- **Screen recording**: full screen or a selected area, 720p/1080p at 30/60 fps, with a one-click
  "Copy to clipboard" as soon as you stop.
  - **WebM · AV1** (default): about 5× smaller than H.264 at higher quality, encoded live with SVT-AV1 and Opus.
  - **MP4 · H.264**: Apple's hardware encoder, plays everywhere. An MP4 copy is always kept for a day so "Copy as MP4" is instant.
- **Meeting notes** (⌃⌥⌘M): records your microphone and the call's audio as separate tracks, with optional
  screen video and echo cancellation for speakers.
- **Live transcript, fully on-device**: NVIDIA's Nemotron 3.5 ASR Streaming 0.6B (INT8, MLX on the GPU)
  transcribes while you record, so `transcript.md` is ready the moment you press Stop. English and Spanish.
- **Meeting summaries** (optional): one click turns a transcript into a summary with decisions, action items
  and open questions, through [Claude Code](https://claude.com/claude-code) and your own Claude account.
- **A library any AI agent can read**: every meeting gets a folder with `transcript.md`, `summary.md` and
  `meta.json`, plus a running `decisions.md` and an `AGENTS.md` that explains the layout.

## Requirements

- A Mac with Apple Silicon (M1 or newer)
- macOS 26 or newer
- About 1.2 GB of free disk space (the app is 50 MB, the speech model 770 MB)
- Optional, for summaries: [Claude Code](https://claude.com/claude-code), signed in

## Install

```sh
git clone https://github.com/octaviusp/BotRecord.git
cd BotRecord
./install
```

No Xcode, no Homebrew, no admin password. `./install` downloads the prebuilt app and the speech model from this
repository's GitHub release, checks every file against the SHA-256 in [`release.json`](release.json), installs
the app to `~/Applications/BotRecord.app`, turns on launch at login and opens it. Interrupted downloads resume
when you run it again.

To update: `git pull && ./install`. Your settings, recordings and notes stay as they are.

## First run and permissions

BotRecord lives in the menu bar. macOS asks for each permission once, the first time it's needed, and you have to
approve it yourself:

- **Screen & System Audio Recording**, on your first recording. BotRecord shows a short guide that opens
  System Settings for you, then relaunch it with one click.
- **Microphone**, on your first meeting (or a recording with the microphone on).

For summaries, click **Connect Claude** in the menu-bar popover. If Claude Code isn't installed, it takes you to the
install page; if it is, it opens Claude's sign-in in your browser. Transcripts work without it.

## Shortcuts

| Keys | Action |
|---|---|
| ⌃⌥⌘R | Start / stop a screen recording |
| ⌃⌥⌘A | Select an area and record it |
| ⌃⌥⌘M | Start / stop meeting notes |
| Esc | Cancel the area selection or countdown |

## Where files go

| What | Where |
|---|---|
| App | `~/Applications/BotRecord.app` |
| Screen recordings (and their `.md`/`.vtt` transcripts) | `~/Movies/BotRecord` (change in Settings) |
| Meeting library | `~/Documents/BotRecord` (change in Settings) |
| Speech model | `~/Library/Application Support/com.octaviusp.botrecord/models` |
| Caches (thumbnails, MP4 copies kept for a day) | `~/Library/Caches/com.octaviusp.botrecord` |
| Launch at login | `~/Library/LaunchAgents/com.octaviusp.botrecord.plist` (toggle in Settings) |

## Privacy

- Recording, encoding and transcription run entirely on your Mac. Nothing is uploaded and there is no telemetry.
- Summaries are the only feature that leaves your Mac, and only when you click the button: the transcript is sent
  through **your** Claude Code installation to **your** Claude account, with every Claude Code tool disabled
  (it can only read the transcript and write text). Without Claude Code installed, nothing is ever sent.

### Several Claude accounts

Summaries use Claude Code's default login. To try several accounts in order (the next one is used when one is out of
quota or signed out), list their Claude Code config directories:

```sh
defaults write com.octaviusp.botrecord claudeConfigDirectories -array "~/.claude" "~/.claude-work"
```

## Uninstall

```sh
./uninstall
```

Removes the app, launch at login, the speech model, caches and settings. Your recordings and meeting library are
never deleted; the script prints where they are.

## Build from source

Needs Command Line Tools (`xcode-select --install`) and Homebrew's `svt-av1` and `opus` (build time only; the
libraries are copied into the app):

```sh
brew install svt-av1 opus
scripts/build.sh          # → out/BotRecord.app
open out/BotRecord.app
```

The first build also downloads MLX's prebuilt Metal library (the PyPI `mlx-metal` wheel matching the MLX core
that mlx-swift vendors, SHA-256 checked), because Command Line Tools can't compile Metal shaders. The app is
signed ad hoc, so macOS asks for Screen Recording again after every rebuild; set `BOTRECORD_SIGN_IDENTITY` to a
code-signing identity in your keychain (a self-signed one works) to keep the permission across builds.

Releases: `scripts/release.sh <version>` builds the app, zips it, collects the model files into `dist/` and
rewrites `release.json`. Commit `release.json` and attach everything in `dist/` to the GitHub release `v<version>`.

| Path | What |
|---|---|
| `Sources/BotRecord/Core` | Shared models, contracts (protocols), design tokens |
| `Sources/BotRecord/App` | Entry point, state machines, hotkeys, library, summaries, launch at login |
| `Sources/BotRecord/UI` | Popover, settings, permission guide, toasts |
| `Sources/BotRecord/Overlay` | Area selection, countdown, recording HUD |
| `Sources/BotRecord/Capture` | ScreenCaptureKit and microphone capture, hardware H.264 writer |
| `Sources/BotRecord/Encoding` | SVT-AV1 and Opus encoders, WebM muxer |
| `Sources/BotRecord/Transcription` | Speech segmenter, Nemotron engine, live transcriber, model download |
| `research/` | Encoder benchmark, Nemotron Swift spike, video quality notes |

## Credits and licenses

BotRecord is MIT licensed ([`LICENSE`](LICENSE)). It builds on [SVT-AV1](https://gitlab.com/AOMediaCodec/SVT-AV1)
(BSD-3-Clause-Clear and the AOMedia Patent License), [Opus](https://opus-codec.org) (BSD-3-Clause),
[speech-swift](https://github.com/soniqo/speech-swift) (Apache-2.0) and [MLX](https://github.com/ml-explore/mlx-swift)
(MIT). The speech model is NVIDIA's
[Nemotron 3.5 ASR Streaming 0.6B](https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b) in the
[MLX INT8 conversion](https://huggingface.co/aufklarer/Nemotron-3.5-ASR-Streaming-0.6B-MLX-8bit) by aufklarer, under
the OpenMDW-1.1 license ([`licenses/LICENSE-OpenMDW-1.1.txt`](licenses/LICENSE-OpenMDW-1.1.txt)). Full notices for
every bundled component are in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md), also inside the app.
