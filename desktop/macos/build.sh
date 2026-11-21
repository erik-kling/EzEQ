#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
dist="$(cd .. && pwd)/dist"
app="$dist/EzEQ.app"
sdk="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$app/Contents/MacOS"
cp Info.plist "$app/Contents/"
for arch in arm64 x86_64; do
    target="$arch-apple-macosx14.2"
    for source in DSP AudioIO; do
        xcrun clang -target "$target" -isysroot "$sdk" -std=c11 -O2 -Wall -Wextra -Werror \
            -c "$source.c" -o "$stage/$source-$arch.o"
    done
    xcrun swiftc -target "$target" -sdk "$sdk" -swift-version 5 -O -parse-as-library \
        -import-objc-header AudioIO.h EzEQ.swift AudioRoute.swift \
        "$stage/DSP-$arch.o" "$stage/AudioIO-$arch.o" \
        -framework CoreAudio -o "$stage/EzEQ-$arch"
done
lipo -create "$stage/EzEQ-arm64" "$stage/EzEQ-x86_64" -output "$app/Contents/MacOS/EzEQ"
lipo -verify_arch arm64 x86_64 "$app/Contents/MacOS/EzEQ"
plutil -lint "$app/Contents/Info.plist"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
