# Third-party notices

Fluxa 1.4.1 · reviewed 2026-10-11

Fluxa's app, device model, collection scheduling, interface and WidgetKit extension
are independently implemented. Its own code and icon are licensed under MIT.
Third-party material retains its original licenses and copyrights.

## Packaged device runtime

| Component | Upstream source | License |
| --- | --- | --- |
| libplist 2.8.0 | [libimobiledevice/libplist](https://github.com/libimobiledevice/libplist/tree/2.8.0) | LGPL-2.1-or-later library |
| libimobiledevice-glue 1.3.3 | [libimobiledevice/libimobiledevice-glue](https://github.com/libimobiledevice/libimobiledevice-glue/tree/1.3.3) | LGPL-2.1-or-later |
| libusbmuxd 2.1.1 | [libimobiledevice/libusbmuxd](https://github.com/libimobiledevice/libusbmuxd/tree/2.1.1) | LGPL-2.1-or-later |
| libtatsu 1.0.5 | [libimobiledevice/libtatsu](https://github.com/libimobiledevice/libtatsu/tree/1.0.5) | LGPL-2.1-or-later |
| libimobiledevice 1.4.0 and idevice_id | [libimobiledevice/libimobiledevice](https://github.com/libimobiledevice/libimobiledevice/tree/1.4.0) | LGPL-2.1-or-later for the packaged library and tool |
| OpenSSL 3.5.9 | [OpenSSL release](https://github.com/openssl/openssl/releases/tag/openssl-3.5.9) | Apache-2.0; Copyright The OpenSSL Project Authors |

Full license texts and corresponding source archives are retained in `Licenses/`
and inside `Fluxa.app/Contents/Resources/Licenses/`. Upstream file headers in those
archives retain their authors' notices. The libimobiledevice snapshot also retains
the ed25519 and Stanford SRP permissive licenses in its `3rd_party` directory;
copies are provided under `Licenses/libimobiledevice-supplemental/`.
GPL texts included by upstream also accompany the complete source snapshots;
unrelated GPL command-line tools are not packaged.

The dated `Fluxa-read-only-handshake.patch` disables automatic pairing in the
convenience handshake. No pairing tool is packaged. The runtime remains dynamically
linked, with relocated install names. Users may modify, rebuild and replace its
libraries and re-sign the bundle; Fluxa adds no restriction on modification or
reverse engineering for debugging those changes. The helper source is
`Tools/device_probe.c`; the full recipe is [Tools/rebuild-runtime.md](Tools/rebuild-runtime.md).
libtatsu is required by upstream; the battery helper does not call its TSS functions.
Apple's system libcurl and system frameworks are linked, not redistributed.

## Energy counters

[macmon](https://github.com/vladkens/macmon) informed the macOS 27 CLPC energy-counter
support. Copyright (c) 2024 vladkens. Its MIT license and copyright are retained
in `Licenses/macmon-MIT.txt`.

## Research reference

[AirBattery](https://github.com/lihaoyun6/AirBattery), by lihaoyun6, is licensed under
AGPL-3.0. It was a feature and device-channel reference. Its Swift application
sources, icons and compiled tools are not included in this distribution.

## 中文

设备读取库保留原有许可、作者署名和对应源码。补丁禁止自动配对；仅发布实际
需要的动态库和设备枚举工具。用户可自行修改、重建和替换，不附加修改限制。
macmon 的 MIT 版权声明已保留。AirBattery 仅作为功能与数据通道参考，其应用
源码、图标和工具未并入发布包。Apple 系统素材及产品名称保留原有权利。
