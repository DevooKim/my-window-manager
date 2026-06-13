#!/bin/bash
# Assembles "dist/My Window Manager.app" from the SPM release binary.
# Signs with the "MyWindowManager Dev" self-signed identity when present, so
# the code signature (and therefore the TCC Accessibility grant) stays stable
# across rebuilds. Falls back to ad-hoc signing, which requires re-granting
# permission after every build. Override the identity with WM_SIGN_IDENTITY.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="dist/My Window Manager.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp .build/release/MyWindowManager "$APP/Contents/MacOS/MyWindowManager"

IDENTITY="${WM_SIGN_IDENTITY:-MyWindowManager Dev}"
# --deep so any nested bundles are signed too; an unsigned nested bundle
# fails the outer signature.
#
# We attempt the real sign directly rather than gating on
# `find-identity -p codesigning`: a self-signed identity that isn't a
# trusted root is omitted from that policy list but still signs fine, and
# we don't want (or need) to register it as a trusted root just to pass a
# precheck. If the sign fails (identity truly missing), fall back to ad-hoc.
if codesign --force --deep --sign "$IDENTITY" "$APP" 2>/dev/null; then
    echo "Signed with: $IDENTITY"
else
    echo "warning: '$IDENTITY' identity unavailable; ad-hoc signing (permission must be re-granted each build)" >&2
    codesign --force --deep --sign - "$APP"
fi
echo "Bundled: $APP"
