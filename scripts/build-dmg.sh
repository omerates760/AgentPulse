#!/bin/bash
set -e

VERSION="${1:-1.0.0}"
APP_NAME="AgentPulse"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_DIR=".dmg-staging"

echo "Building ${APP_NAME} v${VERSION}..."

# Build the app first
./build.sh

# Clean staging
rm -rf "$DMG_DIR" "$DMG_NAME"
mkdir -p "$DMG_DIR"

# Copy app bundle
cp -r "${APP_NAME}.app" "$DMG_DIR/"

# Create Applications symlink for drag-to-install
ln -s /Applications "$DMG_DIR/Applications"

# Create DMG
echo "Creating DMG..."
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov \
    -format UDZO \
    "$DMG_NAME"

# Clean up
rm -rf "$DMG_DIR"

echo ""
echo "DMG created: $DMG_NAME ($(du -sh "$DMG_NAME" | cut -f1))"
echo ""
