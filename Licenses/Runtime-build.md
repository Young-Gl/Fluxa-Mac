# Device runtime source and rebuilding

Corresponding source snapshots, SHA256 checksums and upstream commit metadata
are included in `Sources/`. The dated patch disables automatic pairing inside
libimobiledevice's convenience handshake. Libraries are dynamically linked and
may be rebuilt or replaced.

Build order: OpenSSL 3.5.9, libplist 2.8.0, libimobiledevice-glue 1.3.3,
libusbmuxd 2.1.1, libtatsu 1.0.5, libimobiledevice 1.4.0.
Use `MACOSX_DEPLOYMENT_TARGET=13.0`, `CFLAGS` and `CXXFLAGS` set to
`-O2 -g0 -mmacosx-version-min=13.0`, and `LDFLAGS=-mmacosx-version-min=13.0`.

OpenSSL uses `./Configure darwin64-arm64-cc shared no-tests no-apps
--prefix=<SSL-prefix>`. Run `make -j2` and `make install_sw`.
For each other source, create `.tarball-version` containing its version, then
run `./autogen.sh --prefix=<temporary-prefix> --disable-static --enable-shared`,
`make -j2`, and `make install`. Set `PKG_CONFIG_PATH` to both prefixes' lib/pkgconfig
directories, and `ACLOCAL_PATH` to the pkg-config macro directory.
Add `--without-cython` for libplist and libimobiledevice, and `--with-openssl` for
libimobiledevice. Apply `Sources/Fluxa-read-only-handshake.patch` with `patch -p1`
to libimobiledevice before configuring it. libtatsu uses macOS's libcurl via
`libcurl_CFLAGS=-I<SDK>/usr/include` and `libcurl_LIBS=-lcurl`.

Copy the five shared device libraries, libssl.3.dylib, libcrypto.3.dylib and
idevice_id. Set library IDs and references to `@executable_path/../lib/<name>`;
the packaged device names are libplist.dylib, libimobiledevice-glue.dylib,
libusbmuxd.dylib, libtatsu.dylib and libimobiledevice.dylib. The host app compiles
its independent helper from Tools/device_probe.c.

The complete executable recipe and helper source are available at the matching
release tag in https://github.com/Young-Gl/Fluxa-Mac . See
Tools/rebuild-runtime.command and Tools/rebuild-runtime.md. Building the app
signs the helper, libraries and bundle ad hoc; no developer certificate is needed.
Modified versions may be rebuilt and re-signed without a restriction added by Fluxa.

包内附对应源码及补丁。完整构建脚本和电量辅助程序源码见同版本 GitHub 标签。
动态库可自行修改、替换和重新签名。上述最低部署版本已核对；真实运行测试在
M4 / macOS 27 上完成，并不表示已在所有旧系统或机型上实测。
