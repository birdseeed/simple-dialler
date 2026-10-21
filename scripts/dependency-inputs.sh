#!/bin/bash
# Shared pinned inputs. Source from release/rebuild scripts with set -euo pipefail.
fetch_dependency_inputs() {
    mkdir -p "$1"
    fetch_verified "$1/pjproject-2.17.tar.gz" 065fe06c06788d97c35f563796d59f00ce52fe9558a52d7b490a042a966facce 'https://github.com/pjsip/pjproject/archive/refs/tags/2.17.tar.gz'
    fetch_verified "$1/pjproject-openssl4.patch" 6958040fc0b0502381aa1514cacf1d947ea1a6104b2da388e1c99870f67bc998 'https://github.com/pjsip/pjproject/commit/3923fad2e4f6f3403c3d6f1176b113c1c1b91066.patch?full_index=1'
    fetch_verified "$1/openssl-4.0.3.tar.gz" 325b5c806167c13b40b1ffeadfe0248197c00eccc4cf123ec1e28d2d2fd216d9 'https://github.com/openssl/openssl/releases/download/openssl-4.0.3/openssl-4.0.3.tar.gz'
}
fetch_verified() {
    local destination="$1" expected="$2" url="$3" actual
    if [[ ! -f "$destination" ]]; then
        curl --fail --location --retry 2 "$url" -o "$destination.partial"
        mv "$destination.partial" "$destination"
    fi
    actual="$(shasum -a 256 "$destination" | awk '{print $1}')"
    [[ "$actual" == "$expected" ]] || { printf 'Checksum mismatch: %s\n' "$destination" >&2; return 1; }
}
