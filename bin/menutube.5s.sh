#!/bin/zsh
# <xbar.title>menutube</xbar.title>
# <xbar.version>v0.2.0</xbar.version> # x-release-please-version
# <xbar.author>flamerged</xbar.author>
# <xbar.author.github>flamerged</xbar.author.github>
# <xbar.desc>Background YouTube audio player for the menu bar — mpv + yt-dlp, with macOS media-key support.</xbar.desc>
# <xbar.dependencies>zsh, mpv, yt-dlp, jq, nc</xbar.dependencies>
# <xbar.abouturl>https://github.com/flamerged/menutube</xbar.abouturl>
# <xbar.var>string(MENUTUBE_CONFIG_DIR="~/.config/menutube"): Library / preferences directory</xbar.var>
# <xbar.var>string(MENUTUBE_REPO_DIR=""): Optional menutube git checkout for source metadata</xbar.var>
# <xbar.var>string(MENUTUBE_REPO_URL="https://github.com/flamerged/menutube"): menutube repository URL</xbar.var>
# <xbar.var>string(MENUTUBE_RELEASE_ASSET_URL="https://github.com/flamerged/menutube/releases/latest/download/menutube.5s.sh"): Latest release asset URL for copied-plugin updates</xbar.var>
# <xbar.var>string(MENUTUBE_MPV=""): Override path to mpv binary (auto-detected)</xbar.var>
# <xbar.var>string(MENUTUBE_YTDLP=""): Override path to yt-dlp binary (auto-detected)</xbar.var>
# <xbar.var>string(MENUTUBE_USER_AGENT="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"): User-Agent for HLS segment fetches</xbar.var>
# <xbar.var>string(MENUTUBE_PLAYER_CLIENT="android,web"): yt-dlp extractor-args player_client list (anti-403 for YouTube live HLS)</xbar.var>
# <swiftbar.title>menutube</swiftbar.title>
# <swiftbar.version>v0.2.0</swiftbar.version> # x-release-please-version
# <swiftbar.author>flamerged</swiftbar.author>
# <swiftbar.desc>Background YouTube audio player for the menu bar — mpv + yt-dlp, with macOS media-key support.</swiftbar.desc>
# <swiftbar.refresh>5s</swiftbar.refresh>
#
# menutube — SwiftBar/xbar plugin that plays YouTube audio in the background.
#
# Playback engine: mpv with --no-video. On macOS, mpv auto-registers with
# MPNowPlayingInfoCenter / MPRemoteCommandCenter, so the F7/F8/F9 media keys
# and Bluetooth headphone play-pause buttons work without a native app.
#
# Control: a single mpv process per session, driven over its Unix-socket IPC.
# Library entries dispatch by INDEX so SwiftBar's "<text> | <attrs>" line
# parser never sees raw YouTube URLs (which contain `?` `&` `=` and would
# break parsing).

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export LC_ALL=en_US.UTF-8

PLUGIN_VERSION="0.2.0" # x-release-please-version
# Resolve symlinks so the plugin can find its own git repo even when
# SwiftBar invokes it via ~/SwiftBarPlugins/menutube.5s.sh -> .../bin/...
PLUGIN_PATH="${0:A}"
PLUGIN_DIR="${PLUGIN_PATH:h}"
SCRIPT="$0"

# ============================================================
# Paths (env-overridable)
# ============================================================

: "${MENUTUBE_CONFIG_DIR:=$HOME/.config/menutube}"
: "${MENUTUBE_REPO_DIR:=}"
: "${MENUTUBE_REPO_URL:=https://github.com/flamerged/menutube}"
: "${MENUTUBE_RELEASE_ASSET_URL:=https://github.com/flamerged/menutube/releases/latest/download/menutube.5s.sh}"
# Expand leading ~ in case SwiftBar passes the xbar.var default literally.
# Without this the plugin would read library.json from cwd, get nothing,
# and render an empty library.
MENUTUBE_CONFIG_DIR="${MENUTUBE_CONFIG_DIR/#\~/$HOME}"
MENUTUBE_REPO_DIR="${MENUTUBE_REPO_DIR/#\~/$HOME}"

LIBRARY="$MENUTUBE_CONFIG_DIR/library.json"
REPEAT_FILE="$MENUTUBE_CONFIG_DIR/repeat"      # "yes" | "no"
SOCKET="${TMPDIR:-/tmp}/menutube-mpv.sock"
SOCKET="${SOCKET%/}"                            # strip trailing slash on $TMPDIR
CURRENT_FILE="${TMPDIR:-/tmp}/menutube.current"
LOG="${TMPDIR:-/tmp}/menutube-mpv.log"

mkdir -p "$MENUTUBE_CONFIG_DIR"

# ============================================================
# Resolve binaries (env override → preferred path → PATH lookup)
# ============================================================

resolve_bin() {
  local name="$1" pref="$2"
  [[ -n "${(P)3:-}" ]] && [[ -x "${(P)3}" ]] && { print -- "${(P)3}"; return; }
  [[ -x "$pref" ]] && { print -- "$pref"; return; }
  command -v "$name" 2>/dev/null
}

MPV=$(resolve_bin mpv /opt/homebrew/bin/mpv MENUTUBE_MPV)
# Use brew-prefix symlink for yt-dlp, not /opt/homebrew/bin/yt-dlp — the latter
# is a Python shim that loads whatever yt_dlp module the system Python finds,
# which can be a stale pip install. The prefix path always uses brew's
# isolated Python env with the current Cellar version of yt_dlp.
YTDLP=$(resolve_bin yt-dlp /opt/homebrew/opt/yt-dlp/bin/yt-dlp MENUTUBE_YTDLP)
JQ=$(command -v jq)
NC=$(command -v nc)

# ============================================================
# Defaults you can override via xbar/SwiftBar env panel
# ============================================================

: "${MENUTUBE_USER_AGENT:=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15}"
: "${MENUTUBE_PLAYER_CLIENT:=android,web}"

# ============================================================
# First-run seed
# ============================================================

if [[ ! -f "$LIBRARY" ]]; then
  cat > "$LIBRARY" <<'JSON'
[
  {"title": "lofi hip hop radio – beats to relax/study to", "url": "https://www.youtube.com/watch?v=jfKfPfyJRdk"},
  {"title": "Relaxing Jazz Piano Radio - Slow Jazz Music",  "url": "https://www.youtube.com/watch?v=Dx5qFachd3A"},
  {"title": "Mental Clarity & Logic — High-Energy Techno",  "url": "https://www.youtube.com/watch?v=1rOsggfPJZM"}
]
JSON
fi

# ============================================================
# IPC + state helpers
# ============================================================

mpv_pid()     { pgrep -f "mpv .*--input-ipc-server=$SOCKET" | head -1; }
mpv_running() { [[ -S "$SOCKET" ]] && [[ -n "$(mpv_pid)" ]]; }

mpv_send() { printf '%s\n' "$1" | "$NC" -U "$SOCKET" 2>/dev/null; }

mpv_get() {
  local resp
  resp=$(mpv_send "{\"command\":[\"get_property\",\"$1\"]}")
  printf '%s' "$resp" | /usr/bin/sed -n 's/.*"data":\([^,}]*\).*/\1/p' | tr -d '"'
}

repeat_on() { [[ -f "$REPEAT_FILE" ]] && [[ "$(cat "$REPEAT_FILE" 2>/dev/null)" == "yes" ]]; }

# ============================================================
# yt-dlp helpers
# ============================================================

yt_title() {
  # Title without format resolution — avoids "Requested format is not
  # available" errors on some videos. --extractor-args matches the playback
  # path so adds and plays succeed under the same anti-scraping rules.
  "$YTDLP" --no-warnings --no-playlist --skip-download \
           --extractor-args "youtube:player_client=$MENUTUBE_PLAYER_CLIENT" \
           --print "%(title)s" "$1" 2>/dev/null | head -1
}

yt_version()        { "$YTDLP" --version 2>/dev/null | head -1; }
yt_version_latest() {
  command -v brew >/dev/null 2>&1 || return 0
  brew info --json=v2 yt-dlp 2>/dev/null \
    | "$JQ" -r '.formulae[0].versions.stable // empty'
}
# Normalise so 2026.03.17 == 2026.3.17 (yt-dlp keeps leading zeros; brew strips them).
yt_ver_norm() { printf '%s' "$1" | /usr/bin/sed 's/\.0*\([1-9]\)/.\1/g'; }

notify() {
  /usr/bin/osascript -e "display notification \"${2//\"/\\\"}\" with title \"${1//\"/\\\"}\"" 2>/dev/null
}

# ============================================================
# Plugin self-update / version-from-git-tag (mirrors agent-watch)
# ============================================================

plugin_repo_root() {
  command -v git >/dev/null 2>&1 || return
  local candidate="$MENUTUBE_REPO_DIR"
  if [[ -n "$candidate" ]] && git -C "$candidate" rev-parse --show-toplevel >/dev/null 2>&1; then
    git -C "$candidate" rev-parse --show-toplevel 2>/dev/null
    return
  fi
  candidate="${PLUGIN_DIR:h}"
  if git -C "$candidate" rev-parse --show-toplevel >/dev/null 2>&1; then
    git -C "$candidate" rev-parse --show-toplevel 2>/dev/null
  fi
}

plugin_git_summary() {
  local root="$1" branch sha upstream counts ahead behind dirty state
  command -v git >/dev/null 2>&1 || return
  branch="$(git -C "$root" branch --show-current 2>/dev/null)"
  sha="$(git -C "$root" rev-parse --short HEAD 2>/dev/null)"
  upstream="$(git -C "$root" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"
  dirty="$(git -C "$root" status --porcelain 2>/dev/null)"
  state=""
  if [[ -n "$upstream" ]]; then
    counts="$(git -C "$root" rev-list --left-right --count HEAD..."$upstream" 2>/dev/null)"
    ahead="${counts%%[[:space:]]*}"
    behind="${counts##*[[:space:]]}"
    [[ -n "$ahead" && "$ahead" != "0" ]] && state="${state}, ${ahead} ahead"
    [[ -n "$behind" && "$behind" != "0" ]] && state="${state}, ${behind} behind"
  fi
  [[ -n "$dirty" ]] && state="${state}, dirty"
  printf '%s' "${branch:-detached} ${sha:-unknown}${state}"
}

# Prefer the live git tag when installed from a checkout — that way the
# plugin file's hard-coded PLUGIN_VERSION can stay one version behind the
# tag without anyone needing to bump it manually.
plugin_version_label() {
  local root="${1:-}" exact desc
  if [[ -n "$root" ]] && command -v git >/dev/null 2>&1; then
    exact="$(git -C "$root" describe --tags --exact-match --match 'v[0-9]*' HEAD 2>/dev/null)"
    if [[ -n "$exact" ]]; then
      printf '%s' "$exact"
      return
    fi
    desc="$(git -C "$root" describe --tags --match 'v[0-9]*' --long --always HEAD 2>/dev/null)"
    if [[ "$desc" == v* ]]; then
      printf '%s' "$desc"
      return
    fi
  fi
  printf 'v%s' "$PLUGIN_VERSION"
}

# ============================================================
# Actions
# ============================================================

action_play() {
  local idx="$1" url title loop_mode
  url=$("$JQ"   -r ".[$idx].url"   "$LIBRARY")
  title=$("$JQ" -r ".[$idx].title" "$LIBRARY")
  [[ -z "$url" || "$url" == "null" ]] && return 1
  if mpv_running; then
    pkill -f "mpv .*--input-ipc-server=$SOCKET" 2>/dev/null
    sleep 0.3
  fi
  rm -f "$SOCKET"
  loop_mode="no"
  repeat_on && loop_mode="inf"
  nohup "$MPV" \
    --no-video \
    --no-input-terminal \
    --force-window=no \
    --idle=no \
    --input-media-keys=yes \
    --input-ipc-server="$SOCKET" \
    --force-media-title="$title" \
    --ytdl-format="bestaudio/best" \
    --script-opts=ytdl_hook-ytdl_path="$YTDLP" \
    --ytdl-raw-options-append=extractor-args="youtube:player_client=$MENUTUBE_PLAYER_CLIENT" \
    --user-agent="$MENUTUBE_USER_AGENT" \
    --loop-file="$loop_mode" \
    --cache=yes \
    --cache-secs=20 \
    --demuxer-max-bytes=128MiB \
    --log-file="$LOG" \
    --msg-level=all=info \
    "$url" \
    >/dev/null 2>&1 &
  disown
  printf '%s' "$title" > "$CURRENT_FILE"
}

action_toggle() { mpv_running && mpv_send '{"command":["cycle","pause"]}' >/dev/null; }
action_stop()   { pkill -f "mpv .*--input-ipc-server=$SOCKET" 2>/dev/null; rm -f "$CURRENT_FILE" "$SOCKET"; }
action_seek()   { mpv_running && mpv_send "{\"command\":[\"seek\",$1,\"relative\"]}" >/dev/null; }
action_volume() { mpv_running && mpv_send "{\"command\":[\"set_property\",\"volume\",$1]}" >/dev/null; }

action_repeat() {
  if repeat_on; then
    printf 'no' > "$REPEAT_FILE"
    mpv_running && mpv_send '{"command":["set_property","loop-file","no"]}' >/dev/null
  else
    printf 'yes' > "$REPEAT_FILE"
    mpv_running && mpv_send '{"command":["set_property","loop-file","inf"]}' >/dev/null
  fi
}

action_add() {
  local url fetched title
  url=$(osascript <<'OSA' 2>/dev/null
on run
  try
    set d to display dialog "YouTube URL:" default answer "" with title "Add YouTube Video" buttons {"Cancel","Next"} default button "Next"
    if button returned of d is "Cancel" then return ""
    return text returned of d
  on error
    return ""
  end try
end run
OSA
)
  [[ -z "$url" ]] && return
  url="${url#"${url%%[![:space:]]*}"}"
  url="${url%"${url##*[![:space:]]}"}"
  fetched=$(yt_title "$url")
  [[ -z "$fetched" ]] && fetched="$url"
  title=$(osascript <<OSA 2>/dev/null
on run
  try
    set d to display dialog "Title (edit if needed):" default answer "${fetched//\"/\\\"}" with title "Add YouTube Video" buttons {"Cancel","Add"} default button "Add"
    if button returned of d is "Cancel" then return ""
    return text returned of d
  on error
    return ""
  end try
end run
OSA
)
  [[ -z "$title" ]] && title="$fetched"
  "$JQ" --arg url "$url" --arg title "$title" \
        '. += [{"title": $title, "url": $url}]' \
        "$LIBRARY" > "$LIBRARY.tmp" && command mv -f "$LIBRARY.tmp" "$LIBRARY"
}

action_remove() {
  "$JQ" --argjson i "$1" 'del(.[$i])' "$LIBRARY" > "$LIBRARY.tmp" \
    && command mv -f "$LIBRARY.tmp" "$LIBRARY"
}

action_edit_library() { open -a "TextEdit" "$LIBRARY"; }
action_open_log()     { open -a "Console" "$LOG"; }

action_refetch_titles() {
  local count fixed i url newtitle
  count=$("$JQ" 'length' "$LIBRARY")
  fixed=0
  notify "menutube" "Refetching $count titles…"
  i=0
  while [[ $i -lt $count ]]; do
    url=$("$JQ" -r ".[$i].url" "$LIBRARY")
    newtitle=$(yt_title "$url")
    if [[ -n "$newtitle" ]]; then
      "$JQ" --argjson i $i --arg t "$newtitle" '.[$i].title = $t' \
            "$LIBRARY" > "$LIBRARY.tmp" && command mv -f "$LIBRARY.tmp" "$LIBRARY"
      fixed=$((fixed+1))
    fi
    i=$((i+1))
  done
  notify "menutube" "Refetched $fixed / $count titles."
}

action_update_release() {
  # Refuse if the running plugin file lives inside its own git checkout —
  # we don't want to clobber a developer's working tree from the menu.
  local repo_root
  repo_root="$(plugin_repo_root)"
  if [[ -n "$repo_root" && "$PLUGIN_PATH" == "$repo_root"/* ]]; then
    print "Plugin appears to be running from a git checkout: $repo_root"
    print "Use git commands in the checkout for development updates."
    return 1
  fi

  local curl_bin
  curl_bin="$(command -v curl)"
  if [[ -z "$curl_bin" ]]; then
    print "curl is required to update from the latest release."
    return 1
  fi
  if [[ ! -w "$PLUGIN_PATH" || ! -w "$PLUGIN_DIR" ]]; then
    print "Plugin file or directory is not writable: $PLUGIN_PATH"
    return 1
  fi

  local tmp first_line content
  tmp="${PLUGIN_DIR}/.menutube.5s.sh.$$"
  rm -f "$tmp"

  print "Downloading latest menutube release asset..."
  if ! "$curl_bin" -fsSL \
    --connect-timeout 5 \
    --max-time 30 \
    --retry 2 \
    --retry-delay 1 \
    "$MENUTUBE_RELEASE_ASSET_URL" -o "$tmp"; then
    rm -f "$tmp"
    print "Download failed: $MENUTUBE_RELEASE_ASSET_URL"
    return 1
  fi

  IFS= read -r first_line < "$tmp" || first_line=""
  content="$(< "$tmp")"
  if [[ "$first_line" != "#!/bin/zsh" \
     || "$content" != *"<xbar.title>menutube</xbar.title>"* \
     || "$content" != *"PLUGIN_VERSION=\""* ]]; then
    rm -f "$tmp"
    print "Downloaded file did not look like a menutube plugin."
    return 1
  fi

  chmod +x "$tmp" || {
    rm -f "$tmp"
    print "Could not mark downloaded plugin executable."
    return 1
  }
  mv "$tmp" "$PLUGIN_PATH" || {
    rm -f "$tmp"
    print "Could not replace plugin file: $PLUGIN_PATH"
    return 1
  }
  print "Updated menutube from the latest release."
}

action_update_ytdlp() {
  command -v brew >/dev/null 2>&1 || { notify "menutube" "Homebrew not found — install yt-dlp manually."; return 1; }
  notify "menutube" "Updating yt-dlp via Homebrew…"
  local before after
  before=$(yt_version)
  if brew upgrade yt-dlp >/dev/null 2>&1; then
    after=$(yt_version)
    if [[ "$before" == "$after" ]]; then
      notify "menutube" "yt-dlp already at $after."
    else
      notify "menutube" "Updated yt-dlp $before → $after"
    fi
  else
    notify "menutube" "Update failed — try: brew upgrade yt-dlp"
  fi
}

# ============================================================
# Dispatch
# ============================================================

case "${1:-}" in
  play)     action_play   "$2";    exit 0 ;;
  toggle)   action_toggle;         exit 0 ;;
  stop)     action_stop;           exit 0 ;;
  seek)     action_seek   "$2";    exit 0 ;;
  volume)   action_volume "$2";    exit 0 ;;
  repeat)   action_repeat;         exit 0 ;;
  add)      action_add;            exit 0 ;;
  remove)   action_remove "$2";    exit 0 ;;
  edit)     action_edit_library;   exit 0 ;;
  log)      action_open_log;       exit 0 ;;
  refetch)  action_refetch_titles; exit 0 ;;
  update)   action_update_ytdlp;   exit 0 ;;
  update-release) action_update_release; exit 0 ;;
esac

# ============================================================
# Health checks
# ============================================================

if [[ -z "$MPV" ]]; then
  echo "♫ menutube ⚠️"
  echo "---"
  echo "mpv not found. Install with: brew install mpv | color=#cc6633"
  exit 0
fi
if [[ -z "$YTDLP" ]]; then
  echo "♫ menutube ⚠️"
  echo "---"
  echo "yt-dlp not found. Install with: brew install yt-dlp | color=#cc6633"
  exit 0
fi
if [[ -z "$JQ" ]]; then
  echo "♫ menutube ⚠️"
  echo "---"
  echo "jq not found. Install with: brew install jq | color=#cc6633"
  exit 0
fi

# ============================================================
# Render
# ============================================================

running=false; paused=false; current=""; pos=""; dur=""; vol=""
if mpv_running; then
  running=true
  current=$(cat "$CURRENT_FILE" 2>/dev/null)
  [[ "$(mpv_get pause)" == "true" ]] && paused=true
  pos=$(mpv_get time-pos)
  dur=$(mpv_get duration)
  vol=$(mpv_get volume)
fi

if $running; then
  $paused && echo "⏸︎ YT" || echo "♪ YT"
else
  echo "♫ YT"
fi
echo "---"

if $running; then
  disp="$current"
  # SwiftBar splits each line on the first ASCII | between text and attrs.
  # Fullwidth ｜ (U+FF5C) renders identically but doesn't break the parser.
  disp="${disp//|/｜}"
  [[ ${#disp} -gt 50 ]] && disp="${disp:0:47}…"
  echo "$disp | color=#cccccc"
  if [[ -n "$pos" && -n "$dur" && "$pos" != "null" && "$dur" != "null" ]]; then
    pos_int=${pos%.*}; dur_int=${dur%.*}
    [[ -z "$pos_int" || "$pos_int" == "null" ]] && pos_int=0
    [[ -z "$dur_int" || "$dur_int" == "null" ]] && dur_int=0
    vol_int="${vol%.*}"; [[ -z "$vol_int" || "$vol_int" == "null" ]] && vol_int=0
    printf "%dm%02ds / %dm%02ds  vol %s%% | color=#888888 size=11\n" \
      $((pos_int/60)) $((pos_int%60)) $((dur_int/60)) $((dur_int%60)) "$vol_int"
  fi
  echo "---"
  if $paused; then
    echo "▶ Resume | bash=$SCRIPT param1=toggle terminal=false refresh=true"
  else
    echo "⏸ Pause | bash=$SCRIPT param1=toggle terminal=false refresh=true"
  fi
  echo "⏹ Stop | bash=$SCRIPT param1=stop terminal=false refresh=true"
  echo "⏪ -10s | bash=$SCRIPT param1=seek param2=-10 terminal=false refresh=true"
  echo "⏩ +30s | bash=$SCRIPT param1=seek param2=+30 terminal=false refresh=true"
  if repeat_on; then
    echo "🔁 Repeat: ON — click to turn off | bash=$SCRIPT param1=repeat terminal=false refresh=true"
  else
    echo "🔁 Repeat: OFF — click to loop track | bash=$SCRIPT param1=repeat terminal=false refresh=true"
  fi
  echo "Volume"
  echo "--🔈 25% | bash=$SCRIPT param1=volume param2=25 terminal=false refresh=true"
  echo "--🔉 50% | bash=$SCRIPT param1=volume param2=50 terminal=false refresh=true"
  echo "--🔊 75% | bash=$SCRIPT param1=volume param2=75 terminal=false refresh=true"
  echo "--🔊 100% | bash=$SCRIPT param1=volume param2=100 terminal=false refresh=true"
  echo "---"
fi

count=$("$JQ" 'length' "$LIBRARY")
echo "📚 Library ($count)"
if [[ "$count" -eq 0 ]]; then
  echo "--(empty — use ➕ Add below)"
else
  "$JQ" -r 'to_entries[] | "\(.key)\t\(.value.title)"' "$LIBRARY" \
  | while IFS=$'\t' read -r idx title; do
    disp="$title"
    disp="${disp//|/｜}"
    [[ ${#disp} -gt 50 ]] && disp="${disp:0:47}…"
    prefix=""
    if $running && [[ "$title" == "$current" ]]; then
      $paused && prefix="⏸ " || prefix="▶ "
    fi
    echo "--${prefix}${disp} | bash=$SCRIPT param1=play param2=$idx terminal=false refresh=true"
    echo "----🗑 Remove | bash=$SCRIPT param1=remove param2=$idx terminal=false refresh=true"
  done
fi

echo "---"
echo "➕ Add video… | bash=$SCRIPT param1=add terminal=false refresh=true"
echo "🛠 Edit library file | bash=$SCRIPT param1=edit terminal=false refresh=true"
echo "---"

yt_ver=$(yt_version)
yt_latest=$(yt_version_latest)
yt_outdated=false
if [[ -n "$yt_ver" && -n "$yt_latest" && "$(yt_ver_norm "$yt_ver")" != "$(yt_ver_norm "$yt_latest")" ]]; then
  yt_outdated=true
fi
if $yt_outdated; then
  echo "🔧 Tools (yt-dlp $yt_ver → $yt_latest available) | color=#cc6633"
  echo "--⬆️  Update yt-dlp now ($yt_ver → $yt_latest) | bash=$SCRIPT param1=update terminal=false refresh=true"
else
  echo "🔧 Tools (yt-dlp $yt_ver — up to date)"
  echo "--⬆️  Force update yt-dlp (currently $yt_ver) | bash=$SCRIPT param1=update terminal=false refresh=true"
fi
echo "--🔁 Refetch all library titles | bash=$SCRIPT param1=refetch terminal=false refresh=true"
if repeat_on; then
  echo "--🔁 Repeat mode: ON (next plays will loop) | bash=$SCRIPT param1=repeat terminal=false refresh=true"
else
  echo "--🔁 Repeat mode: OFF (next plays will not loop) | bash=$SCRIPT param1=repeat terminal=false refresh=true"
fi
echo "--📝 Open mpv log | bash=$SCRIPT param1=log terminal=false"
echo "--🔄 Refresh menu | refresh=true"
echo "-----"
plugin_root="$(plugin_repo_root)"
version_label="$(plugin_version_label "$plugin_root")"
echo "--Version: ${version_label} | font=Menlo color=#888888"
echo "--Plugin: ${PLUGIN_PATH/#$HOME/~} | font=Menlo size=10 color=#888888"
if [[ -n "$plugin_root" ]]; then
  git_summary="$(plugin_git_summary "$plugin_root")"
  echo "--Repo: ${plugin_root/#$HOME/~} | font=Menlo size=10 color=#888888"
  echo "--Git: ${git_summary:-unknown} | font=Menlo size=10 color=#888888"
  echo "----Use git commands for development updates | color=gray size=10"
else
  echo "--⬆️ Update to latest release | bash=$SCRIPT param1=update-release terminal=true refresh=true"
fi
echo "--🌐 Open project page | href=$MENUTUBE_REPO_URL"
