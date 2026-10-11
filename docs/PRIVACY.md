# Privacy / 隐私

Fluxa has no account, advertising, analytics, remote backend or automatic upload. It does not send readings to the maintainer.

Mac power is read locally. Bluetooth batteries come from the system's connected-device report. iPhone / iPad use existing USB or Wi-Fi trust connections; Watch readings go through the paired iPhone. Trust records are read through the system service and are not copied into Fluxa's cache. Automatic pairing is disabled in the bundled library.

One bounded local cache holds current names, percentages, read times, connection state and hashed identifiers. There is no battery history; disconnected entries expire after one hour. Raw serial numbers, Bluetooth addresses and pairing certificates are not saved in that cache. The widget only reads its cache and does not scan devices. Settings use standard app preferences. Manually requested diagnostics remain local and are excluded from the release.

Fluxa 不含账户、广告、统计追踪、远程后台或自动上传，不会把读数发送给维护者。Mac 和蓝牙数据本地读取；手机和平板使用已有 USB / Wi-Fi 信任连接，手表经 iPhone 查询。系统信任记录不复制进缓存，自动配对已禁用。

一个固定的小型缓存只保存当前设备名、电量、读取时间、连接状态和哈希后的标识，不保存历史。断连条目一小时后移除，不保存设备序列号、蓝牙地址或配对证书。小组件只读缓存，不扫描设备。设置使用应用偏好；手动诊断只留在本机，不公开发布。
