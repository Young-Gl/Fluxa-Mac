import SwiftUI
import WidgetKit

struct FluxaEntry: TimelineEntry {
    let date: Date
    let archive: BatteryArchive
}
struct FluxaProvider: TimelineProvider {
    func placeholder(in context: Context) -> FluxaEntry { FluxaEntry(date: Date(), archive: BatteryArchive()) }
    func getSnapshot(in context: Context, completion: @escaping (FluxaEntry) -> Void) {
        completion(FluxaEntry(date: Date(), archive: BatteryStore.read(BatteryStore.widgetURL)))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<FluxaEntry>) -> Void) {
        let now = Date(), archive = BatteryStore.read(BatteryStore.widgetURL)
        let entries = [FluxaEntry(date: now, archive: archive)]
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(900))))
    }
}
struct FluxaWidgetView: View {
    let entry: FluxaEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        BatteryRingGrid(devices: Array(entry.archive.selected.prefix(family == .systemLarge ? 8 : 4)), chinese: entry.archive.chinese,
                        diameter: family == .systemSmall ? 44 : 58, columns: family == .systemSmall ? 2 : 4, verticalPadding: family == .systemSmall ? 8 : 25, spacing: family == .systemSmall ? 8 : 18, date: entry.date,
                        emptyMessage: entry.archive.usesCustomSelection && entry.archive.selectedIDs.isEmpty ? (entry.archive.chinese ? "未选择设备" : "No devices selected") : nil)
            .containerBackground(for: .widget) { Color.clear }
            .widgetURL(URL(string: "fluxa://devices"))
    }
}
@main
struct FluxaDevicesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FluxaDevices", provider: FluxaProvider()) { FluxaWidgetView(entry: $0) }
            .configurationDisplayName("Fluxa Batteries")
            .description(Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "Mac 与 Apple 设备电量" : "Batteries across your Apple devices")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
            .contentMarginsDisabled()
    }
}
