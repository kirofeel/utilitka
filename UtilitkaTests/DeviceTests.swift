import Foundation
import Testing
@testable import Utilitka

@MainActor
struct NetworkRateTests {
    typealias Counters = NetworkCollector.Counters

    @Test func sumsInterfacesPerSecond() {
        let before = ["en0": Counters(received: 1_000, sent: 500), "en1": Counters(received: 0, sent: 0)]
        let after = ["en0": Counters(received: 3_000, sent: 1_500), "en1": Counters(received: 2_000, sent: 0)]
        let rates = NetworkCollector.rates(previous: before, current: after, seconds: 2)
        #expect(rates.download == 2_000)
        #expect(rates.upload == 500)
    }

    @Test func survivesCounterWraparound() {
        let before = ["en0": Counters(received: UInt32.max - 99, sent: 0)]
        let after = ["en0": Counters(received: 100, sent: 0)]
        let rates = NetworkCollector.rates(previous: before, current: after, seconds: 1)
        #expect(rates.download == 200)
    }

    @Test func ignoresInterfacesThatJustAppeared() {
        let rates = NetworkCollector.rates(previous: [:], current: ["en0": Counters(received: 9_999, sent: 9_999)], seconds: 1)
        #expect(rates == NetworkRates(upload: 0, download: 0))
    }
}

@MainActor
struct BatteryHealthTests {
    @Test func comparesFullChargeToDesign() {
        #expect(BatteryCollector.health(fullCharge: 4_050, design: 5_000) == 0.81)
    }

    @Test func capsAtHundredPercent() {
        #expect(BatteryCollector.health(fullCharge: 5_100, design: 5_000) == 1)
    }

    @Test func unknownWithoutData() {
        #expect(BatteryCollector.health(fullCharge: nil, design: 5_000) == nil)
        #expect(BatteryCollector.health(fullCharge: 4_000, design: 0) == nil)
    }
}

@MainActor
struct AppPathTests {
    @Test func helperMapsToOutermostApp() {
        #expect(ProcessCollector.enclosingApp(of: "/Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper") == "/Applications/Claude.app")
    }

    @Test func daemonHasNoApp() {
        #expect(ProcessCollector.enclosingApp(of: "/usr/libexec/cloudd") == nil)
    }
}

@MainActor
struct FormatTests {
    @Test func helperNamesReadAsTheirApp() {
        #expect(Format.processName("Brave Browser Helper (Renderer)") == "Brave Browser · Renderer")
        #expect(Format.processName("Claude Helper") == "Claude · помічник")
        #expect(Format.processName("cloudd") == "cloudd")
    }

    @Test func zeroRateIsNumeric() {
        #expect(Format.rate(0).hasPrefix("0"))
    }
}

@MainActor
struct TemperatureTests {
    @Test func averagesReadings() {
        #expect(SensorCollector.average([40, 42, 44]) == 42)
        #expect(SensorCollector.average([]) == nil)
        #expect(SensorCollector.average(nil) == nil)
    }

    @Test func tintFollowsHeat() {
        #expect(TemperaturePill.tint(for: 45).top == Tint.good.top)
        #expect(TemperaturePill.tint(for: 75).top == Tint.warn.top)
        #expect(TemperaturePill.tint(for: 95).top == Tint.bad.top)
    }
}

@MainActor
struct ProcessAveragingTests {
    typealias Sample = ProcessCollector.CPUSample
    let second: UInt64 = 1_000_000_000

    /// Feeds one sample per second and returns the history.
    func feed(_ cpuPerSecond: [UInt64]) -> [Sample] {
        var samples: [Sample] = []
        var total: UInt64 = 0
        for (index, used) in cpuPerSecond.enumerated() {
            total += used
            samples = ProcessCollector.appending(Sample(time: UInt64(index + 1) * second, nanos: total), to: samples)
        }
        return samples
    }

    @Test func averagesOverFiveSeconds() {
        // One busy second (100 %) followed by idle ones: the spike is spread over the window.
        let samples = feed([0, second, 0, 0, 0, 0])
        #expect(abs(ProcessCollector.averageUsage(samples) - 0.2) < 1e-9)
    }

    @Test func spikeLeavesTheWindow() {
        let samples = feed([0, second, 0, 0, 0, 0, 0, 0])
        #expect(ProcessCollector.averageUsage(samples) == 0)
    }

    @Test func windowNeverShrinksBelowFiveSeconds() {
        let samples = feed(Array(repeating: second / 2, count: 20))
        let span = samples.last!.time - samples.first!.time
        #expect(span >= ProcessCollector.averagingWindow)
        #expect(abs(ProcessCollector.averageUsage(samples) - 0.5) < 1e-9)
    }

    @Test func pidReuseStartsOver() {
        let history = feed([second, second])
        let restarted = ProcessCollector.appending(Sample(time: 10 * second, nanos: 5), to: history)
        #expect(restarted.count == 1)
        #expect(ProcessCollector.averageUsage(restarted) == 0)
    }
}

@MainActor
struct HeavyProcessDetectorTests {
    let start = Date(timeIntervalSince1970: 1_000_000)

    func row(_ cpu: Double, pid: pid_t = 42, name: String = "Telegram", canTerminate: Bool = true) -> ProcessRow {
        ProcessRow(pid: pid, name: name, cpu: cpu, memory: 0, canTerminate: canTerminate, appPath: nil)
    }

    @Test func alertsOnlyAfterTheDuration() {
        var detector = HeavyProcessDetector(threshold: 0.8, duration: 120)
        #expect(detector.update(rows: [row(0.9)], now: start, ignored: []).isEmpty)
        #expect(detector.update(rows: [row(0.9)], now: start + 60, ignored: []).isEmpty)
        let alerts = detector.update(rows: [row(0.9)], now: start + 120, ignored: [])
        #expect(alerts.count == 1)
        #expect(alerts.first?.heavyFor == 120)
    }

    @Test func dippingBelowResetsTheClock() {
        var detector = HeavyProcessDetector(threshold: 0.8, duration: 120)
        _ = detector.update(rows: [row(0.9)], now: start, ignored: [])
        _ = detector.update(rows: [row(0.2)], now: start + 60, ignored: [])
        #expect(detector.update(rows: [row(0.9)], now: start + 130, ignored: []).isEmpty)
    }

    @Test func respectsCooldownAndIgnoreList() {
        var detector = HeavyProcessDetector(threshold: 0.8, duration: 0)
        #expect(detector.update(rows: [row(0.9)], now: start, ignored: []).count == 1)
        #expect(detector.update(rows: [row(0.9)], now: start + 60, ignored: []).isEmpty)
        #expect(detector.update(rows: [row(0.9, name: "Safari")], now: start + 60, ignored: ["Safari"]).isEmpty)
    }

    @Test func skipsProcessesItCannotQuit() {
        var detector = HeavyProcessDetector(threshold: 0.8, duration: 0)
        #expect(detector.update(rows: [row(0.9, canTerminate: false)], now: start, ignored: []).isEmpty)
    }
}
