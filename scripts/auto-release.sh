#!/usr/bin/env bash
set -euo pipefail

# auto-release.sh — bump-and-release based on conventional commits since the
# last v* tag. Runs on push to main from .github/workflows/release.yml.
#
# Bump rules:
#   - "feat:" or "feat(scope):"           -> minor
#   - "fix:" or "perf:" (with scope)      -> patch
#   - any "type!:" or "BREAKING CHANGE:"  -> major
#
# The release asset is bin/menutube.5s.sh with its version markers patched
# to the new version. The hard-coded PLUGIN_VERSION in the file is only a
# fallback; at runtime the plugin prefers git-tag-derived versioning.

latest_tag="$(git describe --tags --match 'v[0-9]*' --abbrev=0 2>/dev/null || true)"
if [[ -n "$latest_tag" ]]; then
  base_version="${latest_tag#v}"
  commit_range="${latest_tag}..HEAD"
else
  base_version="0.0.0"
  commit_range="HEAD"
fi

commit_subjects="$(git log --format=%s "$commit_range")"
commit_bodies="$(git log --format=%B "$commit_range")"

bump=""
if grep -Eq '(^[a-zA-Z]+(\([^)]+\))?!:|BREAKING CHANGE:)' <<<"$commit_bodies"; then
  bump="major"
elif grep -Eq '^feat(\([^)]+\))?: ' <<<"$commit_subjects"; then
  bump="minor"
elif grep -Eq '^(fix|perf)(\([^)]+\))?: ' <<<"$commit_subjects"; then
  bump="patch"
fi

if [[ -z "$bump" ]]; then
  echo "No releasable conventional commits since ${latest_tag:-repository start}."
  exit 0
fi

if [[ ! "$base_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid version format from latest tag: ${latest_tag:-$base_version}" >&2
  exit 1
fi

IFS=. read -r major minor patch <<<"$base_version"
case "$bump" in
  major)
    major=$((major + 1))
    minor=0
    patch=0
    ;;
  minor)
    minor=$((minor + 1))
    patch=0
    ;;
  patch)
    patch=$((patch + 1))
    ;;
esac

next_version="${major}.${minor}.${patch}"
next_tag="v${next_version}"

if [[ "${AUTO_RELEASE_DRY_RUN:-0}" == "1" ]]; then
  echo "Would create ${next_tag} (${bump}) from ${latest_tag:-repository start}."
  exit 0
fi

if [[ -n "${GITHUB_REF:-}" && "$GITHUB_REF" != "refs/heads/main" ]]; then
  echo "Release script must run on refs/heads/main, not ${GITHUB_REF}." >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "GitHub CLI is not authenticated." >&2
  exit 1
fi

today="$(date -u +%Y-%m-%d)"
notes_file="$(mktemp)"
{
  if [[ -n "$latest_tag" ]]; then
    printf '## [%s](https://github.com/flamerged/menutube/compare/%s...%s) (%s)\n\n' "$next_version" "$latest_tag" "$next_tag" "$today"
  else
    printf '## %s (%s)\n\n' "$next_version" "$today"
  fi

  features="$(grep -E '^feat(\([^)]+\))?: ' <<<"$commit_subjects" | sed -E 's/^feat(\([^)]+\))?: /- /' || true)"
  fixes="$(grep -E '^(fix|perf)(\([^)]+\))?: ' <<<"$commit_subjects" | sed -E 's/^(fix|perf)(\([^)]+\))?: /- /' || true)"
  breaking="$(grep -E '(^[a-zA-Z]+(\([^)]+\))?!:|BREAKING CHANGE:)' <<<"$commit_bodies" || true)"

  if [[ -n "$breaking" ]]; then
    printf '### Breaking Changes\n\n'
    grep -E '^[a-zA-Z]+(\([^)]+\))?!: ' <<<"$commit_subjects" | sed -E 's/^[a-zA-Z]+(\([^)]+\))?!: /- /' || true
    grep -E '^BREAKING CHANGE: ' <<<"$commit_bodies" | sed -E 's/^BREAKING CHANGE: /- /' || true
    printf '\n'
  fi
  if [[ -n "$features" ]]; then
    printf '### Features\n\n%s\n\n' "$features"
  fi
  if [[ -n "$fixes" ]]; then
    printf '### Fixes\n\n%s\n\n' "$fixes"
  fi
} > "$notes_file"

asset_dir="$(mktemp -d)"
asset_path="${asset_dir}/menutube.5s.sh"
cp bin/menutube.5s.sh "$asset_path"
perl -0pi -e "s#(<xbar\\.version>v)[^<]+(</xbar\\.version>)#\${1}${next_version}\${2}#g; s#(<swiftbar\\.version>v)[^<]+(</swiftbar\\.version>)#\${1}${next_version}\${2}#g; s#(PLUGIN_VERSION=\")[^\"]+(\")#\${1}${next_version}\${2}#g" "$asset_path"
chmod +x "$asset_path"

created_tag=0
if ! git rev-parse "$next_tag" >/dev/null 2>&1; then
  git tag "$next_tag"
  git push origin "$next_tag"
  created_tag=1
fi

if gh release view "$next_tag" >/dev/null 2>&1; then
  echo "Release ${next_tag} already exists."
  exit 0
fi

if ! gh release create "$next_tag" "$asset_path#menutube.5s.sh" --title "$next_tag" --notes-file "$notes_file"; then
  if [[ "$created_tag" == "1" ]]; then
    git push --delete origin "$next_tag" >/dev/null 2>&1 || true
    git tag -d "$next_tag" >/dev/null 2>&1 || true
  fi
  exit 1
fi
