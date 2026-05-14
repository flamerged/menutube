#!/bin/zsh
set -euo pipefail

TARGET_DIR="${1:-$HOME/SwiftBarPlugins}"
TARGET="$TARGET_DIR/menutube.5s.sh"
RELEASE_ASSET_URL="${MENUTUBE_RELEASE_ASSET_URL:-https://github.com/flamerged/menutube/releases/latest/download/menutube.5s.sh}"

if [[ "$RELEASE_ASSET_URL" != https://* ]]; then
  print -u2 "refusing non-HTTPS release asset URL: $RELEASE_ASSET_URL"
  exit 1
fi

mkdir -p "$TARGET_DIR"
tmp="$TARGET_DIR/.menutube.5s.sh.$$"
rm -f "$tmp"
trap 'rm -f "$tmp"' EXIT

curl -fsSL \
  --connect-timeout 5 \
  --max-time 30 \
  --retry 2 \
  --retry-delay 1 \
  "$RELEASE_ASSET_URL" -o "$tmp"

IFS= read -r first_line < "$tmp" || first_line=""
content="$(< "$tmp")"
if [[ "$first_line" != "#!/bin/zsh" || "$content" != *"<xbar.title>menutube</xbar.title>"* || "$content" != *"PLUGIN_VERSION=\""* ]]; then
  print -u2 "Downloaded file did not look like a menutube plugin."
  exit 1
fi

chmod +x "$tmp"
rm -f "$TARGET"
mv "$tmp" "$TARGET"
trap - EXIT

print "installed $TARGET"
