#!/usr/bin/env bash
# build-app.sh — Build Caffeine and wrap it in a signed, distributable .app
#
# Usage:  ./scripts/build-app.sh [--help] [--version <x.y.z>]
# Output: dist/Caffeine-<version>.app   (also symlinked as dist/Caffeine.app)
#
# Requirements: Xcode Command Line Tools (swift, codesign)

set -euo pipefail

# ─── Defaults ─────────────────────────────────────────────────────────────────
APP_NAME="Caffeine"
BUNDLE_ID="com.project9.caffeine"
MIN_MACOS="13.0"
SIGN_IDENTITY="-"          # "-" = ad-hoc; replace with "Developer ID Application: ..." for notarization
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── Argument parsing ─────────────────────────────────────────────────────────
VERSION=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            echo "Usage: $0 [--version x.y.z]"
            echo "  --version x.y.z   Override the version string (default: git describe)"
            exit 0 ;;
        --version|-v)
            VERSION="$2"; shift 2 ;;
        *)
            echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# Derive version from git if not supplied
if [[ -z "$VERSION" ]]; then
    VERSION=$(git -C "$PROJECT_DIR" describe --tags --always --dirty 2>/dev/null || echo "1.0.0")
    # Strip leading 'v'
    VERSION="${VERSION#v}"
fi
BUILD_NUMBER=$(git -C "$PROJECT_DIR" rev-list --count HEAD 2>/dev/null || echo "1")

echo "▶  Building $APP_NAME v$VERSION (build $BUILD_NUMBER) …"

# ─── Swift build ──────────────────────────────────────────────────────────────
cd "$PROJECT_DIR"
swift build -c release 2>&1 | sed 's/^/   /'

# ─── Bundle structure ─────────────────────────────────────────────────────────
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp ".build/release/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

# ─── Info.plist ───────────────────────────────────────────────────────────────
cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSUserNotificationAlertStyle</key>
    <string>alert</string>
    <key>NSUserNotificationsUsageDescription</key>
    <string>Caffeine notifies you when a timed session ends.</string>
</dict>
</plist>
PLIST

# ─── Entitlements ─────────────────────────────────────────────────────────────
ENTITLEMENTS_FILE="$DIST_DIR/Caffeine.entitlements"
cat > "$ENTITLEMENTS_FILE" << ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.network.client</key>
    <false/>
</dict>
</plist>
ENT

# ─── Code sign ────────────────────────────────────────────────────────────────
echo "▶  Signing with identity: $SIGN_IDENTITY"
codesign --force --deep --sign "$SIGN_IDENTITY" \
         --entitlements "$ENTITLEMENTS_FILE" \
         --options runtime \
         "$APP_DIR"

# ─── Versioned copy ───────────────────────────────────────────────────────────
VERSIONED="$DIST_DIR/$APP_NAME-$VERSION.app"
cp -R "$APP_DIR" "$VERSIONED"

# ─── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "✅  Built successfully:"
echo "    $APP_DIR"
echo "    $VERSIONED"
echo ""
echo "   Drag $APP_NAME.app into /Applications, or right-click › Open on first launch."
