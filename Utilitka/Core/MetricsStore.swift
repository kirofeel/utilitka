import Foundation
import Observation
import SwiftUI

struct MenuBarValues: Equatable {
    var cpu = "–"
    var temperature: String?
    var memory = "–"
}

struct CPUPoint: Identifiable, Equatable {
    let id: Int
    let user: Double
    let system: Double
}

/// The single source of data for the UI. One sampling loop for the whole app:
/// every 2 s while the panel is closed, every second while it is open.
@Observable
final class MetricsStore {
    static let historyLength = 120

    private(set) var cpu: CPULoad?
    private(set) var cpuHistory: [CPUPoint] = []
    private(set) var memory: MemoryStats?
    private(set) var topCPU: [ProcessRow] = []
    private(set) var topMemory: [ProcessRow] = []
    private(set) var network: NetworkRates?
    private(set) var battery: BatteryStats?
    private(set) var disk: DiskStats?
    private(set) var temperatures: Temperatures?
    /// What the menu bar shows. Redrawing a status item costs ~50 ms on every display, so it is
    /// refreshed at most every `menuBarInterval` and only when a value actually changed.
    private(set) var menuBar = MenuBarValues()
    /// False until the first slow sample, so the UI can tell "no battery" from "not read yet".
    private(set) var hasSlowSample = false

    var isPanelOpen = false {
        didSet {
            if isPanelOpen && !oldValue { sampleSlow() }
        }
    }

    /// Battery and disk change slowly and cost more to read.
    static let slowInterval: TimeInterval = 20
    static let menuBarInterval: TimeInterval = 4

    @ObservationIgnored private var history = RingBuffer<CPUPoint>(capacity: historyLength)
    @ObservationIgnored private var nextPointID = 0
    @ObservationIgnored private let cpuCollector = CPUCollector()
    @ObservationIgnored private let memoryCollector = MemoryCollector()
    @ObservationIgnored private let processCollector = ProcessCollector()
    @ObservationIgnored private let networkCollector = NetworkCollector()
    @ObservationIgnored private let batteryCollector = BatteryCollector()
    @ObservationIgnored private let diskCollector = DiskCollector()
    @ObservationIgnored private let sensorCollector = SensorCollector()
    @ObservationIgnored private var lastSlowSample = Date.distantPast
    @ObservationIgnored private var lastTemperatureSample = Date.distantPast
    @ObservationIgnored private var lastMenuBarUpdate = Date.distantPast
    @ObservationIgnored private var lastProcessSample = Date.distantPast
    /// Processes we just asked to quit stay hidden briefly so they don't flash back before exiting.
    @ObservationIgnored private var hiddenUntil: [pid_t: Date] = [:]
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var heavyDetector = HeavyProcessDetector(threshold: AlertSettings.defaultThreshold,
                                                                         duration: AlertSettings.defaultDuration)
    @ObservationIgnored private var memoryPressureSince: Date?
    @ObservationIgnored private var lastMemoryAlert = Date.distantPast
    /// Memory pressure that counts as critical, and how long it must last before an alert.
    static let memoryAlertPressure = 0.85
    static let memoryAlertDuration: TimeInterval = 60

    var cpuPercentText: String {
        guard let cpu else { return "–" }
        return "\(Int((cpu.busy * 100).rounded()))%"
    }

    var memoryPercentText: String {
        guard let memory else { return "–" }
        return "\(Int((memory.pressure * 100).rounded()))%"
    }

    var cpuTemperatureText: String? {
        temperatures?.cpu.map { "\(Int($0.rounded()))°" }
    }

    /// Battery temperature from the battery driver, or from the gas-gauge sensor when the driver hides it.
    var batteryTemperature: Double? {
        battery?.temperature ?? temperatures?.battery
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick()
                try? await Task.sleep(for: self.isPanelOpen ? .seconds(1) : .seconds(2))
            }
        }
    }

    func tick() {
        if let load = cpuCollector.sample() {
            cpu = load
            history.append(CPUPoint(id: nextPointID, user: load.user, system: load.system))
            nextPointID += 1
            cpuHistory = history.elements
        }

        memory = memoryCollector.sample()
        if let rates = networkCollector.sample() { network = rates }
        // Temperature changes slowly; with the panel closed, once every 6 s is plenty for the menu bar.
        if isPanelOpen || Date().timeIntervalSince(lastTemperatureSample) >= 6 {
            temperatures = sensorCollector.sample()
            lastTemperatureSample = Date()
        }

        let now = Date()
        if now.timeIntervalSince(lastSlowSample) >= Self.slowInterval { sampleSlow() }

        if now.timeIntervalSince(lastMenuBarUpdate) >= Self.menuBarInterval { updateMenuBar() }

        // Nobody sees the lists while the panel is closed; a slower scan still keeps a 5-second
        // CPU history, so the averages are ready the moment the panel opens.
        guard isPanelOpen || now.timeIntervalSince(lastProcessSample) >= 6 else { return }
        lastProcessSample = now
        hiddenUntil = hiddenUntil.filter { $0.value > now }
        let processes = processCollector.sample().filter { hiddenUntil[$0.pid] == nil }
        checkAlerts(processes: processes, now: now)
        topCPU = Array(processes.sorted { $0.cpu > $1.cpu }.prefix(6))
        topMemory = Array(processes.sorted { $0.memory > $1.memory }.prefix(6))
    }

    private func checkAlerts(processes: [ProcessRow], now: Date) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: AlertSettings.enabled) else { return }

        heavyDetector.threshold = defaults.double(forKey: AlertSettings.cpuThreshold)
        heavyDetector.duration = defaults.double(forKey: AlertSettings.duration)
        for alert in heavyDetector.update(rows: processes, now: now, ignored: AlertSettings.ignored) {
            NotificationManager.shared.notifyHeavy(alert.row, heavyFor: alert.heavyFor)
        }

        if let pressure = memory?.pressure, pressure >= Self.memoryAlertPressure {
            let since = memoryPressureSince ?? now
            memoryPressureSince = since
            if now.timeIntervalSince(since) >= Self.memoryAlertDuration,
               now.timeIntervalSince(lastMemoryAlert) >= 30 * 60 {
                lastMemoryAlert = now
                let biggest = processes.filter(\.canTerminate).max { $0.memory < $1.memory }
                NotificationManager.shared.notifyMemoryPressure(pressure, biggest: biggest)
            }
        } else {
            memoryPressureSince = nil
        }
    }

    /// CPU is averaged over the points since the last refresh, so a one-second spike doesn't flash in the menu bar.
    private func updateMenuBar() {
        lastMenuBarUpdate = Date()
        let recent = cpuHistory.suffix(isPanelOpen ? 4 : 2)
        let busy = recent.isEmpty ? nil : recent.map { $0.user + $0.system }.reduce(0, +) / Double(recent.count)
        let values = MenuBarValues(
            cpu: busy.map { "\(Int(($0 * 100).rounded()))%" } ?? "–",
            temperature: cpuTemperatureText,
            memory: memoryPercentText
        )
        if values != menuBar { menuBar = values }
    }

    func sampleSlow() {
        lastSlowSample = Date()
        battery = batteryCollector.sample()
        disk = diskCollector.sample()
        hasSlowSample = true
    }

    func terminate(_ row: ProcessRow, force: Bool) {
        guard row.canTerminate else { return }
        ProcessKiller.terminate(pid: row.pid, force: force)
        hiddenUntil[row.pid] = Date().addingTimeInterval(4)
        withAnimation(.snappy) {
            topCPU.removeAll { $0.pid == row.pid }
            topMemory.removeAll { $0.pid == row.pid }
        }
    }
}
