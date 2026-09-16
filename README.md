# Tunesmith

A native macOS app for generating original songs locally with [YuE2](https://github.com/multimodal-art-projection/YuE) via the [mlx-Yue](https://github.com/vanch007/mlx-Yue) Apple Silicon port, with Claude writing the lyrics through the Claude Code CLI (your subscription — no API key).

## Features

- **Composer** — idea → *Refine prompt* → *Write song* (title, style line, lyrics) → *Generate*. Full score / melody / direct modes, fast-draft toggle, seeds, lyrics find & replace.
- **Libraries › Categories › Songs** with playlists (drag to reorder, sequential playback).
- **Playback** — play a library, a category or a playlist in order or **shuffled**. Shuffle sits next to *Start radio* on a library page, next to *Play all* on a playlist, and in the right-click menu of any library, category or playlist. While something is playing, the shuffle button in the now-playing bar and the player transport reshuffles only what is still to come, leaving the current track alone.
- **Radio** — describe a library, refine it into a station brief, turn on radio: Claude keeps writing new songs that fit, YuE2 renders them one after another, and each is auto-filed into a matching category (created on demand). With Auto-play on the station never goes silent — while the next song renders it airs random songs from the same library, and the fresh song goes on the air as soon as the current track ends. Stopping the station lets the song already rendering finish and file itself.
- **Song player** — timeline scrubber, transport, lyrics; *Edit* reopens the exact generation details (saved as `studio.json` with every song) to tweak and *Regenerate* in place. Every song gets its own cover art, generated from a hash of its id, so it looks the same everywhere it appears.
- Export to M4A, view the ABC score, reveal in Finder.
- **Share via email** — sends the song as an M4A attachment (with its style and, optionally, lyrics and a note) through [Remail](https://remail.foo). Add your Remail API key, From address (must be on a verified Remail domain) and optional Reply-to in Settings › Email sharing; *Check connection* runs Remail's account status. The key is stored in the login Keychain.

## Requirements

- Apple Silicon Mac, macOS 14+, Xcode command-line tools (Swift 5.9+).
- An [mlx-Yue](https://github.com/vanch007/mlx-Yue) checkout with weights downloaded (default location `~/repos/mlx-Yue`, changeable in Settings):
  ```bash
  git clone https://github.com/vanch007/mlx-Yue.git ~/repos/mlx-Yue && cd ~/repos/mlx-Yue
  uv sync --frozen --no-dev
  uvx --from huggingface_hub hf download vanch007/mlx-Yue2-3B --local-dir models/converted
  uvx --from huggingface_hub hf download m-a-p/YuE2-Vae --local-dir models/vae
  rm -rf models/converted/.cache models/vae/.cache models/converted/.gitattributes
  ```
- [Claude Code](https://claude.com/claude-code) installed and logged in (`claude` on your PATH) for song writing and radio.
- `ffmpeg` (Homebrew) for M4A export.

## Build

```bash
./build.sh
```

Builds a release binary, wraps it as `Tunesmith.app`, ad-hoc signs it, and installs it to `~/Applications`.

Songs and library metadata live in `~/Music/Tunesmith/` (changeable in Settings). An existing `~/Music/YuE2 Studio/` from before the rename keeps being used as-is.

### Rebuilding on every save

```bash
scripts/autobuild-toggle.sh on     # off | status
```

Loads a launchd agent that checks every 15s whether anything under `Sources/`, `Package.swift`, `Info.plist`, `make-icon.swift` or `build.sh` has changed since the last successful build, and if so reruns `build.sh`. A failed build leaves the installed app alone. Log: `~/Library/Logs/tunesmith-autobuild.log`. An app that is already running keeps its old code until you quit and reopen it.

## License note

YuE2's model weights are licensed **CC BY-NC 4.0** (non-commercial). This app's code is MIT; what you generate is subject to the model license.
