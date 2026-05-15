#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
PLUGIN="$ROOT/bin/menutube.5s.sh"

print "==> zsh syntax check"
zsh -n "$PLUGIN"
zsh -n "$ROOT/scripts/install-swiftbar.sh"
zsh -n "$ROOT/scripts/install-dev-swiftbar.sh"
bash -n "$ROOT/scripts/auto-release.sh"
print "    OK"

print "==> required metadata tags"
for tag in \
  '<xbar.title>' \
  '<xbar.version>' \
  '<xbar.author>' \
  '<xbar.author.github>' \
  '<xbar.desc>' \
  '<xbar.dependencies>' \
  '<xbar.abouturl>' \
  '<swiftbar.title>' \
  '<swiftbar.version>' \
  '<swiftbar.refresh>'; do
  grep -F -q "$tag" "$PLUGIN" || { print -u2 "missing metadata tag: $tag"; exit 1; }
done
print "    OK"

print "==> required xbar.var declarations"
for var in \
  'MENUTUBE_CONFIG_DIR' \
  'MENUTUBE_REPO_DIR' \
  'MENUTUBE_REPO_URL' \
  'MENUTUBE_RELEASE_ASSET_URL' \
  'MENUTUBE_UPDATE_LOG' \
  'MENUTUBE_CHECK_RELEASE_UPDATES' \
  'MENUTUBE_RELEASE_CHECK_TTL_SECONDS' \
  'MENUTUBE_RELEASE_CHECK_CACHE' \
  'MENUTUBE_MPV' \
  'MENUTUBE_YTDLP' \
  'MENUTUBE_USER_AGENT' \
  'MENUTUBE_PLAYER_CLIENT'; do
  grep -q "<xbar.var>.*$var" "$PLUGIN" || { print -u2 "missing xbar.var: $var"; exit 1; }
done
print "    OK"

print "==> dry render"
output="$(MENUTUBE_CONFIG_DIR="$(mktemp -d)" MENUTUBE_CHECK_RELEASE_UPDATES=0 "$PLUGIN")"
print -r -- "$output" | grep -q '📚 Library' || { print -u2 "Library header missing"; exit 1; }
print -r -- "$output" | grep -q '➕ Add video' || { print -u2 "Add action missing"; exit 1; }
print -r -- "$output" | grep -q '🛠 Edit library file' || { print -u2 "Edit action missing"; exit 1; }
print -r -- "$output" | grep -q '🔧 Tools' || { print -u2 "Tools section missing"; exit 1; }
print "    OK"

print "==> debug-mode toggle (renders + persists; regression guard)"
debug_cfg="$(mktemp -d)"
# OFF state: render mentions "Debug mode: OFF"
off_output="$(MENUTUBE_CONFIG_DIR="$debug_cfg" MENUTUBE_CHECK_RELEASE_UPDATES=0 "$PLUGIN")"
print -r -- "$off_output" | grep -q 'Debug mode: OFF' \
  || { print -u2 "default render should show 'Debug mode: OFF'"; exit 1; }
# Flip via dispatch
MENUTUBE_CONFIG_DIR="$debug_cfg" "$PLUGIN" debug
[[ "$(cat "$debug_cfg/debug" 2>/dev/null)" == "yes" ]] \
  || { print -u2 "action debug did not write 'yes' to \$DEBUG_FILE"; exit 1; }
on_output="$(MENUTUBE_CONFIG_DIR="$debug_cfg" MENUTUBE_CHECK_RELEASE_UPDATES=0 "$PLUGIN")"
print -r -- "$on_output" | grep -q 'Debug mode: ON' \
  || { print -u2 "render after toggle should show 'Debug mode: ON'"; exit 1; }
print "    OK"

print "==> literal-tilde defense (regression guard for the 0.1.0 bug)"
literal_tilde_output="$(MENUTUBE_CONFIG_DIR='~/.config/menutube-literal-tilde-test' MENUTUBE_CHECK_RELEASE_UPDATES=0 "$PLUGIN" 2>&1 || true)"
print -r -- "$literal_tilde_output" | grep -q '📚 Library' \
  || { print -u2 "literal-tilde MENUTUBE_CONFIG_DIR should still render Library section"; exit 1; }
print "    OK"

print "==> auto-release dry-run"
AUTO_RELEASE_DRY_RUN=1 "$ROOT/scripts/auto-release.sh"
print "    OK"

print
print "all checks passed."
