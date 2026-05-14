#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"

print "==> zsh syntax check"
zsh -n "$ROOT/bin/menutube.5s.sh"
zsh -n "$ROOT/scripts/install-swiftbar.sh"
print "    OK"

if command -v shellcheck >/dev/null 2>&1; then
  print "==> shellcheck (zsh-dialect — informational only)"
  shellcheck -s bash "$ROOT/bin/menutube.5s.sh" || true
  print "    done"
fi

print "==> render plugin (dry)"
"$ROOT/bin/menutube.5s.sh" >/dev/null
print "    OK"

print
print "all checks passed."
