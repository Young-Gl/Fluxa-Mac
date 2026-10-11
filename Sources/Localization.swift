import Foundation

enum L10n {
    static var chinese: Bool {
        let preference = UserDefaults.standard.string(forKey: "languagePreference") ?? "auto"
        if preference == "zh" { return true }
        if preference == "en" { return false }
        return Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
    }
    static func text(_ chinese: String, _ english: String) -> String { self.chinese ? chinese : english }
    static var appName: String { "Fluxa" }
}

struct USBOutput: Codable {
    var index: Int
    var watts: Double
    var volts: Double?
    var amps: Double?
}
struct PowerBreakdown: Codable {
    var energy = EnergyValues()
    var screenBacklightW: Double?
    var usbW: Double?
    var ports: [USBOutput] = []
    var usbUpdatedAt: Date?
    var otherW: Double?
}
