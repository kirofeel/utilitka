import SwiftUI

struct OverviewSection: View {
    @Environment(MetricsStore.self) private var store

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Огляд")
                        .font(.system(size: 15, weight: .semibold))
                    Text(SystemInfo.chipName)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer()
            }

            LazyVGrid(columns: columns, spacing: 8) {
                diskCard
                memoryCard
                batteryCard
                cpuCard
                networkCard
                uptimeCard
            }
        }
    }

    private var diskCard: some View {
        let disk = store.disk
        let isLow = (disk?.freeFraction ?? 1) < 0.1
        return OverviewCard(symbol: "internaldrive.fill",
                            title: "Диск",
                            value: disk.map { Format.storage($0.available) } ?? "—",
                            note: disk.map { "вільно з \(Format.storage($0.total))" } ?? "Зчитую…",
                            tint: isLow ? .bad : .storage,
                            fraction: disk.map { 1 - $0.freeFraction })
    }

    private var memoryCard: some View {
        let memory = store.memory
        return OverviewCard(symbol: "memorychip.fill",
                            title: "Пам'ять",
                            value: memory.map { Format.percent($0.pressure, digits: 0) } ?? "—",
                            note: memory.map { "\(Format.bytes($0.used)) з \(Format.bytes($0.total))" } ?? "Зчитую…",
                            tint: memory.map { $0.pressure >= 0.5 ? Tint.load($0.pressure) : .wired } ?? .wired,
                            fraction: memory?.pressure)
    }

    @ViewBuilder
    private var batteryCard: some View {
        if let battery = store.battery {
            OverviewCard(symbol: battery.isCharging ? "battery.100percent.bolt" : "battery.75percent",
                         title: "Акумулятор",
                         value: Format.percent(battery.level, digits: 0),
                         note: battery.statusText,
                         tint: battery.level < 0.15 && !battery.isOnAC ? .bad : .good,
                         fraction: battery.level)
        } else {
            OverviewCard(symbol: "powerplug.fill",
                         title: "Живлення",
                         value: "Мережа",
                         note: store.hasSlowSample ? "Акумулятора немає" : "Зчитую…",
                         tint: .good)
        }
    }

    private var cpuCard: some View {
        let busy = store.cpu?.busy ?? 0
        return OverviewCard(symbol: "cpu.fill",
                            title: "Процесор",
                            value: store.cpu.map { Format.percent($0.busy, digits: 0) } ?? "—",
                            note: store.temperatures?.cpu.map { "Ядер: \(SystemInfo.coreCount) · \(Int($0.rounded())) °C" }
                                ?? "Ядер: \(SystemInfo.coreCount)",
                            tint: busy >= 0.5 ? Tint.load(busy) : .user,
                            fraction: store.cpu?.busy)
    }

    private var networkCard: some View {
        OverviewCard(symbol: "arrow.up.arrow.down",
                     title: "Мережа",
                     value: store.network.map { "↓ " + Format.rate($0.download) } ?? "—",
                     note: store.network.map { "↑ " + Format.rate($0.upload) } ?? "Вимірюю…",
                     tint: .network)
    }

    private var uptimeCard: some View {
        let uptime = SystemInfo.bootDate.map { Date().timeIntervalSince($0) }
        let isLong = (uptime ?? 0) > 7 * 86_400
        return OverviewCard(symbol: "clock.fill",
                            title: "Час роботи",
                            value: uptime.map { Format.duration($0) } ?? "—",
                            note: isLong ? "Варто перезавантажитися" : "Від останнього запуску",
                            tint: isLong ? .warn : .accent)
    }
}

struct OverviewCard: View {
    let symbol: String
    let title: String
    let value: String
    let note: String
    let tint: Tint
    /// Optional 0...1 meter under the value.
    var fraction: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                IconTile(symbol: symbol, tint: tint, size: 20)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint.diagonal)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            if let fraction {
                UsageBar(fraction: fraction, tint: tint)
            }
            Text(note)
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .glassCard(padding: 10)
        .accessibilityElement(children: .combine)
    }
}
