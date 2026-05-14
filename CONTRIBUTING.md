# Contributing to menutube

Thanks for taking the time to contribute.

## Development setup

```sh
git clone https://github.com/flamerged/menutube.git
cd menutube
brew install mpv yt-dlp jq        # runtime deps
./scripts/install-swiftbar.sh     # symlinks bin/menutube.5s.sh into ~/SwiftBarPlugins
./scripts/check.sh                # syntax check + dry render
```

The plugin is a single zsh file at `bin/menutube.5s.sh`. Edits become live within 5 seconds (SwiftBar's refresh interval) or immediately when you click "🔄 Refresh menu".

## Testing changes locally

You can invoke any menu action from the CLI without going through SwiftBar:

```sh
./bin/menutube.5s.sh                    # render the menu
./bin/menutube.5s.sh play 0             # play library index 0
./bin/menutube.5s.sh toggle             # pause/resume
./bin/menutube.5s.sh stop               # stop
./bin/menutube.5s.sh repeat             # toggle repeat
./bin/menutube.5s.sh refetch            # refetch all library titles
./bin/menutube.5s.sh update             # brew upgrade yt-dlp
```

mpv's log lives at `$TMPDIR/menutube-mpv.log` — tail it while testing playback.

## Style

- Plain zsh, no external runtime dependencies beyond what's in `README.md` → Requirements.
- Use absolute paths for system binaries when zsh's PATH resolution has bitten us before (`/usr/bin/jq`, `/usr/bin/nc`, etc.) — see existing code for the pattern.
- Library entries must dispatch by index, not URL, to keep SwiftBar's `|` parser happy. See the "How it works" section of the README for the full list of subtle parsing rules.
- Run `./scripts/check.sh` before pushing.

## Pull requests

- One concern per PR.
- Update `CHANGELOG.md` under the `Unreleased` section.
- If you're adding a new environment variable, declare it in both the `<xbar.var>` header block (so it appears in SwiftBar's variable panel) and the README configuration table.

## Releases

This repo uses [release-please](https://github.com/googleapis/release-please). Versioning is derived from conventional commit messages on `main`. The plugin file's version markers (`# x-release-please-version`) are kept in sync automatically.
