import SwiftUI

/// Keys for what the menu bar shows; read by the label and toggled in Settings.
enum MenuBarItem {
    static let showCPU = "menuBar.showCPU"
    static let showTemperature = "menuBar.showTemperature"
    static let showMemory = "menuBar.showMemory"
}

/// The menu bar draws its label as a monochrome template, so this is one Text with an inline SF Symbol.
/// With every value switched off only the gauge symbol remains, so the item never disappears.
struct MenuBarText: View {
    let store: MetricsStore
    @AppStorage(MenuBarItem.showCPU) private var showCPU = true
    @AppStorage(MenuBarItem.showTemperature) private var showTemperature = true
    @AppStorage(MenuBarItem.showMemory) private var showMemory = false

    var body: some View {
        let values = self.values
        if values.isEmpty {
            Image(systemName: "gauge.with.dots.needle.50percent")
        } else {
            Text("\(Image(systemName: "gauge.with.dots.needle.50percent")) \(values)")
                .monospacedDigit()
        }
    }

    private var values: String {
        var parts: [String] = []
        let values = store.menuBar
        if showTemperature, let temperature = values.temperature { parts.append(temperature) }
        if showCPU { parts.append(values.cpu) }
        if showMemory { parts.append("RAM " + values.memory) }
        return parts.joined(separator: "  ")
    }
}
