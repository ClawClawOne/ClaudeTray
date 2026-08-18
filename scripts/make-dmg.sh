#!/bin/bash
#
# Construit ClaudeTray en Release, le signe Developer ID, produit un DMG,
# le fait notariser par Apple et y agrafe le ticket.
#
# Prérequis, une seule fois :
#   1. Certificat « Developer ID Application » installé dans le trousseau.
#        security find-identity -v -p codesigning | grep "Developer ID Application"
#   2. Identifiants de notarisation enregistrés sous un profil nommé :
#        xcrun notarytool store-credentials claudetray \
#          --apple-id "ton@email" --team-id "XXXXXXXXXX" --password "mot-de-passe-app"
#      (mot de passe d'application créé sur appleid.apple.com, pas le mot de passe du compte)
#
# Usage :
#   ./scripts/make-dmg.sh                    # build + signature + DMG + notarisation
#   SKIP_NOTARIZE=1 ./scripts/make-dmg.sh    # s'arrête après le DMG signé (test local)

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="ClaudeTray"
SCHEME="ClaudeTray"
NOTARY_PROFILE="${NOTARY_PROFILE:-claudetray}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
BUILD_DIR="build"
DIST_DIR="dist"
STAGING_DIR="$BUILD_DIR/dmg-staging"

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

step "Vérification du certificat"
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo "Aucun certificat « Developer ID Application » dans le trousseau." >&2
    echo "Les certificats « Apple Development » ne passent pas Gatekeeper ailleurs que sur cette machine." >&2
    exit 1
fi

step "Build Release"
rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$DIST_DIR" "$STAGING_DIR"
xcodebuild \
    -project "$APP_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO \
    build | grep -E "error:|warning:|BUILD" || true

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/Release/$APP_NAME.app"
[ -d "$APP_PATH" ] || { echo "Build introuvable : $APP_PATH" >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"

step "Signature de l'app (Developer ID, hardened runtime)"
# --options runtime est exigé par la notarisation ; l'horodatage sécurisé aussi.
codesign --force --deep \
    --options runtime \
    --timestamp \
    --entitlements "$APP_NAME/$APP_NAME.entitlements" \
    --sign "$SIGN_IDENTITY" \
    "$APP_PATH"
codesign --verify --strict --verbose=2 "$APP_PATH"

step "Construction du DMG"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov -format UDZO \
    "$DMG_PATH" >/dev/null

step "Signature du DMG"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"

if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
    echo
    echo "DMG signé, notarisation ignorée : $DMG_PATH"
    echo "Sans notarisation, Gatekeeper refusera ce DMG sur une autre machine."
    exit 0
fi

step "Notarisation Apple (quelques minutes)"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

step "Agrafage du ticket"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

step "Vérification finale"
# Ce que Gatekeeper verra chez l'utilisateur qui monte le DMG.
spctl --assess --type open --context context:primary-signature -vv "$DMG_PATH"

echo
echo "Prêt à distribuer : $DMG_PATH"
