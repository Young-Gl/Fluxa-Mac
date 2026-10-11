# Publication notes / 公开发布说明

Reviewed on 2026-10-11. This is a publication review, not a legal opinion or trademark clearance.

## Licenses

Fluxa-specific code and its own icon use MIT. Third-party software, Apple system graphics and trademarks retain their rights. The macOS 27 energy-counter support references macmon; its MIT copyright and license are retained.

The device helper dynamically loads LGPL-2.1-or-later libraries. Corresponding source archives, a dated read-only handshake patch and build instructions accompany the binary. Users can rebuild and replace them; local builds require no developer certificate, and modified bundles can be signed again ad hoc. No restriction is added against modification or reverse engineering for debugging such changes. OpenSSL retains Apache-2.0. See the [GNU LGPL](https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html) and [GNU FAQ](https://www.gnu.org/licenses/gpl-faq.html#LGPLStaticVsDynamic).

AirBattery uses [AGPL-3.0](https://github.com/lihaoyun6/AirBattery/blob/main/LICENSE). It was studied for features and data channels; its Swift application sources, icons and compiled tools are not published here. Incorporating that code later would require a new license assessment. MIT must not be used to remove another author's rights.

## Apple platform

System frameworks are linked, not redistributed. SF Symbols identify devices and controls inside the macOS app, not the Fluxa logo. Screenshots show the app and its system widget UI. Apple-owned elements retain their rights. Relevant terms: [Xcode and Apple SDKs Agreement](https://www.apple.com/legal/sla/docs/xcode.pdf), section 2.10, and [Apple's trademark guidelines](https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html).

SMC and IOReport are not stable public application APIs and may change. GitHub distribution does not imply App Store approval: [App Store section 2.5.1](https://developer.apple.com/app-store/review/guidelines/#software-requirements) requires public APIs. The binary is ad hoc signed, not notarized, and makes no claim of Apple certification or endorsement.

## Name and publication data

Unrelated software uses the Fluxa name, including [this project-management platform](https://fluxa.in/). **Fluxa-Mac** distinguishes the repository's scope but does not establish trademark rights or eliminate naming disputes. Commercial branding needs jurisdiction-specific clearance.

Source, required dependencies, license material and product screenshots are published. Research, runtime diagnostics, identifiers, trust records, credentials, notification captures and crash reports are excluded. Screenshot percentages are real local readings.

## 中文摘要

已补齐 MIT、macmon 版权声明、LGPL 对应源码与日期明确的补丁，以及 OpenSSL 许可。动态库可自行替换和重建，研究用 AirBattery 文件和工具不发布。必要的开源署名保留。

Apple 系统图形用于应用界面，不作为品牌标志；Fluxa 使用自己的图标，不宣称官方认可。私有接口可能随系统更新失效，GitHub 发布不等同于 App Store 审核通过，当前包未公证。

Fluxa 有同名软件。仓库名只帮助区分用途，不等于取得商标权；检索不能保证零侵权风险，也不能替代正式商标清查或法律意见。个人诊断和研究资料不公开。
