import Foundation
import Darwin
import WidgetKit

// One bounded child at a time, on the monitor's worker queue. No shell, pairing or log scanner.
final class BoundedCommand {
    private let lock = NSLock()
    private var child: Process?
    private var cancelled = false
    private var launchCount = 0
    var launches: Int { lock.lock(); defer { lock.unlock() }; return launchCount }
    func begin() { lock.lock(); cancelled = false; lock.unlock() }
    func cancel() {
        lock.lock(); cancelled = true
        if let child, child.isRunning { kill(child.processIdentifier, SIGKILL) }
        lock.unlock()
    }
    var stopped: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func run(_ url: URL, _ args: [String], timeout: Double = 4, limit: Int = 262144) -> Data? {
        let pipe = Pipe(), p = Process()
        p.executableURL = url; p.arguments = args
        p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        lock.lock()
        guard !cancelled else { lock.unlock(); return nil }
        do { try p.run() } catch { lock.unlock(); return nil }
        child = p; launchCount += 1; lock.unlock()
        pipe.fileHandleForWriting.closeFile()
        let fd = pipe.fileHandleForReading.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        var data = Data(), buffer = [UInt8](repeating: 0, count: 8192), failed = false
        let deadline = ProcessInfo.processInfo.systemUptime + max(0.1, min(timeout, 12))
        while true {
            while true {
                let count = Darwin.read(fd, &buffer, buffer.count)
                if count <= 0 { break }
                if data.count + count > limit { failed = true; break }
                data.append(contentsOf: buffer.prefix(count))
            }
            if failed || stopped || ProcessInfo.processInfo.systemUptime >= deadline {
                failed = true
                if p.isRunning { kill(p.processIdentifier, SIGKILL) }
            }
            if !p.isRunning { break }
            Thread.sleep(forTimeInterval: 0.04)
        }
        p.waitUntilExit()
        // Drain bytes written immediately before exit; the nonblocking descriptor cannot hang.
        while !failed {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count <= 0 { break }
            if data.count + count > limit { failed = true; break }
            data.append(contentsOf: buffer.prefix(count))
        }
        pipe.fileHandleForReading.closeFile()
        lock.lock(); if child === p { child = nil }; lock.unlock()
        return !failed && p.terminationStatus == 0 ? data : nil
    }
}

enum DeviceDecoder {
    static func bluetooth(_ data: Data, at date: Date = Date()) -> [DeviceBattery] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        var result: [DeviceBattery] = []
        for entry in entries {
            for group in entry["device_connected"] as? [[String: Any]] ?? [] {
                for (name, object) in group {
                    guard let d = object as? [String: Any] else { continue }
                    let id = d["device_address"] as? String ?? name
                    let safeName = DeviceBattery.cleanName(name, fallback: "Bluetooth")
                    let parts: [(String, DeviceKind, String)] = [("device_batteryLevelLeft", .earLeft, " L"), ("device_batteryLevelRight", .earRight, " R"), ("device_batteryLevelCase", .earCase, " Case")]
                    var split = false
                    for (key, kind, suffix) in parts {
                        guard let percent = DeviceBattery.level(d[key]) else { continue }
                        split = true
                        result.append(DeviceBattery(id: DeviceBattery.safeID("bt:\(id):\(key)"), name: String((safeName + suffix).prefix(64)), kind: kind, percent: percent, observedAt: date, source: "Bluetooth"))
                    }
                    if !split, let percent = DeviceBattery.level(d["device_batteryLevelMain"]) {
                        let type = (d["device_minorType"] as? String ?? "").lowercased()
                        let kind: DeviceKind = type.contains("keyboard") ? .keyboard : type.contains("mouse") ? .mouse : type.contains("head") ? .headphones : .accessory
                        result.append(DeviceBattery(id: DeviceBattery.safeID("bt:\(id):main"), name: safeName, kind: kind, percent: percent, observedAt: date, source: "Bluetooth"))
                    }
                }
            }
        }
        return Array(result.prefix(32))
    }
    static func mobile(_ data: Data, at date: Date = Date()) -> [DeviceBattery] {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else { return [] }
        return root.prefix(16).compactMap { d in
            guard let id = d["ID"] as? String, let percent = DeviceBattery.level(d["BatteryCurrentCapacity"]),
                  let kindString = d["Kind"] as? String else { return nil }
            let kind: DeviceKind = kindString == "Watch" ? .watch : kindString == "iPad" ? .tablet : .phone
            return DeviceBattery(id: DeviceBattery.safeID("mobile:\(id)"), name: DeviceBattery.cleanName(d["Name"] as? String ?? "", fallback: kindString), kind: kind, percent: percent, charging: d["BatteryIsCharging"] as? Bool, observedAt: date, source: d["Source"] as? String ?? "USB")
        }
    }
}

final class DeviceBatteryMonitor {
    #if RESOURCE_AUDIT
    var auditCollect: (() -> [DeviceBattery])?
    #endif
    var onUpdate: ((BatteryArchive) -> Void)?
    private let queue = DispatchQueue(label: "local.hanchao.Watts.devices", qos: .utility)
    private let command = BoundedCommand()
    private let defaults: UserDefaults
    private var timer: Timer?
    private var busy = false
    private var generation = 0
    private var paused = false
    private var lastStarted: TimeInterval = -1000
    private var lastWrite: TimeInterval = -1000
    private var lastReload: TimeInterval = -1000
    private var lastSignature = ""
    private var lastWrittenSignature = ""
    private(set) var archive: BatteryArchive
    private(set) var cycles = 0
    private(set) var cacheWritable = true
    private(set) var lastDuration: Double = 0
    private(set) var lastCompleted: Date?
    private var mac: DeviceBattery?
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if RESOURCE_AUDIT
        archive = BatteryArchive()
        #else
        archive = BatteryStore.read(BatteryStore.hostURL)
        #endif
    }
    var diagnostic: [String: Any] { ["busy": busy, "paused": paused, "timerActive": timer?.isValid ?? false, "cycles": cycles, "intervalSeconds": 60, "childLaunches": command.launches, "lastCycleSeconds": lastDuration, "cacheWritable": cacheWritable, "cacheBytes": (try? FileManager.default.attributesOfItem(atPath: BatteryStore.hostURL.path)[.size]) ?? 0] }
    func start() {
        let savedSelection = defaults.stringArray(forKey: "widgetDeviceIDs")
        archive.selectedIDs = savedSelection ?? []
        archive.customSelection = savedSelection != nil
        archive.chinese = L10n.chinese
        restartTimer(); refresh()
    }
    private func restartTimer() {
        timer?.invalidate(); timer = nil
        guard !paused else { return }
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
        t.tolerance = 8; RunLoop.main.add(t, forMode: .common); timer = t
    }
    func setPaused(_ value: Bool) {
        guard paused != value else { return }
        paused = value; generation += 1
        if value { timer?.invalidate(); timer = nil; command.cancel() }
        else { lastStarted = -1000; restartTimer(); if !busy { refresh() } }
    }
    func stop() { paused = true; generation += 1; timer?.invalidate(); timer = nil; command.cancel() }
    func updateMac(_ s: PowerSnapshot) {
        guard let p = s.batteryPercent else { return }
        let old = mac
        mac = DeviceBattery(id: "this-mac", name: "Mac", kind: .mac, percent: p, charging: s.state == .waiting || s.state == .unavailable ? nil : s.state == .charging, observedAt: s.sampledAt, source: "Mac")
        if old?.percent != p || old?.charging != mac?.charging || old == nil {
            archive.devices.removeAll { $0.id == "this-mac" }; archive.devices.insert(mac!, at: 0); publish()
        }
    }
    func select(_ id: String) {
        guard archive.devices.contains(where: { $0.id == id }) else { return }
        var selected = archive.selected.map { $0.id }
        if selected.contains(id) { selected.removeAll { $0 == id } }
        else if selected.count < 8 { selected.append(id) }
        defaults.set(selected, forKey: "widgetDeviceIDs")
        archive.selectedIDs = selected; archive.customSelection = true; publish(forceWrite: true)
    }
    func resetSelection() {
        defaults.removeObject(forKey: "widgetDeviceIDs")
        archive.selectedIDs = []; archive.customSelection = false; publish(forceWrite: true)
    }
    func languageChanged() { archive.chinese = L10n.chinese; publish(forceWrite: true) }
    func refresh() {
        let now = ProcessInfo.processInfo.systemUptime
        guard !paused, !busy, now - lastStarted >= 15 else { return }
        busy = true; lastStarted = now; let token = generation
        command.begin()
        let base = Bundle.main.resourceURL?.appendingPathComponent("libimobiledevice")
        queue.async { [weak self] in
            guard let self else { return }
            let started = ProcessInfo.processInfo.systemUptime
            let fresh = autoreleasepool { () -> [DeviceBattery] in
                #if RESOURCE_AUDIT
                if let auditCollect = self.auditCollect { return auditCollect() }
                #endif
                return self.collect(base: base)
            }
            let duration = ProcessInfo.processInfo.systemUptime - started
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.busy = false
                guard !self.paused else { return }
                guard token == self.generation else { self.refresh(); return }
                self.cycles += 1; self.lastDuration = duration; self.lastCompleted = Date()
                var all = fresh
                if let mac = self.mac { all.insert(mac, at: 0) }
                self.archive.devices = BatteryArchive.merge(old: self.archive.devices, fresh: all, at: Date())
                self.publish(forceWrite: self.cycles == 1)
            }
        }
    }
    private func collect(base: URL?) -> [DeviceBattery] {
        var devices: [DeviceBattery] = []
        if let data = command.run(URL(fileURLWithPath: "/usr/sbin/system_profiler"), ["SPBluetoothDataType", "-json"], timeout: 5) { devices += DeviceDecoder.bluetooth(data) }
        guard let base, !command.stopped else { return devices }
        let bin = base.appendingPathComponent("bin"), list = bin.appendingPathComponent("idevice_id")
        var ids: [(String, String)] = [], seen = Set<String>()
        for (flag, transport) in [("-l", "usb"), ("-n", "network")] {
            guard let data = command.run(list, [flag], timeout: 3), let text = String(data: data, encoding: .utf8) else { continue }
            for line in text.split(whereSeparator: \.isNewline) {
                let id = String(line).trimmingCharacters(in: .whitespaces)
                guard id.count >= 20, id.count <= 64, id.allSatisfy({ $0.isHexDigit || $0 == "-" }), seen.insert(id).inserted else { continue }
                ids.append((id, transport))
            }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 20
        for (id, transport) in ids.prefix(4) {
            guard !command.stopped, ProcessInfo.processInfo.systemUptime < deadline else { break }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            let probe = bin.appendingPathComponent("FluxaDeviceProbe")
            if let data = command.run(probe, [id, transport, "phone"], timeout: min(4, remaining)) {
                let mobile = DeviceDecoder.mobile(data); devices += mobile
                let watchRemaining = deadline - ProcessInfo.processInfo.systemUptime
                if mobile.contains(where: { $0.kind == .phone }), watchRemaining > 0,
                   let watchData = command.run(probe, [id, transport, "watch"], timeout: min(6, watchRemaining)) { devices += DeviceDecoder.mobile(watchData) }
            }
        }
        return devices
    }
    private func publish(forceWrite: Bool = false) {
        archive.chinese = L10n.chinese
        let now = ProcessInfo.processInfo.systemUptime
        let signature = archive.devices.map { "\($0.id):\($0.percent):\(String(describing: $0.charging)):\($0.disconnected)" }.joined(separator: "|") + archive.selectedIDs.joined() + String(archive.chinese)
        let changed = signature != lastSignature
        lastSignature = signature
        // Fixed file, bounded devices, at most once a minute during normal polling.
        #if !RESOURCE_AUDIT
        if forceWrite || now - lastWrite >= 45 {
            archive.writtenAt = Date(); cacheWritable = BatteryStore.write(archive, to: BatteryStore.hostURL)
            if !cacheWritable { _ = BatteryStore.write(archive, to: diagnosticDirectory().appendingPathComponent("batteries.json")) }
            lastWrite = now
            if signature != lastWrittenSignature && (forceWrite || now - lastReload >= 60) {
                if #available(macOS 14.0, *) { WidgetCenter.shared.reloadTimelines(ofKind: "FluxaDevices") }
                lastReload = now
            }
            lastWrittenSignature = signature
        }
        #endif
        if changed || lastCompleted != nil { onUpdate?(archive) }
    }
}
