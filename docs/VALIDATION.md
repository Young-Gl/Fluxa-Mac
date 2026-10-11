# Validation / 验证记录

2026-10-11 · Fluxa 1.4.1, build 11 · Apple M4 MacBook · macOS 27.0.1 (26A434)

## Functional checks

`./test.command` passed **60** boundary and lifecycle checks. They cover power
arithmetic, weak chargers and stale input, invalid percentages and flags, malformed
device data, explicit empty widget selection, older cache compatibility, cache
limits, duplicate and expired entries, failed process launches, output floods,
timeouts, cancellation, refresh coalescing and overlapping sleep / wake events.
Charging-state arithmetic is tested with controlled data; a physical charger
transition was not performed during this release check.

The installed app reads changing SMC power on battery and available CPU, GPU,
Neural Engine and USB output values. Unavailable independent RAM and backlight
readings are hidden. Real iPhone, iPad and Apple Watch reads succeeded through
existing Wi-Fi trust connections; a connected Bluetooth headset reported its
battery. Earbud decoding is covered by tests; disconnected AirPods are not claimed
as a live-device result for this release check.

The actual Settings menu was used to uncheck all five detected devices. Selection
counts fell to 4, 3, 2, 1 and 0, and stayed empty. Automatic selection was restored.
Chinese and English overrides, automatic system language, device navigation,
closing the panel and a second launch were checked. A second launch exits without
creating another menu-bar app. Closing details releases the energy subscription.
The feedback address appears within the About text, with no separate email item.

The native macOS Edit Widgets gallery shows Fluxa in small, medium and large
sizes. One existing native desktop widget remains installed. Gallery and panel
screenshots are actual window captures; battery values are real local readings.
WidgetKit and system device telemetry control their own refresh cadence.

## Resource observations

| Observation | Result |
| --- | --- |
| Five-minute session, including UI checks | 61 samples; parent CPU averaged 0.045% of one core |
| UI memory | Temporary footprint peak 145.97 MiB; fell to 48.47 MiB after panels closed |
| Additional two-minute background observation | 25 samples; parent CPU averaged 0.009% of one core |
| Background physical footprint | 48.55–50.09 MiB |
| Actual parent file descriptors | 8 throughout the background observation |
| Background disk writes | 24 KiB over two minutes |
| Current battery cache | 914 bytes; overwritten, no history; 64 KiB / 32-device cap |
| New Fluxa / widget crash reports | None during the release verification window |

The parent-process CPU figures exclude short-lived helpers and macOS widget
processes. Separately measured device queries used about 0.018 CPU seconds for an
iPad, 0.019 for an iPhone, and 0.076 for the paired Watch; elapsed times were about
0.21, 0.13 and 1.20 seconds. These are individual observations, not energy-use
guarantees. Automatic device collection runs every minute, one bounded child at a
time; it stops on sleep. No continuing application log writer or history database
is present. Manual diagnostics used for verification remain private.

## Build and package

A fresh source checkout without an existing `build` directory built successfully.
Both app and widget builds completed without compiler warnings. The app, helper,
enumeration tool and seven runtime libraries report a macOS 13.0 deployment
target; the WidgetKit extension reports 14.0. Runtime dependencies contain no
absolute temporary-build or Homebrew library paths.

The DMG was mounted read-only. All 39 app-bundle files matched the installed
version, deep signature verification passed, and license texts, corresponding
library sources and the patch were present. Research and personal diagnostic
files are excluded. SHA256 is supplied with the release. Signatures are ad hoc;
the app is not Apple-notarized.

These are checks on the stated machine and short observation windows. Deployment
metadata is not proof of execution on macOS 13 / 14 or other Mac models. Private
power interfaces, Bluetooth data, Wi-Fi discovery and widget scheduling may vary
with hardware and OS updates. Long-term operation and all device combinations
have not been tested.

## 中文

60 项边界与生命周期检查全部通过，并已通过真实设置菜单验证取消全部设备后
保持空选择、恢复自动选择、中英文切换与关闭面板。当前 Mac 的 SMC 功率、可用
分项功率、手机、平板、手表和蓝牙耳机电量已实测；此轮没有进行物理插拔充电器，
充电状态的计算使用受控数据验证。截图来自真实窗口。

五分钟含界面操作的观察中，主进程平均占用单核 CPU 0.045%，界面关闭后内存
回落至 48.47 MiB。额外两分钟后台观察中，平均 CPU 0.009%，物理内存占用在
48.55–50.09 MiB 之间，文件句柄始终为 8，写入 24 KiB。上述 CPU 不包括短时
辅助进程及系统小组件进程；辅助读取已另行测量。没有新增崩溃报告，也没有
观察到持续内存增长。缓存覆盖写入，不保存历史。

全新源码目录构建通过，DMG 与安装版本逐文件核对通过。已核对各程序的最低
部署版本，但真实运行验证限于此台 M4 / macOS 27，并非覆盖全部旧系统或机型。
有限时长的检查不能保证长期使用没有任何问题；发布包未经过 Apple 公证。
