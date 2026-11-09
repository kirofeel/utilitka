import Charts
import SwiftUI

struct MemorySection: View {
    @Environment(MetricsStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Пам'ять")
                        .font(.system(size: 15, weight: .semibold))
                    Text(store.memory.map { "Усього \(Format.bytes($0.total))" } ?? " ")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                BigValue(text: store.memory.map { Format.percent($0.pressure, digits: 0) } ?? "–",
                         tint: Tint.load(store.memory?.pressure ?? 0))
            }

            if let memory = store.memory {
                HStack(spacing: 16) {
                    MemoryDonut(stats: memory)
                        .frame(width: 120, height: 120)
                    VStack(alignment: .leading, spacing: 10) {
                        LegendValue(title: "Програми", text: Format.bytes(memory.app), tint: .user)
                        LegendValue(title: "Закріплена", text: Format.bytes(memory.wired), tint: .wired)
                        LegendValue(title: "Стиснута", text: Format.bytes(memory.compressed), tint: .warn)
                    }
                    Spacer(minLength: 0)
                }
                .glassCard()

                HStack(spacing: 8) {
                    StatCard(symbol: "gauge.with.dots.needle.67percent",
                             title: "Навантаження",
                             value: Format.percent(memory.pressure, digits: 0),
                             tint: Tint.load(memory.pressure),
                             note: pressureNote(memory.pressure))
                    StatCard(symbol: "arrow.down.doc",
                             title: "Підкачка",
                             value: Format.bytes(memory.swapUsed),
                             tint: .storage,
                             note: "Записано на диск")
                }
            }

            ProcessList(title: "Найбільше пам'яті", rows: store.topMemory, metric: .memory)
        }
    }

    private func pressureNote(_ pressure: Double) -> String {
        switch pressure {
        case ..<0.5: "Пам'яті достатньо"
        case ..<0.75: "Закрийте зайві програми"
        default: "Mac сповільнюється"
        }
    }
}

struct MemoryDonut: View {
    let stats: MemoryStats

    private struct Segment: Identifiable {
        let name: String
        let bytes: UInt64
        let tint: Tint
        var id: String { name }
    }

    private var segments: [Segment] {
        [
            Segment(name: "Програми", bytes: stats.app, tint: .user),
            Segment(name: "Закріплена", bytes: stats.wired, tint: .wired),
            Segment(name: "Стиснута", bytes: stats.compressed, tint: .warn),
            Segment(name: "Вільна", bytes: stats.free, tint: Tint(top: .white.opacity(0.1), bottom: .white.opacity(0.06))),
        ]
    }

    var body: some View {
        Chart(segments) { segment in
            SectorMark(angle: .value("Обсяг", Double(segment.bytes)),
                       innerRadius: .ratio(0.72),
                       angularInset: 2)
                .cornerRadius(4)
                .foregroundStyle(segment.tint.diagonal)
        }
        .chartBackground { _ in
            VStack(spacing: 0) {
                Text(Format.bytes(stats.used))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("зайнято")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .shadow(color: Palette.blue.opacity(0.35), radius: 10)
        .accessibilityLabel("Зайнято \(Format.bytes(stats.used)) з \(Format.bytes(stats.total))")
    }
}

struct StatCard: View {
    let symbol: String
    let title: String
    let value: String
    let tint: Tint
    let note: String

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
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint.diagonal)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .contentTransition(.numericText())
            Text(note)
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 10)
        .accessibilityElement(children: .combine)
    }
}
