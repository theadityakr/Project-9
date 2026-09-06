#!/usr/bin/env bash
# build-app.sh — Build Caffeine, bundle it as a .app, and package a DMG installer.
#
# Usage:  ./scripts/build-app.sh [--help] [--version <x.y.z>] [--no-dmg]
# Output: dist/Caffeine.app
#         dist/Caffeine-<version>.dmg
#
# Requirements: Xcode Command Line Tools (swift, codesign, hdiutil, iconutil)

set -euo pipefail

# ─── Defaults ─────────────────────────────────────────────────────────────────
APP_NAME="Caffeine"
BUNDLE_ID="com.project9.caffeine"
MIN_MACOS="13.0"
SIGN_IDENTITY="-"          # "-" = ad-hoc; swap for "Developer ID Application: ..." if you have one
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MAKE_DMG=true

# ─── Argument parsing ─────────────────────────────────────────────────────────
VERSION=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            echo "Usage: $0 [--version x.y.z] [--no-dmg]"
            echo "  --version x.y.z   Override the version string (default: git describe)"
            echo "  --no-dmg          Skip DMG creation (faster for local testing)"
            exit 0 ;;
        --version|-v)
            VERSION="$2"; shift 2 ;;
        --no-dmg)
            MAKE_DMG=false; shift ;;
        *)
            echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# Derive version from git if not supplied
if [[ -z "$VERSION" ]]; then
    VERSION=$(git -C "$PROJECT_DIR" describe --tags --always --dirty 2>/dev/null || echo "1.0.0")
    VERSION="${VERSION#v}"   # strip leading 'v'
fi
BUILD_NUMBER=$(git -C "$PROJECT_DIR" rev-list --count HEAD 2>/dev/null || echo "1")

echo "▶  Building $APP_NAME v$VERSION (build $BUILD_NUMBER) …"

# ─── Output paths ─────────────────────────────────────────────────────────────
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
mkdir -p "$DIST_DIR"

# ─── 1. Generate app icon from SF Symbol ──────────────────────────────────────
ICNS_PATH="$DIST_DIR/$APP_NAME.icns"
echo "▶  Generating icon from SF Symbol …"
swift "$SCRIPT_DIR/make-icon.swift" --symbol "cup.and.saucer.fill" --output "$ICNS_PATH"

# ─── 2. Swift release build ───────────────────────────────────────────────────
echo "▶  Compiling …"
cd "$PROJECT_DIR"
swift build -c release 2>&1 | sed 's/^/   /'

# ─── 3. Assemble .app bundle ──────────────────────────────────────────────────
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp ".build/release/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

# Place the generated ICNS inside the bundle
cp "$ICNS_PATH" "$APP_DIR/Contents/Resources/$APP_NAME.icns"

# ─── 4. Info.plist ────────────────────────────────────────────────────────────
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
    <key>CFBundleIconFile</key>
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

# ─── 5. Entitlements ──────────────────────────────────────────────────────────
ENTITLEMENTS_FILE="$DIST_DIR/$APP_NAME.entitlements"
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

# ─── 6. Code sign ─────────────────────────────────────────────────────────────
echo "▶  Signing ($SIGN_IDENTITY) …"
codesign --force --deep --sign "$SIGN_IDENTITY" \
         --entitlements "$ENTITLEMENTS_FILE" \
         --options runtime \
         "$APP_DIR"

# ─── 7. DMG installer ─────────────────────────────────────────────────────────
if $MAKE_DMG; then
    DMG_STAGING="$DIST_DIR/dmg-staging"
    DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
    DMG_TMP="$DIST_DIR/$APP_NAME-tmp.dmg"

    echo "▶  Packaging DMG …"

    # Build staging folder: app + /Applications symlink
    rm -rf "$DMG_STAGING"
    mkdir -p "$DMG_STAGING"
    cp -R "$APP_DIR" "$DMG_STAGING/"
    ln -s /Applications "$DMG_STAGING/Applications"

    # Create a read-write DMG from the staging folder
    rm -f "$DMG_TMP" "$DMG_PATH"
    hdiutil create \
        -volname "$APP_NAME $VERSION" \
        -srcfolder "$DMG_STAGING" \
        -fs HFS+ \
        -format UDRW \
        -ov \
        "$DMG_TMP" > /dev/null

    # Convert to compressed, read-only DMG for distribution
    hdiutil convert "$DMG_TMP" \
        -format UDZO \
        -imagekey zlib-level=9 \
        -o "$DMG_PATH" > /dev/null

    rm -f "$DMG_TMP"
    rm -rf "$DMG_STAGING"

    echo "   DMG → $DMG_PATH"
fi

# ─── 8. Versioned .app copy ───────────────────────────────────────────────────
VERSIONED_APP="$DIST_DIR/$APP_NAME-$VERSION.app"
cp -R "$APP_DIR" "$VERSIONED_APP"

# ─── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "✅  Build complete!"
echo "    App  → $APP_DIR"
if $MAKE_DMG; then
    echo "    DMG  → $DIST_DIR/$APP_NAME-$VERSION.dmg"
fi
echo ""
echo "   Drag $APP_NAME.app into /Applications, or mount the DMG and drag from there."
echo "   On first launch: right-click › Open to bypass Gatekeeper (ad-hoc signed)."

