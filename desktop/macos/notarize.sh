#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../dist"
: "${MAC_CERTIFICATE:?Set the base64 Developer ID Application certificate export}"
: "${MAC_CERTIFICATE_PASSWORD:?Set the certificate export password}"
: "${MAC_SIGNING_IDENTITY:?Set the Developer ID Application signing identity}"
: "${MAC_NOTARY_KEY:?Set the base64 App Store Connect API key}"
: "${MAC_NOTARY_KEY_ID:?Set the notary key ID}"
: "${MAC_NOTARY_ISSUER_ID:?Set the notary issuer UUID}"
stage="$(mktemp -d)"
keychain="$stage/release.keychain-db"
old_keychains=()
while IFS= read -r line; do
    path="${line#*\"}"
    old_keychains+=("${path%\"*}")
done < <(security list-keychains -d user)
trap 'security list-keychains -d user -s "${old_keychains[@]}"; security delete-keychain "$keychain" >/dev/null 2>&1 || true; rm -rf "$stage"' EXIT
password="$(openssl rand -hex 24)"
security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 7200 "$keychain"
security unlock-keychain -p "$password" "$keychain"
printf '%s' "$MAC_CERTIFICATE" | base64 -D > "$stage/signing.p12"
security import "$stage/signing.p12" -k "$keychain" -P "$MAC_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$password" "$keychain"
security list-keychains -d user -s "$keychain" "${old_keychains[@]}"
codesign --force --options runtime --timestamp --sign "$MAC_SIGNING_IDENTITY" EzEQ.app
codesign --verify --strict EzEQ.app

mkdir "$stage/image"
ditto EzEQ.app "$stage/image/EzEQ.app"
ln -s /Applications "$stage/image/Applications"
dmg=EzEQ-macOS-Apple-Silicon-and-Intel.dmg
hdiutil create -ov -format UDZO -volname EzEQ -srcfolder "$stage/image" "$dmg"
codesign --force --timestamp --sign "$MAC_SIGNING_IDENTITY" "$dmg"
printf '%s' "$MAC_NOTARY_KEY" | base64 -D > "$stage/notary.p8"
xcrun notarytool submit "$dmg" --key "$stage/notary.p8" --key-id "$MAC_NOTARY_KEY_ID" \
    --issuer "$MAC_NOTARY_ISSUER_ID" --wait --timeout 40m
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
