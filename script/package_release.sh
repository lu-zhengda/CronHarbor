#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CronHarbor"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
RELEASE_ZIP="$DIST_DIR/$APP_NAME-$VERSION.zip"

export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/ModuleCache"
export XDG_CACHE_HOME="$ROOT_DIR/.build/cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$XDG_CACHE_HOME" "$DIST_DIR"

"$ROOT_DIR/script/verify_menu_bar_architecture.sh"
swift test --package-path "$ROOT_DIR" --disable-sandbox
swift build --package-path "$ROOT_DIR" --disable-sandbox --configuration release --product "$APP_NAME" --arch arm64 --arch x86_64
BUILD_BINARY="$(swift build --package-path "$ROOT_DIR" --disable-sandbox --configuration release --show-bin-path --arch arm64 --arch x86_64)/$APP_NAME"

rm -rf "$RELEASE_ZIP"
"$ROOT_DIR/script/stage_app_bundle.sh" "$BUILD_BINARY" "$APP_BUNDLE" "$VERSION"

plutil -lint "$INFO_PLIST"
test "$(plutil -extract LSUIElement raw "$INFO_PLIST")" = "true"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$RELEASE_ZIP"

if [[ -n "${NOTARYTOOL_PROFILE:-}" && "${CODESIGN_IDENTITY:--}" != "-" ]]; then
  xcrun notarytool submit "$RELEASE_ZIP" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
  xcrun stapler staple "$APP_BUNDLE"
  xcrun stapler validate "$APP_BUNDLE"
  rm -f "$RELEASE_ZIP"
  ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$RELEASE_ZIP"
fi

VERIFY_DIR="$(mktemp -d "$DIST_DIR/.release-verify.XXXXXX")"
trap 'rm -rf "$VERIFY_DIR"' EXIT
ditto -x -k "$RELEASE_ZIP" "$VERIFY_DIR"
EXTRACTED_APP="$VERIFY_DIR/$APP_NAME.app"
plutil -lint "$EXTRACTED_APP/Contents/Info.plist"
test "$(plutil -extract LSUIElement raw "$EXTRACTED_APP/Contents/Info.plist")" = "true"
codesign --verify --deep --strict --verbose=2 "$EXTRACTED_APP"
lipo "$EXTRACTED_APP/Contents/MacOS/$APP_NAME" -verify_arch arm64 x86_64

shasum -a 256 "$RELEASE_ZIP"
