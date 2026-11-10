import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var errorText: String?
    @AppStorage(MenuBarItem.showCPU) private var showCPU = true
    @AppStorage(MenuBarItem.showTemperature) private var showTemperature = true
    @AppStorage(MenuBarItem.showMemory) private var showMemory = false
    @AppStorage(RefreshSettings.interval) private var refreshInterval = RefreshSettings.defaultInterval
    @AppStorage(AlertSettings.enabled) private var alertsEnabled = true
    @AppStorage(AlertSettings.cpuThreshold) private var alertThreshold = AlertSettings.defaultThreshold
    @AppStorage(AlertSettings.duration) private var alertDuration = AlertSettings.defaultDuration
    @State private var ignoredNames = AlertSettings.ignored.sorted()

    private func unignore(_ name: String) {
        var names = AlertSettings.ignored
        names.remove(name)
        UserDefaults.standard.set(names.sorted(), forKey: AlertSettings.ignoredNames)
        ignoredNames = names.sorted()
    }

    var body: some View {
        Form {
            Section {
                Picker("Оновлювати дані", selection: $refreshInterval) {
                    ForEach(RefreshSettings.choices, id: \.self) { seconds in
                        Text(RefreshSettings.label(seconds).capitalizedFirst).tag(seconds)
                    }
                }
            } header: {
                Text("Оновлення")
            } footer: {
                Text("Рідше — менше навантаження на процесор. Рядок меню оновлюється не частіше ніж кожні 4 с.")
                    .foregroundStyle(.secondary)
            }

            Section("Рядок меню") {
                Toggle("Температура процесора", isOn: $showTemperature)
                Toggle("Завантаження процесора", isOn: $showCPU)
                Toggle("Навантаження на пам'ять", isOn: $showMemory)
            }

            Section {
                Toggle("Сповіщати про важкі програми", isOn: $alertsEnabled)
                Picker("Поріг навантаження", selection: $alertThreshold) {
                    Text("50% одного ядра").tag(0.5)
                    Text("80% одного ядра").tag(0.8)
                    Text("Ціле ядро (100%)").tag(1.0)
                    Text("Два ядра (200%)").tag(2.0)
                }
                .disabled(!alertsEnabled)
                Picker("Якщо триває довше ніж", selection: $alertDuration) {
                    Text("1 хвилину").tag(60.0)
                    Text("2 хвилини").tag(120.0)
                    Text("5 хвилин").tag(300.0)
                }
                .disabled(!alertsEnabled)
                if !ignoredNames.isEmpty {
                    ForEach(ignoredNames, id: \.self) { name in
                        HStack {
                            Text(Format.processName(name))
                            Spacer()
                            Button("Знову стежити") { unignore(name) }
                                .buttonStyle(.link)
                        }
                    }
                }
            } header: {
                Text("Сповіщення")
            } footer: {
                Text("Пам'ять: сповіщення приходить, коли навантаження тримається вище 85% понад хвилину.")
                    .foregroundStyle(.secondary)
            }

            Section("Запуск") {
                Toggle("Запускати при вході в систему", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
                if let errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorText = nil
        } catch {
            errorText = "Не вдалося змінити автозапуск: \(error.localizedDescription)"
            let actual = SMAppService.mainApp.status == .enabled
            if actual != launchAtLogin { launchAtLogin = actual }
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
