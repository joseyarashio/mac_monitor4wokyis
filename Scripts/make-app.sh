#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> swift build -c release"
swift build -c release

APP_DIR="$ROOT_DIR/build/WokyMon.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

BUILD_BIN="$ROOT_DIR/.build/release/WokyMon"
if [ ! -x "$BUILD_BIN" ]; then
    echo "error: $BUILD_BIN not found after build" >&2
    exit 1
fi
cp "$BUILD_BIN" "$MACOS_DIR/WokyMon"

# SwiftPM names the generated resource bundle "<PackageName>_<TargetName>.bundle".
BUNDLE_SRC="$ROOT_DIR/.build/release/WokyMon_WokyMon.bundle"
if [ -d "$BUNDLE_SRC" ]; then
    cp -R "$BUNDLE_SRC" "$RESOURCES_DIR/"
else
    echo "error: resource bundle not found at $BUNDLE_SRC" >&2
    exit 1
fi

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>local.wokymon</string>
	<key>CFBundleName</key>
	<string>WokyMon</string>
	<key>CFBundleExecutable</key>
	<string>WokyMon</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
</dict>
</plist>
PLIST

echo "==> codesign (ad-hoc)"
codesign --force --deep --sign - "$APP_DIR"

echo "==> verifying Bundle.module resource lookup from the .app"
if "$MACOS_DIR/WokyMon" --dump >/dev/null; then
    echo "OK: $APP_DIR built and resource bundle resolves."
else
    echo "error: $MACOS_DIR/WokyMon --dump failed (resource bundle lookup likely broken)" >&2
    exit 1
fi

# --install: copy the bundle into /Applications (or ~/Applications if not writable).
if [ "${1:-}" = "--install" ]; then
    DEST="/Applications"
    if [ ! -w "$DEST" ]; then DEST="$HOME/Applications"; mkdir -p "$DEST"; fi
    rm -rf "$DEST/WokyMon.app"
    cp -R "$APP_DIR" "$DEST/WokyMon.app"
    echo "installed: $DEST/WokyMon.app"
fi
