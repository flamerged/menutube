#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
PLUGIN="$ROOT/bin/menutube.5s.sh"
TARGET_DIR="${1:-$HOME/SwiftBarPlugins}"
TARGET="$TARGET_DIR/menutube.5s.sh"

mkdir -p "$TARGET_DIR"
ln -sf "$PLUGIN" "$TARGET"
chmod +x "$PLUGIN"

print "installed $TARGET"
