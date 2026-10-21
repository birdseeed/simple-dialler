#!/bin/bash
# Build only committed, clean source; publish the resulting ZIP and source archive together.
set -euo pipefail
export COPYFILE_DISABLE=1
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
[[ -z "$(git status --porcelain)" ]] || { echo 'Commit or remove working-tree changes before packaging a release.' >&2; exit 1; }
[[ "$(uname -m)" == arm64 ]] || { echo 'Release packaging requires Apple Silicon.' >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Expected a three-part release version.' >&2; exit 1; }
COMMIT="$(git rev-parse HEAD)"
OUTPUT="${SIMPLE_DIALLER_RELEASE_DIR:-$HOME/Library/Developer/SimpleDialler/releases/$VERSION}"
mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"
case "$OUTPUT/" in "$ROOT_DIR/"*) echo 'Release output must be outside the repository.' >&2; exit 1 ;; esac
STAGE="$(mktemp -d "$OUTPUT/staging.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
SOURCE_NAME="Simple-Dialler-$VERSION-source"
SOURCE="$STAGE/$SOURCE_NAME"
mkdir -p "$SOURCE"
git archive "$COMMIT" | tar -xf - -C "$SOURCE"
source "$SOURCE/scripts/dependency-inputs.sh"
fetch_dependency_inputs "$OUTPUT/inputs"
mkdir -p "$SOURCE/dependency-sources"
cp "$OUTPUT/inputs/pjproject-2.17.tar.gz" "$OUTPUT/inputs/pjproject-openssl4.patch" "$OUTPUT/inputs/openssl-4.0.3.tar.gz" "$SOURCE/dependency-sources/"
printf 'Simple Dialler %s\nApp source commit: %s\n' "$VERSION" "$COMMIT" > "$SOURCE/RELEASE-SOURCE.txt"
# Always produce the release PJSIP configuration from the archived recipe. By default
# OpenSSL is rebuilt too; a pinned local OpenSSL prefix can be selected explicitly.
SIMPLE_DIALLER_DEPS_DIR="$STAGE/dependencies" SIMPLE_DIALLER_INPUTS_DIR="$SOURCE/dependency-sources" "$SOURCE/scripts/rebuild-dependencies.sh"
source "$STAGE/dependencies/dependencies.env"
# Check the actual libraries selected by the generated package configuration.
if grep -E '(-l(ilbccodec|g7221codec|yuv|opus|avcodec|SDL)|-L/opt/homebrew/lib)' "$SIMPLE_DIALLER_PJ_PREFIX/lib/pkgconfig/libpjproject.pc"; then
    echo 'Unexpected optional dependency in release PJSIP configuration.' >&2; exit 1
fi
SIMPLE_DIALLER_BUILD_DIR="$STAGE/build" "$SOURCE/build.sh"
APP="$STAGE/build/Simple Dialler.app"
EXECUTABLE="$APP/Contents/MacOS/Simple Dialler"
[[ "$(lipo -archs "$EXECUTABLE")" == arm64 ]] || { echo 'Unexpected app architecture.' >&2; exit 1; }
if nm "$EXECUTABLE" | grep -E '(_pjmedia_codec_(g7221|ilbc)_init|_iLBC_(encode|decode))$'; then
    echo 'Excluded codec found in release executable.' >&2; exit 1
fi
# Embed exact build provenance alongside the source and licences before signing.
{
    printf '\nDependency inputs (SHA-256):\n'
    (cd "$SOURCE/dependency-sources" && shasum -a 256 *)
    printf '\nLinked OpenSSL static libraries (SHA-256):\n'
    (cd "$SIMPLE_DIALLER_SSL_PREFIX/lib" && shasum -a 256 libssl.a libcrypto.a)
    printf '\nBuild host OS: '
    sw_vers -productVersion
    printf '\nCompiler:\n'
    swiftc --version
} >> "$SOURCE/RELEASE-SOURCE.txt"
cp "$SOURCE/RELEASE-SOURCE.txt" "$APP/Contents/Resources/RELEASE-SOURCE.txt"
xattr -cr "$APP"
codesign --force --sign - --identifier com.andybridson.simple-dialler "$APP"
codesign --verify --deep --strict "$APP"
ZIP="Simple-Dialler-$VERSION-macOS-arm64.zip"
TGZ="Simple-Dialler-$VERSION-source.tar.gz"
ditto -c -k --norsrc --keepParent "$APP" "$STAGE/$ZIP"
mkdir "$STAGE/extracted"
ditto -x -k "$STAGE/$ZIP" "$STAGE/extracted"
codesign --verify --deep --strict "$STAGE/extracted/Simple Dialler.app"
# Build scripts generate icon resources deterministically; archive them with all
# app source, notices, exact dependency inputs and both dependency build recipes.
tar -czf "$STAGE/$TGZ" -C "$STAGE" "$SOURCE_NAME"
(
    cd "$STAGE"
    shasum -a 256 "$ZIP" "$TGZ" > SHA256SUMS
)
# Do not silently replace a previously prepared release.
for name in "$ZIP" "$TGZ" SHA256SUMS; do
    [[ ! -e "$OUTPUT/$name" ]] || { printf 'Output already exists: %s\n' "$OUTPUT/$name" >&2; exit 1; }
done
for name in "$ZIP" "$TGZ" SHA256SUMS; do mv "$STAGE/$name" "$OUTPUT/$name"; done
printf 'Verified release assets for commit %s:\n%s\n%s\n%s\n' "$COMMIT" "$OUTPUT/$ZIP" "$OUTPUT/$TGZ" "$OUTPUT/SHA256SUMS"
