import SwiftUI

enum PanelTab: String, CaseIterable, Identifiable {
    case cpu
    case memory
    case power
    case overview

    var id: Self { self }

    var title: String {
        switch self {
        case .cpu: "Процесор"
        case .memory: "Пам'ять"
        case .power: "Живлення"
        case .overview: "Огляд"
        }
    }
}

struct MenuPanel: View {
    @Environment(MetricsStore.self) private var store
    @Environment(\.openSettings) private var openSettings
    @AppStorage("panelTab") private var tab: PanelTab = .cpu
    @AppStorage(RefreshSettings.interval) private var refreshInterval = RefreshSettings.defaultInterval
    @Namespace private var tabNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            tabBar

            // The menu bar window stays alive while hidden; without this guard SwiftUI would keep
            // redrawing charts nobody can see on every sample.
            if store.isPanelOpen {
                Group {
                    switch tab {
                    case .cpu: CPUSection()
                    case .memory: MemorySection()
                    case .power: PowerSection()
                    case .overview: OverviewSection()
                    }
                }
                .transition(.opacity)
            }

            footer
        }
        .padding(16)
        .frame(width: 372)
        .foregroundStyle(.white)
        .background { Backdrop().ignoresSafeArea() }
        .environment(\.colorScheme, .dark)
        .animation(.spring(duration: 0.35, bounce: 0), value: tab)
        .onAppear { store.isPanelOpen = true }
        .onDisappear { store.isPanelOpen = false }
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(PanelTab.allCases) { item in
                let selected = tab == item
                Button {
                    tab = item
                } label: {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(selected ? Color.white : Palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Tint.accent.horizontal)
                                    .shadow(color: Palette.indigo.opacity(0.6), radius: 10, y: 3)
                                    .matchedGeometryEffect(id: "selection", in: tabNamespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(.black.opacity(0.25), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Palette.mint)
                .frame(width: 6, height: 6)
                .shadow(color: Palette.mint, radius: 3)
            Text("Оновлення " + RefreshSettings.label(refreshInterval))
                .foregroundStyle(Palette.textSecondary)
            Spacer()
            Button("Налаштування…") {
                NSApp.activate()
                openSettings()
            }
            Button("Вийти") { NSApp.terminate(nil) }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white.opacity(0.8))
    }
}
