import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum ProcessMetric {
    case cpu
    case memory
}

struct ProcessList: View {
    let title: String
    let rows: [ProcessRow]
    let metric: ProcessMetric

    /// Bars are relative to the busiest row, but CPU bars never exceed one full core.
    private var scale: Double {
        switch metric {
        case .cpu: max(1, rows.map(\.cpu).max() ?? 1)
        case .memory: Double(rows.map(\.memory).max() ?? 1)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: title, detail: metric == .cpu ? "CPU" : "Обсяг")
                .padding(.horizontal, 4)
                .padding(.bottom, 4)

            if rows.isEmpty {
                Text("Збираю дані…")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textSecondary)
                    .padding(6)
            }
            ForEach(rows) { row in
                ProcessRowView(row: row, metric: metric, scale: scale)
            }
        }
        .glassCard(padding: 8)
    }
}

struct ProcessRowView: View {
    @Environment(MetricsStore.self) private var store
    let row: ProcessRow
    let metric: ProcessMetric
    let scale: Double
    @State private var confirming = false
    @State private var hovering = false

    private var isHot: Bool { metric == .cpu && row.cpu > 0.5 }

    private var value: Double {
        switch metric {
        case .cpu: row.cpu
        case .memory: Double(row.memory)
        }
    }

    private var valueText: String {
        switch metric {
        case .cpu: Format.percent(row.cpu)
        case .memory: Format.bytes(row.memory)
        }
    }

    private var barTint: Tint {
        switch metric {
        case .cpu: isHot ? .system : .user
        case .memory: .wired
        }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 10) {
                AppIcon(appPath: row.appPath)
                    .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 5) {
                    Text(Format.processName(row.name))
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(row.name)
                    UsageBar(fraction: scale > 0 ? value / scale : 0, tint: barTint)
                }

                Text(valueText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isHot ? AnyShapeStyle(Tint.bad.horizontal) : AnyShapeStyle(Color.white))
                    .contentTransition(.numericText())
                    .frame(minWidth: 58, alignment: .trailing)

                PillButton(title: "Завершити") {
                    withAnimation(.spring(duration: 0.3, bounce: 0)) { confirming.toggle() }
                }
                .disabled(!row.canTerminate)
                .opacity(row.canTerminate ? 1 : 0)
                .accessibilityHidden(!row.canTerminate)
            }

            if confirming {
                HStack(spacing: 6) {
                    Text("Завершити «\(row.name)»?")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    PillButton(title: "Скасувати") {
                        withAnimation(.spring(duration: 0.3, bounce: 0)) { confirming = false }
                    }
                    PillButton(title: "Завершити", style: .accent) { store.terminate(row, force: false) }
                        .keyboardShortcut(.defaultAction)
                    PillButton(title: "Примусово", style: .danger) { store.terminate(row, force: true) }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .background(.white.opacity(hovering || confirming ? 0.07 : 0),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// The parent app's icon for apps and their helpers; the generic executable icon for daemons.
struct AppIcon: View {
    let appPath: String?

    var body: some View {
        Image(nsImage: IconCache.icon(forApp: appPath))
            .resizable()
            .interpolation(.high)
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }
}

enum IconCache {
    private static var cache: [String: NSImage] = [:]
    private static let executable = NSWorkspace.shared.icon(for: .unixExecutable)

    static func icon(forApp path: String?) -> NSImage {
        guard let path else { return executable }
        if let cached = cache[path] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache[path] = icon
        return icon
    }
}
