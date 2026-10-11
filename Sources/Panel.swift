import AppKit

final class FlippedView: NSView { override var isFlipped: Bool { true } }
final class FlippedMaterial: NSVisualEffectView { override var isFlipped: Bool { true } }
@available(macOS 26.0, *)
final class FlippedGlass: NSGlassEffectView { override var isFlipped: Bool { true } }

final class PowerPanelController: NSViewController {
    let width: CGFloat = 344
    var height: CGFloat { detailsShown ? detailsHeight : 368 }
    private var detailsHeight: CGFloat = 544
    private(set) var detailsShown = false
    private var mainPage: NSView!
    private var detailPage: NSView!
    private var fields: [String: NSTextField] = [:]
    private var detailButtons: [String: NSButton] = [:]
    private var rowIcons: [String: NSImageView] = [:]
    private var detailSeparator: NSBox?
    private var mainSettingsButton: NSButton?
    private var detailGearContainer: NSView?
    private(set) var visualStyle = "vibrancy"
    var onDevices: (() -> Void)?
    var onSettings: ((NSButton) -> Void)?
    var onRefresh: (() -> Void)?
    var onPageChanged: ((Bool) -> Void)?
    private var lastSnapshot = PowerSnapshot()
    private let formatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    override func loadView() {
        let bounds = NSRect(x: 0, y: 0, width: width, height: height)
        let content = FlippedView(frame: bounds)
        content.autoresizingMask = [.width, .height]
        if #available(macOS 26.0, *) {
            let glass = FlippedGlass(frame: bounds)
            glass.style = .regular; glass.cornerRadius = 24
            glass.contentView = content
            view = glass; visualStyle = "native Liquid Glass"
        } else {
            let material = FlippedMaterial(frame: bounds)
            material.material = .popover; material.blendingMode = .behindWindow; material.state = .active
            material.addSubview(content); view = material
        }
        mainPage = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: 368))
        detailPage = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: 634))
        content.addSubview(mainPage); content.addSubview(detailPage); detailPage.isHidden = true
        field("title", parent: mainPage, x: 22, y: 19, w: 180, h: 26, size: 18, weight: .semibold)
        field("battery", parent: mainPage, x: 220, y: 23, w: 100, h: 19, size: 12, color: .secondaryLabelColor, right: true)
        field("caption", parent: mainPage, x: 22, y: 57, w: 280, h: 16, size: 11, color: .secondaryLabelColor)
        field("hero", parent: mainPage, x: 20, y: 77, w: 304, h: 46, size: 37, weight: .medium, digits: true)
        field("state", parent: mainPage, x: 22, y: 122, w: 300, h: 18, size: 11, color: .secondaryLabelColor)
        separator(parent: mainPage, y: 149)
        row("input", symbol: "powerplug", parent: mainPage, y: 159)
        row("system", symbol: "laptopcomputer", parent: mainPage, y: 199)
        row("net", symbol: "battery.100percent", parent: mainPage, y: 239)
        let detail = button("", parent: mainPage, x: 52, y: 207, w: 165, h: 24, action: #selector(openDetails))
        detail.alignment = .left; detail.font = .systemFont(ofSize: 13)
        detailButtons["details"] = detail
        fields["systemName"]?.isHidden = true
        separator(parent: mainPage, y: 282)
        field("formula", parent: mainPage, x: 22, y: 290, w: 300, h: 18, size: 11, color: .secondaryLabelColor, digits: true)
        field("electrical", parent: mainPage, x: 22, y: 315, w: 155, h: 17, size: 11, color: .secondaryLabelColor, digits: true)
        field("limit", parent: mainPage, x: 169, y: 315, w: 151, h: 17, size: 10, color: .secondaryLabelColor, right: true)
        field("freshness", parent: mainPage, x: 22, y: 341, w: 172, h: 17, size: 10, color: .tertiaryLabelColor)
        let devices = button("", parent: mainPage, x: 199, y: 337, w: 84, h: 25, action: #selector(devicesPressed))
        devices.font = .systemFont(ofSize: 11, weight: .medium)
        devices.alignment = .right
        detailButtons["devices"] = devices
        let gear = button("", parent: mainPage, x: 292, y: 336, w: 30, h: 26, action: #selector(settingsPressed(_:)))
        mainSettingsButton = gear
        gear.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Settings")
        gear.setAccessibilityLabel(L10n.text("设置", "Settings"))
        _ = glassButton(gear, in: mainPage)
        let back = button("", parent: detailPage, x: 17, y: 16, w: 25, h: 27, action: #selector(backPressed))
        back.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")
        _ = glassButton(back, in: detailPage)
        field("detailTitle", parent: detailPage, x: 49, y: 18, w: 271, h: 25, size: 17, weight: .semibold)
        field("detailTotal", parent: detailPage, x: 22, y: 58, w: 298, h: 39, size: 29, weight: .medium, digits: true)
        field("detailCaption", parent: detailPage, x: 23, y: 97, w: 297, h: 18, size: 11, color: .secondaryLabelColor)
        for (index, pair) in [("cpu","cpu"),("gpu","square.3.layers.3d"),("ane","brain"),("memory","memorychip"),("screen","display"),("usb","cable.connector"),("other","ellipsis.circle")].enumerated() {
            let y = CGFloat(126 + index * 45)
            row(pair.0, symbol: pair.1, parent: detailPage, y: y, subtitle: true)
        }
        separator(parent: detailPage, y: 448)
        detailSeparator = detailPage.subviews.last as? NSBox
        field("ports", parent: detailPage, x: 23, y: 460, w: 298, h: 56, size: 11, color: .secondaryLabelColor, wrap: true)
        field("usbAge", parent: detailPage, x: 23, y: 519, w: 298, h: 18, size: 10, color: .tertiaryLabelColor)
        field("detailNote", parent: detailPage, x: 23, y: 548, w: 298, h: 59, size: 10, color: .secondaryLabelColor, wrap: true)
        field("detailRefresh", parent: detailPage, x: 23, y: 611, w: 268, h: 17, size: 10, color: .tertiaryLabelColor)
        let detailGear = button("", parent: detailPage, x: 292, y: 605, w: 30, h: 26, action: #selector(settingsPressed(_:)))
        detailGear.image = gear.image
        detailButtons["gear"] = detailGear
        detailGearContainer = glassButton(detailGear, in: detailPage)
        detailGear.setAccessibilityLabel(L10n.text("设置", "Settings"))
    }

    @objc private func devicesPressed() { onDevices?() }

    private func row(_ id: String, symbol: String, parent: NSView, y: CGFloat, subtitle: Bool = false) {
        let icon = NSImageView(frame: NSRect(x: 23, y: y + 12, width: 18, height: 18))
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: id)
        icon.contentTintColor = .secondaryLabelColor
        parent.addSubview(icon)
        if subtitle { rowIcons[id] = icon }
        field(id + "Name", parent: parent, x: 52, y: y + (subtitle ? 5 : 11), w: 155, h: 21, size: 13)
        field(id + "Value", parent: parent, x: 199, y: y + 9, w: 121, h: 24, size: 17, weight: .medium, right: true, digits: true)
        if subtitle { field(id + "Hint", parent: parent, x: 53, y: y + 26, w: 267, h: 14, size: 9, color: .tertiaryLabelColor) }
    }
    private func field(_ id: String, parent: NSView, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
                       size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor,
                       right: Bool = false, digits: Bool = false, wrap: Bool = false) {
        let f = wrap ? NSTextField(wrappingLabelWithString: "") : NSTextField(labelWithString: "")
        f.frame = NSRect(x: x, y: y, width: w, height: h)
        f.font = digits ? .monospacedDigitSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
        f.textColor = color; f.alignment = right ? .right : .left
        f.isSelectable = false; parent.addSubview(f); fields[id] = f
    }
    private func separator(parent: NSView, y: CGFloat) {
        let line = NSBox(frame: NSRect(x: 23, y: y, width: 298, height: 1))
        line.boxType = .separator; parent.addSubview(line)
    }
    private func button(_ title: String, parent: NSView, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.frame = NSRect(x: x, y: y, width: w, height: h); b.isBordered = false
        parent.addSubview(b); return b
    }
    private func glassButton(_ button: NSButton, in parent: NSView) -> NSView {
        let frame = button.frame.insetBy(dx: -4, dy: -3)
        let content = FlippedView(frame: NSRect(origin: .zero, size: frame.size))
        content.autoresizingMask = [.width, .height]
        button.frame.origin = NSPoint(x: 4, y: 3)
        content.addSubview(button)
        if #available(macOS 26.0, *) {
            let glass = FlippedGlass(frame: frame)
            glass.style = .regular; glass.cornerRadius = frame.height / 2
            if #available(macOS 27.0, *) { glass.effectIsInteractive = true }
            glass.contentView = content; parent.addSubview(glass); return glass
        }
        content.frame = frame; parent.addSubview(content); return content
    }
    private func text(_ id: String, _ value: String) {
        if fields[id]?.stringValue != value { fields[id]?.stringValue = value }
    }
    @objc private func settingsPressed(_ button: NSButton) { onSettings?(button) }
    func showSettings() { if let button = mainSettingsButton { onSettings?(button) } }
    @objc private func openDetails() { setDetails(true) }
    @objc private func backPressed() { setDetails(false) }
    func setDetails(_ value: Bool) {
        _ = view
        guard detailsShown != value else { return }
        detailsShown = value; mainPage.isHidden = value; detailPage.isHidden = !value
        view.setFrameSize(NSSize(width: width, height: height))
        onPageChanged?(value)
    }
    func update(_ s: PowerSnapshot, interval: Double, unchangedSeconds: Double, paused: Bool) {
        _ = view; lastSnapshot = s
        text("title", L10n.appName)
        detailButtons["devices"]?.title = L10n.text("设备电量 ›", "Devices ›")
        text("battery", s.batteryPercent.map { "\($0)%" } ?? "—%")
        text("caption", s.connected == true ? L10n.text("输入功率", "Input power") : L10n.text("耗电功率", "Power consumption"))
        text("hero", wattText(s.barW))
        text("state", s.state.title)
        fields["state"]?.textColor = s.state == .supplemental ? .systemOrange : .secondaryLabelColor
        text("inputName", L10n.text("充电器输入", "Charger input"))
        text("inputValue", s.connected == false ? L10n.text("未接电", "Unplugged") : wattText(s.inputW))
        detailButtons["details"]?.title = L10n.text("运行消耗  ›", "System power  ›")
        text("systemValue", wattText(s.systemW))
        text("netName", s.connected == false ? L10n.text("电池放电", "Battery drain") : L10n.text("电池净充电", "Net charging"))
        text("netValue", wattText(s.netBatteryW, signed: true))
        fields["netValue"]?.textColor = s.netBatteryW.map { $0 < -0.15 ? .systemOrange : .systemGreen } ?? .secondaryLabelColor
        if let input = s.inputW, let system = s.systemW, let net = s.netBatteryW {
            text("formula", "\(wattText(input, unit: false)) − \(wattText(system, unit: false)) = \(wattText(net, signed: true))")
        } else { text("formula", L10n.text("等待有效功率数据", "Waiting for valid power data")) }
        let volts = s.voltageV.map { String(format: "%.2f V", $0) } ?? "— V"
        let amps = s.currentA.map { String(format: "%.2f A", $0) } ?? "— A"
        text("electrical", s.connected == true ? "\(volts) · \(amps)" : L10n.text("电池 ", "Battery ") + volts)
        text("limit", s.connected == true ? L10n.text("上限 ", "Limit ") + wattText(s.adapterLimitW) : "")
        let time = formatter.string(from: s.sampledAt)
        text("freshness", paused ? L10n.text("已暂停", "Paused") : "\(Int(interval))s · \(s.estimated ? L10n.text("估算", "Estimated") : L10n.text("实时", "Live")) · \(time)")
        fields["hero"]?.setAccessibilityLabel((fields["caption"]?.stringValue ?? "") + " " + wattText(s.barW))
        if detailsShown { updateDetails(s, time: time) }
    }
    private func updateDetails(_ s: PowerSnapshot, time: String) {
        let d = s.breakdown ?? PowerBreakdown()
        text("detailTitle", L10n.text("消耗明细", "Power breakdown"))
        text("detailTotal", wattText(s.systemW))
        text("detailCaption", L10n.text("整机运行消耗", "Total system consumption"))
        let entries: [(String, String, String, Double?, String, String)] = [
            ("cpu", "CPU", "CPU", d.energy.cpuW, "程序运算与系统任务", "Apps and system computation"),
            ("gpu", "GPU", "GPU", d.energy.gpuW, "图形、视频与界面渲染", "Graphics, video and rendering"),
            ("ane", "神经网络引擎", "Neural Engine", d.energy.aneW, "本地 AI 运算", "Local AI processing"),
            ("memory", "内存", "Memory", d.energy.memoryW, "RAM 供电", "RAM power"),
            ("screen", "屏幕背光", "Display backlight", d.screenBacklightW, "仅背光，不包括 GPU", "Backlight only; excludes GPU"),
            ("usb", "USB 向外供电", "USB power output", d.usbW, "给外接设备供电，非 USB 协商上限", "Power to connected devices, not their rating"),
            ("other", "其它未分项", "Other / unallocated", d.otherW, "未单列的屏幕、内存、主板、损耗等", "Unmetered display, RAM, board and losses")
        ]
        var visibleCount = 0
        for (id, zh, en, value, hintZh, hintEn) in entries {
            let hidden = value == nil
            rowIcons[id]?.isHidden = hidden
            for suffix in ["Name", "Value", "Hint"] { fields[id + suffix]?.isHidden = hidden }
            guard let value else { continue }
            let y = CGFloat(126 + visibleCount * 45)
            rowIcons[id]?.frame.origin.y = y + 12
            fields[id + "Name"]?.frame.origin.y = y + 5
            fields[id + "Value"]?.frame.origin.y = y + 9
            fields[id + "Hint"]?.frame.origin.y = y + 26
            visibleCount += 1
            text(id + "Name", L10n.text(zh, en))
            text(id + "Value", (id == "other" ? "≈" : "") + wattText(value))
            text(id + "Hint", L10n.text(hintZh, hintEn))
        }
        let separatorY = CGFloat(133 + visibleCount * 45)
        detailSeparator?.frame.origin.y = separatorY
        let usbPresent = d.usbW != nil
        fields["ports"]?.isHidden = !usbPresent
        fields["usbAge"]?.isHidden = !usbPresent
        fields["ports"]?.frame.origin.y = separatorY + 12
        fields["usbAge"]?.frame.origin.y = separatorY + 71
        let footerShift: CGFloat = usbPresent ? 0 : 78
        fields["detailNote"]?.frame.origin.y = separatorY + 100 - footerShift
        fields["detailRefresh"]?.frame.origin.y = separatorY + 163 - footerShift
        detailGearContainer?.frame.origin.y = separatorY + 154 - footerShift
        detailsHeight = separatorY + 186 - footerShift
        let detailSize = NSSize(width: width, height: detailsHeight)
        if detailPage.frame.size != detailSize { detailPage.setFrameSize(detailSize) }
        let rootSize = NSSize(width: width, height: height)
        if view.frame.size != rootSize { view.setFrameSize(rootSize) }
        if d.ports.isEmpty {
            text("ports", d.usbW == 0 ? L10n.text("未检测到向外供电的 USB 端口", "No USB power output reported") : L10n.text("USB 端口遥测暂未提供", "USB port telemetry unavailable"))
        } else {
            text("ports", d.ports.prefix(3).map { p in
                let v = p.volts.map { String(format: "%.2f V", $0) } ?? "— V"
                let a = p.amps.map { String(format: "%.2f A", $0) } ?? "— A"
                return L10n.text("系统端口 ", "System port ") + "\(p.index)  ·  \(wattText(p.watts))  ·  \(v) / \(a)"
            }.joined(separator: "\n"))
        }
        if let updated = d.usbUpdatedAt {
            let age = max(0, Int(Date().timeIntervalSince(updated)))
            text("usbAge", L10n.text("USB 为系统缓存读数 · ", "USB uses cached macOS readings · ") + "\(age)s")
        } else { text("usbAge", L10n.text("USB 刷新周期由系统决定", "USB refresh timing is controlled by macOS")) }
        text("detailNote", L10n.text("CPU/GPU 为采样期间平均值；整机为瞬时值。\n仅展示有效读数。“其它”是未分项部分的估算，\n不代表屏幕或内存的独立功率。",
            "CPU/GPU are interval averages; total power is instantaneous.\nOnly available readings are shown. Other is an estimate,\nnot a separate display or RAM measurement."))
        text("detailRefresh", L10n.text("更新 ", "Updated ") + time + " · " + d.energy.source)
    }
    var visibleTexts: [String: String] {
        fields.filter { !$0.value.isHidden && $0.value.superview?.isHidden == false }.mapValues { $0.stringValue }
    }
}
