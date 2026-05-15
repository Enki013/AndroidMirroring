#!/usr/bin/env bash
# Build Android Mirror without full Xcode IDE (uses swiftc + asset catalog if available)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Android Mirror"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
SRC="$ROOT/AndroidMirror"
SDK="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"

mkdir -p "$BUILD_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

echo "Compiling Swift sources…"
swiftc \
  -target "${ARCH}-apple-macos14.0" \
  -sdk "$SDK" \
  -O \
  -framework AppKit -framework SwiftUI -framework MetalKit -framework CoreImage \
  -framework VideoToolbox -framework CoreMedia -framework Network \
  -o "$APP_DIR/Contents/MacOS/AndroidMirror" \
  $(find "$SRC" -name "*.swift" | sort)

echo "Copying resources…"
cp -R "$SRC/Resources/Binaries" "$APP_DIR/Contents/Resources/" 2>/dev/null || {
  echo "Warning: Binaries missing. Run scripts/fetch-binaries.sh"
}
if [ -d "$SRC/Resources/Assets.xcassets" ]; then
  xcrun actool "$SRC/Resources/Assets.xcassets" \
    --compile "$APP_DIR/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon 2>/dev/null || cp -R "$SRC/Resources/Assets.xcassets" "$APP_DIR/Contents/Resources/"
fi

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>AndroidMirror</string>
	<key>CFBundleIdentifier</key>
	<string>com.androidmirror.app</string>
	<key>CFBundleName</key>
	<string>Android Mirror</string>
	<key>CFBundleDisplayName</key>
	<string>Android Mirror</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

echo "Built: $APP_DIR"
echo "Run: open \"$APP_DIR\""
