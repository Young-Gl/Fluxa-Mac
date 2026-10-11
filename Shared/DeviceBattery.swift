import Foundation
import CryptoKit
import CoreFoundation

enum DeviceKind: String, Codable {
    case mac, phone, tablet, watch, earLeft, earRight, earCase, headphones, keyboard, mouse, accessory
    var symbol: String {
        switch self {
        case .mac: return "laptopcomputer"
        case .phone: return "iphone"
        case .tablet: return "ipad"
        case .watch: return "applewatch"
        case .earLeft: return "airpodpro.left"
        case .earRight: return "airpodpro.right"
        case .earCase: return "airpodspro.chargingcase.wireless"
        case .headphones: return "headphones"
        case .keyboard: return "keyboard"
        case .mouse: return "computermouse"
        case .accessory: return "wave.3.right"
        }
    }
    var rank: Int {
        switch self { case .mac: return 0; case .phone: return 1; case .earLeft: return 2; case .earRight: return 3; case .tablet: return 4; case .watch: return 5; default: return 6 }
    }
}

struct DeviceBattery: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var kind: DeviceKind
    var percent: Int
    var charging: Bool?
    var observedAt: Date
    var source: String
    var disconnected = false
    func stale(at date: Date = Date()) -> Bool { disconnected || date.timeIntervalSince(observedAt) > 180 }
    static func safeID(_ raw: String) -> String { SHA256.hash(data: Data(raw.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined() }
    static func level(_ value: Any?) -> Int? {
        guard let value else { return nil }
        let number: Double?
        if let n = value as? NSNumber {
            guard CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
            number = n.doubleValue
        } else if let s = value as? String { number = Double(s.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)) }
        else { number = nil }
        guard let n = number, n.isFinite, (0...100).contains(n) else { return nil }
        return Int(n.rounded())
    }
    static func cleanName(_ value: String, fallback: String) -> String {
        let s = String(value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(64)).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? fallback : s
    }
}

struct BatteryArchive: Codable {
    var schema = 1
    var devices: [DeviceBattery] = []
    var selectedIDs: [String] = []
    var customSelection: Bool?
    var chinese = false
    var writtenAt = Date()
    var usesCustomSelection: Bool { customSelection ?? !selectedIDs.isEmpty }
    var selected: [DeviceBattery] {
        let available = devices.filter { Date().timeIntervalSince($0.observedAt) < 3600 }
        if !usesCustomSelection {
            return Array(available.sorted { a, b in
                if a.kind.rank != b.kind.rank { return a.kind.rank < b.kind.rank }
                if a.name != b.name { return a.name < b.name }
                return a.id < b.id
            }.prefix(8))
        }
        return Array(selectedIDs.compactMap { id in available.first { $0.id == id } }.prefix(8))
    }
    static func merge(old: [DeviceBattery], fresh: [DeviceBattery], at date: Date) -> [DeviceBattery] {
        var values = [String: DeviceBattery]()
        for var d in old where date.timeIntervalSince(d.observedAt) < 3600 && (0...100).contains(d.percent) {
            d.disconnected = true; values[d.id] = d
        }
        for d in fresh where (0...100).contains(d.percent) { values[d.id] = d }
        return Array(values.values.sorted { a, b in a.kind.rank == b.kind.rank ? a.name < b.name : a.kind.rank < b.kind.rank }.prefix(32))
    }
}

enum BatteryStore {
    static let widgetID = "local.hanchao.Watts.Widget"
    static var hostURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers/\(widgetID)/Data/Documents/batteries.json")
    }
    static var widgetURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("batteries.json")
    }
    static func read(_ url: URL) -> BatteryArchive {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              attrs[.type] as? FileAttributeType == .typeRegular,
              let size = attrs[.size] as? NSNumber, size.intValue <= 65536,
              let file = try? FileHandle(forReadingFrom: url) else { return BatteryArchive() }
        defer { try? file.close() }
        guard let data = try? file.read(upToCount: 65537), data.count <= 65536,
              let decoded = try? JSONDecoder().decode(BatteryArchive.self, from: data), decoded.schema == 1 else { return BatteryArchive() }
        var a = decoded
        let now = Date()
        var seen = Set<String>()
        a.devices = Array(a.devices.filter {
            (0...100).contains($0.percent) && !$0.name.isEmpty && $0.name.count <= 64 &&
            !$0.id.isEmpty && $0.id.count <= 64 && $0.source.count <= 64 &&
            $0.observedAt <= now.addingTimeInterval(300) && now.timeIntervalSince($0.observedAt) < 3600 &&
            seen.insert($0.id).inserted
        }.prefix(32))
        var selections = Set<String>()
        a.selectedIDs = Array(a.selectedIDs.filter { selections.insert($0).inserted }.prefix(8))
        return a
    }
    @discardableResult static func write(_ archive: BatteryArchive, to url: URL) -> Bool {
        guard let data = try? JSONEncoder().encode(archive), data.count <= 65536 else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch { return false }
    }
}
