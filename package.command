#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
[[ -f build/APP_PATH.txt ]] || ./build.command
task_app_path=$(cat build/APP_PATH.txt)
[[ -d "$task_app_path" ]] || { print -u2 '请先运行 build.command'; exit 1; }
task_dmg_stage=$(mktemp -d /private/tmp/FluxaDMG.XXXXXX)
trap 'rm -rf "$task_dmg_stage"' EXIT
ditto --norsrc --noextattr "$task_app_path" "$task_dmg_stage/Fluxa.app"
codesign --verify --strict "$task_dmg_stage/Fluxa.app"
ln -s /Applications "$task_dmg_stage/Applications"
cat > "$task_dmg_stage/使用说明.txt" <<'GUIDE'
Fluxa 1.4.1

将 Fluxa.app 拖入 Applications，然后打开。菜单栏会显示实时瓦数。
已安装的电脑：直接打开「应用程序」中的 Fluxa。

接电显示实际输入功率，电池供电显示运行消耗。
点击菜单栏数字查看输入、运行、净充电（输入减运行）。
点击「运行消耗」查看 CPU / GPU / USB 向外供电等明细。
只显示硬件提供的有效读数；无法独立读取的项目自动隐藏。
USB 数据使用 macOS 的缓存，更新时间在明细中注明。

点击面板底部「设备电量」查看 iPhone、iPad、Apple Watch 与已连接耳机电量。
右键桌面 → 编辑小组件 → 搜索 Fluxa，选择小 / 中 / 大尺寸并添加。
小组件显示的设备可以在 Fluxa 设置中选择。小 / 中最多 4 项，大最多 8 项。
手机 / 平板首次需通过 USB 信任此 Mac，随后可通过可发现的同网 Wi-Fi 读取。
手表通过已配对的 iPhone 读取。没有有效读数的耳机盒等项目不显示。
设备页每分钟自动读取；小组件更新由 macOS 调度。断连读数变灰，一小时后移除。

设置可选择刷新间隔、登录启动、电压显示和语言。
语言默认跟随系统：中文系统用中文，其余用英文。
「关于 Fluxa」说明中提供反馈方式。应用不会弹出功率通知。
欢迎将反馈与建议发送至 yanghanchao2002@outlook.com。

Drag Fluxa.app into Applications, then launch it.
AC: actual input power. Battery: system consumption.
Click System power for available CPU, GPU and USB output readings.
Unavailable components are hidden. USB readings follow the macOS cache.
Search Fluxa in macOS Edit Widgets to add a native desktop widget.
Click Devices at the bottom of the power panel for trusted iPhone / iPad / Watch
and connected Bluetooth batteries. Automatic device polling every minute;
WidgetKit controls widget refresh timing. Unavailable batteries are hidden.
Automatic Chinese / English. No power notifications.
Feedback is welcome at yanghanchao2002@outlook.com, also included in About Fluxa.

适用于 Apple 芯片 MacBook，macOS 13 或更新版本；桌面小组件需 macOS 14+。
已在本机 M4 / macOS 27 上实际验证；不同机型可用传感器可能不同。
此版本为本地签名，未经过 Apple 公证。
若系统阻止打开，请参阅 Apple 的官方说明：
https://support.apple.com/zh-cn/102445

Apple silicon MacBook, macOS 13+. Desktop widgets require macOS 14+.
This release is ad hoc signed, not notarized. Opening instructions:
https://support.apple.com/en-us/102445
GUIDE
if [[ -f THIRD_PARTY_NOTICES.md ]]; then cp THIRD_PARTY_NOTICES.md "$task_dmg_stage/"; fi
hdiutil create -quiet -volname Fluxa -srcfolder "$task_dmg_stage" -format UDZO -ov Fluxa.dmg
hdiutil verify Fluxa.dmg
print "已生成：$PWD/Fluxa.dmg"
