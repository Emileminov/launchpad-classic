#!/bin/bash
# Сборка для раздачи: подпись Developer ID, нотаризация САМОГО приложения (+ staple), затем dmg (тоже нотаризован).
# Один раз заранее (спросит Apple ID, пароль приложения):
#   xcrun notarytool store-credentials launchpad-notary --team-id 4AR298V292
set -e
cd "$(dirname "$0")/.."
export SIGN_ID="${SIGN_ID:-Developer ID Application: Emil EMINOV (4AR298V292)}"
PROFILE="${NOTARY_PROFILE:-launchpad-notary}"
NAME="Launchpad Classic"
APP="build/$NAME.app"
DMG="build/LaunchpadClassic.dmg"

xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 || {
  echo "Нет профиля нотаризации «$PROFILE». Выполни: xcrun notarytool store-credentials $PROFILE --team-id 4AR298V292"; exit 1; }

./scripts/build.sh

# 1) нотаризация самого приложения
rm -f build/app.zip
ditto -c -k --keepParent "$APP" build/app.zip
xcrun notarytool submit build/app.zip --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute -v "$APP"

# 2) dmg из уже проштампованного приложения
rm -rf build/dmg-stage "$DMG"
mkdir -p build/dmg-stage
cp -R "$APP" build/dmg-stage/
ln -s /Applications build/dmg-stage/Applications
hdiutil create -volname "$NAME" -srcfolder build/dmg-stage -ov -format UDZO "$DMG" >/dev/null
codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

# 3) в ~/Applications — проштампованная версия
pkill -x LaunchpadClassic 2>/dev/null || true
rm -rf "$HOME/Applications/$NAME.app"
cp -R "$APP" "$HOME/Applications/$NAME.app"
echo "Готово: приложение и dmg нотаризованы, штампы прикреплены."
