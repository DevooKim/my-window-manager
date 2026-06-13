#!/bin/bash
# Tags v$VERSION, pushes, and creates a GitHub release whose changelog is
# built from commit subjects since the previous tag (we commit straight to
# main, so GitHub's --generate-notes, which lists merged PRs, comes up empty).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
ZIP="dist/My-Window-Manager-v$VERSION.zip"

if ! git diff-index --quiet HEAD --; then
    echo "error: uncommitted changes — commit before publishing" >&2
    exit 1
fi
if git rev-parse "v$VERSION" >/dev/null 2>&1; then
    echo "error: tag v$VERSION already exists — bump the version in Info.plist" >&2
    exit 1
fi
[ -f "$ZIP" ] || { echo "error: $ZIP not found — run 'make release' first" >&2; exit 1; }

PREV_TAG=$(git describe --tags --abbrev=0 2>/dev/null || true)

NOTES_FILE=$(mktemp)
trap 'rm -f "$NOTES_FILE"' EXIT
{
    echo "**Install:** unzip, move \`My Window Manager.app\` to Applications, open via System Settings > Privacy & Security (\"Open Anyway\"), then grant Accessibility permission. See the [README](README.md#install) / [한국어 안내](README.ko.md#설치)."
    echo
    echo "## Changes"
    echo
    if [ -n "$PREV_TAG" ]; then
        # Commit subjects since the last release; version-bump chores are noise.
        git log "$PREV_TAG"..HEAD --no-merges --pretty="- %s" | grep -v "^- chore: bump version" || true
        echo
        echo "**Full Changelog**: https://github.com/DevooKim/my-window-manager/compare/$PREV_TAG...v$VERSION"
    else
        git log --no-merges --pretty="- %s" | grep -v "^- chore: bump version" || true
    fi
} > "$NOTES_FILE"

git tag "v$VERSION"
git push origin main "v$VERSION"
gh release create "v$VERSION" "$ZIP" \
    --title "My Window Manager v$VERSION" \
    --notes-file "$NOTES_FILE"
echo "Published: v$VERSION"
