#!/bin/bash
# Builds "Switch Launcher.app" into ./build.
#   --install   also copy it to /Applications
#   --dist      also create dist/Switch-Launcher-<version>.zip and its .sha256
#
# Signing (optional, see docs/SIGNING.md):
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"   sign for distribution (hardened runtime)
#   NOTARY_PROFILE=switch-launcher                             with --dist: notarize and staple
# Without SIGN_IDENTITY the app is ad-hoc signed, which macOS warns about when downloaded.
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

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    # Developer ID: hardened runtime and a secure timestamp, both required for notarization.
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
    # Ad-hoc signature, but with a designated requirement on the bundle id only, so macOS privacy
    # answers (e.g. access to Documents) are kept across rebuilds instead of being asked again.
    codesign --force --sign - --requirements '=designated => identifier "dev.vinicius.switchlauncher"' "$APP"
fi
codesign --verify --strict "$APP"
echo "Built $APP ($VERSION build $BUILD_NUMBER, $COMMIT, signed by ${SIGN_IDENTITY:-ad-hoc})"

package() {
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
}

if [[ $DIST == 1 ]]; then
    mkdir -p dist
    ZIP="dist/Switch-Launcher-$VERSION.zip"
    package
    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
        [[ -n "${SIGN_IDENTITY:-}" ]] || { echo "NOTARY_PROFILE needs SIGN_IDENTITY" >&2; exit 2; }
        echo "Notarizing (this usually takes a few minutes)…"
        xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$APP"
        package   # re-zip so the download carries the stapled ticket
        spctl --assess --type execute --verbose "$APP"
    fi
    (cd dist && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
    echo "Packaged $ZIP"
fi

if [[ $INSTALL == 1 ]]; then
    rm -rf "/Applications/Switch Launcher.app"
    cp -R "$APP" /Applications/
    echo "Installed to /Applications"
fi
