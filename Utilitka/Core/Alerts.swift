import Foundation
import UserNotifications

/// UserDefaults keys for alert settings, shared by Settings and the store.
enum AlertSettings {
    static let enabled = "alerts.enabled"
    /// Share of one core, e.g. 0.8 = 80 %.
    static let cpuThreshold = "alerts.cpuThreshold"
    /// Seconds a process must stay above the threshold.
    static let duration = "alerts.duration"
    static let ignoredNames = "alerts.ignoredNames"

    static let defaultThreshold = 0.8
    static let defaultDuration: TimeInterval = 120

    static func register() {
        UserDefaults.standard.register(defaults: [
            enabled: true,
            cpuThreshold: defaultThreshold,
            duration: defaultDuration,
        ])
    }

    static var ignored: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: ignoredNames) ?? [])
    }

    static func ignore(_ name: String) {
        var names = ignored
        names.insert(name)
        UserDefaults.standard.set(names.sorted(), forKey: ignoredNames)
    }
}

/// Decides when a process has been heavy long enough to deserve a notification.
/// Pure logic, so it is tested without the notification center.
struct HeavyProcessDetector {
    var threshold: Double
    var duration: TimeInterval
    /// One notification per app per half hour at most.
    var cooldown: TimeInterval = 30 * 60

    private var heavySince: [pid_t: Date] = [:]
    private var lastAlert: [String: Date] = [:]

    init(threshold: Double, duration: TimeInterval) {
        self.threshold = threshold
        self.duration = duration
    }

    /// Returns the processes to alert about now, each with how long it has been heavy.
    mutating func update(rows: [ProcessRow], now: Date, ignored: Set<String>) -> [(row: ProcessRow, heavyFor: TimeInterval)] {
        var alerts: [(ProcessRow, TimeInterval)] = []
        var stillHeavy: [pid_t: Date] = [:]
        for row in rows where row.cpu >= threshold && row.canTerminate && !ignored.contains(row.name) {
            let since = heavySince[row.pid] ?? now
            stillHeavy[row.pid] = since
            let heavyFor = now.timeIntervalSince(since)
            let cooledDown = lastAlert[row.name].map { now.timeIntervalSince($0) >= cooldown } ?? true
            if heavyFor >= duration, cooledDown {
                lastAlert[row.name] = now
                alerts.append((row, heavyFor))
            }
        }
        heavySince = stillHeavy
        return alerts
    }
}

/// Posts alerts and handles their buttons.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private enum ID {
        static let heavyCategory = "HEAVY_PROCESS"
        static let quit = "QUIT"
        static let ignore = "IGNORE"
    }

    private let center = UNUserNotificationCenter.current()

    /// Call once at launch: registers the buttons and asks for permission the first time.
    func setUp() {
        center.delegate = self
        let quit = UNNotificationAction(identifier: ID.quit, title: "Завершити", options: [.destructive])
        let ignore = UNNotificationAction(identifier: ID.ignore, title: "Не стежити за цією програмою")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: ID.heavyCategory, actions: [quit, ignore], intentIdentifiers: []),
        ])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyHeavy(_ row: ProcessRow, heavyFor: TimeInterval) {
        let name = Format.processName(row.name)
        let content = UNMutableNotificationContent()
        content.title = "\(name) навантажує процесор"
        content.body = "\(Format.percent(row.cpu, digits: 0)) CPU вже \(Format.duration(heavyFor)). Mac гріється, а батарея сідає швидше."
        content.categoryIdentifier = ID.heavyCategory
        content.userInfo = ["pid": Int(row.pid), "name": row.name]
        content.sound = .default
        post(content, id: "heavy-\(row.pid)")
    }

    func notifyMemoryPressure(_ pressure: Double, biggest: ProcessRow?) {
        let content = UNMutableNotificationContent()
        content.title = "Пам'яті майже не лишилося"
        if let biggest {
            content.body = "Навантаження \(Format.percent(pressure, digits: 0)). Найбільше займає \(Format.processName(biggest.name)): \(Format.bytes(biggest.memory))."
            content.categoryIdentifier = ID.heavyCategory
            content.userInfo = ["pid": Int(biggest.pid), "name": biggest.name]
        } else {
            content.body = "Навантаження \(Format.percent(pressure, digits: 0)). Закрийте програми, якими не користуєтесь."
        }
        content.sound = .default
        post(content, id: "memory-pressure")
    }

    private func post(_ content: UNNotificationContent, id: String) {
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // Show banners even though a menu bar app always counts as "active".
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        let pid = (info["pid"] as? Int).map { pid_t($0) }
        let name = info["name"] as? String
        Task { @MainActor in
            switch action {
            case ID.quit:
                // Only act if the pid still belongs to the same program, not a newer process that reused it.
                if let pid, let name, ProcessCollector.currentName(of: pid) == name {
                    ProcessKiller.terminate(pid: pid, force: false)
                }
            case ID.ignore:
                if let name { AlertSettings.ignore(name) }
            default:
                break
            }
            completionHandler()
        }
    }
}
