#!/usr/bin/env bash
# Builds Transcribation.app (Release) and packs it into build/Transcribation.dmg.
#   --bundle-codex   embed the installed `codex` binary (unmodified, keeps OpenAI's signature) in Contents/Helpers
#   --quarantine     mark the dmg as downloaded from the internet, to reproduce what another Mac's Gatekeeper sees
#   --public         a public release: built from scratch out of the committed files in a neutral folder, and
#                    signed with the self-signed "Transcribation" certificate from the Keychain (PUBLIC_IDENTITY
#                    names another), or ad hoc when there is none. Neither carries a developer name, email or team
#                    ID, and the paths the compiler records name no one's home folder. The one certificate keeps the
#                    app the same to macOS from release to release, so its permissions stay granted; ad hoc builds
#                    lose them with every update. The app is not notarized either way.
# SIGN_IDENTITY overrides the signing identity (default: "Apple Development").
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$ROOT/build"
STAGING="$BUILD/dmg-staging"
# Its own build folder: sharing build/DerivedData with Debug builds made FluidAudio's explicit-module Release
# compile fail now and then, with nothing in the output but "2 failures".
DERIVED="$BUILD/ReleaseDerivedData"
APP="$DERIVED/Build/Products/Release/Transcribation.app"
LOG="$BUILD/make-dmg.log"
DMG="$BUILD/Transcribation.dmg"
IDENTITY="${SIGN_IDENTITY:-Apple Development}"
BUNDLE_CODEX=0
QUARANTINE=0
PUBLIC=0

for argument in "$@"; do
  case "$argument" in
    --bundle-codex) BUNDLE_CODEX=1 ;;
    --quarantine) QUARANTINE=1 ;;
    --public) PUBLIC=1 ;;
    *) echo "unknown option: $argument" >&2; exit 2 ;;
  esac
done

SIGNING=()
SOURCE="$ROOT"
RUNTIME=(--options runtime)
if [ "$PUBLIC" -eq 1 ]; then
  IDENTITY="${PUBLIC_IDENTITY:-Transcribation}"
  if ! security find-identity -p codesigning | grep -qF "\"$IDENTITY\""; then
    echo "note: no \"$IDENTITY\" certificate in the Keychain; signing ad hoc" >&2
    IDENTITY="-"
  fi
  # Without a team, the hardened runtime's library validation refuses to load Sparkle ("different Team IDs"). It
  # matters only for notarization, which an ad hoc build never gets, so it is left off.
  RUNTIME=()
  SIGNING=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= TRANSCRIBATION_TEAM= ENABLE_HARDENED_RUNTIME=NO)
  # Re-signing a binary leaves the old certificate's bytes in its padding, and an earlier build's products may be
  # reused: a fresh copy with its own build folder is the only way to be sure no certificate was ever in it.
  SOURCE="/private/tmp/transcribation-public"
  rm -rf "$SOURCE"
  mkdir -p "$SOURCE"
  git -C "$ROOT" archive HEAD | tar -x -C "$SOURCE"
  DERIVED="$SOURCE/build/DerivedData"
  APP="$DERIVED/Build/Products/Release/Transcribation.app"
  # The packages' sources from an ordinary release build, so they are not downloaded again: source code only.
  if [ -d "$BUILD/ReleaseDerivedData/SourcePackages" ]; then
    mkdir -p "$DERIVED"
    cp -R "$BUILD/ReleaseDerivedData/SourcePackages" "$DERIVED/SourcePackages"
  fi
fi

cd "$SOURCE"
xcodegen generate >/dev/null
mkdir -p "$BUILD"
release_build() {
  xcodebuild -project CallRecorder.xcodeproj -scheme CallRecorder -configuration Release \
    -derivedDataPath "$DERIVED" "${SIGNING[@]+"${SIGNING[@]}"}" "$@" build >>"$LOG" 2>&1
}
: >"$LOG"
# A clean Release build sometimes loses FluidAudio's whole-module compile without a word ("Failed frontend
# command", no diagnostics). The cause is not known: the system log shows no memory kill of the compiler, and no
# crash report is left. A second try, with the other modules already built and fewer parallel jobs, gets through.
if ! release_build; then
  echo "Release build failed once; retrying with fewer parallel jobs (log: $LOG)" >&2
  if ! release_build -jobs 2; then
    echo "Release build failed; the errors (full log: $LOG):" >&2
    grep -E "error:|Failed frontend command|The following build commands failed" "$LOG" | cut -c1-300 | tail -20 >&2
    exit 1
  fi
fi

RESEAL=0
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE" ]; then
  # Sparkle's helpers keep Sparkle's own signature when Xcode embeds the framework. Sign them with ours, inside
  # out, as Sparkle's documentation describes for the hardened runtime.
  for helper in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do
    target="$SPARKLE/Versions/B/$helper"
    [ -e "$target" ] || continue
    extra=()
    [ "$helper" = "XPCServices/Downloader.xpc" ] && extra=(--preserve-metadata=entitlements)
    codesign --force "${RUNTIME[@]+"${RUNTIME[@]}"}" "${extra[@]+"${extra[@]}"}" --sign "$IDENTITY" "$target"
  done
  codesign --force "${RUNTIME[@]+"${RUNTIME[@]}"}" --sign "$IDENTITY" "$SPARKLE"
  RESEAL=1
fi

if [ "$BUNDLE_CODEX" -eq 1 ]; then
  CODEX="$(readlink -f "$(command -v codex)")"
  mkdir -p "$APP/Contents/Helpers"
  cp "$CODEX" "$APP/Contents/Helpers/codex"
  # The binary itself keeps OpenAI's signature; the app is re-sealed around it below.
  RESEAL=1
fi

if [ "$RESEAL" -eq 1 ]; then
  codesign --force "${RUNTIME[@]+"${RUNTIME[@]}"}" --sign "$IDENTITY" \
    --entitlements "$SOURCE/CallRecorder/App/CallRecorder.entitlements" "$APP"
fi

codesign --verify --deep --strict --verbose=2 "$APP"

if [ "$PUBLIC" -eq 1 ]; then
  # Nothing personal may be inside: a certificate, or the words of the ignored private-patterns list.
  patterns=("Apple (Development|Distribution): ")
  if [ -f "$ROOT/Tools/release/private-patterns.txt" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] && [ "${line#\#}" = "$line" ] && patterns+=("$line")
    done <"$ROOT/Tools/release/private-patterns.txt"
  fi
  leaks=0
  while IFS= read -r file; do
    for pattern in "${patterns[@]}"; do
      if grep -qaiE -- "$pattern" "$file"; then
        echo "personal data inside ${file#"$APP"/}" >&2
        leaks=1
      fi
    done
  done < <(find "$APP" -type f)
  [ "$leaks" -eq 0 ] || { echo "the public app is not clean; no dmg made" >&2; exit 1; }
fi

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Transcribation" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
# A disk image takes only a certificate; an ad hoc dmg stays unsigned (the app inside is signed).
[ "$IDENTITY" = "-" ] || codesign --force --sign "$IDENTITY" "$DMG"

if [ "$QUARANTINE" -eq 1 ]; then
  xattr -w com.apple.quarantine "0081;$(printf '%x' "$(date +%s)");Safari;" "$DMG"
fi

echo "dmg: $DMG ($(du -h "$DMG" | cut -f1))"
echo "--- Gatekeeper assessment of the dmg"
spctl -a -t open --context context:primary-signature -vv "$DMG" 2>&1 || true
echo "--- Gatekeeper assessment of the app"
spctl -a -t exec -vv "$APP" 2>&1 || true
