# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
