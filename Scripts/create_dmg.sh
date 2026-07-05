#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

APP_NAME=${APP_NAME:-HiDPIToggle}
CONF=${1:-release}
ARCHES=${ARCHES:-arm64}

if [[ -f "$ROOT/version.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/version.env"
fi
VERSION=${MARKETING_VERSION:-1.0.0}
DMG_NAME="${APP_NAME}-v${VERSION%.*}.dmg"

APP="$ROOT/${APP_NAME}.app"
if [[ ! -d "$APP" ]]; then
  ARCHES="$ARCHES" APP_NAME="$APP_NAME" BUNDLE_ID=${BUNDLE_ID:-com.local.hidpitoggle} MENU_BAR_APP=${MENU_BAR_APP:-1} \
    "$ROOT/Scripts/package_app.sh" "$CONF"
fi

BINARY="$APP/Contents/MacOS/$APP_NAME"
ACTUAL_ARCHES=$(lipo -archs "$BINARY")
if [[ "$ACTUAL_ARCHES" != *"arm64"* ]] || [[ "$ACTUAL_ARCHES" == *"x86_64"* ]]; then
  echo "ERROR: Expected Apple Silicon (arm64) binary, got: $ACTUAL_ARCHES" >&2
  exit 1
fi

DIST="$ROOT/dist"
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

mkdir -p "$DIST"
DMG_PATH="$DIST/$DMG_NAME"
rm -f "$DMG_PATH"

hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH"

echo "Created $DMG_PATH (arm64, Apple Silicon only)"
