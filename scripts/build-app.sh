#!/bin/bash
# Builds "Switch Launcher.app" into ./build.
#   --install   also copy it to /Applications
#   --dist      also create dist/Switch-Launcher-<version>.zip and its .sha256
set -euo pipefail
cd "$(dirname "$0")/.."

INSTALL=0
DIST=0
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=1 ;;
        --dist) DIST=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo dev)"

swift build -c release
BIN="$(swift build -c release --show-bin-path)"
APP="build/Switch Launcher.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/SwitchLauncher" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :SLGitCommit string $COMMIT" "$APP/Contents/Info.plist"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
swift scripts/make-icon.swift "$WORK/icon.png"
ICONSET="$WORK/AppIcon.iconset"
mkdir "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s "$WORK/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$WORK/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature, but with a designated requirement on the bundle id only, so macOS privacy
# answers (e.g. access to Documents) are kept across rebuilds instead of being asked again.
codesign --force --sign - --requirements '=designated => identifier "dev.vinicius.switchlauncher"' "$APP"
codesign --verify "$APP"
echo "Built $APP ($VERSION build $BUILD_NUMBER, $COMMIT)"

if [[ $DIST == 1 ]]; then
    mkdir -p dist
    ZIP="dist/Switch-Launcher-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    (cd dist && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
    echo "Packaged $ZIP"
fi

if [[ $INSTALL == 1 ]]; then
    rm -rf "/Applications/Switch Launcher.app"
    cp -R "$APP" /Applications/
    echo "Installed to /Applications"
fi
