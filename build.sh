#!/bin/bash
set -e

echo "=== Building CleanDisk in Release mode ==="
swift build -c release

echo "=== Packaging CleanDisk.app ==="
APP_DIR="CleanDisk.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Clean old bundle if exists
rm -rf "$APP_DIR"

# Create folder structure
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy compiled executable
cp .build/release/CleanDisk "$MACOS_DIR/"

# Generate AppIcon.icns from icon.png if it exists
if [ -f "icon.png" ]; then
    echo "=== Generating AppIcon.icns from icon.png ==="
    rm -rf AppIcon.iconset
    mkdir -p AppIcon.iconset
    sips -s format png -z 16 16     icon.png --out AppIcon.iconset/icon_16x16.png > /dev/null
    sips -s format png -z 32 32     icon.png --out AppIcon.iconset/icon_16x16@2x.png > /dev/null
    sips -s format png -z 32 32     icon.png --out AppIcon.iconset/icon_32x32.png > /dev/null
    sips -s format png -z 64 64     icon.png --out AppIcon.iconset/icon_32x32@2x.png > /dev/null
    sips -s format png -z 128 128   icon.png --out AppIcon.iconset/icon_128x128.png > /dev/null
    sips -s format png -z 256 256   icon.png --out AppIcon.iconset/icon_128x128@2x.png > /dev/null
    sips -s format png -z 256 256   icon.png --out AppIcon.iconset/icon_256x256.png > /dev/null
    sips -s format png -z 512 512   icon.png --out AppIcon.iconset/icon_256x256@2x.png > /dev/null
    sips -s format png -z 512 512   icon.png --out AppIcon.iconset/icon_512x512.png > /dev/null
    sips -s format png -z 1024 1024 icon.png --out AppIcon.iconset/icon_512x512@2x.png > /dev/null
    iconutil -c icns AppIcon.iconset
    rm -rf AppIcon.iconset
fi

# Copy AppIcon.icns to Resources if it exists
if [ -f "AppIcon.icns" ]; then
    echo "=== Copying AppIcon.icns ==="
    cp AppIcon.icns "$RESOURCES_DIR/"
fi

# Create Info.plist
cat <<EOF > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>CleanDisk</string>
    <key>CFBundleIdentifier</key>
    <string>com.simons.CleanDisk</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>CleanDisk</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>CleanDisk scans Downloads to show large files and move selected items to the Trash.</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>CleanDisk scans Desktop to show large files and move selected items to the Trash.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>CleanDisk may scan selected document folders to show large files and move selected items to the Trash.</string>
</dict>
</plist>
EOF

echo "=== CleanDisk.app package successfully created! ==="
echo "You can launch it with: open CleanDisk.app"

echo "=== Packaging CleanDisk.dmg ==="
# Create temporary packaging folder
rm -rf dmg_root
mkdir -p dmg_root
cp -R CleanDisk.app dmg_root/
ln -s /Applications dmg_root/Applications

# Run hdiutil to create the DMG
hdiutil create -volname "CleanDisk" -srcfolder dmg_root -ov -format UDZO CleanDisk.dmg

# Clean up temporary folder
rm -rf dmg_root

echo "=== CleanDisk.dmg successfully created! ==="
