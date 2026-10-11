import Foundation
import IOKit

final class PowerReader {
    private var service: io_service_t = 0
    private let smc = SMCReader()
    private var energy: EnergyReader?
    var energySubscriptionActive: Bool { energy != nil }
    func stopDetails() { energy = nil }
    deinit { if service != 0 { IOObjectRelease(service) } }

    func properties() -> [String: Any]? {
        if service == 0 {
            service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        }
        guard service != 0 else { return nil }
        var properties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS, let properties else {
            IOObjectRelease(service); service = 0
            return nil
        }
        return properties.takeRetainedValue() as NSDictionary as? [String: Any]
    }
    func read(includeDetails: Bool = false) -> PowerSnapshot {
        if !includeDetails { stopDetails() }
        guard var raw = properties() else {
            var s = PowerSnapshot()
            s.note = "暂时无法读取系统功率数据；稍后会自动重试。"
            return s
        }
        // Prefer the live SMC power meters. IORegistry power telemetry on this Mac
        // refreshed once per minute; these meters change at every 2-second sample.
        var usesSMC = false
        if let input = PowerDecoder.valid(smc.read("PDTR"), min: 0, max: 1000),
           let load = PowerDecoder.valid(smc.read("PSTR"), min: 0, max: 1000),
           PowerDecoder.flag(raw, "BatteryInstalled") != false {
            var telemetry = PowerDecoder.dictionary(raw, "PowerTelemetryData")
            telemetry["SystemPowerIn"] = NSNumber(value: Int64((input * 1000).rounded()))
            telemetry["SystemLoad"] = NSNumber(value: Int64((load * 1000).rounded()))
            telemetry.removeValue(forKey: "BatteryPower")
            telemetry.removeValue(forKey: "SystemVoltageIn")
            telemetry.removeValue(forKey: "SystemCurrentIn")
            if let volts = PowerDecoder.valid(smc.read("VD0R"), min: 0, max: 60) {
                telemetry["SystemVoltageIn"] = NSNumber(value: Int64((volts * 1000).rounded()))
            }
            if let amps = PowerDecoder.valid(smc.read("ID0R"), min: 0, max: 50) {
                telemetry["SystemCurrentIn"] = NSNumber(value: Int64((amps * 1000).rounded()))
            }
            raw["PowerTelemetryData"] = telemetry
            // Battery voltage/current in IORegistry may have the slower cadence.
            raw.removeValue(forKey: "InstantAmperage")
            raw.removeValue(forKey: "Amperage")
            if let volts = PowerDecoder.valid(smc.read("SBAV"), min: 1, max: 60) {
                raw["Voltage"] = NSNumber(value: Int64((volts * 1000).rounded()))
            }
            usesSMC = true
        }
        var snapshot = PowerDecoder.decode(raw)
        if usesSMC { snapshot.source = "SMC" }
        if includeDetails {
            if energy == nil { energy = EnergyReader() }
            var details = PowerBreakdown()
            details.energy = energy?.read() ?? EnergyValues()
            // Only use a known backlight meter, never assign an undocumented rail to the screen.
            details.screenBacklightW = PowerDecoder.valid(smc.read("PBwo"), min: 0, max: 100)
            if let outputs = raw["PowerOutDetails"] as? [[String: Any]] {
                for port in outputs {
                    guard let watts = PowerDecoder.watts(port, "Watts"), let index = Int(exactly: PowerDecoder.number(port, "PortIndex") ?? 0), index >= 0 else { continue }
                    details.ports.append(USBOutput(index: index, watts: watts,
                        volts: PowerDecoder.number(port, "AdapterVoltage").map { $0 / 1000 },
                        amps: PowerDecoder.number(port, "Current").map { $0 / 1000 }))
                }
                if outputs.isEmpty || !details.ports.isEmpty { details.usbW = details.ports.reduce(0) { $0 + $1.watts } }
            }
            if let timestamp = PowerDecoder.number(raw, "UpdateTime"), timestamp > 0,
               timestamp <= Date().timeIntervalSince1970 + 300 {
                details.usbUpdatedAt = Date(timeIntervalSince1970: timestamp)
            }
            // Residual is approximate: component counters are interval averages, PSTR is instantaneous.
            if let total = snapshot.systemW, let cpu = details.energy.cpuW, let gpu = details.energy.gpuW, let usb = details.usbW {
                let residual = total - cpu - gpu - usb - (details.energy.aneW ?? 0) - (details.energy.memoryW ?? 0) - (details.screenBacklightW ?? 0)
                details.otherW = residual >= 0 ? residual : nil
            }
            snapshot.breakdown = details
        }
        return snapshot
    }
}
