# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Debug mode toggle** in the Tools submenu (🐞). Default playback uses a quieter mpv log (`--msg-level=all=info,ipc=warn,ffmpeg=warn`) and truncates the log on stop, so long-running sessions don't bloat `$TMPDIR`. Toggling debug ON flips mpv to verbose (`--msg-level=all=v`) and preserves the log across stop/play cycles for diagnostics. State persists in `$MENUTUBE_CONFIG_DIR/debug` and takes effect on the next track.
- **Update to latest release** menu action for copied-plugin installs: downloads the release asset from `MENUTUBE_RELEASE_ASSET_URL` via `curl` with timeout/retry, validates shebang + plugin metadata, and atomically replaces the plugin file. Refuses to run when the plugin path is inside a git checkout (developers should use git).
- Live version label in the Tools footer derived from the local git tag (`git describe --tags HEAD`), with a fallback to the hard-coded `PLUGIN_VERSION` when not in a checkout.
- "Open project page" footer link pointing at `MENUTUBE_REPO_URL`.
- `scripts/auto-release.sh` and a matching `release.yml` workflow that auto-tags and creates a GitHub Release on push to main, based on conventional commit prefixes since the last `v*` tag. Replaces the prior release-please scaffold.
- `MENUTUBE_REPO_DIR`, `MENUTUBE_REPO_URL`, and `MENUTUBE_RELEASE_ASSET_URL` env vars (declared as `xbar.var` entries).
- Defensive tilde expansion on `MENUTUBE_CONFIG_DIR` and `MENUTUBE_REPO_DIR` so xbar.var defaults with a literal `~` resolve correctly when SwiftBar injects them.
- `scripts/check.sh` now validates xbar.var declarations, runs an auto-release dry-run, and guards against the literal-tilde regression.

### Changed

- README install instructions now point at the latest release asset (`curl ... releases/latest/download/menutube.5s.sh`) for both SwiftBar and xbar. Git clone is documented as the **Development Install** path only.

### Removed

- `release-please-config.json` and `.release-please-manifest.json` — release-please is replaced by the auto-release script.

### Fixed

- Library appearing empty in SwiftBar after the xbar.var injection used a literal `~/` path (now expanded explicitly).

## [0.2.0](https://github.com/flamerged/menutube/compare/v0.1.0...v0.2.0) (2026-05-14)


### Features

* initial menutube plugin ([ae15f5e](https://github.com/flamerged/menutube/commit/ae15f5ee3bb562ea6744ca92422f901a274b7473))

## [0.1.0] - 2026-05-14

### Added

- Background YouTube audio playback via mpv (`--no-video`) with macOS `MPNowPlayingInfoCenter` integration so F7/F8/F9 and Bluetooth headphone play-pause buttons work.
- JSON-backed library at `~/.config/menutube/library.json` with three demo 24/7 streams (lofi, jazz, focus techno) seeded on first run.
- Add Video flow: AppleScript dialog pre-fills the title field with the result of `yt-dlp --print "%(title)s" --skip-download`.
- Repeat-on-end toggle, persisted to `~/.config/menutube/repeat` and live-applied to the current track via mpv IPC.
- One-click `brew upgrade yt-dlp` action with macOS notification on completion.
- Refetch-all-titles action.
- Anti-403 wiring for YouTube live HLS streams: `--extractor-args youtube:player_client=android,web` + a Safari User-Agent override (`MENUTUBE_PLAYER_CLIENT`, `MENUTUBE_USER_AGENT` env-tunable).
- Health-check menu fallback if `mpv`, `yt-dlp`, or `jq` are missing.

[0.1.0]: https://github.com/flamerged/menutube/releases/tag/v0.1.0
