#!/bin/bash
set -e

echo "=== Compiling Swift application ==="
swift build -c release

echo "=== Creating macOS App Bundle ==="
APP_DIR="MiniMagnet.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Clear old bundle if exists
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "=== Copying executable ==="
cp .build/release/mini "$MACOS_DIR/MiniMagnet"

echo "=== Generating icon assets ==="
SRC="Sources/mini/Resources/AppIcon.png"
ICONSET="$RESOURCES_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"

sips -z 16   16   "$SRC" -s format png --out "$ICONSET/icon_16x16.png"      > /dev/null
sips -z 32   32   "$SRC" -s format png --out "$ICONSET/icon_16x16@2x.png"   > /dev/null
sips -z 32   32   "$SRC" -s format png --out "$ICONSET/icon_32x32.png"      > /dev/null
sips -z 64   64   "$SRC" -s format png --out "$ICONSET/icon_32x32@2x.png"   > /dev/null
sips -z 128  128  "$SRC" -s format png --out "$ICONSET/icon_128x128.png"    > /dev/null
sips -z 256  256  "$SRC" -s format png --out "$ICONSET/icon_128x128@2x.png" > /dev/null
sips -z 256  256  "$SRC" -s format png --out "$ICONSET/icon_256x256.png"    > /dev/null
sips -z 512  512  "$SRC" -s format png --out "$ICONSET/icon_256x256@2x.png" > /dev/null
sips -z 512  512  "$SRC" -s format png --out "$ICONSET/icon_512x512.png"    > /dev/null
sips -z 1024 1024 "$SRC" -s format png --out "$ICONSET/icon_512x512@2x.png" > /dev/null

iconutil -c icns "$ICONSET" -o "$RESOURCES_DIR/AppIcon.icns"
rm -rf "$ICONSET"

# Copy the PNG alongside the executable for runtime icon loading
cp "$SRC" "$MACOS_DIR/AppIcon.png"

echo "=== Creating Info.plist ==="
cat <<EOF > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MiniMagnet</string>
    <key>CFBundleIdentifier</key>
    <string>com.betrend.minimagnet</string>
    <key>CFBundleName</key>
    <string>MiniMagnet</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "=== Build and packaging successful! ==="
echo "App bundle: $(pwd)/$APP_DIR"
