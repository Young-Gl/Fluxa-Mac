import Foundation
import AppKit
import Darwin

@main struct DeviceAudit {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        precondition(condition(), label); checks += 1
    }
    static func main() {
        let now = Date()
        let telemetry: [String: Any] = ["SystemPowerIn": 90000, "SystemLoad": 25000, "BatteryPower": 65000]
        var raw: [String: Any] = ["BatteryInstalled": true, "ExternalConnected": true, "CurrentCapacity": 50, "MaxCapacity": 100,
                                  "PowerTelemetryData": telemetry, "AdapterDetails": ["Watts": 140]]
        var power = PowerDecoder.decode(raw)
        check(power.state == .charging && power.barW == 90 && power.systemW == 25 && power.netBatteryW == 65 && power.batteryPercent == 50, "Charging uses input and net power, not adapter rating")
        raw["PowerTelemetryData"] = ["SystemPowerIn": 30000, "SystemLoad": 45000, "BatteryPower": -15000]
        power = PowerDecoder.decode(raw)
        check(power.state == .supplemental && power.netBatteryW == -15 && power.barW == 30, "Weak charger can still drain the battery")
        raw["PowerTelemetryData"] = ["SystemPowerIn": 30000, "SystemLoad": 30000]
        check(PowerDecoder.decode(raw).state == .pluggedIdle, "Plugged in without net charging")
        raw["PowerTelemetryData"] = ["SystemPowerIn": 0, "SystemLoad": 5000]
        power = PowerDecoder.decode(raw)
        check(power.state == .waiting && power.barW == nil, "Stale zero input on AC is hidden")
        raw["ExternalConnected"] = false; raw["PowerTelemetryData"] = telemetry
        raw["Voltage"] = 13000; raw["InstantAmperage"] = -1000
        power = PowerDecoder.decode(raw)
        check(power.state == .discharging && power.systemW == 13 && power.netBatteryW == -13 && power.estimated, "Cached AC values cannot become battery consumption")
        raw["PowerTelemetryData"] = ["SystemPowerIn": 0, "SystemLoad": 7500, "BatteryPower": -7500]
        power = PowerDecoder.decode(raw)
        check(power.systemW == 7.5 && power.netBatteryW == -7.5 && !power.estimated, "Battery telemetry shows live consumption")
        raw["ExternalConnected"] = true
        raw["PowerTelemetryData"] = ["SystemVoltageIn": 20000, "SystemCurrentIn": 2000, "SystemLoad": 20000]
        power = PowerDecoder.decode(raw)
        check(power.inputW == 40 && power.netBatteryW == 20 && power.estimated, "Voltage-current fallback is marked estimated")
        raw.removeValue(forKey: "PowerTelemetryData"); raw.removeValue(forKey: "InstantAmperage")
        check(PowerDecoder.decode(raw).barW == nil, "Negotiated adapter rating is never a measured reading")
        raw.removeValue(forKey: "CurrentCapacity"); raw.removeValue(forKey: "MaxCapacity")
        raw["BatteryData"] = ["CurrentCapacity": 4200]
        check(PowerDecoder.decode(raw).batteryPercent == nil, "Raw mAh without a maximum is not 100 percent")
        raw["BatteryData"] = ["CurrentCapacity": 3000, "MaxCapacity": 6000]
        check(PowerDecoder.decode(raw).batteryPercent == 50, "Capacity ratio fallback uses matching units")
        raw["BatteryData"] = ["CurrentCapacity": -1, "MaxCapacity": 6000]
        check(PowerDecoder.decode(raw).batteryPercent == nil, "Invalid capacity is hidden")
        check(PowerDecoder.flag(["flag": 2], "flag") == nil && PowerDecoder.number(["n": true], "n") == nil, "Malformed flags and Boolean measurements rejected")
        check(PowerDecoder.number(["n": NSNumber(value: UInt64.max)], "n") == -1, "Unsigned two's-complement discharge preserved")
        check(PowerDecoder.decode([:]).state == .unavailable && PowerDecoder.decode(["BatteryInstalled": false]).barW == nil, "Missing battery yields no invented power")
        check(DeviceBattery.level(true) == nil, "Boolean is not a percentage")
        check(DeviceBattery.level(NSNumber(value: Double.infinity)) == nil, "Infinity rejected")
        check(DeviceBattery.level(NSNumber(value: 1e30)) == nil, "Huge number rejected without conversion trap")
        check(DeviceBattery.level(-1) == nil && DeviceBattery.level(101) == nil, "Out of bounds")
        check(DeviceBattery.level("85%") == 85 && DeviceBattery.level(0) == 0, "Real percentage including empty battery")
        check(DeviceBattery.cleanName("bad\nname", fallback: "?") == "badname", "Control characters removed")
        check(DeviceBattery.cleanName(" \t ", fallback: "Bluetooth") == "Bluetooth", "Blank device names use a visible fallback")
        check(DeviceBattery.cleanName(String(repeating: "x", count: 10000), fallback: "?").count == 64, "Name bounded")
        check(DeviceBattery.safeID("private-device-id").count == 24 && !DeviceBattery.safeID("private-device-id").contains("private"), "IDs are hashed")
        let bt: [String: Any] = ["SPBluetoothDataType": [["device_connected": [["Earphones": ["device_address": "private-address", "device_batteryLevelLeft": "85%", "device_batteryLevelRight": "91%", "device_batteryLevelCase": "unknown"]]]]]]
        let data = try! JSONSerialization.data(withJSONObject: bt)
        let split = DeviceDecoder.bluetooth(data, at: now)
        check(split.count == 2 && split.map(\.percent) == [85,91], "Two ear batteries, unavailable case hidden")
        check(DeviceDecoder.bluetooth(Data("malformed".utf8)).isEmpty, "Bad Bluetooth JSON")
        let plist: [[String: Any]] = [["ID": "phone", "Name": "Phone", "Kind": "iPhone", "BatteryCurrentCapacity": 64, "BatteryIsCharging": true], ["ID": "ipad", "Kind": "iPad", "BatteryCurrentCapacity": 75], ["ID": "watch", "Kind": "Watch", "BatteryCurrentCapacity": 100], ["ID": "bad", "Kind": "iPhone", "BatteryCurrentCapacity": true]]
        let mobile = DeviceDecoder.mobile(try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0), at: now)
        check(mobile.count == 3 && mobile[1].kind == .tablet && mobile[2].kind == .watch && mobile[0].charging == true, "Phone, tablet, Watch and malformed percentage")
        check(DeviceDecoder.mobile(Data("bad".utf8)).isEmpty, "Bad mobile XML")
        var old = split[0]; old.observedAt = now.addingTimeInterval(-70)
        let offline = BatteryArchive.merge(old: [old], fresh: [], at: now)
        check(offline.count == 1 && offline[0].disconnected && offline[0].stale(at: now), "Disconnected reading visibly stale")
        check(BatteryArchive.merge(old: [old], fresh: split, at: now).count == 2, "No duplicates")
        old.observedAt = now.addingTimeInterval(-3601)
        check(BatteryArchive.merge(old: [old], fresh: [], at: now).isEmpty, "Expired device removed")
        let many = (0..<1000).map { DeviceBattery(id: "\($0)", name: "\($0)", kind: .phone, percent: 50, observedAt: now, source: "Test") }
        check(BatteryArchive.merge(old: [], fresh: many, at: now).count == 32, "Device count bounded")
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("Fluxa-device-audit-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let file = tmp.appendingPathComponent("batteries.json")
        check(BatteryStore.write(BatteryArchive(devices: split), to: file), "Atomic cache write")
        for _ in 0..<100 { _ = BatteryStore.write(BatteryArchive(devices: split), to: file) }
        check(BatteryStore.read(file).devices.count == 2 && (try! FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)).count == 1, "Overwrite, no accumulating files")
        try! Data(repeating: 32, count: 65537).write(to: file)
        check(BatteryStore.read(file).devices.isEmpty, "Oversized cache rejected")
        var future = split[0]; future.observedAt = now.addingTimeInterval(3600)
        _ = BatteryStore.write(BatteryArchive(devices: [split[0], split[0], future]), to: file)
        check(BatteryStore.read(file).devices.count == 1, "Duplicate and future-dated cache entries rejected")
        var selected = BatteryArchive(devices: split)
        check(selected.selected.count == 2, "Default selection includes available devices")
        selected.customSelection = true
        check(selected.selected.isEmpty, "Explicitly empty selection stays empty")
        selected.selectedIDs = [split[1].id]
        check(selected.selected.map(\.id) == [split[1].id], "Explicit selection retains its order")
        var legacy = selected; legacy.customSelection = nil
        check(legacy.selected.map(\.id) == [split[1].id], "Legacy nonempty selections remain compatible")
        var oldJSON = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(selected)) as! [String: Any]
        oldJSON.removeValue(forKey: "customSelection")
        check((try! JSONDecoder().decode(BatteryArchive.self, from: JSONSerialization.data(withJSONObject: oldJSON))).selected.count == 1, "Older cache schema decodes without the new optional field")
        let command = BoundedCommand(); command.begin()
        check(String(data: command.run(URL(fileURLWithPath: "/usr/bin/printf"), ["hello"])!, encoding: .utf8) == "hello", "Bounded command drains output")
        check(command.run(URL(fileURLWithPath: "/usr/bin/false"), []) == nil, "Nonzero exit rejected")
        check(command.run(URL(fileURLWithPath: "/does/not/exist"), []) == nil, "Missing executable handled")
        let began = ProcessInfo.processInfo.systemUptime
        check(command.run(URL(fileURLWithPath: "/bin/sleep"), ["10"], timeout: 0.15) == nil, "Timeout child killed and reaped")
        check(ProcessInfo.processInfo.systemUptime - began < 1, "Timeout bounded")
        check(command.run(URL(fileURLWithPath: "/usr/bin/yes"), [], limit: 4096) == nil, "Flooding output killed at cap")
        command.cancel()
        check(command.run(URL(fileURLWithPath: "/usr/bin/true"), []) == nil, "Cancelled worker cannot launch")
        command.begin()
        let group = DispatchGroup(); group.enter()
        DispatchQueue.global().async { _ = command.run(URL(fileURLWithPath: "/bin/sleep"), ["10"], timeout: 12); group.leave() }
        Thread.sleep(forTimeInterval: 0.1); command.cancel()
        check(group.wait(timeout: .now() + 1) == .success, "In-flight cancellation reaps child")
        for _ in 0..<100 { command.begin(); _ = command.run(URL(fileURLWithPath: "/usr/bin/true"), []) }
        func descriptors() -> Int { (0..<256).filter { fcntl(Int32($0), F_GETFD) != -1 }.count }
        let initialFDs = descriptors()
        for _ in 0..<100 { autoreleasepool { _ = command.run(URL(fileURLWithPath: "/does/not/exist"), []) } }
        check(descriptors() <= initialFDs + 1, "Repeated launch failures do not leak file descriptors")
        let suiteName = "local.hanchao.FluxaAudit." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let monitor = DeviceBatteryMonitor(defaults: defaults)
        var completed = 0
        monitor.auditCollect = { Thread.sleep(forTimeInterval: 0.15); return split }
        monitor.onUpdate = { _ in completed += 1 }
        monitor.start()
        for _ in 0..<20000 { monitor.refresh() }
        check(monitor.diagnostic["busy"] as? Bool == true, "Device requests coalesce into one active worker")
        monitor.setPaused(true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        check(completed == 0 && monitor.cycles == 0 && monitor.diagnostic["timerActive"] as? Bool == false, "Sleep cancels publication and device timer")
        monitor.setPaused(false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        check(monitor.cycles == 1 && completed == 1, "Wake starts exactly one fresh device cycle")
        for _ in 0..<20000 { monitor.refresh() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        check(monitor.cycles == 1, "Repeated refresh cannot exceed cooldown")
        monitor.select(split[0].id); monitor.select(split[1].id)
        check(monitor.archive.usesCustomSelection && monitor.archive.selected.isEmpty, "Unchecking the final device does not select everything again")
        monitor.resetSelection()
        check(!monitor.archive.usesCustomSelection && monitor.archive.selected.count == 2, "Automatic selection restores available devices")
        monitor.select("missing")
        check(!monitor.archive.usesCustomSelection, "Unknown IDs cannot occupy widget slots")
        monitor.stop()
        // Existing power sampling coalescing and sleep invariants still apply.
        let app = NSApplication.shared
        let delegate = WattsAppDelegate(); app.delegate = delegate
        delegate.auditStart()
        let first = delegate.auditCount
        for _ in 0..<20000 { delegate.auditRequest() }
        check(delegate.auditCount <= first + 1 && delegate.auditPending, "Power sample requests coalesce")
        delegate.auditSetActivity(.displaySleep, paused: true)
        delegate.auditSetActivity(.systemSleep, paused: true)
        check(!delegate.auditTimerActive && !delegate.auditPending && delegate.auditPaused, "Sleep stops power work")
        delegate.auditSetActivity(.displaySleep, paused: false)
        check(delegate.auditPaused && !delegate.auditTimerActive, "Partial wake stays paused")
        delegate.auditSetActivity(.systemSleep, paused: false)
        check(!delegate.auditPaused && delegate.auditTimerActive, "Full wake resumes one timer")
        delegate.auditStop()
        print("PASS: \(checks) device, child-process, cache and power lifecycle checks")
    }
}
