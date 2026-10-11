# Rebuild the device runtime

Fluxa includes shared libraries and `idevice_id`, built for Apple silicon with a
macOS 13.0 deployment target. The app compiles its own battery-only helper from
`Tools/device_probe.c`. Trust-management tools are not packaged.

## Sources and changes

The exact source snapshots are in `Licenses/Sources`, with upstream commits and
SHA256 values in `BUILD-INFO.json` and `SHA256SUMS`:

| Component | Version | License |
| --- | --- | --- |
| libplist | 2.8.0 | LGPL-2.1-or-later library |
| libimobiledevice-glue | 1.3.3 | LGPL-2.1-or-later |
| libusbmuxd | 2.1.1 | LGPL-2.1-or-later |
| libtatsu | 1.0.5 | LGPL-2.1-or-later |
| libimobiledevice | 1.4.0 | LGPL-2.1-or-later library and idevice_id |
| OpenSSL | 3.5.9 | Apache-2.0 |

The dated `Fluxa-read-only-handshake.patch` changes the convenience handshake to
reject missing trust instead of pairing. Other library source is unmodified.
Runtime paths are relocated and binaries are signed ad hoc. libtatsu is an
upstream dependency; Fluxa does not call its signing-server functions. It links
Apple's system libcurl rather than a bundled curl.

## Build

Use Xcode command-line tools, Python 3, Perl, Make, Autoconf, Automake, Libtool and
pkg-config. For example, install the four Autotools dependencies with your package
manager, then make their executables available on PATH. Nothing is installed
globally by this script.

```sh
./Tools/rebuild-runtime.command
./build.command
```

The runtime script verifies the included source hashes, downloads OpenSSL's
official archive and checks its pinned SHA256, then builds all components with
two workers in a temporary directory. It uses `-O2 -g0
-mmacosx-version-min=13.0`, enables shared libraries, disables static libraries
and disables Cython. The OpenSSL configuration is
`darwin64-arm64-cc shared no-tests no-apps`.

Only the required libraries and `idevice_id` are copied into
`Resources/libimobiledevice`. Absolute build-prefix dependencies are rewritten
to `@executable_path/../lib/`. Every result must report a 13.0 deployment target
before it replaces the previous runtime. Temporary build files are removed.

To reuse a previously downloaded, verified OpenSSL archive, set
`FLUXA_OPENSSL_ARCHIVE=/absolute/path/openssl-3.5.9.tar.gz`. An optional
`FLUXA_SSL_PREFIX` may point to an already built matching OpenSSL installation;
it must contain the headers, shared libraries and pkg-config files. The archive
checksum is still required. Omitting the prefix builds OpenSSL from source.

## Replace libraries in an installed app

Users may rebuild and replace the libraries in
`Fluxa.app/Contents/Resources/libimobiledevice/lib`, or modify the helper. Use
matching install names and compatible APIs. A modified bundle must be signed
again; a local ad hoc signature is sufficient for local building and requires
no paid developer certificate. Run `build.command` to create a freshly signed
bundle. There is no additional restriction on modification or reverse engineering
to debug changes to these libraries.

## 中文

包内附设备读取库的对应源码、完整许可、日期明确的只读补丁和校验值。
上述脚本从源码重建依赖，最低部署版本为 macOS 13，最多使用两个编译任务。
补丁禁止电量查询过程自动建立信任；应用不打包配对工具。
用户可自行修改、重建和替换动态库，再通过 `build.command` 生成本地签名的应用。
