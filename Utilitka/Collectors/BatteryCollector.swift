import Foundation
import IOKit
import IOKit.ps

struct BatteryStats: Equatable {
    /// 0...1
    var level: Double
    var isCharging: Bool
    var isOnAC: Bool
    var isCharged: Bool
    var cycleCount: Int?
    var designCycleCount: Int?
    /// Current full-charge capacity relative to the design capacity, 0...1.
    var health: Double?
    /// mAh the battery holds when full today, and when it was new.
    var fullChargeCapacity: Int?
    var designCapacity: Int?
    /// Degrees Celsius.
    var temperature: Double?
    /// Minutes until empty, when the system has an estimate.
    var minutesRemaining: Int?

    var statusText: String {
        if isCharged || (isOnAC && level >= 0.995) { return "Повністю заряджений" }
        if isCharging { return "Заряджається" }
        if isOnAC { return "Від адаптера, не заряджається" }
        return "Від акумулятора"
    }
}

final class BatteryCollector {
    /// Returns nil on Macs without an internal battery.
    func sample() -> BatteryStats? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let timeToEmpty = description[kIOPSTimeToEmptyKey] as? Int ?? -1
            let isOnAC = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue

            var stats = BatteryStats(
                level: maximum > 0 ? Double(current) / Double(maximum) : 0,
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                isOnAC: isOnAC,
                isCharged: description[kIOPSIsChargedKey] as? Bool ?? false,
                minutesRemaining: !isOnAC && timeToEmpty > 0 ? timeToEmpty : nil
            )
            Self.addRegistryDetails(to: &stats)
            return stats
        }
        return nil
    }

    /// Cycle count, health and temperature are only exposed by the AppleSmartBattery driver.
    private static func addRegistryDetails(to stats: inout BatteryStats) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any]
        else { return }

        // Recent macOS versions move the capacity figures into a nested "BatteryData" dictionary.
        let nested = properties["BatteryData"] as? [String: Any] ?? [:]
        func value(_ key: String) -> Int? { properties[key] as? Int ?? nested[key] as? Int }

        stats.cycleCount = value("CycleCount")
        stats.designCycleCount = value("DesignCycleCount9C")
        stats.fullChargeCapacity = value("AppleRawMaxCapacity") ?? value("FullChargeCapacity") ?? value("NominalChargeCapacity")
        stats.designCapacity = value("DesignCapacity")
        stats.health = health(fullCharge: stats.fullChargeCapacity, design: stats.designCapacity)
        // Not every macOS version publishes it; when it's missing the UI hides the row.
        if let raw = value("Temperature") ?? value("VirtualTemperature"), raw > 0 {
            stats.temperature = Double(raw) / 100 // hundredths of a degree
        }
    }

    static func health(fullCharge: Int?, design: Int?) -> Double? {
        guard let fullCharge, let design, design > 0, fullCharge > 0 else { return nil }
        return min(1, Double(fullCharge) / Double(design))
    }
}
