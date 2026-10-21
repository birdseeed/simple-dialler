# Third-party notices

Simple Dialler is Copyright © 2026 Andy Bridson and is distributed under GNU GPL version 3 or, at your option, any later version. See `LICENSE`.

The app statically links PJSIP 2.17 and OpenSSL 4.0.3. The matching release source archive includes the complete upstream source archives, the PJSIP OpenSSL 4 backport patch, app source, build scripts and notices. Download it beside the app from <https://github.com/birdseeed/simple-dialler/releases>. `docs/RELEASING.md` explains rebuilding and relinking a modified version.

## PJSIP and bundled components

PJSIP/PJPROJECT is Copyright © Teluu Inc. and its contributors, distributed under GNU GPL version 2 or later. The retained licence is `Licenses/PJSIP-COPYING`; upstream is <https://github.com/pjsip/pjproject/tree/2.17>.

The release uses the PJSIP 2.17 source distribution's bundled components below. Their exact versions are the copies in that pinned archive, including upstream modifications. These libraries may be linked as part of PJSIP even where the app does not expose the corresponding functionality.

| Component | Licence and retained notices |
| --- | --- |
| GSM 1.0.12 | Permissive licence; `Licenses/PJSIP-bundled/gsm-COPYRIGHT` |
| Speex (upstream identifies SVN r12832) | BSD licence; `Licenses/PJSIP-bundled/speex-COPYING` |
| Resample | LGPL 2.1 or later; `Licenses/PJSIP-bundled/resample-COPYING` and `resample-README-resample` |
| libsrtp 2.5.0 | BSD licence; `Licenses/PJSIP-bundled/srtp-LICENSE` |
| WebRTC | BSD licence, additional component licences and patent grant; `Licenses/PJSIP-bundled/webrtc-*` |


`Licenses/PJSIP-bundled/SOURCE-COPYRIGHT-NOTICES.txt` additionally retains copyright and licence headers from those bundled sources. Complete source files and their original notices remain in the source archive. The G.722.1 and iLBC codecs are disabled in the release build; their upstream source remains in the unmodified PJSIP source archive. Video, libyuv and optional external codecs are also disabled. Retained libyuv notices apply to its source in the complete upstream archive. Standard G.711 PCMU and PCMA codecs remain enabled. G.722.1 is distinct from G.722.

## OpenSSL

OpenSSL 4.0.3 is distributed under the Apache License, Version 2.0. See `Licenses/OpenSSL-LICENSE.txt` and <https://github.com/openssl/openssl/tree/openssl-4.0.3>. The exact Homebrew formula used for the optional prebuilt OpenSSL dependency is retained in `scripts/dependency-recipes/openssl@4.rb`; the source rebuild script provides a local alternative.

## Where to find these notices

The app includes `LICENSE`, this file and the `Licenses` directory in `Simple Dialler.app/Contents/Resources`. The source archive accompanies every binary release at the same download location. No Apple SDK or system framework is redistributed in the app.
