# Song Studio

A native macOS app for generating original songs locally with [YuE2](https://github.com/multimodal-art-projection/YuE) via the [mlx-Yue](https://github.com/vanch007/mlx-Yue) Apple Silicon port, with Claude writing the lyrics through the Claude Code CLI (your subscription — no API key).

## Features

- **Composer** — idea → *Refine prompt* → *Write song* (title, style line, lyrics) → *Generate*. Full score / melody / direct modes, fast-draft toggle, seeds, lyrics find & replace.
- **Libraries › Categories › Songs** with playlists (drag to reorder, sequential playback).
- **Radio** — describe a library, refine it into a station brief, turn on radio: Claude keeps writing new songs that fit, YuE2 renders them one after another, and each is auto-filed into a matching category (created on demand).
- **Song player** — timeline scrubber, transport, lyrics; *Edit* reopens the exact generation details (saved as `studio.json` with every song) to tweak and *Regenerate* in place.
- Export to M4A, view the ABC score, reveal in Finder.

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

Builds a release binary, wraps it as `YuE2 Studio.app`, ad-hoc signs it, and installs it to `~/Applications`.

Songs and library metadata live in `~/Music/YuE2 Studio/` (changeable in Settings).

## License note

YuE2's model weights are licensed **CC BY-NC 4.0** (non-commercial). This app's code is MIT; what you generate is subject to the model license.
