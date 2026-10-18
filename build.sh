#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/.build"
DIST="${1:-$ROOT/dist}"
mkdir -p "$BUILD/cache" "$DIST"
APP="$DIST/Connection Workbench.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
for ARCH in arm64 x86_64; do
    echo "Building for ${ARCH}…"
    xcrun swiftc -O -swift-version 5 -module-cache-path "$BUILD/cache" -parse-as-library -target "$ARCH-apple-macosx13.0" "$ROOT/Sources/Core.swift" "$ROOT/Sources/App.swift" -o "$BUILD/app-$ARCH"
    xcrun swiftc -O -swift-version 5 -module-cache-path "$BUILD/cache" -parse-as-library -target "$ARCH-apple-macosx13.0" "$ROOT/Sources/Core.swift" "$ROOT/Sources/CLI.swift" -o "$BUILD/cli-$ARCH"
done
xcrun lipo -create "$BUILD/app-arm64" "$BUILD/app-x86_64" -output "$APP/Contents/MacOS/ConnectionWorkbench"
xcrun lipo -create "$BUILD/cli-arm64" "$BUILD/cli-x86_64" -output "$DIST/connection-workbench"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ConnectionWorkbench</string>
<key>CFBundleIdentifier</key><string>tools.connectionworkbench.desktop</string>
<key>CFBundleName</key><string>Connection Workbench</string>
<key>CFBundleDisplayName</key><string>Connection Workbench</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleIconFile</key><string>Workbench</string>
</dict></plist>
PLIST
xcrun swiftc -module-cache-path "$BUILD/cache" "$ROOT/Tools/Icon.swift" -o "$BUILD/icon"
"$BUILD/icon" "$BUILD/Workbench.iconset" "$APP/Contents/Resources/Workbench.icns"
# Finder/file providers may attach FinderInfo to newly created app bundles.
# Remove only that build artifact metadata before signing; never change quarantine policy.
/usr/bin/xattr -dr com.apple.FinderInfo "$APP" 2>/dev/null || true
/usr/bin/codesign --force --sign - "$APP"
/usr/bin/codesign --force --sign - "$DIST/connection-workbench"
/usr/bin/codesign --verify --strict "$APP"
echo "Built: $APP"
