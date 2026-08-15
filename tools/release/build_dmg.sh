#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT="$ROOT/app/MactivateApp.xcodeproj"
SCHEME="MactivateApp"
BUILD_ROOT="${BUILD_ROOT:-$ROOT/build/release}"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
STAGING="$BUILD_ROOT/staging"
DIST="$BUILD_ROOT/dist"

project_version="$(
    xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Release \
        -showBuildSettings |
        awk '$1 == "MARKETING_VERSION" && $2 == "=" { print $3; exit }'
)"

version="${1:-$project_version}"
version="${version#v}"

if [[ -z "$project_version" ]]; then
    echo "Could not read MARKETING_VERSION from the Xcode project." >&2
    exit 1
fi

if [[ "$version" != "$project_version" ]]; then
    echo "Release version $version does not match MARKETING_VERSION $project_version." >&2
    exit 1
fi

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.]+)?$ ]]; then
    echo "Version must be semantic, for example 1.0.0." >&2
    exit 1
fi

rm -rf "$DERIVED_DATA" "$STAGING"
mkdir -p "$STAGING" "$DIST"

xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    ARCHS=arm64 \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGNING_REQUIRED=YES \
    clean build

app="$DERIVED_DATA/Build/Products/Release/Mactivate.app"
if [[ ! -d "$app" ]]; then
    echo "Release build did not produce $app." >&2
    exit 1
fi

codesign --verify --deep --strict "$app"
if ! lipo "$app/Contents/MacOS/Mactivate" -verify_arch arm64; then
    echo "Release executable does not contain the required arm64 architecture." >&2
    exit 1
fi

ditto "$app" "$STAGING/Mactivate.app"
ln -s /Applications "$STAGING/Applications"

dmg="$DIST/Mactivate-$version.dmg"
rm -f "$dmg" "$dmg.sha256"

hdiutil create \
    -volname "Mactivate $version" \
    -srcfolder "$STAGING" \
    -format UDZO \
    -ov \
    "$dmg"

shasum -a 256 "$dmg" > "$dmg.sha256"

echo "Created $dmg"
echo "Checksum: $(awk '{ print $1 }' "$dmg.sha256")"
