import SwiftUI

struct BatteryRing: View {
    let device: DeviceBattery
    var diameter: CGFloat = 60
    var showName = false
    var date = Date()
    var chinese = false
    private var stale: Bool { device.stale(at: date) }
    private var accent: Color { stale ? .secondary : (device.percent <= 15 ? .red : device.percent <= 25 ? .orange : Color(red: 0.05, green: 0.82, blue: 0.33)) }
    var body: some View {
        VStack(spacing: 9) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.13), lineWidth: 6)
                Circle().trim(from: 0, to: CGFloat(device.percent) / 100)
                    .stroke(accent, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
                Image(systemName: device.kind.symbol).font(.system(size: diameter * 0.35, weight: .regular)).foregroundStyle(.secondary)
                if device.charging == true && !stale {
                    Image(systemName: "bolt.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary)
                        .shadow(color: .black.opacity(0.2), radius: 2).offset(y: -diameter / 2)
                }
            }.frame(width: diameter, height: diameter)
            Text("\(device.percent)%").font(.system(size: diameter * 0.29, weight: .medium, design: .rounded)).monospacedDigit()
                .foregroundStyle(stale ? .secondary : .primary)
            if showName { Text(device.name).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }
        }
        .opacity(stale ? 0.65 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(device.name), \(device.percent)%" + (device.charging == true ? (chinese ? "，正在充电" : ", charging") : "") + (stale ? (chinese ? "，上次读数" : ", last reading") : ""))
    }
}

struct BatteryRingGrid: View {
    let devices: [DeviceBattery]
    var chinese = false
    var diameter: CGFloat = 60
    var columns = 4
    var verticalPadding: CGFloat = 25
    var spacing: CGFloat = 18
    var date = Date()
    var emptyMessage: String?
    var body: some View {
        if devices.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "laptopcomputer.and.iphone").font(.system(size: 28)).foregroundStyle(.secondary)
                Text(emptyMessage ?? (chinese ? "打开 Fluxa 读取电量" : "Open Fluxa to read batteries")).font(.system(size: 12)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: max(1, columns)), spacing: spacing) {
                ForEach(devices) { BatteryRing(device: $0, diameter: diameter, date: date, chinese: chinese) }
            }.padding(.horizontal, 20).padding(.vertical, verticalPadding)
        }
    }
}
