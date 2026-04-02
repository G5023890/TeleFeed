#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

APP_NAME="${APP_NAME:-TeleFeed}"
BUNDLE_ID="${BUNDLE_ID:-com.codex.TeleFeed}"
SCHEME="${SCHEME:-TeleFeed}"
CONFIGURATION="${CONFIGURATION:-Release}"
INSTALL_DIR="${INSTALL_DIR:-/Applications/${APP_NAME}.app}"
LEGACY_APP_NAME="${LEGACY_APP_NAME:-TeleFeed}"
LEGACY_INSTALL_DIR="${LEGACY_INSTALL_DIR:-/Applications/${LEGACY_APP_NAME}.app}"
LAUNCH_AFTER_INSTALL="${LAUNCH_AFTER_INSTALL:-1}"
DIST_DIR="${DIST_DIR:-$PROJECT_DIR/dist}"
APP_DIST_PATH="${APP_DIST_PATH:-$DIST_DIR/${APP_NAME}.app}"
DERIVED_DATA_ROOT="${DERIVED_DATA_ROOT:-$(mktemp -d "${TMPDIR:-/tmp}/telega-derived.XXXXXX")}"
STAGING_ROOT="${STAGING_ROOT:-$(mktemp -d "${TMPDIR:-/tmp}/telega-stage.XXXXXX")}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
SKIP_SIGN="${SKIP_SIGN:-0}"
RESOLVED_SIGN_IDENTITY=""
TEAM_ID="${TEAM_ID:-53YUZ2U35Z}"

cleanup() {
  rm -rf "$DERIVED_DATA_ROOT" "$STAGING_ROOT"
}
trap cleanup EXIT

log() {
  echo "[build] $*"
}

launch_app() {
  local app_bin="$INSTALL_DIR/Contents/MacOS/$APP_NAME"

  if [[ ! -x "$app_bin" ]]; then
    log "Launch skipped: executable not found: $app_bin"
    return 1
  fi

  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  sleep 0.3

  if open -a "$INSTALL_DIR" >/dev/null 2>&1; then
    sleep 1
  fi

  if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    log "open failed or app not running; launching binary directly"
    nohup "$app_bin" >/tmp/telega.run.log 2>&1 &
    sleep 1
  fi

  if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    log "App is running"
    return 0
  fi

  log "App failed to start; see /tmp/telega.run.log"
  return 1
}

resolve_sign_identity() {
  if [[ "$SKIP_SIGN" == "1" ]]; then
    return 0
  fi

  if [[ -n "$SIGN_IDENTITY" ]]; then
    RESOLVED_SIGN_IDENTITY="$SIGN_IDENTITY"
    return 0
  fi

  local identities_output first_available
  identities_output="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  first_available="$(printf '%s\n' "$identities_output" | awk -F '"' '/Apple Development: /{print $2; exit}')"
  if [[ -n "$first_available" ]]; then
    RESOLVED_SIGN_IDENTITY="$first_available"
  fi
}

sign_bundle() {
  local bundle="$1"

  xattr -cr "$bundle" || true
  chmod -R u+rwX "$bundle" || true

  if [[ "$SKIP_SIGN" == "1" ]]; then
    log "Skipping codesign (SKIP_SIGN=1)"
    return 0
  fi

  if [[ -n "$RESOLVED_SIGN_IDENTITY" ]]; then
    log "Signing with identity: $RESOLVED_SIGN_IDENTITY"
    codesign --force --deep --options runtime --sign "$RESOLVED_SIGN_IDENTITY" "$bundle"
  else
    log "No Apple Development identity found; using ad-hoc signature"
    codesign --force --deep --sign - "$bundle"
  fi

  codesign --verify --deep --strict "$bundle"
}

resolve_sign_identity
if [[ -n "$RESOLVED_SIGN_IDENTITY" ]]; then
  log "Resolved signing identity: $RESOLVED_SIGN_IDENTITY"
fi

mkdir -p "$DIST_DIR"

log "Generating Xcode project"
xcodegen generate

log "Building into temporary DerivedData outside Documents"
xcodebuild \
  -project TeleFeed.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination platform=macOS \
  -derivedDataPath "$DERIVED_DATA_ROOT" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  build

BUILT_APP="$DERIVED_DATA_ROOT/Build/Products/$CONFIGURATION/${APP_NAME}.app"
if [[ ! -d "$BUILT_APP" ]]; then
  echo "Built app not found: $BUILT_APP" >&2
  exit 1
fi

APP_STAGE="$STAGING_ROOT/${APP_NAME}.app"
rm -rf "$APP_STAGE" "$APP_DIST_PATH" "$INSTALL_DIR"
if [[ "$LEGACY_INSTALL_DIR" != "$INSTALL_DIR" ]]; then
  rm -rf "$LEGACY_INSTALL_DIR"
fi
/usr/bin/ditto --norsrc "$BUILT_APP" "$APP_STAGE"
/usr/bin/ditto --norsrc "$APP_STAGE" "$APP_DIST_PATH"
/usr/bin/ditto --norsrc "$APP_STAGE" "$INSTALL_DIR"

mkdir -p "$INSTALL_DIR/Contents/Resources/Assets/Icons"
if [[ -f "$PROJECT_DIR/Resources/Assets/Icons/MenuBarIcon.png" ]]; then
  /usr/bin/ditto --norsrc "$PROJECT_DIR/Resources/Assets/Icons/MenuBarIcon.png" "$INSTALL_DIR/Contents/Resources/Assets/Icons/MenuBarIcon.png"
fi
if [[ -f "$PROJECT_DIR/Resources/Assets/Icons/TeleFeed.icns" ]]; then
  /usr/bin/ditto --norsrc "$PROJECT_DIR/Resources/Assets/Icons/TeleFeed.icns" "$INSTALL_DIR/Contents/Resources/TeleFeed.icns"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$INSTALL_DIR/Contents/Info.plist" >/dev/null
if /usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$INSTALL_DIR/Contents/Info.plist" >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile TeleFeed.icns" "$INSTALL_DIR/Contents/Info.plist" >/dev/null
else
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string TeleFeed.icns" "$INSTALL_DIR/Contents/Info.plist" >/dev/null
fi

sign_bundle "$INSTALL_DIR"

log "Installed: $INSTALL_DIR"
codesign -dv --verbose=4 "$INSTALL_DIR" 2>&1 | sed -n '1,40p'
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INSTALL_DIR/Contents/Info.plist"

if [[ "$LAUNCH_AFTER_INSTALL" == "1" ]]; then
  launch_app
fi
