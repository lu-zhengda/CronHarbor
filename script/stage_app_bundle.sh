#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <executable> <destination.app> <version>" >&2
  exit 2
fi

APP_NAME="CronHarbor"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_BINARY="$1"
APP_BUNDLE="$2"
VERSION="$3"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
SIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

[[ -x "$SOURCE_BINARY" ]] || {
  echo "executable not found: $SOURCE_BINARY" >&2
  exit 1
}

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$SOURCE_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$ROOT_DIR/Resources/Info.plist" "$INFO_PLIST"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$INFO_PLIST"
plutil -lint "$INFO_PLIST" >/dev/null

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - --timestamp=none "$APP_BUNDLE" >/dev/null
else
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
fi

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
