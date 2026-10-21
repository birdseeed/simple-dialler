# Rebuilding and packaging a release

Use an Apple Silicon Mac with macOS 27 or later and Xcode Command Line Tools. Build products and dependency downloads belong outside the Git repository. No Apple Developer account is required: the result is ad-hoc signed and is not notarised.

## Rebuild from the complete release source archive

Download `Simple-Dialler-VERSION-source.tar.gz` and `SHA256SUMS` from the same GitHub release as the app. Verify its SHA-256 checksum, extract it, then run from the extracted source directory:

```sh
./scripts/rebuild-dependencies.sh
source "$HOME/Library/Developer/SimpleDialler/dependencies/dependencies.env"
./build.sh
```

The source archive contains both complete dependency tarballs and the PJSIP patch in `dependency-sources/`, so the rebuild does not need a dependency download. In a Git checkout, the script downloads the same pinned inputs to its external working directory. Every input is checked against the SHA-256 pin in `scripts/dependency-inputs.sh` before use. The script builds OpenSSL 4.0.3, then PJSIP 2.17 with the OpenSSL 4 backport and `--disable-g7221-codec --disable-ilbc-codec`. It retains standard G.711 PCMU/PCMA. The recipe also disables video, libyuv and optional external codec/device libraries so installed Homebrew packages cannot silently add dependencies. The exact configure flags and persistent `config_site.h` definitions are in the script.

The dependency script creates a fresh build/prefix directory each time and records it in `dependencies.env`. Set `SIMPLE_DIALLER_DEPS_DIR` to choose another output directory (without whitespace), or `SIMPLE_DIALLER_BUILD_JOBS` to limit OpenSSL build concurrency. PJSIP builds serially, matching its Homebrew recipe. To reuse the pinned Homebrew OpenSSL libraries, set `SIMPLE_DIALLER_SSL_PREFIX=/opt/homebrew/Cellar/openssl@4/4.0.3` when running the dependency script. The original installed Homebrew formulae are included in `scripts/dependency-recipes/` as recipe evidence; the PJSIP release recipe deliberately disables the two additional codecs.

To modify and relink the libraries, edit the extracted dependency sources in the script's retained `rebuild.*` directory, rerun their `make` and `make install` commands, source `dependencies.env`, then rerun `build.sh`. Alternatively modify the pinned source archive and update its checksum for your own build. `SIMPLE_DIALLER_PJ_PREFIX` and `SIMPLE_DIALLER_SSL_PREFIX` select the library prefixes consumed by `build.sh`. The app has no locked signing requirement: you can build and ad-hoc sign your own modified version. Compiler and operating-system differences mean the rebuild is not promised to be byte-identical.

## Maintainer release packaging

Commit the reviewed changes first. From a clean checkout run:

```sh
./scripts/package-release.sh
```

The script archives the exact app commit, rebuilds dependencies from pinned sources, runs the app's offline tests, verifies that it is self-contained and arm64, includes licences and commit provenance, ad-hoc signs it, creates a ZIP and checks its signature again after extraction. It also creates a corresponding-source tarball with the full app source, dependency source tarballs, patch, build recipes and notices, plus `SHA256SUMS` for both assets. By default output is in `~/Library/Developer/SimpleDialler/releases/VERSION`; override with `SIMPLE_DIALLER_RELEASE_DIR`. It refuses to overwrite existing release assets. For the documented optional Homebrew OpenSSL build, set `SIMPLE_DIALLER_SSL_PREFIX` as above when invoking the packaging script.

Publish the app ZIP, matching source tarball and `SHA256SUMS` together on the same GitHub release. The source snapshot records the exact commit in `RELEASE-SOURCE.txt`, also embedded in the app. Packaging does not install, launch, tag, push or upload anything. Perform any live call testing separately with the account owner's authorisation.
