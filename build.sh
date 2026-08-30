#!/bin/bash
#
# Builds Clipwell.app.
#
#   ./build.sh              build and assemble into dist/
#   ./build.sh --run        build, then launch
#   ./build.sh --install    build, then copy into /Applications
#
# Set SKIP_TESTS=1 to skip the test run.
#
# Signing: set CLIPWELL_SIGN_IDENTITY to a code-signing identity to get a
# stable code signature, which is what lets macOS remember the Accessibility
# permission across rebuilds. See scripts/make-signing-cert.sh. Without it the
# app is ad-hoc signed and you will have to re-grant Accessibility after every
# build.
set -euo pipefail

APP_NAME="Clipwell"
BUNDLE_ID="com.ezralevy.clipwell"
VERSION="1.0.0"

cd "$(dirname "$0")"
ROOT="$(pwd)"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

echo "==> Building (release)"
swift build -c release --disable-sandbox

BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"
if [ ! -f "$BINARY" ]; then
    echo "error: built binary not found at $BINARY" >&2
    exit 1
fi

if [ "${SKIP_TESTS:-0}" != "1" ]; then
    echo "==> Running tests"
    # Not a gate: a failing test shouldn't stop you getting a build you can
    # run. The result is reported either way.
    if swift test > /tmp/clipwell-test.log 2>&1; then
        echo "    all tests passed"
    else
        echo "    TESTS FAILED -- app still built. Full log: /tmp/clipwell-test.log"
        grep -E "error:|XCTAssert.*failed|failed \(" /tmp/clipwell-test.log | head -15 || true
    fi
fi

echo "==> Assembling $APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                  <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>           <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>            <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>               <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>    <string>$VERSION</string>
    <key>CFBundlePackageType</key>           <string>APPL</string>
    <key>CFBundleExecutable</key>            <string>$APP_NAME</string>
    <key>LSMinimumSystemVersion</key>        <string>13.0</string>
    <!-- Menu-bar only: no Dock icon, no app switcher entry. -->
    <key>LSUIElement</key>                   <true/>
    <key>NSHighResolutionCapable</key>       <true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key>   <false/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing"
if [ -n "${CLIPWELL_SIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime \
             --sign "$CLIPWELL_SIGN_IDENTITY" \
             --identifier "$BUNDLE_ID" \
             "$APP"
    echo "    signed with: $CLIPWELL_SIGN_IDENTITY"
else
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
    echo "    ad-hoc signed."
    echo "    NOTE: Accessibility permission will reset on each rebuild."
    echo "    Run scripts/make-signing-cert.sh once to avoid that."
fi

echo "==> Built $APP"

case "${1:-}" in
    --run)
        echo "==> Launching"
        # Replace a running copy so you're not left with two menu bar icons.
        pkill -x "$APP_NAME" 2>/dev/null || true
        sleep 0.5
        open "$APP"
        ;;
    --install)
        echo "==> Installing to /Applications"
        pkill -x "$APP_NAME" 2>/dev/null || true
        rm -rf "/Applications/$APP_NAME.app"
        cp -R "$APP" "/Applications/"
        echo "    installed. Launch it from /Applications."
        ;;
esac
