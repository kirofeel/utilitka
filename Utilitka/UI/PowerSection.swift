import SwiftUI

struct PowerSection: View {
    @Environment(MetricsStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let battery = store.battery {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Акумулятор")
                            .font(.system(size: 15, weight: .semibold))
                        Text(battery.statusText)
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Spacer()
                    if let health = battery.health {
                        BigValue(text: Format.percent(health, digits: 0), tint: health >= 0.8 ? .good : .warn)
                            .help("Здоров'я акумулятора")
                    }
                }

                HStack(spacing: 18) {
                    LevelRing(value: battery.level,
                              tint: levelTint(battery),
                              label: Format.percent(battery.level, digits: 0),
                              symbol: battery.isCharging ? "bolt.fill" : nil)
                        .frame(width: 120, height: 120)
                    VStack(alignment: .leading, spacing: 10) {
                        LegendValue(title: "Здоров'я",
                                    text: battery.health.map { Format.percent($0, digits: 0) },
                                    tint: (battery.health ?? 1) >= 0.8 ? .good : .warn)
                        LegendValue(title: "Циклів заряду",
                                    text: cyclesText(battery),
                                    tint: .user)
                        if let temperature = store.batteryTemperature {
                            LegendValue(title: "Температура",
                                        text: "\(Int(temperature.rounded())) °C",
                                        tint: .warn)
                        } else {
                            LegendValue(title: capacityTitle(battery),
                                        text: battery.fullChargeCapacity.map { "\($0.formatted()) мА·год" },
                                        tint: .wired)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .glassCard()

                HStack(spacing: 8) {
                    StatCard(symbol: battery.isOnAC ? "powerplug.fill" : "battery.75percent",
                             title: "Джерело",
                             value: battery.isOnAC ? "Адаптер" : "Батарея",
                             tint: battery.isOnAC ? .good : .user,
                             note: battery.isOnAC ? "Підключено до мережі" : "Працює автономно")
                    StatCard(symbol: "hourglass",
                             title: "Залишилось",
                             value: battery.minutesRemaining.map { Format.duration(TimeInterval($0 * 60)) } ?? "—",
                             tint: .warn,
                             note: battery.minutesRemaining == nil ? "Оцінка недоступна" : "За поточного навантаження")
                }
            } else if store.hasSlowSample {
                ContentUnavailableView("Акумулятора немає",
                                       systemImage: "powerplug",
                                       description: Text("Цей Mac живиться від мережі."))
                    .glassCard()
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            }

            ProcessList(title: "Найбільше навантажують", rows: Array(store.topCPU.prefix(4)), metric: .cpu)
        }
    }

    private func cyclesText(_ battery: BatteryStats) -> String? {
        guard let cycles = battery.cycleCount else { return nil }
        if let design = battery.designCycleCount { return "\(cycles) з \(design)" }
        return "\(cycles)"
    }

    private func capacityTitle(_ battery: BatteryStats) -> String {
        guard let design = battery.designCapacity else { return "Ємність" }
        return "Ємність, нова \(design.formatted())"
    }

    private func levelTint(_ battery: BatteryStats) -> Tint {
        if battery.isCharging || battery.isOnAC { return .good }
        switch battery.level {
        case ..<0.15: return .bad
        case ..<0.3: return .warn
        default: return .good
        }
    }
}

struct LevelRing: View {
    let value: Double
    let tint: Tint
    let label: String
    var symbol: String?

    private var clamped: Double { max(0.001, min(1, value)) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.08), lineWidth: 13)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    AngularGradient(colors: [tint.bottom, tint.top],
                                    center: .center,
                                    startAngle: .degrees(0),
                                    endAngle: .degrees(360 * clamped)),
                    style: StrokeStyle(lineWidth: 13, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.top.opacity(0.55), radius: 8)
                .animation(.spring(duration: 0.6, bounce: 0), value: clamped)
            VStack(spacing: 0) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(tint.vertical)
                }
                Text(label)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .padding(7)
        .accessibilityElement(children: .combine)
    }
}
