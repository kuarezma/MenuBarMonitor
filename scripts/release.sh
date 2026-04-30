#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/release.sh v1.0.0
#
# What it does:
# - Builds Release app
# - Creates distributable zip
# - Generates SHA256 checksum file
# - Optionally creates GitHub Release (if gh is installed/authenticated)

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <version-tag>"
  echo "Example: $0 v1.0.0"
  exit 1
fi

TAG="$1"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$PROJECT_ROOT/build/release-derived-data"
ARTIFACT_DIR="$PROJECT_ROOT/build/releases/$TAG"
APP_PATH="$DERIVED_DATA/Build/Products/Release/MenuBarMonitor.app"
ZIP_NAME="MenuBarMonitor-${TAG}.zip"
ZIP_PATH="$ARTIFACT_DIR/$ZIP_NAME"
SHA_PATH="$ARTIFACT_DIR/$ZIP_NAME.sha256.txt"

echo "==> Building Release app..."
xcodebuild \
  -project "$PROJECT_ROOT/MenuBarMonitor.xcodeproj" \
  -scheme "MenuBarMonitor" \
  -configuration Release \
  -destination "platform=macOS,arch=arm64,name=My Mac" \
  -derivedDataPath "$DERIVED_DATA" \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Build output not found: $APP_PATH"
  exit 1
fi

echo "==> Preparing artifacts..."
mkdir -p "$ARTIFACT_DIR"
rm -f "$ZIP_PATH" "$SHA_PATH"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH" > "$SHA_PATH"

echo "==> Created artifacts:"
echo "    $ZIP_PATH"
echo "    $SHA_PATH"

if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    echo "==> Creating/updating GitHub Release: $TAG"
    gh release create "$TAG" "$ZIP_PATH" "$SHA_PATH" \
      --title "$TAG" \
      --notes "MenuBarMonitor release $TAG"
  else
    echo "==> gh found but not authenticated. Skipping GitHub release upload."
    echo "   Run: gh auth login"
  fi
else
  echo "==> GitHub CLI not found. Skipping GitHub release upload."
fi

echo "Done."
