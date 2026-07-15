#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="CronHarbor"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"

export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/ModuleCache"
export XDG_CACHE_HOME="$ROOT_DIR/.build/cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$XDG_CACHE_HOME"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build --package-path "$ROOT_DIR" --disable-sandbox --product "$APP_NAME"
BUILD_BINARY="$(swift build --package-path "$ROOT_DIR" --disable-sandbox --show-bin-path)/$APP_NAME"

CODESIGN_IDENTITY=- "$ROOT_DIR/script/stage_app_bundle.sh" "$BUILD_BINARY" "$APP_BUNDLE" "$VERSION"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.luzhengda.CronHarbor"'
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
