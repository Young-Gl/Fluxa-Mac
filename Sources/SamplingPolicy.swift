import Foundation
struct SamplingGate {
    let minimumSpacing: Double = 0.5
    private var lastSample: Double = -.infinity
    func delay(at uptime: Double) -> Double { max(0, minimumSpacing - (uptime - lastSample)) }
    mutating func record(at uptime: Double) { lastSample = uptime }
}
struct ActivityState {
    enum Reason: String, Hashable { case systemSleep, displaySleep }
    private(set) var reasons = Set<Reason>()
    var paused: Bool { !reasons.isEmpty }
    mutating func set(_ reason: Reason, paused value: Bool) -> Bool {
        let before = paused
        if value { reasons.insert(reason) } else { reasons.remove(reason) }
        return before != paused
    }
}
