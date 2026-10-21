# Third-party notices

This repository contains source code for Simple Dialler and retains the third-party licence documents listed below. The build obtains dependencies separately through Homebrew; it does not include Homebrew dependency source in this repository.

## PJSIP

- Version: 2.17
- Licence: GNU GPL version 2 or later
- Upstream source and notices: <https://github.com/pjsip/pjproject/tree/2.17>
- Licence text retained in this repository: `Licenses/PJSIP-COPYING`

The Homebrew `pjproject` formula declares OpenSSL as a dependency and does not declare a separate codec formula. PJSIP source distributions may contain bundled codec components and their own notices. Review the notices for the exact PJSIP source and build used before distributing a binary.

## OpenSSL

- Version used for the documented build: 4.0.3
- Licence: Apache License, Version 2.0
- Upstream source and notices: <https://github.com/openssl/openssl/tree/openssl-4.0.3>
- Licence text retained in this repository: `Licenses/OpenSSL-LICENSE.txt`

## Simple Dialler

Simple Dialler's own source is offered under GNU GPL version 3 or, at your option, any later version. See the root `LICENSE` file. Third-party components remain under their respective licences. The repository contains source and build instructions only; it does not include or provide an app binary.
