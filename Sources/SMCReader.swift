import Foundation
import IOKit

// Read-only AppleSMC user-client ABI: metadata, reads and optional key enumeration.
// Key meanings: https://asahilinux.org/docs/hw/soc/smc/
final class SMCReader {
    private var connection: io_connect_t = 0
    private var metadata: [String: (size: UInt32, type: UInt32)] = [:]
    private var unsupported = Set<String>()

    init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        if IOServiceOpen(service, mach_task_self_, 0, &connection) != KERN_SUCCESS { connection = 0 }
    }
    deinit { if connection != 0 { IOServiceClose(connection) } }
    private func fourCC(_ name: String) -> UInt32 { name.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }

    private func call(key: String, command: UInt8, size: UInt32 = 0, index: UInt32 = 0) -> [UInt8]? {
        guard connection != 0, key.utf8.count == 4 else { return nil }
        var input = [UInt8](repeating: 0, count: 80)
        var output = [UInt8](repeating: 0, count: 80)
        input.withUnsafeMutableBytes {
            $0.storeBytes(of: fourCC(key), toByteOffset: 0, as: UInt32.self)
            $0.storeBytes(of: size, toByteOffset: 28, as: UInt32.self)
            $0.storeBytes(of: index, toByteOffset: 44, as: UInt32.self)
        }
        input[42] = command
        var outputSize = 80
        let result = input.withUnsafeBytes { i in
            output.withUnsafeMutableBytes { o in
                IOConnectCallStructMethod(connection, 2, i.baseAddress, i.count, o.baseAddress, &outputSize)
            }
        }
        guard result == KERN_SUCCESS, outputSize == 80, output[40] == 0 else { return nil }
        return output
    }
    func powerKeys() -> [String] {
        guard let count = read("#KEY"), count > 0, count < 10000 else { return [] }
        var keys: [String] = []
        for index in 0..<Int(count) {
            guard let r = call(key: "#KEY", command: 8, index: UInt32(index)) else { continue }
            let value = r.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }
            let bytes = [UInt8((value >> 24) & 255), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)]
            if let name = String(bytes: bytes, encoding: .ascii), name.hasPrefix("P") { keys.append(name) }
        }
        return keys
    }
    func read(_ key: String) -> Double? {
        guard !unsupported.contains(key) else { return nil }
        if metadata[key] == nil {
            guard let result = call(key: key, command: 9) else { unsupported.insert(key); return nil }
            let info = result.withUnsafeBytes { b in
                (b.loadUnaligned(fromByteOffset: 28, as: UInt32.self), b.loadUnaligned(fromByteOffset: 32, as: UInt32.self))
            }
            guard info.0 > 0, info.0 <= 32 else { unsupported.insert(key); return nil }
            metadata[key] = (info.0, info.1)
        }
        guard let info = metadata[key], let result = call(key: key, command: 5, size: info.size) else { return nil }
        let bytes = Array(result[48..<80])
        let value: Double
        switch info.type {
        case fourCC("flt "):
            guard info.size == 4 else { return nil }
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            value = Double(Float(bitPattern: bits))
        case fourCC("sp78"):
            value = Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        case fourCC("fpe2"):
            value = Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case fourCC("ui8 "):
            value = Double(bytes[0])
        case fourCC("ui16"):
            value = Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case fourCC("si16"):
            value = Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1])))
        case fourCC("ui32"):
            value = Double(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
        default:
            unsupported.insert(key); return nil
        }
        return value.isFinite ? value : nil
    }
}
