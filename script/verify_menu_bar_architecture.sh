#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_SOURCE="$ROOT_DIR/Sources/CronHarbor/App/CronHarborApp.swift"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"

grep -Eq '^[[:space:]]*MenuBarExtra[[:space:]]*(\(|\{)' "$APP_SOURCE" || {
  echo "CronHarborApp must declare MenuBarExtra as its primary scene" >&2
  exit 1
}

if grep -Eq '^[[:space:]]*(Window|WindowGroup)[[:space:]]*(\(|\{)' "$APP_SOURCE"; then
  echo "CronHarborApp must not declare a normal window scene" >&2
  exit 1
fi

if [[ "$(plutil -extract LSUIElement raw "$INFO_PLIST")" != "true" ]]; then
  echo "CronHarbor must remain an LSUIElement menu bar accessory" >&2
  exit 1
fi

echo "Verified menu-bar-only app architecture"
