import Foundation
import IOKit
import IOKit.hidsystem

/// Degrees Celsius; nil when this Mac has no such sensor.
struct Temperatures: Equatable {
    var cpu: Double?
    var gpu: Double?
    var battery: Double?
}

// Reading a sensor's value needs two functions Apple ships but doesn't publish in the SDK.
// Every Apple Silicon monitor (Stats, iStat Menus) uses the same pair. If a future macOS
// removes them, only this file needs changing; the app simply shows no temperature.
@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEvent(_ service: IOHIDServiceClient, _ type: Int64, _ options: Int32, _ timestamp: Int64) -> OpaquePointer?

@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: OpaquePointer, _ field: Int32) -> Double

// The public "simple" client lists the sensors but returns no readings; the full client does.
@_silgen_name("IOHIDEventSystemClientCreate")
private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> IOHIDEventSystemClient

@_silgen_name("IOHIDEventSystemClientSetMatching")
private func IOHIDEventSystemClientSetMatching(_ client: IOHIDEventSystemClient, _ matching: CFDictionary) -> Int32

/// Apple Silicon temperature sensors exposed through the HID event system.
final class SensorCollector {
    private enum Kind { case cpu, gpu, battery }

    private struct Sensor {
        let service: IOHIDServiceClient
        let kind: Kind
    }

    private static let temperatureEventType: Int64 = 15
    private static let temperatureField = Int32(15 << 16)
    /// Vendor usage page and usage that Apple's thermal sensors register under.
    private static let sensorUsagePage = 0xFF00
    private static let sensorUsage = 5

    private lazy var client: IOHIDEventSystemClient = {
        let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)
        let matching = [kIOHIDPrimaryUsagePageKey: Self.sensorUsagePage, kIOHIDPrimaryUsageKey: Self.sensorUsage] as CFDictionary
        _ = IOHIDEventSystemClientSetMatching(client, matching)
        return client
    }()
    private lazy var sensors: [Sensor] = discoverSensors()

    func sample() -> Temperatures? {
        guard !sensors.isEmpty else { return nil }
        var readings: [Kind: [Double]] = [:]
        for sensor in sensors {
            guard let event = IOHIDServiceClientCopyEvent(sensor.service, Self.temperatureEventType, 0, 0) else { continue }
            let value = IOHIDEventGetFloatValue(event, Self.temperatureField)
            Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(event)).release()
            if value > 0, value < 130 { readings[sensor.kind, default: []].append(value) }
        }
        return Temperatures(cpu: Self.average(readings[.cpu]),
                            gpu: Self.average(readings[.gpu]),
                            battery: Self.average(readings[.battery]))
    }

    private func discoverSensors() -> [Sensor] {
        guard let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else { return [] }
        var cpuDie: [Sensor] = []
        var cpuCluster: [Sensor] = []
        var others: [Sensor] = []
        // Each sensor is often published twice; reading one copy halves the cost.
        var seenNames: Set<String> = []

        for service in services {
            guard Self.intProperty(service, kIOHIDPrimaryUsagePageKey) == Self.sensorUsagePage,
                  Self.intProperty(service, kIOHIDPrimaryUsageKey) == Self.sensorUsage,
                  let name = IOHIDServiceClientCopyProperty(service, kIOHIDProductKey as CFString) as? String,
                  seenNames.insert(name).inserted
            else { continue }

            if name.contains("tdie") {
                cpuDie.append(Sensor(service: service, kind: .cpu))
            } else if name.contains("ACC MTR") {
                cpuCluster.append(Sensor(service: service, kind: .cpu))
            } else if name.contains("GPU") {
                others.append(Sensor(service: service, kind: .gpu))
            } else if name.localizedCaseInsensitiveContains("battery") {
                others.append(Sensor(service: service, kind: .battery))
            }
        }
        // Die sensors are the most direct CPU reading; cluster sensors are the fallback on chips without them.
        return (cpuDie.isEmpty ? cpuCluster : cpuDie) + others
    }

    private static func intProperty(_ service: IOHIDServiceClient, _ key: String) -> Int? {
        (IOHIDServiceClientCopyProperty(service, key as CFString) as? NSNumber)?.intValue
    }

    static func average(_ values: [Double]?) -> Double? {
        guard let values, !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
