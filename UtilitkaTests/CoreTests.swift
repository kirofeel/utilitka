import Testing
@testable import Utilitka

@MainActor
struct RingBufferTests {
    @Test func returnsElementsInOrderBeforeFull() {
        var buffer = RingBuffer<Int>(capacity: 3)
        buffer.append(1)
        buffer.append(2)
        #expect(buffer.elements == [1, 2])
        #expect(buffer.last == 2)
    }

    @Test func overwritesOldestAfterWrap() {
        var buffer = RingBuffer<Int>(capacity: 3)
        (1...5).forEach { buffer.append($0) }
        #expect(buffer.elements == [3, 4, 5])
        #expect(buffer.last == 5)
        #expect(buffer.count == 3)
    }
}

@MainActor
struct CPULoadTests {
    @Test func splitsTicksIntoShares() {
        // One core, ticks ordered [user, system, idle, nice]. Deltas: 60, 20, 100, 20 → total 200.
        let load = CPUCollector.load(previous: [100, 50, 800, 0], current: [160, 70, 900, 20], cpuCount: 1)
        #expect(abs(load.user - 0.4) < 1e-9)   // user + nice
        #expect(abs(load.system - 0.1) < 1e-9)
        #expect(abs(load.idle - 0.5) < 1e-9)
    }

    @Test func handlesCounterWraparound() {
        let load = CPUCollector.load(previous: [UInt32.max - 9, 0, 0, 0], current: [10, 0, 20, 0], cpuCount: 1)
        #expect(abs(load.user - 0.5) < 1e-9)
    }

    @Test func idleWhenNoTicksPassed() {
        let load = CPUCollector.load(previous: [1, 1, 1, 1], current: [1, 1, 1, 1], cpuCount: 1)
        #expect(load == CPULoad(user: 0, system: 0, idle: 1))
    }
}

struct RefreshSettingsTests {
    @Test func labelsReadNaturally() {
        #expect(RefreshSettings.label(1) == "щосекунди")
        #expect(RefreshSettings.label(2) == "кожні 2 с")
        #expect(RefreshSettings.label(5) == "кожні 5 с")
    }

    @Test func defaultIsTwoSecondsAndAChoice() {
        #expect(RefreshSettings.choices.contains(RefreshSettings.defaultInterval))
        #expect(RefreshSettings.defaultInterval == 2)
    }
}
