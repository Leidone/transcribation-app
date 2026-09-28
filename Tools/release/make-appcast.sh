#!/usr/bin/env bash
# Prepares an update for publishing, without uploading anything: copies build/Transcribation.dmg into the updates
# folder as Transcribation-<version>.dmg and (re)writes appcast.xml there, signed with the EdDSA private key that
# Sparkle's generate_keys keeps in the login Keychain. Upload the folder's contents to the public address yourself.
#   DOWNLOAD_URL_PREFIX  the public address the dmg files will be served from (required), e.g. https://example.org/transcribation/
#   UPDATES_DIR          the folder with every published dmg and appcast.xml (default: build/updates)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DERIVED="$ROOT/build/ReleaseDerivedData"
APP="$DERIVED/Build/Products/Release/Transcribation.app"
DMG="$ROOT/build/Transcribation.dmg"
TOOLS="$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin"
UPDATES="${UPDATES_DIR:-$ROOT/build/updates}"
: "${DOWNLOAD_URL_PREFIX:?set DOWNLOAD_URL_PREFIX to the public address the dmg files will be served from}"

[ -f "$DMG" ] || { echo "no $DMG: run Tools/dmg/make-dmg.sh first" >&2; exit 1; }
[ -x "$TOOLS/generate_appcast" ] || { echo "Sparkle's tools are not in $TOOLS: run Tools/dmg/make-dmg.sh first" >&2; exit 1; }

FEED="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$APP/Contents/Info.plist" 2>/dev/null || true)"
KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist" 2>/dev/null || true)"
if [ -z "$FEED" ] || [ -z "$KEY" ]; then
  echo "this build has no UPDATE_FEED_URL or SPARKLE_PUBLIC_KEY (project.yml): it would never look for this update" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
mkdir -p "$UPDATES"
cp "$DMG" "$UPDATES/Transcribation-$VERSION.dmg"
"$TOOLS/generate_appcast" --download-url-prefix "$DOWNLOAD_URL_PREFIX" "$UPDATES"

echo "ready: $UPDATES (appcast.xml and Transcribation-$VERSION.dmg)"
echo "the app reads the feed from: $FEED"
