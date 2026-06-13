#!/bin/bash
# Bumps the semver in Info.plist (patch|minor|major), increments the build
# number, and commits. Refuses to run with unrelated uncommitted changes so
# the bump commit stays clean.
set -euo pipefail
cd "$(dirname "$0")/.."

PLIST=Info.plist
PART="${1:?usage: bump.sh patch|minor|major}"

if ! git diff-index --quiet HEAD --; then
    echo "error: uncommitted changes — commit them before bumping" >&2
    exit 1
fi

CURRENT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
IFS=. read -r MAJOR MINOR PATCH <<< "$CURRENT"

case "$PART" in
    patch) PATCH=$((PATCH + 1)) ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    *) echo "error: unknown part '$PART' (patch|minor|major)" >&2; exit 1 ;;
esac

NEW="$MAJOR.$MINOR.$PATCH"
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")
NEW_BUILD=$((BUILD + 1))

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$PLIST"

git add "$PLIST"
git commit -q -m "chore: bump version to $NEW (build $NEW_BUILD)"
echo "$CURRENT -> $NEW (build $NEW_BUILD)"
