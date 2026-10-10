# BotRecord — agent guide

BotRecord is a native macOS menu-bar app: screen/area recording, meeting notes (mic + any app's audio as two
tracks), live on-device transcription (NVIDIA Nemotron 0.6B INT8 on MLX/GPU) and optional one-click summaries
through the user's own Claude Code. Apple Silicon + macOS 26 only. Users install a prebuilt app; nothing compiles.

## Install BotRecord on this Mac

Follow these steps in order. Run every command yourself; only step 5 needs the user. Never use `sudo`.

**1. Check the Mac** (stop and tell the user if any check fails):
```sh
uname -m                          # must print arm64 (Apple Silicon)
sw_vers -productVersion           # must be 26.0 or newer
df -g ~ | awk 'NR==2 {print $4}'  # free GB, must be >= 2
```

**2. Get the repo** (keep it: it's used to update and uninstall):
```sh
git clone https://github.com/octaviusp/BotRecord.git ~/BotRecord   # or `git -C ~/BotRecord pull` if it exists
cd ~/BotRecord
```

**3. Install** (non-interactive, ~1 min, downloads ~820 MB, safe to re-run; it resumes and re-verifies):
```sh
./install
```
It ends with "BotRecord <version> is installed." Any error message says what to do; a SHA-256 mismatch → re-run.

**4. Verify**:
```sh
pgrep -x BotRecord >/dev/null && echo running                    # app is up (menu-bar icon ◉)
ls ~/Library/Application\ Support/com.octaviusp.botrecord/models/*/model.safetensors   # speech model in place
launchctl print gui/$(id -u)/com.octaviusp.botrecord >/dev/null && echo "launch at login on"
claude auth status 2>/dev/null | grep -q '"loggedIn": true' && echo "Claude connected" || echo "summaries need Connect Claude"
```

**5. Hand over to the user** — tell them, briefly:
- Click **◉** in the menu bar, or press **⌃⌥⌘R** to record the screen and **⌃⌥⌘M** for meeting notes.
- macOS will ask once for **Screen & System Audio Recording** (first recording) and **Microphone** (first meeting).
  They must click Allow themselves; agents can't grant these. If the app shows "Allow screen recording", they follow
  it and press "Relaunch BotRecord".
- If step 4 printed "summaries need Connect Claude": click **Connect Claude** in the popover (installs/sign-in
  guidance for Claude Code). Transcripts work without it.
- Recordings: `~/Movies/BotRecord` · Meetings: `~/Documents/BotRecord`.

Optional settings (only if the user asks):
```sh
defaults write com.octaviusp.botrecord outputDirectory "$HOME/path/for/recordings"
defaults write com.octaviusp.botrecord libraryDirectory "$HOME/path/for/meetings"
defaults write com.octaviusp.botrecord claudeConfigDirectories -array "~/.claude" "~/.claude-work"  # account fallback order
```

Update: `cd ~/BotRecord && git pull && ./install`. Uninstall: `cd ~/BotRecord && ./uninstall` (keeps recordings/notes).

## Development

- **Build:** Command Line Tools + `brew install svt-av1 opus`, then `scripts/build.sh` → `out/BotRecord.app`
  (ad-hoc signed; set `BOTRECORD_SIGN_IDENTITY` to a keychain identity to keep TCC permissions across rebuilds).
  No Xcode: the MLX Metal library comes prebuilt from the PyPI `mlx-metal` wheel matching mlx-swift's vendored core,
  SHA-256 checked (`research/2026-10-10-nemotron-swift-spike.md`).
- **Release:** `scripts/release.sh <version>` → `dist/` + `release.json`. Commit `release.json`, push, then
  `gh release create v<version> dist/*`. `./install` reads `release.json` and downloads from that release
  (git can't hold the 768 MB weights; `BOTRECORD_ASSETS_DIR=<dir> ./install --no-launch` tests offline).
- **Layout:** `Sources/BotRecord/{Core (contracts, models, tokens), App (state machines, library, summaries, hotkeys),
  UI, Overlay (area selection, HUD), Capture (ScreenCaptureKit, mic), Encoding (SVT-AV1, Opus, WebM muxer),
  Transcription (VAD, Nemotron engine)}`. Design: `design/screen-recorder.pen` (Pen). Screenshots: `docs/images/`.
- **Conventions:** files < 1000 lines, one responsibility each, protocols for swappable parts, explicit errors,
  no dead code. Every action gives visible feedback; the status item always shows state.

### Things that look wrong but are deliberate
- The Nemotron model loads only while a recording with transcript runs and unloads right after (idle app ≈ 40 MB).
- Meetings always capture all apps' audio: ScreenCaptureKit can't see the helper processes Discord/Chrome/Teams play
  sound from, so per-app capture recorded silence.
- Voice processing (echo cancellation) is Auto: on only with built-in speakers; it lowers call audio ~8 dB.
- Install the mic tap with `format: nil` and recreate `AVAudioEngine` after configuration changes: a stale format
  raises an uncatchable Objective-C exception.
- The popover closes on outside clicks, not on focus loss (launching `claude` briefly steals focus).
- speech-swift 0.0.28 needs 320 ms of lead-in and 640 ms of trailing silence per utterance, and `es-US` for Spanish.
- WhatsApp re-encodes video to 848/1280 px; "Copy as MP4" pre-fits 1280 px (`research/2026-10-10-whatsapp-quality.md`).
- zsh's `log` builtin shadows macOS `log`: use `/usr/bin/log show|stream --predicate 'process == "BotRecord"'`.
