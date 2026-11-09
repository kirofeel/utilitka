import Darwin
import Foundation

// MARK: - Disk

struct DiskStats: Equatable {
    var total: Int64
    /// Space macOS is willing to free for important data (includes purgeable caches), as Finder shows it.
    var available: Int64

    var freeFraction: Double { total > 0 ? Double(available) / Double(total) : 0 }
}

final class DiskCollector {
    func sample() -> DiskStats? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return DiskStats(total: Int64(total), available: available)
    }
}

// MARK: - Network

struct NetworkRates: Equatable {
    /// Bytes per second.
    var upload: Double
    var download: Double
}

/// Counts traffic on physical interfaces (en0, en1…). VPN tunnels are skipped so traffic isn't counted twice.
final class NetworkCollector {
    struct Counters: Equatable {
        var received: UInt32
        var sent: UInt32
    }

    private var previous: [String: Counters] = [:]
    private var previousTime: UInt64 = 0

    /// Returns nil on the first call: a rate needs two samples.
    func sample() -> NetworkRates? {
        let current = Self.readCounters()
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        defer {
            previous = current
            previousTime = now
        }
        guard previousTime != 0, now > previousTime else { return nil }
        return Self.rates(previous: previous, current: current, seconds: Double(now - previousTime) / 1e9)
    }

    /// Kernel counters are 32-bit and wrap at 4 GB, so deltas use wrapping subtraction per interface.
    static func rates(previous: [String: Counters], current: [String: Counters], seconds: Double) -> NetworkRates {
        guard seconds > 0 else { return NetworkRates(upload: 0, download: 0) }
        var received: UInt64 = 0
        var sent: UInt64 = 0
        for (name, now) in current {
            guard let before = previous[name] else { continue }
            received += UInt64(now.received &- before.received)
            sent += UInt64(now.sent &- before.sent)
        }
        return NetworkRates(upload: Double(sent) / seconds, download: Double(received) / seconds)
    }

    private static func readCounters() -> [String: Counters] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [:] }
        defer { freeifaddrs(head) }

        var result: [String: Counters] = [:]
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_LINK),
                  let data = entry.ifa_data
            else { continue }
            let name = String(cString: entry.ifa_name)
            guard name.hasPrefix("en") else { continue }
            let stats = data.load(as: if_data.self)
            result[name] = Counters(received: stats.ifi_ibytes, sent: stats.ifi_obytes)
        }
        return result
    }
}
