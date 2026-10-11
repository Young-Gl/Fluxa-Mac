import Foundation
import IOKit

struct EnergyValues: Codable {
    var cpuW: Double?
    var gpuW: Double?
    var aneW: Double?
    var memoryW: Double?
    var intervalSeconds: Double?
    var source = "IOReport"
}

final class EnergyReader {
    private var subscription: OpaquePointer?
    private var subscribedChannels: CFMutableDictionary?
    private var baseline: CFDictionary?
    private var baselineUptime: Double = 0

    init() {
        var selected: [NSMutableDictionary] = []
        if let group = IOReportCopyChannelsInGroup("Energy Model" as CFString, nil, 0, 0, 0),
           let channels = (group as NSDictionary)["IOReportChannels"] as? [[String: Any]] {
            for c in channels {
                let legend = c["LegendChannel"] as? [Any] ?? []
                let name = legend.count > 2 ? legend[2] as? String ?? "" : ""
                if name.hasSuffix("CPU Energy") || name == "GPU Energy" || name.hasPrefix("ANE") || name.hasPrefix("DRAM") {
                    selected.append(NSMutableDictionary(dictionary: c))
                }
            }
        }
        selected += Self.clpcChannels()
        guard !selected.isEmpty else { return }
        let desired = ["IOReportChannels": selected] as CFDictionary
        var unmanaged: Unmanaged<CFMutableDictionary>?
        subscription = IOReportCreateSubscription(nil, desired, &unmanaged, 0, nil)
        subscribedChannels = unmanaged?.takeRetainedValue()
        if let subscription, let subscribedChannels {
            baseline = IOReportCreateSamples(subscription, subscribedChannels, nil)
            baselineUptime = ProcessInfo.processInfo.systemUptime
        }
    }
    deinit {
        if let subscription { Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(subscription)).release() }
    }

    // Driver-specific macOS 27 report IDs, independently guarded by OS and actual driver.
    // Reference: macmon/src/clpc.rs (MIT), https://github.com/vladkens/macmon
    private static func clpcChannels() -> [NSMutableDictionary] {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27 else { return [] }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleCLPC"))
        guard service != 0 else { return [] }
        defer { IOObjectRelease(service) }
        guard let bundle = IORegistryEntryCreateCFProperty(service, "CFBundleIdentifier" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
              bundle == "com.apple.driver.AppleT8132CLPC" else { return [] }
        var driver: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(service, &driver) == KERN_SUCCESS else { return [] }
        let ids: [(UInt64, String)] = [(0x000000104a854d94, "CPU Energy"), (0x000000193b3e3b79, "GPU Energy"), (0x000000181ff4a9ec, "ANE")]
        return ids.map { id, name in
            NSMutableDictionary(dictionary: [
                "DriverID": NSNumber(value: driver), "DriverName": "AppleCLPC",
                "IOReportGroupName": "CLPC", "IOReportSubGroupName": "Energy Counters",
                "LegendChannel": [NSNumber(value: id), NSNumber(value: UInt64(1 | (2 << 16) | (1 << 32))), name],
                "IOReportChannelInfo": ["IOReportChannelUnit": NSNumber(value: UInt64(3 << 56) | UInt64(118 << 32))]
            ])
        }
    }

    func read() -> EnergyValues {
        var result = EnergyValues()
        guard let subscription, let channels = subscribedChannels,
              let next = IOReportCreateSamples(subscription, channels, nil) else { return result }
        let uptime = ProcessInfo.processInfo.systemUptime
        defer { baseline = next; baselineUptime = uptime }
        guard let baseline, uptime - baselineUptime >= 0.3,
              let delta = IOReportCreateSamplesDelta(baseline, next, nil),
              let items = (delta as NSDictionary)["IOReportChannels"] as? [NSMutableDictionary] else { return result }
        let dt = uptime - baselineUptime
        result.intervalSeconds = dt
        var legacy: [String: Double] = [:]
        var clpc: [String: Double] = [:]
        for item in items {
            let c = item as CFDictionary
            let name = (IOReportChannelGetChannelName(c) as String?) ?? ""
            let unit = (IOReportChannelGetUnitLabel(c) as String?) ?? ""
            let integer = IOReportSimpleGetIntegerValue(c, 0)
            guard integer >= 0 else { continue }
            let scale: Double
            switch unit.trimmingCharacters(in: .whitespacesAndNewlines) {
            case "J": scale = 1
            case "mJ": scale = 1e-3
            case "uJ", "µJ": scale = 1e-6
            case "nJ": scale = 1e-9
            default: continue
            }
            let watts = Double(integer) * scale / dt
            guard watts.isFinite, watts >= 0, watts < 1000 else { continue }
            let key: String
            if name.hasSuffix("CPU Energy") { key = "cpu" }
            else if name == "GPU Energy" { key = "gpu" }
            else if name.hasPrefix("ANE") { key = "ane" }
            else if name.hasPrefix("DRAM") { key = "memory" }
            else { continue }
            if item["IOReportGroupName"] as? String == "CLPC" { clpc[key, default: 0] += watts }
            else { legacy[key, default: 0] += watts }
        }
        result.cpuW = clpc["cpu"] ?? legacy["cpu"]
        result.gpuW = clpc["gpu"] ?? legacy["gpu"]
        result.aneW = clpc["ane"] ?? legacy["ane"]
        result.memoryW = legacy["memory"]
        // On macOS 27 the old PMGR energy counters can be frozen. Do not call those zero watts.
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27 {
            if clpc["cpu"] == nil && result.cpuW == 0 { result.cpuW = nil }
            if clpc["gpu"] == nil && result.gpuW == 0 { result.gpuW = nil }
            if clpc["ane"] == nil && result.aneW == 0 { result.aneW = nil }
            if result.memoryW == 0 { result.memoryW = nil }
        }
        if !clpc.isEmpty { result.source = "CLPC / IOReport" }
        return result
    }
}
