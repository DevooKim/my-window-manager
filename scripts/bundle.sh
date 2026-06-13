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
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    codesign --force --deep --sign "$IDENTITY" "$APP"
    echo "Signed with: $IDENTITY"
else
    echo "warning: '$IDENTITY' identity not found; ad-hoc signing (permission must be re-granted each build)" >&2
    codesign --force --deep --sign - "$APP"
fi
echo "Bundled: $APP"
