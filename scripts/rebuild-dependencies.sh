#!/bin/bash
set -euo pipefail
export COPYFILE_DISABLE=1
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/scripts/dependency-inputs.sh"
[[ "$(uname -m)" == arm64 ]] || { echo 'Use an Apple Silicon Mac.' >&2; exit 1; }
WORK="${SIMPLE_DIALLER_DEPS_DIR:-$HOME/Library/Developer/SimpleDialler/dependencies}"
# pkg-config's space-separated flags cannot represent prefixes containing whitespace.
[[ "$WORK" != *[[:space:]]* ]] || { echo 'Dependency output path must not contain whitespace.' >&2; exit 1; }
mkdir -p "$WORK"
WORK="$(cd "$WORK" && pwd)"
DEFAULT_INPUTS="$WORK/inputs"
[[ ! -d "$ROOT_DIR/dependency-sources" ]] || DEFAULT_INPUTS="$ROOT_DIR/dependency-sources"
INPUTS="${SIMPLE_DIALLER_INPUTS_DIR:-$DEFAULT_INPUTS}"
fetch_dependency_inputs "$INPUTS"
INPUTS="$(cd "$INPUTS" && pwd)"
# Each rebuild owns a fresh directory; existing prefixes are never removed.
BUILD="$(mktemp -d "$WORK/rebuild.XXXXXX")"
SSL_PREFIX="${SIMPLE_DIALLER_SSL_PREFIX:-$BUILD/openssl}"
[[ "$SSL_PREFIX" != *[[:space:]]* ]] || { echo 'OpenSSL prefix must not contain whitespace.' >&2; exit 1; }
export MACOSX_DEPLOYMENT_TARGET=27.0
if [[ -z "${SIMPLE_DIALLER_SSL_PREFIX:-}" ]]; then
    tar -xzf "$INPUTS/openssl-4.0.3.tar.gz" -C "$BUILD"
    (
        cd "$BUILD/openssl-4.0.3"
        perl ./Configure darwin64-arm64-cc enable-ec_nistp_64_gcc_128 --prefix="$SSL_PREFIX" --openssldir="$SSL_PREFIX/etc/ssl" --libdir=lib
        make -j "${SIMPLE_DIALLER_BUILD_JOBS:-4}"
        make install_sw
    )
fi
[[ -f "$SSL_PREFIX/lib/libssl.a" && -f "$SSL_PREFIX/lib/libcrypto.a" ]] || { echo 'OpenSSL static libraries are missing.' >&2; exit 1; }
grep -Eq '^# *define OPENSSL_VERSION_STR "4\.0\.3"$' "$SSL_PREFIX/include/openssl/opensslv.h" || { echo 'Expected OpenSSL 4.0.3 headers.' >&2; exit 1; }
tar -xzf "$INPUTS/pjproject-2.17.tar.gz" -C "$BUILD"
(
    cd "$BUILD/pjproject-2.17"
    patch -p1 < "$INPUTS/pjproject-openssl4.patch"
    # Keep these settings in installed headers as well as compiler flags, so
    # consumers and all upstream make targets share the same codec configuration.
    cat > pjlib/include/pj/config_site.h <<'CONFIG'
#define PJMEDIA_HAS_G7221_CODEC 0
#define PJMEDIA_HAS_ILBC_CODEC 0
#define PJMEDIA_HAS_VIDEO 0
CONFIG
    ./configure --prefix="$BUILD/pjproject" --with-ssl="$SSL_PREFIX" \
        --disable-g7221-codec --disable-ilbc-codec --disable-video \
        --disable-sdl --disable-ffmpeg --disable-v4l2 --disable-openh264 \
        --disable-vpx --disable-libyuv --disable-opus --disable-opencore-amr \
        --disable-silk --disable-bcg729 --disable-lyra --disable-upnp
    make dep
    make
    make install
)
# Machine-readable output for the app build; paths cannot contain shell whitespace.
printf 'export SIMPLE_DIALLER_PJ_PREFIX=%q\nexport SIMPLE_DIALLER_SSL_PREFIX=%q\n' "$BUILD/pjproject" "$SSL_PREFIX" > "$WORK/dependencies.env"
printf 'Dependencies built. Run:\n  source %q\n  ./build.sh\n' "$WORK/dependencies.env"
