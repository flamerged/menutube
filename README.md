# menutube

menutube is a SwiftBar/xbar-compatible menu bar plugin that plays YouTube audio in the background, with macOS media-key support, a clickable library, repeat-on-end, and one-click `yt-dlp` updates from the menu.

Built on `mpv` + `yt-dlp`. The plugin is a thin UI; mpv handles playback and auto-registers with `MPNowPlayingInfoCenter` so the F7/F8/F9 keys and Bluetooth headphone play-pause buttons work without any native app.

## Features

- Plays any URL `yt-dlp` can resolve — YouTube videos, YouTube live streams, Twitch, SoundCloud, direct media URLs.
- Audio-only (`mpv --no-video`), runs in the background.
- Macros media keys + Bluetooth headphone play/pause work out of the box (mpv registers with `MPRemoteCommandCenter`).
- Library stored as a plain JSON file you can hand-edit (`~/.config/menutube/library.json`).
- Add via menu: paste a URL → title auto-fetched via `yt-dlp` and pre-filled in a confirmation dialog.
- Repeat-on-end toggle: persists across plays, also flips the loop state on the currently-playing track via mpv IPC.
- Built-in `yt-dlp` version display and one-click update via Homebrew.
- Refetch-all-titles action for when YouTube changes something.
- No private data leaves your machine; the plugin only talks to local mpv IPC and (when invoked) `brew`, `osascript`, and the public YouTube/Homebrew endpoints `yt-dlp` and `brew` reach out to.

## Demo

When you first install, the library is seeded with three known-good 24/7 audio streams (lofi, jazz piano, focus techno) so you can verify everything works in one click. Remove them via the menu or edit the library JSON.

## Install

### SwiftBar

1. Install [SwiftBar](https://github.com/swiftbar/SwiftBar).
2. Install runtime dependencies:
   ```sh
   brew install mpv yt-dlp jq
   ```
3. Clone this repo and symlink the plugin:
   ```sh
   git clone https://github.com/flamerged/menutube.git
   cd menutube
   ./scripts/install-swiftbar.sh "$HOME/SwiftBarPlugins"
   ```

SwiftBar picks up `menutube.5s.sh` and refreshes every 5 seconds.

### xbar

menutube uses the BitBar/xbar stdout menu format. Install it by copying or symlinking `bin/menutube.5s.sh` into your xbar plugin folder.

### Linux

The plugin uses macOS-specific bits: `osascript` for the "Add video" dialog, `open -a` to open the library/log, and mpv's `MPRemoteCommandCenter` integration for media keys. Linux menu bar runners like Argos can render the menu, but the macOS integrations won't work.

## Requirements

- `zsh`
- `mpv` (0.34+ recommended for macOS media-key support)
- `yt-dlp`
- `jq`
- `nc` (system `/usr/bin/nc` is fine — used for Unix-socket IPC to mpv)

macOS ships `zsh`, `nc`, and `osascript`. Install the rest via Homebrew:

```sh
brew install mpv yt-dlp jq
```

## Usage

The menu bar icon is `♫ YT` (idle), `♪ YT` (playing), or `⏸︎ YT` (paused).

- **Click a library entry** → starts playback. Existing playback is replaced.
- **F8 / headphone play-pause** → toggles pause/resume on the active mpv session.
- **➕ Add video…** → AppleScript dialog asks for the URL; the plugin pre-fetches the title via yt-dlp and shows a confirmation dialog you can accept or edit.
- **🛠 Edit library file** → opens `library.json` in TextEdit for bulk cleanup or reordering.
- **🔁 Repeat** → toggles loop-on-end for the current and future plays. Persisted across restarts.
- **🔧 Tools → Update yt-dlp** → runs `brew upgrade yt-dlp` in the background and notifies you when it's done.
- **🔧 Tools → Refetch all titles** → re-resolves every title in the library. Useful after a yt-dlp update or YouTube format change.

## Configuration

menutube works without configuration. These environment variables can tailor it to your setup, declared as SwiftBar `<xbar.var>` entries so they appear in SwiftBar's plugin variable panel:

| Variable | Default | Purpose |
| --- | --- | --- |
| `MENUTUBE_CONFIG_DIR` | `~/.config/menutube` | Library and preferences directory |
| `MENUTUBE_MPV` | auto-detected | Override path to mpv |
| `MENUTUBE_YTDLP` | auto-detected | Override path to yt-dlp |
| `MENUTUBE_USER_AGENT` | Safari 17 desktop UA | User-Agent for HLS segment fetches |
| `MENUTUBE_PLAYER_CLIENT` | `android,web` | yt-dlp `--extractor-args` player_client list (anti-403 for YouTube live HLS) |

The library and preferences live at:

- `$MENUTUBE_CONFIG_DIR/library.json` — JSON array of `{title, url}` objects.
- `$MENUTUBE_CONFIG_DIR/repeat` — file containing `yes` or `no`.

mpv runtime state lives at:

- `$TMPDIR/menutube-mpv.sock` — Unix-socket IPC.
- `$TMPDIR/menutube.current` — title of the currently-playing entry.
- `$TMPDIR/menutube-mpv.log` — mpv log file (informational; openable from the menu).

## How it works (and the bugs you would otherwise hit)

A few non-obvious lessons baked into this plugin, in case you fork it:

1. **mpv `--no-terminal` silences all mpv logging**, even with `--msg-level=all=info`. Use `--no-input-terminal` instead and rely on `--log-file` for diagnostics.
2. **mpv's `ytdl_hook` finds whatever `yt-dlp` is in PATH first.** On many machines this is a stale pip-installed module that predates current YouTube format changes. menutube pins to `/opt/homebrew/opt/yt-dlp/bin/yt-dlp` (the brew-prefix symlink, always current) via `--script-opts=ytdl_hook-ytdl_path`.
3. **YouTube live-stream HLS segments return HTTP 403** when fetched with ffmpeg's default headers, even when yt-dlp's resolved URL is valid. The fix is `--extractor-args=youtube:player_client=android,web` — yt-dlp returns URLs that ffmpeg can fetch unchallenged.
4. **SwiftBar splits each menu line on the first ASCII `|`** between display text and attributes. A title like `Mental Clarity & Logic | High-Energy Techno` breaks the click handler entirely. menutube replaces `|` with the visually-identical fullwidth `｜` (U+FF5C) at render time.
5. **Library entries dispatch by INDEX**, not URL. `bash=… param2=0` is parser-safe; `param2='https://www.youtube.com/watch?v=...'` is not (the `?`/`&` characters confuse SwiftBar's attribute parser).
6. **`yt-dlp -e` performs format resolution** as part of its workflow and can fail with "Requested format is not available" on some videos. Use `--print "%(title)s" --skip-download` to get the title without format resolution.

## Troubleshooting

- **No audio**: check `$TMPDIR/menutube-mpv.log` — look for `HTTP 403` (YouTube anti-scraping; try a `MENUTUBE_PLAYER_CLIENT` value like `ios` or `tv_simply`) or `Requested format is not available` (yt-dlp out of date; click 🔧 Tools → Update yt-dlp).
- **Click does nothing**: titles containing `|` were a bug fixed in v0.1.0. If a title with another special char misbehaves, please open an issue with the offending string.
- **Media keys go to the wrong app**: macOS gives them to the most recently active media app. Pause/resume in the menu once to make mpv the active one.

## Security

menutube only talks to:

- The local mpv process over its Unix socket
- `yt-dlp` as a subprocess, which fetches from YouTube/Twitch/etc.
- `brew` as a subprocess for the optional yt-dlp update action
- `osascript` for the Add Video dialog and notifications

No telemetry. No background network activity beyond `yt-dlp` and `brew` when you trigger them.

See [SECURITY.md](SECURITY.md) for vulnerability reporting.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).
