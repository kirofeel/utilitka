import Foundation

struct MemoryStats: Equatable {
    var total: UInt64
    /// "App memory" in Activity Monitor terms: anonymous pages minus purgeable ones.
    var app: UInt64
    var wired: UInt64
    var compressed: UInt64
    var swapUsed: UInt64
    /// 0...1, derived from the kernel's memorystatus level.
    var pressure: Double

    var used: UInt64 { app + wired + compressed }
    var free: UInt64 { total > used ? total - used : 0 }
}

final class MemoryCollector {
    func sample() -> MemoryStats? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let page = UInt64(getpagesize())
        let anonymous = UInt64(stats.internal_page_count)
        let purgeable = min(UInt64(stats.purgeable_count), anonymous)
        return MemoryStats(
            total: ProcessInfo.processInfo.physicalMemory,
            app: (anonymous - purgeable) * page,
            wired: UInt64(stats.wire_count) * page,
            compressed: UInt64(stats.compressor_page_count) * page,
            swapUsed: Self.swapUsed(),
            pressure: Self.pressure()
        )
    }

    private static func swapUsed() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        return sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 ? usage.xsu_used : 0
    }

    /// The kernel reports the percentage of memory still available; pressure is the rest.
    private static func pressure() -> Double {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_level", &level, &size, nil, 0) == 0 else { return 0 }
        return Double(max(0, min(100, 100 - level))) / 100
    }
}
