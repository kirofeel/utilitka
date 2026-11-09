import Charts
import SwiftUI

struct CPUSection: View {
    @Environment(MetricsStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(SystemInfo.chipName)
                        .font(.system(size: 15, weight: .semibold))
                    HStack(spacing: 8) {
                        Text("Ядер: \(SystemInfo.coreCount)")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textSecondary)
                        if let celsius = store.temperatures?.cpu {
                            TemperaturePill(celsius: celsius)
                        }
                    }
                }
                Spacer()
                BigValue(text: store.cpu.map { Format.percent($0.busy, digits: 0) } ?? "–",
                         tint: Tint.load(store.cpu?.busy ?? 0))
            }

            VStack(spacing: 12) {
                CPUChart(points: store.cpuHistory)
                    .frame(height: 112)
                HStack(spacing: 0) {
                    LegendValue(title: "Користувач", text: store.cpu.map { Format.percent($0.user) }, tint: .user)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    LegendValue(title: "Система", text: store.cpu.map { Format.percent($0.system) }, tint: .system)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    LegendValue(title: "Вільно", text: store.cpu.map { Format.percent($0.idle) }, tint: .neutral)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .glassCard()

            ProcessList(title: "Найбільше навантажують", rows: store.topCPU, metric: .cpu)
        }
    }
}

/// Thermometer chip: mint while cool, amber when warm, red when hot.
struct TemperaturePill: View {
    let celsius: Double

    static func tint(for celsius: Double) -> Tint {
        switch celsius {
        case ..<65: .good
        case ..<85: .warn
        default: .bad
        }
    }

    var body: some View {
        let tint = Self.tint(for: celsius)
        HStack(spacing: 3) {
            Image(systemName: "thermometer.medium")
                .font(.system(size: 9, weight: .bold))
            Text("\(Int(celsius.rounded())) °C")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .foregroundStyle(tint.horizontal)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(tint.top.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.top.opacity(0.3)))
        .accessibilityLabel("Температура процесора \(Int(celsius.rounded())) градусів")
    }
}

/// Large rounded number with a gradient, used as each tab's headline figure.
struct BigValue: View {
    let text: String
    let tint: Tint

    var body: some View {
        Text(text)
            .font(.system(size: 30, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint.diagonal)
            .shadow(color: tint.top.opacity(0.35), radius: 8)
            .contentTransition(.numericText())
    }
}

/// Two charts drawn on identical scales and stacked: total load (cyan) behind, system share (pink) in front.
/// Separate charts keep each series a single clean area without Swift Charts' automatic stacking.
struct CPUChart: View {
    let points: [CPUPoint]

    private var xDomain: ClosedRange<Int> {
        let upper = max(points.last?.id ?? 0, MetricsStore.historyLength - 1)
        return (upper - MetricsStore.historyLength + 1)...upper
    }

    var body: some View {
        ZStack {
            Chart {
                ForEach(points) { point in
                    AreaMark(x: .value("Час", point.id), y: .value("Разом", (point.user + point.system) * 100))
                        .foregroundStyle(Tint.user.areaFill)
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Час", point.id), y: .value("Разом", (point.user + point.system) * 100))
                        .foregroundStyle(Tint.user.horizontal)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
                if let last = points.last {
                    PointMark(x: .value("Час", last.id), y: .value("Разом", (last.user + last.system) * 100))
                        .symbolSize(36)
                        .foregroundStyle(Palette.cyan)
                }
            }
            .cpuChartStyle(domain: xDomain, showLabels: true)

            Chart {
                ForEach(points) { point in
                    AreaMark(x: .value("Час", point.id), y: .value("Система", point.system * 100))
                        .foregroundStyle(Tint.system.areaFill)
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Час", point.id), y: .value("Система", point.system * 100))
                        .foregroundStyle(Tint.system.horizontal)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
            }
            .cpuChartStyle(domain: xDomain, showLabels: false)
        }
        .accessibilityElement()
        .accessibilityLabel("Завантаження процесора за останні хвилини")
    }
}

private extension View {
    /// Both layers share axes and plot size; only the back layer shows labels and grid.
    func cpuChartStyle(domain: ClosedRange<Int>, showLabels: Bool) -> some View {
        chartXScale(domain: domain)
            .chartXAxis(.hidden)
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                        .foregroundStyle(.white.opacity(showLabels ? 0.12 : 0))
                    AxisValueLabel {
                        if let percent = value.as(Int.self) {
                            Text("\(percent)%")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(showLabels ? Palette.textTertiary : .clear)
                        }
                    }
                }
            }
    }
}

struct LegendValue: View {
    let title: String
    let text: String?
    let tint: Tint

    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(tint.vertical)
                .frame(width: 4, height: 30)
                .shadow(color: tint.top.opacity(0.6), radius: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(text ?? "–")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(title)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
        }
    }
}
