#!/bin/bash
# Собирает Launchpad Classic.app и ставит его в ~/Applications
set -e
cd "$(dirname "$0")/.."
NAME="Launchpad Classic"
OUT="build/$NAME.app"

swift build -c release
rm -rf "$OUT"; mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp .build/release/LaunchpadClassic "$OUT/Contents/MacOS/LaunchpadClassic"

# значок
mkdir -p build/icon.iconset
swift scripts/make_icon.swift build/icon_1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon_1024.png --out build/icon.iconset/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon_1024.png --out build/icon.iconset/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns build/icon.iconset -o "$OUT/Contents/Resources/AppIcon.icns"

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>com.emil.launchpadclassic</string>
  <key>CFBundleExecutable</key><string>LaunchpadClassic</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSAppleEventsUsageDescription</key><string>Нужно, чтобы переместить приложение в Корзину через Finder, когда у Launchpad Classic недостаточно прав.</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict></plist>
PLIST

if [ -n "$SIGN_ID" ]; then
  # Developer ID + hardened runtime + timestamp — нужно для нотаризации
  codesign --force --options runtime --timestamp --entitlements LaunchpadClassic.entitlements --sign "$SIGN_ID" "$OUT"
else
  codesign --force --deep -s - --entitlements LaunchpadClassic.entitlements "$OUT"
fi
mkdir -p "$HOME/Applications"
pkill -x LaunchpadClassic 2>/dev/null || true
rm -rf "$HOME/Applications/$NAME.app"
cp -R "$OUT" "$HOME/Applications/$NAME.app"
echo "Установлено: $HOME/Applications/$NAME.app"
