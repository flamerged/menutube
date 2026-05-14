# Security Policy

## Reporting a vulnerability

Please report security issues privately by opening a GitHub security advisory on this repository, or by emailing the maintainer. Do not disclose vulnerabilities in public issues until a fix is available.

## Scope

menutube is a local-only SwiftBar/xbar plugin. It:

- Reads from `~/.config/menutube/` (your library and preferences).
- Spawns `mpv` and `yt-dlp` subprocesses.
- Talks to mpv over a local Unix-domain socket in `$TMPDIR`.
- Calls `osascript` for AppleScript dialogs and macOS notifications.
- Optionally invokes `brew upgrade yt-dlp` when you click the menu action.

It does not transmit telemetry, open network listeners, or persist data outside `$HOME/.config/menutube` and `$TMPDIR`.

## Hardening notes

- Library entries with URLs come from user input (the Add dialog or hand-edits of `library.json`). The plugin passes URLs to `yt-dlp` as positional arguments without shell evaluation, but anyone who can write to the library JSON can cause arbitrary `yt-dlp` URLs to be fetched when you click play.
- The mpv IPC socket is in `$TMPDIR` with default umask. On a single-user macOS install this is acceptable; on a multi-user system you may want to set `MENUTUBE_CONFIG_DIR` to a private location and consider that other users with shell access could send IPC commands to the socket while it exists.
