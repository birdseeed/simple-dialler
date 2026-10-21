#!/bin/bash
set -euo pipefail
export COPYFILE_DISABLE=1
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

PJ_PREFIX="$(brew --prefix pjproject)"
SSL_PREFIX="$(brew --prefix openssl@4)"
PC_FILE="$PJ_PREFIX/lib/pkgconfig/libpjproject.pc"
read -r -a CFLAGS <<< "$(sed -n 's/^Cflags: //p' "$PC_FILE")"
read -r -a LINK_FLAGS <<< "$(sed -n 's/^Libs: //p' "$PC_FILE") $(sed -n 's/^Libs.private: //p' "$PC_FILE")"
# Bundle dependencies into the executable. The finished app needs no Homebrew installation.
for index in "${!LINK_FLAGS[@]}"; do
    case "${LINK_FLAGS[$index]}" in
        -lssl) LINK_FLAGS[$index]="$SSL_PREFIX/lib/libssl.a" ;;
        -lcrypto) LINK_FLAGS[$index]="$SSL_PREFIX/lib/libcrypto.a" ;;
    esac
done
# Documents may be managed by iCloud, which adds FinderInfo after signing.
# Keep all generated binaries in a local developer build directory.
BUILD_DIR="${SIMPLE_DIALLER_BUILD_DIR:-$HOME/Library/Developer/SimpleDialler/build}"
mkdir -p "$BUILD_DIR"
clang -std=c11 -O2 -Wall -Wextra -Werror "${CFLAGS[@]}" -ISources -c Sources/SIPBridge.c -o "$BUILD_DIR/SIPBridge.o"
swiftc -swift-version 5 Sources/DialRules.swift Tests/main.swift -o "$BUILD_DIR/dial-tests"
"$BUILD_DIR/dial-tests"
clang -std=c11 -O2 -Wall -Wextra -Werror -ISources Tests/bridge.c "$BUILD_DIR/SIPBridge.o" "${LINK_FLAGS[@]}" -lc++ -o "$BUILD_DIR/bridge-tests"
"$BUILD_DIR/bridge-tests"
clang -std=c11 -O2 -Wall -Wextra -Werror "${CFLAGS[@]}" -ISources Tests/call-race.c "${LINK_FLAGS[@]}" -lc++ -o "$BUILD_DIR/call-race-tests"
"$BUILD_DIR/call-race-tests"

APP="$BUILD_DIR/Simple Dialler.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Licenses"
swiftc -swift-version 5 -O -import-objc-header Sources/SIPBridge.h Sources/DialRules.swift Sources/AccountStore.swift Sources/main.swift "$BUILD_DIR/SIPBridge.o" "${LINK_FLAGS[@]}" -lc++ -framework Security -o "$APP/Contents/MacOS/Simple Dialler"
cp Info.plist "$APP/Contents/Info.plist"
"$ROOT_DIR/scripts/build-icon.sh"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Licenses/* "$APP/Contents/Resources/Licenses/"
xattr -cr "$APP"
codesign --force --sign - --identifier com.andybridson.simple-dialler "$APP"
codesign --verify --deep --strict "$APP"
if otool -L "$APP/Contents/MacOS/Simple Dialler" | tail -n +2 | awk '{print $1}' | grep -Ev '^(/System/Library/|/usr/lib/)' ; then
    printf '%s\n' 'Unexpected non-system dependency; app is not self-contained.' >&2
    exit 1
fi
printf '%s\n' "Built and verified: $APP"
