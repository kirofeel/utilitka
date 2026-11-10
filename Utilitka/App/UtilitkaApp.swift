import SwiftUI

@main
struct UtilitkaApp: App {
    private let store: MetricsStore

    init() {
        AlertSettings.register()
        RefreshSettings.register()
        NotificationManager.shared.setUp()
        let store = MetricsStore()
        store.start()
        self.store = store
    }

    var body: some Scene {
        MenuBarExtra {
            MenuPanel()
                .environment(store)
        } label: {
            // One Text with an inline SF Symbol is the most reliable way to show icon + values in the menu bar.
            MenuBarText(store: store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
