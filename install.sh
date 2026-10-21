#!/bin/bash
# Install the locally built app for this user. Never stop an app or alter account data.
set -euo pipefail
export COPYFILE_DISABLE=1
BUILD_DIR="${SIMPLE_DIALLER_BUILD_DIR:-$HOME/Library/Developer/SimpleDialler/build}"
SOURCE_APP="$BUILD_DIR/Simple Dialler.app"
APPS_DIR="$HOME/Applications"
DEST_APP="$APPS_DIR/Simple Dialler.app"
BUNDLE_ID="com.andybridson.simple-dialler"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

fail() { printf '%s\n' "$*" >&2; exit 1; }
require_stopped() {
    if /usr/bin/pgrep -x 'Simple Dialler' >/dev/null; then
        fail 'Quit Simple Dialler first, after ending any call, then run ./install.sh again.'
    fi
}
check_bundle() {
    [[ -d "$1" && ! -L "$1" ]] || fail "Expected an app directory: $1"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist")" == "$BUNDLE_ID" ]] || fail "Unexpected app identity: $1"
    /usr/bin/codesign --verify --deep --strict "$1"
}
require_stopped
check_bundle "$SOURCE_APP"
mkdir -p "$APPS_DIR"
[[ ! -L "$DEST_APP" ]] || fail "Refusing to replace a symbolic link: $DEST_APP"
if [[ -e "$DEST_APP" ]]; then
    # Identity check protects an unrelated bundle at this destination. Old ad-hoc
    # signatures can be invalidated by Finder metadata, so only the new copy is verified.
    [[ -d "$DEST_APP" && "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST_APP/Contents/Info.plist")" == "$BUNDLE_ID" ]] || fail "Unexpected existing app: $DEST_APP"
fi
STAGING_DIR="$(mktemp -d "$APPS_DIR/.simple-dialler-install.XXXXXX")"
REPLACED=0
INSTALLED=0
cleanup() {
    local result=$?
    if [[ "$result" != 0 && "$REPLACED" == 1 ]]; then
        # Only these validated app bundles are moved; preferences and Keychain stay untouched.
        if [[ "$INSTALLED" == 1 ]] && ! mv "$DEST_APP" "$STAGING_DIR/failed.app"; then
            printf '%s\n' "Rollback needs manual recovery; preserved files at: $STAGING_DIR" >&2
            exit "$result"
        fi
        if [[ -d "$STAGING_DIR/previous.app" ]] && ! mv "$STAGING_DIR/previous.app" "$DEST_APP"; then
            printf '%s\n' "Rollback needs manual recovery; previous app preserved at: $STAGING_DIR/previous.app" >&2
            exit "$result"
        fi
    fi
    rm -rf "$STAGING_DIR"
    exit "$result"
}
trap cleanup EXIT
/usr/bin/ditto --noextattr --norsrc "$SOURCE_APP" "$STAGING_DIR/Simple Dialler.app"
check_bundle "$STAGING_DIR/Simple Dialler.app"
require_stopped
if [[ -e "$DEST_APP" ]]; then mv "$DEST_APP" "$STAGING_DIR/previous.app"; fi
REPLACED=1
mv "$STAGING_DIR/Simple Dialler.app" "$DEST_APP"
INSTALLED=1
check_bundle "$DEST_APP"
touch "$DEST_APP"
"$LSREGISTER" -f "$DEST_APP"
printf '%s\n' "Installed and signature verified: $DEST_APP" 'Open Simple Dialler when ready. No app was launched.'
