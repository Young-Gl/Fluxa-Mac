import Foundation
import CoreFoundation

enum PowerState: String, Codable {
    case charging, discharging, pluggedIdle, supplemental, waiting, unavailable
    var title: String {
        switch self {
        case .charging: return L10n.text("正在充电", "Charging")
        case .discharging: return L10n.text("电池供电", "On battery")
        case .pluggedIdle: return L10n.text("接电 · 电池未充电", "Plugged in · battery idle")
        case .supplemental: return L10n.text("接电 · 电池仍在放电", "Plugged in · battery draining")
        case .waiting: return L10n.text("等待电源数据更新", "Waiting for power data")
        case .unavailable: return L10n.text("暂时无法读取功率", "Power data unavailable")
        }
    }
}

struct PowerSnapshot: Codable {
    var sampledAt: Date = Date()
    var breakdown: PowerBreakdown?
    var connected: Bool?
    var state: PowerState = .unavailable
    var inputW: Double?
    var systemW: Double?
    // Positive = into battery; negative = battery supplying the Mac.
    var netBatteryW: Double?
    var measuredBatteryW: Double?
    var batteryTerminalW: Double?
    var voltageV: Double?
    var currentA: Double?
    var adapterLimitW: Double?
    var batteryPercent: Int?
    var source = "IOKit"
    var estimated = false
    var note = ""
    var telemetryCounter: Int64?

    var barW: Double? { connected == true ? inputW : systemW }
    var symbol: String {
        switch state {
        case .charging: return "bolt"
        case .supplemental: return "bolt"
        case .pluggedIdle: return "bolt"
        case .discharging: return "battery.50percent"
        case .waiting: return "arrow.triangle.2.circlepath"
        case .unavailable: return "questionmark.circle"
        }
    }
    var fingerprint: String {
        let values = [inputW, systemW, netBatteryW, voltageV, currentA].map { $0.map { String($0) } ?? "nil" }
        return (connected.map { String($0) } ?? "nil") + "|" + values.joined(separator: "|") + "|" + state.rawValue
    }
}

struct PowerDecoder {
    // IOKit can expose negative values as unsigned two's-complement numbers.
    static func number(_ dictionary: [String: Any], _ key: String) -> Double? {
        guard let n = dictionary[key] as? NSNumber,
              CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let value = Double(n.int64Value)
        return value.isFinite ? value : nil
    }
    static func flag(_ dictionary: [String: Any], _ key: String) -> Bool? {
        guard let n = dictionary[key] as? NSNumber,
              n == 0 || n == 1 else { return nil }
        return n.boolValue
    }
    static func dictionary(_ parent: [String: Any], _ key: String) -> [String: Any] {
        parent[key] as? [String: Any] ?? [:]
    }
    static func valid(_ value: Double?, min lower: Double, max upper: Double) -> Double? {
        guard let value, value.isFinite, value >= lower, value <= upper else { return nil }
        return value
    }
    static func watts(_ dictionary: [String: Any], _ key: String, signed: Bool = false) -> Double? {
        valid(number(dictionary, key).map { $0 / 1000 }, min: signed ? -1000 : 0, max: 1000)
    }

    private static func percentage(_ value: Double) -> Int? {
        guard value.isFinite else { return nil }
        return Int(Swift.min(100, Swift.max(0, value.rounded())))
    }
    static func decode(_ raw: [String: Any], at date: Date = Date()) -> PowerSnapshot {
        var s = PowerSnapshot(sampledAt: date)
        guard !raw.isEmpty, flag(raw, "BatteryInstalled") != false else {
            s.note = "未检测到内置电池。此应用适用于 MacBook。"
            return s
        }
        guard let connected = flag(raw, "ExternalConnected") else {
            s.note = "系统未提供电源连接状态。"
            return s
        }
        s.connected = connected
        let telemetry = dictionary(raw, "PowerTelemetryData")
        let adapter = dictionary(raw, "AdapterDetails")
        let battery = dictionary(raw, "BatteryData")
        if let now = number(raw, "CurrentCapacity"), let max = number(raw, "MaxCapacity"),
           now >= 0, max > 0, now <= max {
            s.batteryPercent = percentage(now / max * 100)
        } else if let now = number(battery, "CurrentCapacity"),
                  let max = number(battery, "MaxCapacity"), now >= 0, max > 0, now <= max {
            // BatteryData capacity can be mAh. It is not a percentage without a matching maximum.
            s.batteryPercent = percentage(now / max * 100)
        }
        let rawInput = watts(telemetry, "SystemPowerIn")
        let rawLoad = watts(telemetry, "SystemLoad")
        let rawBattery = watts(telemetry, "BatteryPower", signed: true)
        if let n = telemetry["SystemLoadAccumulatorCount"] as? NSNumber {
            s.telemetryCounter = n.int64Value
        }
        let batteryVoltage = valid(number(raw, "Voltage"), min: 1000, max: 60000)
        let amperage = valid(number(raw, "InstantAmperage") ?? number(raw, "Amperage"), min: -50000, max: 50000)
        if let batteryVoltage, let amperage {
            s.batteryTerminalW = valid(batteryVoltage * amperage / 1_000_000, min: -1000, max: 1000)
        }
        if connected {
            s.adapterLimitW = valid(number(adapter, "Watts"), min: 1, max: 1000)
            s.voltageV = valid(number(telemetry, "SystemVoltageIn").map { $0 / 1000 }, min: 1, max: 60)
            s.currentA = valid(number(telemetry, "SystemCurrentIn").map { $0 / 1000 }, min: 0, max: 50)
            // Never substitute AdapterDetails.Watts: it is negotiated capacity, not measured input.
            s.inputW = rawInput
            if s.inputW == nil, let v = s.voltageV, let a = s.currentA {
                s.inputW = valid(v * a, min: 0, max: 1000)
                s.estimated = true
            }
            // SystemLoad and SystemPowerIn come from the same telemetry snapshot.
            s.systemW = rawLoad
            s.measuredBatteryW = rawBattery
            if let input = s.inputW, let load = s.systemW {
                s.netBatteryW = input - load
                if let battery = rawBattery, abs(input - load - battery) > max(1, input * 0.05) {
                    s.note = "输入与电池遥测暂未同步；净功率按输入减去运行功耗计算。"
                }
            } else if let input = s.inputW, let battery = rawBattery ?? s.batteryTerminalW {
                s.systemW = valid(input - battery, min: 0, max: 1000)
                if s.systemW != nil { s.netBatteryW = battery; s.estimated = true }
            } else if s.systemW == nil {
                s.netBatteryW = s.batteryTerminalW
                s.estimated = s.batteryTerminalW != nil
            }
            if let input = s.inputW, input < 0.1 {
                // The previous battery-only telemetry can persist briefly after plugging in.
                s.inputW = nil; s.systemW = nil; s.netBatteryW = nil
                s.measuredBatteryW = nil; s.voltageV = nil; s.currentA = nil
                s.state = .waiting
                s.note = "已接电源，等待系统提供有效输入功率。"
            } else if let net = s.netBatteryW {
                s.state = net > 0.15 ? .charging : (net < -0.15 ? .supplemental : .pluggedIdle)
            } else {
                s.state = s.inputW == nil ? .unavailable : .pluggedIdle
                s.note = "系统未提供完整遥测，缺失项目显示为 —。"
            }
        } else {
            s.inputW = 0
            // Ignore cached AC telemetry after unplugging. Never show old charging watts as consumption.
            if let input = rawInput, input < 0.1, let load = rawLoad,
               rawBattery == nil || (rawBattery! <= 0.1 && abs(load + rawBattery!) <= max(1, load * 0.05)) {
                s.systemW = load
                s.measuredBatteryW = rawBattery
                s.netBatteryW = -load
            } else if let terminal = s.batteryTerminalW, terminal <= 0 {
                s.systemW = -terminal
                s.netBatteryW = terminal
                s.estimated = true
                s.note = "耗电功率由电池电压 × 放电电流估算。"
            } else if rawInput == nil, let battery = rawBattery, battery <= 0 {
                s.systemW = -battery
                s.netBatteryW = battery
                s.estimated = true
            } else {
                s.state = .waiting
                s.note = "已切换电池供电，等待放电读数更新。"
            }
            if s.systemW != nil { s.state = .discharging }
            s.voltageV = batteryVoltage.map { $0 / 1000 }
            if let amperage, amperage <= 0 { s.currentA = abs(amperage) / 1000 }
        }
        return s
    }
}

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int { Swift.min(range.upperBound, Swift.max(range.lowerBound, self)) }
}

func wattText(_ value: Double?, signed: Bool = false, unit: Bool = true) -> String {
    guard let value, value.isFinite else { return unit ? "— W" : "—" }
    let n = abs(value) < 0.05 ? 0 : value
    return String(format: signed && n > 0 ? "+%.1f" : "%.1f", n) + (unit ? " W" : "")
}
