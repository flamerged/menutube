#!/bin/zsh
# <xbar.title>menutube</xbar.title>
# <xbar.version>v0.2.0</xbar.version> # x-release-please-version
# <xbar.author>flamerged</xbar.author>
# <xbar.author.github>flamerged</xbar.author.github>
# <xbar.desc>Background YouTube audio player for the menu bar — mpv + yt-dlp, with macOS media-key support.</xbar.desc>
# <xbar.dependencies>zsh, mpv, yt-dlp, jq, nc, curl</xbar.dependencies>
# <xbar.abouturl>https://github.com/flamerged/menutube</xbar.abouturl>
# <xbar.var>string(MENUTUBE_CONFIG_DIR="~/.config/menutube"): Library / preferences directory</xbar.var>
# <xbar.var>string(MENUTUBE_REPO_DIR=""): Optional menutube git checkout for source metadata</xbar.var>
# <xbar.var>string(MENUTUBE_REPO_URL="https://github.com/flamerged/menutube"): menutube repository URL</xbar.var>
# <xbar.var>string(MENUTUBE_RELEASE_ASSET_URL="https://github.com/flamerged/menutube/releases/latest/download/menutube.5s.sh"): Latest release asset URL for copied-plugin updates</xbar.var>
# <xbar.var>string(MENUTUBE_UPDATE_LOG="~/.cache/menutube/update.log"): Update log file path</xbar.var>
# <xbar.var>boolean(MENUTUBE_CHECK_RELEASE_UPDATES=true): Check latest menutube release in the background</xbar.var>
# <xbar.var>string(MENUTUBE_RELEASE_CHECK_TTL_SECONDS="86400"): Seconds between latest-release checks when enabled</xbar.var>
# <xbar.var>string(MENUTUBE_RELEASE_CHECK_CACHE="~/.cache/menutube/release-check.tsv"): Latest-release check cache path</xbar.var>
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
: "${MENUTUBE_UPDATE_LOG:=$HOME/.cache/menutube/update.log}"
: "${MENUTUBE_CHECK_RELEASE_UPDATES:=1}"
: "${MENUTUBE_RELEASE_CHECK_TTL_SECONDS:=86400}"
: "${MENUTUBE_RELEASE_CHECK_CACHE:=$HOME/.cache/menutube/release-check.tsv}"
# Expand leading ~ in case SwiftBar passes the xbar.var default literally.
# Without this the plugin would read library.json from cwd, get nothing,
# and render an empty library.
MENUTUBE_CONFIG_DIR="${MENUTUBE_CONFIG_DIR/#\~/$HOME}"
MENUTUBE_REPO_DIR="${MENUTUBE_REPO_DIR/#\~/$HOME}"
MENUTUBE_UPDATE_LOG="${MENUTUBE_UPDATE_LOG/#\~/$HOME}"
MENUTUBE_RELEASE_CHECK_CACHE="${MENUTUBE_RELEASE_CHECK_CACHE/#\~/$HOME}"

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

truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

cache_mtime() {
  local file="$1"
  [[ -f "$file" ]] || { printf ''; return; }
  if stat -f %m "$file" >/dev/null 2>&1; then
    stat -f %m "$file"
  elif stat -c %Y "$file" >/dev/null 2>&1; then
    stat -c %Y "$file"
  fi
}

release_tag_norm() {
  printf '%s' "${1%%-*}" | /usr/bin/sed 's/^v//'
}

latest_release_tag_from_asset_url() {
  local tag
  tag="$(printf '%s' "$MENUTUBE_RELEASE_ASSET_URL" | /usr/bin/sed -n 's#.*releases/download/\([^/]*\)/.*#\1#p' | head -1)"
  [[ -n "$tag" && "$tag" != "latest" ]] || return 1
  printf '%s' "$tag"
}

github_repo_slug() {
  local slug
  [[ "$MENUTUBE_REPO_URL" == https://github.com/* ]] || return 1
  slug="${MENUTUBE_REPO_URL#https://github.com/}"
  slug="${slug%%\?*}"
  slug="${slug%%#*}"
  slug="${slug%/}"
  slug="${slug%.git}"
  [[ "$slug" == */* && "$slug" != */*/* ]] || return 1
  printf '%s' "$slug"
}

latest_release_tag() {
  local curl_bin repo tag
  curl_bin="$(command -v curl)"
  [[ -n "$curl_bin" ]] || return 1
  if repo="$(github_repo_slug)" && [[ -n "$repo" ]]; then
    tag="$("$curl_bin" -fsSL \
      --connect-timeout 5 \
      --max-time 15 \
      --retry 1 \
      -H 'Accept: application/vnd.github+json' \
      "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null \
      | "$JQ" -r '.tag_name // empty' 2>/dev/null)"
    if [[ -n "$tag" && "$tag" != "null" ]]; then
      printf '%s' "$tag"
      return
    fi
  fi
  latest_release_tag_from_asset_url
}

write_release_check_cache() {
  local now tmp latest check_status rc
  now="$(date +%s 2>/dev/null || printf '0')"
  mkdir -p "${MENUTUBE_RELEASE_CHECK_CACHE:h}" 2>/dev/null || {
    rm -f "${MENUTUBE_RELEASE_CHECK_CACHE}.lock" 2>/dev/null || true
    return 1
  }
  tmp="${MENUTUBE_RELEASE_CHECK_CACHE}.$$"
  if latest="$(latest_release_tag)"; then
    check_status="ok"
  else
    check_status="error"
    latest=""
  fi
  if printf '%s\t%s\t%s\n' "$now" "$check_status" "$latest" > "$tmp" \
    && mv "$tmp" "$MENUTUBE_RELEASE_CHECK_CACHE"; then
    [[ "$check_status" == "ok" ]]
    rc=$?
  else
    rm -f "$tmp" 2>/dev/null || true
    rc=1
  fi
  rm -f "${MENUTUBE_RELEASE_CHECK_CACHE}.lock" 2>/dev/null || true
  return "$rc"
}

release_check_cache_fields() {
  [[ -f "$MENUTUBE_RELEASE_CHECK_CACHE" ]] || return 1
  local ts check_status latest rest
  IFS=$'\t' read -r ts check_status latest rest < "$MENUTUBE_RELEASE_CHECK_CACHE" || return 1
  printf '%s\t%s\t%s\n' "$ts" "$check_status" "$latest"
}

release_check_cache_age() {
  local mtime now
  mtime="$(cache_mtime "$MENUTUBE_RELEASE_CHECK_CACHE")"
  [[ -n "$mtime" ]] || { printf ''; return; }
  now="$(date +%s 2>/dev/null || printf '0')"
  printf '%s' $(( now - mtime ))
}

maybe_refresh_release_check() {
  truthy "$MENUTUBE_CHECK_RELEASE_UPDATES" || return
  [[ "$MENUTUBE_RELEASE_CHECK_TTL_SECONDS" == <-> ]] || MENUTUBE_RELEASE_CHECK_TTL_SECONDS=86400
  local age lock_file lock_mtime current_mtime now lock_age
  age="$(release_check_cache_age)"
  if [[ -n "$age" && "$age" -le "$MENUTUBE_RELEASE_CHECK_TTL_SECONDS" ]]; then
    return
  fi
  mkdir -p "${MENUTUBE_RELEASE_CHECK_CACHE:h}" 2>/dev/null || return
  lock_file="${MENUTUBE_RELEASE_CHECK_CACHE}.lock"
  lock_mtime="$(cache_mtime "$lock_file")"
  if [[ -n "$lock_mtime" ]]; then
    now="$(date +%s 2>/dev/null || printf '0')"
    lock_age=$(( now - lock_mtime ))
    if [[ "$lock_age" -gt 300 ]]; then
      current_mtime="$(cache_mtime "$lock_file")"
      [[ "$current_mtime" == "$lock_mtime" ]] && rm -f "$lock_file" 2>/dev/null || true
    fi
  fi
  ( set -C; : > "$lock_file" ) 2>/dev/null || return
  "$SCRIPT" check-release >/dev/null 2>&1 &
}

release_status_label() {
  local current="$1" fields ts check_status latest
  truthy "$MENUTUBE_CHECK_RELEASE_UPDATES" || { printf 'update checks disabled'; return; }
  fields="$(release_check_cache_fields)" || { printf 'checking latest release'; return; }
  IFS=$'\t' read -r ts check_status latest <<< "$fields"
  if [[ "$check_status" != "ok" || -z "$latest" ]]; then
    printf 'latest check unavailable'
  elif [[ "$(release_tag_norm "$latest")" == "$(release_tag_norm "$current")" ]]; then
    printf 'latest'
  else
    printf 'update %s available' "$latest"
  fi
}

release_status_color() {
  local label="$1"
  case "$label" in
    update\ *\ available) printf '#cc6633' ;;
    latest) printf '#2f8f46' ;;
    *) printf '#888888' ;;
  esac
}

cached_latest_release_tag() {
  local fields ts check_status latest
  fields="$(release_check_cache_fields)" || return 1
  IFS=$'\t' read -r ts check_status latest <<< "$fields"
  [[ "$check_status" == "ok" && -n "$latest" ]] || return 1
  printf '%s' "$latest"
}

update_log() {
  mkdir -p "${MENUTUBE_UPDATE_LOG:h}" 2>/dev/null || return
  print -r -- "[$(date '+%Y-%m-%d %H:%M:%S %z' 2>/dev/null || date)] ${1:-}" >> "$MENUTUBE_UPDATE_LOG" 2>/dev/null || true
}

update_message() {
  local message="${1:-}"
  print "$message"
  update_log "$message"
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
action_open_update_log() {
  mkdir -p "${MENUTUBE_UPDATE_LOG:h}" 2>/dev/null || true
  touch "$MENUTUBE_UPDATE_LOG" 2>/dev/null || true
  open -a "TextEdit" "$MENUTUBE_UPDATE_LOG"
}

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
  mkdir -p "${MENUTUBE_UPDATE_LOG:h}" 2>/dev/null || true
  update_log "=== menutube release update started ==="
  update_log "Plugin: $PLUGIN_PATH"
  update_log "Asset: $MENUTUBE_RELEASE_ASSET_URL"

  # Refuse if the running plugin file lives inside its own git checkout —
  # we don't want to clobber a developer's working tree from the menu.
  local repo_root
  repo_root="$(plugin_repo_root)"
  if [[ -n "$repo_root" && "$PLUGIN_PATH" == "$repo_root"/* ]]; then
    update_message "Plugin appears to be running from a git checkout: $repo_root"
    update_message "Use git commands in the checkout for development updates."
    return 1
  fi

  local curl_bin
  curl_bin="$(command -v curl)"
  if [[ -z "$curl_bin" ]]; then
    update_message "curl is required to update from the latest release."
    return 1
  fi
  if [[ ! -w "$PLUGIN_PATH" || ! -w "$PLUGIN_DIR" ]]; then
    update_message "Plugin file or directory is not writable: $PLUGIN_PATH"
    return 1
  fi
  if [[ "$MENUTUBE_RELEASE_ASSET_URL" != https://* ]]; then
    update_message "Refusing non-HTTPS release asset URL: $MENUTUBE_RELEASE_ASSET_URL"
    return 1
  fi

  local tmp first_line content curl_log
  tmp="${PLUGIN_DIR}/.menutube.5s.sh.$$"
  curl_log="$MENUTUBE_UPDATE_LOG"
  [[ -d "${MENUTUBE_UPDATE_LOG:h}" && -w "${MENUTUBE_UPDATE_LOG:h}" ]] || curl_log="/dev/null"
  rm -f "$tmp"

  update_message "Downloading latest menutube release asset..."
  if ! "$curl_bin" -fsSL \
    --connect-timeout 5 \
    --max-time 30 \
    --retry 2 \
    --retry-delay 1 \
    "$MENUTUBE_RELEASE_ASSET_URL" -o "$tmp" >> "$curl_log" 2>&1; then
    rm -f "$tmp"
    update_message "Download failed: $MENUTUBE_RELEASE_ASSET_URL"
    return 1
  fi

  IFS= read -r first_line < "$tmp" || first_line=""
  content="$(< "$tmp")"
  if [[ "$first_line" != "#!/bin/zsh" \
     || "$content" != *"<xbar.title>menutube</xbar.title>"* \
     || "$content" != *"PLUGIN_VERSION=\""* ]]; then
    rm -f "$tmp"
    update_message "Downloaded file did not look like a menutube plugin."
    return 1
  fi

  chmod +x "$tmp" || {
    rm -f "$tmp"
    update_message "Could not mark downloaded plugin executable."
    return 1
  }
  mv "$tmp" "$PLUGIN_PATH" || {
    rm -f "$tmp"
    update_message "Could not replace plugin file: $PLUGIN_PATH"
    return 1
  }
  update_message "Updated menutube from the latest release."
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
  repeat)   action_repeat;         exit 0 ;;
  add)      action_add;            exit 0 ;;
  remove)   action_remove "$2";    exit 0 ;;
  edit)     action_edit_library;   exit 0 ;;
  log)      action_open_log;       exit 0 ;;
  update-log) action_open_update_log; exit 0 ;;
  refetch)  action_refetch_titles; exit 0 ;;
  update)   action_update_ytdlp;   exit 0 ;;
  check-release) write_release_check_cache; exit $? ;;
  update-release) action_update_release; exit $? ;;
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
if [[ -z "$plugin_root" ]]; then
  maybe_refresh_release_check
  release_status="$(release_status_label "$version_label")"
  release_color="$(release_status_color "$release_status")"
  echo "--Version: ${version_label} (${release_status}) | font=Menlo color=$release_color"
else
  echo "--Version: ${version_label} | font=Menlo color=#888888"
fi
echo "--Plugin: ${PLUGIN_PATH/#$HOME/~} | font=Menlo size=10 color=#888888"
if [[ -n "$plugin_root" ]]; then
  git_summary="$(plugin_git_summary "$plugin_root")"
  echo "--Repo: ${plugin_root/#$HOME/~} | font=Menlo size=10 color=#888888"
  echo "--Git: ${git_summary:-unknown} | font=Menlo size=10 color=#888888"
  echo "----Use git commands for development updates | color=gray size=10"
else
  latest_release="$(cached_latest_release_tag 2>/dev/null || true)"
  if [[ -n "$latest_release" && "$(release_tag_norm "$latest_release")" != "$(release_tag_norm "$version_label")" ]]; then
    echo "--⬆️ Update to $latest_release | bash=$SCRIPT param1=update-release terminal=false refresh=true"
  else
    echo "--⬆️ Update to latest release | bash=$SCRIPT param1=update-release terminal=false refresh=true"
  fi
  echo "--🔎 Check plugin update status now | bash=$SCRIPT param1=check-release terminal=false refresh=true"
fi
[[ -f "$MENUTUBE_UPDATE_LOG" ]] && echo "--📝 Open update log | bash=$SCRIPT param1=update-log terminal=false"
echo "--🌐 Open project page | href=$MENUTUBE_REPO_URL"
