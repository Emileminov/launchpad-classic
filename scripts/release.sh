#!/bin/bash
# Сборка для раздачи: подпись Developer ID, dmg, нотаризация, staple.
# Один раз заранее (спросит Apple ID, пароль приложения и Team ID):
#   xcrun notarytool store-credentials launchpad-notary
set -e
cd "$(dirname "$0")/.."
export SIGN_ID="${SIGN_ID:-Developer ID Application: Emil EMINOV (4AR298V292)}"
PROFILE="${NOTARY_PROFILE:-launchpad-notary}"
NAME="Launchpad Classic"
DMG="build/LaunchpadClassic.dmg"

./scripts/build.sh

rm -rf build/dmg-stage "$DMG"
mkdir -p build/dmg-stage
cp -R "build/$NAME.app" build/dmg-stage/
ln -s /Applications build/dmg-stage/Applications
hdiutil create -volname "$NAME" -srcfolder build/dmg-stage -ov -format UDZO "$DMG" >/dev/null
codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
echo "Собран и подписан: $DMG"

if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature -v "$DMG"
  echo "Готово: нотаризован и прикреплён штамп — открывается у других без предупреждений."
else
  echo "Профиль нотаризации «$PROFILE» не найден — dmg подписан, но НЕ нотаризован."
fi
