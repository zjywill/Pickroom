# Third-party software in Pickroom

## LibRaw 0.22.2

RAW decoding. <https://www.libraw.org>

Copyright © 2008-2021 LibRaw LLC. DHT and AAHD demosaic copyright © 2013
Anton Petrusevich.

LibRaw is dual licensed, and the choice is the user's to make:

- GNU Lesser General Public License version 2.1 (`LibRaw-LGPL-2.1.txt`)
- Common Development and Distribution License version 1.0 (`LibRaw-CDDL-1.0.txt`)

**Pickroom uses LibRaw under the CDDL-1.0.** LGPL 2.1 section 6 requires that
a user be able to relink the program against a modified library, which an App
Store binary cannot offer. The CDDL has no such requirement: its copyleft is
per file, and it says in section 3.6 that a larger work combining covered
files may be distributed under terms of the distributor's choosing.

### Source

Pickroom links an unmodified upstream build. Nothing in LibRaw is patched, so
there are no modifications to publish.

- Archive: `Packages/RawEngine/Libraries/LibRaw-0.22.2.tar.gz`, mirrored here
  because upstream download links outlive neither versions nor domains
- Upstream: <https://www.libraw.org/data/LibRaw-0.22.2.tar.gz>
- sha256: `de86b035655accff8d4010f1a221fdf50d353cb7b1422ba26f14a0db92612cfa`

`Tools/build-libraw.sh` rebuilds the shipped `LibRaw.xcframework` from that
archive. It pins the checksum and refuses to build on a mismatch. The
framework in the tree was verified against a fresh build from this archive:
identical exported symbols on both architectures, identical headers.
