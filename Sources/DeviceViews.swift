import AppKit
import SwiftUI

private struct DevicesContent: View {
    let archive: BatteryArchive
    let completed: Date?
    let onBack: () -> Void
    let onRefresh: () -> Void
    let onSettings: () -> Void
    private var chinese: Bool { archive.chinese }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) { Image(systemName: "chevron.left").frame(width: 24, height: 24) }
                    .help(chinese ? "功率" : "Power")
                Text(chinese ? "设备电量" : "Devices").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button(action: onRefresh) { Image(systemName: "arrow.clockwise").frame(width: 24, height: 24) }
                    .help(chinese ? "刷新设备电量" : "Refresh batteries")
            }.buttonStyle(.plain).padding(.horizontal, 20).padding(.top, 17)
            BatteryRingGrid(devices: Array(archive.selected.prefix(4)), chinese: chinese, diameter: 58)
                .frame(height: 145)
            Divider().padding(.horizontal, 22)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(archive.devices) { device in
                        HStack(spacing: 12) {
                            Image(systemName: device.kind.symbol).font(.system(size: 20)).foregroundStyle(.secondary).frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(device.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                HStack(spacing: 4) {
                                    Text(device.source)
                                    if device.stale() { Text(chinese ? "· 上次读数" : "· last reading") }
                                }.font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 5)
                            if device.charging == true && !device.stale() { Image(systemName: "bolt.fill").font(.system(size: 11)).foregroundStyle(.green) }
                            Text("\(device.percent)%").font(.system(size: 14, weight: .medium)).monospacedDigit()
                                .foregroundStyle(device.stale() ? .secondary : .primary)
                        }.padding(.vertical, 10).padding(.horizontal, 22)
                        .help((chinese ? "读取于 " : "Read at ") + device.observedAt.formatted(date: .omitted, time: .standard) + (device.source == "Bluetooth" ? (chinese ? "；随 macOS 蓝牙缓存更新" : "; follows the macOS Bluetooth cache") : ""))
                    }
                }
            }.frame(maxHeight: .infinity)
            HStack {
                if let completed {
                    Text((chinese ? "读取 " : "Read ") + completed.formatted(date: .omitted, time: .standard))
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                } else {
                    Text(chinese ? "正在读取…" : "Reading…").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                Spacer()
                Button(action: onSettings) { Image(systemName: "slider.horizontal.3").frame(width: 24, height: 24) }.buttonStyle(.plain)
                    .help(chinese ? "设置" : "Settings")
            }.padding(.horizontal, 22).padding(.vertical, 12)
        }
    }
}

final class DevicePanelController: NSViewController {
    let width: CGFloat = 360
    let height: CGFloat = 480
    var onBack: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onSettings: ((NSButton) -> Void)?
    private var host: NSHostingView<DevicesContent>?
    private var archive = BatteryArchive()
    private var completed: Date?
    private let settingsAnchor = NSButton(frame: NSRect(x: 308, y: 10, width: 30, height: 25))
    override func loadView() {
        let bounds = NSRect(x: 0, y: 0, width: width, height: height)
        let content = NSView(frame: bounds)
        content.autoresizingMask = [.width, .height]
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: bounds); glass.style = .regular; glass.cornerRadius = 24; glass.contentView = content; view = glass
        } else {
            let material = NSVisualEffectView(frame: bounds); material.material = .popover; material.state = .active; material.addSubview(content); view = material
        }
        let hosting = NSHostingView(rootView: makeContent()); hosting.sizingOptions = []; hosting.frame = bounds; hosting.autoresizingMask = [.width, .height]
        content.addSubview(hosting); host = hosting
        settingsAnchor.isHidden = true; content.addSubview(settingsAnchor)
    }
    private func makeContent() -> DevicesContent {
        DevicesContent(archive: archive, completed: completed, onBack: { [weak self] in self?.onBack?() }, onRefresh: { [weak self] in self?.onRefresh?() }, onSettings: { [weak self] in guard let self else { return }; self.onSettings?(self.settingsAnchor) })
    }
    func update(_ a: BatteryArchive, completed: Date?) { archive = a; self.completed = completed; host?.rootView = makeContent() }

}
