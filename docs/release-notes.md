Security maintenance update for `lbry-rocksdb-ng` 0.8.4. Python code continues
to use `import rocksdb`; the database engine remains RocksDB 6.25.3.

The bundled LZ4 library is updated from 1.9.3 to 1.10.0, fixing CVE-2021-3520.
zlib is updated from 1.2.12 to 1.3.2, including the upstream patch
`df84af25dc1942490e1d1c899a07619152a46148` for CVE-2026-85091. This also
includes the earlier fix for CVE-2022-37434. The source archives are checked
against SHA-256 hashes, and zlib's self-tests run during compilation.

Persistence checks exercise Snappy, zlib, LZ4, LZ4HC and Zstandard databases,
column families, WAL entries and serialized write batches across Python 3.9
and 3.13. CI also checks upgrade and downgrade with the released 0.8.3 wheel.
No database migration is introduced. Callers must still synchronize database
close with concurrent operations.

Wheel targets:

- Standard CPython 3.9, Linux x86-64, `manylinux_2_31`.
- Standard CPython 3.13, Linux x86-64, `manylinux_2_35`.

Python 3.13 uses setuptools 84.1.0. Python 3.9 retains compatible setuptools
80.9.0 in the Linux build environment; the Windows-only legacy installation
advisory does not apply to this build path. Other operating systems,
architectures and free-threaded interpreters are not covered.

Do not install this alongside `lbry-rocksdb` or `python-rocksdb`; they own the
same module files. Download the wheels into `wheels/` and `SHA256SUMS` into its
parent, verify with `sha256sum --check SHA256SUMS`, then install the wheel
matching your interpreter. `release.json` records the wrapper and engine
source commits. Hub must update its pinned wheel to consume this release.
