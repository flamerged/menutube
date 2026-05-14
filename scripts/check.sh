#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
PLUGIN="$ROOT/bin/menutube.5s.sh"

print "==> zsh syntax check"
zsh -n "$PLUGIN"
zsh -n "$ROOT/scripts/install-swiftbar.sh"
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
  grep -q "$tag" "$PLUGIN" || { print -u2 "missing metadata tag: $tag"; exit 1; }
done
print "    OK"

print "==> required xbar.var declarations"
for var in \
  'MENUTUBE_CONFIG_DIR' \
  'MENUTUBE_REPO_DIR' \
  'MENUTUBE_REPO_URL' \
  'MENUTUBE_RELEASE_ASSET_URL' \
  'MENUTUBE_MPV' \
  'MENUTUBE_YTDLP' \
  'MENUTUBE_USER_AGENT' \
  'MENUTUBE_PLAYER_CLIENT'; do
  grep -q "<xbar.var>.*$var" "$PLUGIN" || { print -u2 "missing xbar.var: $var"; exit 1; }
done
print "    OK"

print "==> dry render"
output="$(MENUTUBE_CONFIG_DIR="$(mktemp -d)" "$PLUGIN")"
print -r -- "$output" | grep -q '📚 Library' || { print -u2 "Library header missing"; exit 1; }
print -r -- "$output" | grep -q '➕ Add video' || { print -u2 "Add action missing"; exit 1; }
print -r -- "$output" | grep -q '🛠 Edit library file' || { print -u2 "Edit action missing"; exit 1; }
print -r -- "$output" | grep -q '🔧 Tools' || { print -u2 "Tools section missing"; exit 1; }
print "    OK"

print "==> literal-tilde defense (regression guard for the 0.1.0 bug)"
literal_tilde_output="$(MENUTUBE_CONFIG_DIR='~/.config/menutube-literal-tilde-test' "$PLUGIN" 2>&1 || true)"
print -r -- "$literal_tilde_output" | grep -q '📚 Library' \
  || { print -u2 "literal-tilde MENUTUBE_CONFIG_DIR should still render Library section"; exit 1; }
print "    OK"

print "==> auto-release dry-run"
AUTO_RELEASE_DRY_RUN=1 "$ROOT/scripts/auto-release.sh"
print "    OK"

print
print "all checks passed."
