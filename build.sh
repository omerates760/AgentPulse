#!/bin/bash
set -e

echo "Building AgentPulse..."

BUILD_DIR=".build"
APP_NAME="AgentPulse"
APP_BUNDLE="$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"

# Check for best available SDK
for sdk in MacOSX14.sdk MacOSX13.3.sdk MacOSX13.sdk MacOSX.sdk; do
    if [ -d "/Library/Developer/CommandLineTools/SDKs/$sdk" ]; then
        SDK="/Library/Developer/CommandLineTools/SDKs/$sdk"
        break
    fi
done
echo "  Using SDK: $SDK"

mkdir -p "$BUILD_DIR"

# Find all Swift sources for main app
SOURCES=$(find Sources/AgentPulse -name "*.swift" | sort)
echo "  Found $(echo "$SOURCES" | wc -l | tr -d ' ') source files"

# Compile main app
echo "  Compiling AgentPulse..."
swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macosx13.0 \
  -framework AppKit \
  -framework SwiftUI \
  -framework Combine \
  -framework Carbon \
  -framework CoreServices \
  \
  $SOURCES \
  -o "$BUILD_DIR/$APP_NAME" \
  -O \
  \
  2>&1

# Compile bridge binary
echo "  Compiling AgentPulseBridge..."
swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macosx13.0 \
  Sources/AgentPulseBridge/main.swift \
  -o "$BUILD_DIR/agent-pulse-bridge" \
  -O \
  \
  2>&1

# Create app bundle structure
echo "  Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Helpers"
mkdir -p "$CONTENTS/Resources"

# Copy binaries
cp "$BUILD_DIR/$APP_NAME" "$CONTENTS/MacOS/$APP_NAME"
cp "$BUILD_DIR/agent-pulse-bridge" "$CONTENTS/Helpers/agent-pulse-bridge"
chmod +x "$CONTENTS/MacOS/$APP_NAME"
chmod +x "$CONTENTS/Helpers/agent-pulse-bridge"

# Copy Info.plist and icon
cp "Resources/Info.plist" "$CONTENTS/Info.plist"
cp "Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns" 2>/dev/null || true

# Create PkgInfo
echo -n "APPL????" > "$CONTENTS/PkgInfo"

# Ad-hoc sign
echo "  Signing..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || echo "  (signing skipped)"

# Install bridge to ~/.agent-pulse/bin
echo "  Installing bridge..."
BRIDGE_DIR="$HOME/.agent-pulse/bin"
mkdir -p "$BRIDGE_DIR"
cp "$BUILD_DIR/agent-pulse-bridge" "$BRIDGE_DIR/agent-pulse-bridge"
chmod +x "$BRIDGE_DIR/agent-pulse-bridge"

echo ""
echo "Build complete: $APP_BUNDLE ($(du -sh "$APP_BUNDLE" | cut -f1))"
echo ""
echo "To run:  open $APP_BUNDLE"
echo "To install:  cp -r $APP_BUNDLE /Applications/"
echo ""
