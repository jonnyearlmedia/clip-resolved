#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="ClipResolved"
BUNDLE_ID="media.jonnyearl.clip-resolved"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/Clip Resolved.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
DEFAULT_SIGNING_IDENTITY="Apple Development: brownjonnybravo@icloud.com (GY9P5X8TYS)"
INSTALL_APP_BUNDLE="/Applications/Clip Resolved.app"
RUNTIME_ROOT="$HOME/Library/Application Support/Clip Resolved/Runtime"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

cp "$ROOT_DIR/Resources/Info.plist" "$INFO_PLIST"

# A stable Apple Development signature is important here, even for a local-only
# build. macOS privacy grants are tied to the app's designated requirement. An
# ad-hoc signature changes on every rebuild, which makes Documents and removable
# volume access look like it is coming from a brand-new app each time.
SIGNING_IDENTITY="${CLIP_RESOLVED_SIGNING_IDENTITY:-$DEFAULT_SIGNING_IDENTITY}"
if ! /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "\"$SIGNING_IDENTITY\""; then
  echo "error: Clip Resolved needs the stable signing identity '$SIGNING_IDENTITY'." >&2
  echo "Set CLIP_RESOLVED_SIGNING_IDENTITY to another installed Apple Development identity." >&2
  exit 1
fi
/usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --identifier "$BUNDLE_ID" --timestamp=none "$APP_BUNDLE" >/dev/null

open_app() { CLIP_RESOLVED_REPO="$ROOT_DIR" /usr/bin/open -n "$APP_BUNDLE"; }

install_runtime() {
  echo "Installing the local Clip Resolved runtime outside Documents..."
  mkdir -p \
    "$RUNTIME_ROOT" \
    "$RUNTIME_ROOT/external" \
    "$RUNTIME_ROOT/external/VideoHighlighter" \
    "$RUNTIME_ROOT/external/kontentmanager"
  /usr/bin/ditto "$ROOT_DIR/.venv" "$RUNTIME_ROOT/.venv"
  /usr/bin/ditto "$ROOT_DIR/src" "$RUNTIME_ROOT/src"
  /usr/bin/ditto "$ROOT_DIR/bridges" "$RUNTIME_ROOT/bridges"
  /usr/bin/ditto "$ROOT_DIR/external/SynthCut" "$RUNTIME_ROOT/external/SynthCut"
  /usr/bin/ditto "$ROOT_DIR/external/VideoHighlighter/modules" "$RUNTIME_ROOT/external/VideoHighlighter/modules"
  /usr/bin/ditto "$ROOT_DIR/external/kontentmanager/backend" "$RUNTIME_ROOT/external/kontentmanager/backend"
  /usr/bin/ditto "$ROOT_DIR/external/davinci-resolve-mcp" "$RUNTIME_ROOT/external/davinci-resolve-mcp"
  cp "$ROOT_DIR/pyproject.toml" "$RUNTIME_ROOT/pyproject.toml"
}

install_app() {
  install_runtime
  echo "Installing Clip Resolved in /Applications..."
  /usr/bin/ditto "$APP_BUNDLE" "$INSTALL_APP_BUNDLE"
  /usr/bin/codesign --verify --deep --strict "$INSTALL_APP_BUNDLE"
  /usr/bin/open -n "$INSTALL_APP_BUNDLE"
}

case "$MODE" in
  run) open_app ;;
  --install|install) install_app ;;
  --debug|debug) CLIP_RESOLVED_REPO="$ROOT_DIR" lldb -- "$APP_BINARY" ;;
  --logs|logs) open_app; /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\"" ;;
  --telemetry|telemetry) open_app; /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\"" ;;
  --verify|verify) open_app; sleep 1; pgrep -x "$APP_NAME" >/dev/null ;;
  *) echo "usage: $0 [run|--install|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac
