#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <homebrew-prefix>" >&2
  exit 2
fi

APP_NAME="CronHarbor"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_PREFIX="$1"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/ModuleCache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$CLANG_MODULE_CACHE_PATH}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$ROOT_DIR/.build/cache}"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$XDG_CACHE_HOME"

swift build \
  --package-path "$ROOT_DIR" \
  --disable-sandbox \
  --configuration release \
  --product "$APP_NAME"
BUILD_BINARY="$(swift build --package-path "$ROOT_DIR" --disable-sandbox --configuration release --show-bin-path)/$APP_NAME"

CODESIGN_IDENTITY=- "$ROOT_DIR/script/stage_app_bundle.sh" \
  "$BUILD_BINARY" \
  "$INSTALL_PREFIX/$APP_NAME.app" \
  "$VERSION"
