#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
version="$(xcrun --sdk iphoneos --show-sdk-version)"
if [[ "${version%%.*}" -lt 27 ]]; then
    echo 'Seleciona Xcode 27 ou posterior antes de compilar.' >&2
    exit 1
fi
dest="$(mktemp -d)"
trap 'rm -rf "$dest"' EXIT
app="$dest/Payload/TurnoEuro.app"
mkdir -p "$app" dist
xcrun --sdk iphoneos swiftc -target arm64-apple-ios27.0 -sdk "$sdk" -swift-version 5 \
    -parse-as-library -O -Xlinker -rpath -Xlinker /usr/lib/swift -module-name TurnoEuro App/*.swift -o "$app/TurnoEuro"
cp App/offer.js App/Info.plist App/Icon*.png "$app/"
plutil -replace CFBundleIdentifier -string pt.turnoeuro.personal "$app/Info.plist"
plutil -lint "$app/Info.plist"
codesign --force --sign - "$app"
(cd "$dest" && /usr/bin/zip -qry TurnoEuro.ipa Payload)
cp "$dest/TurnoEuro.ipa" dist/
unzip -tq dist/TurnoEuro.ipa
