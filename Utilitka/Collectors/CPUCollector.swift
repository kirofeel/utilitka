import Darwin

/// Share of total CPU time across all cores, each 0...1, summing to 1.
struct CPULoad: Equatable {
    var user: Double
    var system: Double
    var idle: Double

    var busy: Double { user + system }
}

/// Reads per-core tick counters and turns the difference between two reads into a load.
final class CPUCollector {
    private var previousTicks: [UInt32]?

    /// Returns nil on the first call: a load needs two samples.
    func sample() -> CPULoad? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        let current = (0..<Int(infoCount)).map { UInt32(bitPattern: info[$0]) }
        let previous = previousTicks
        previousTicks = current
        guard let previous, previous.count == current.count else { return nil }
        return Self.load(previous: previous, current: current, cpuCount: Int(cpuCount))
    }

    /// Ticks are laid out per core as [user, system, idle, nice]. Counters may wrap, hence `&-`.
    static func load(previous: [UInt32], current: [UInt32], cpuCount: Int) -> CPULoad {
        let stride = Int(CPU_STATE_MAX)
        var user = 0.0, system = 0.0, idle = 0.0, nice = 0.0
        for core in 0..<cpuCount {
            let base = core * stride
            func delta(_ state: Int32) -> Double {
                Double(current[base + Int(state)] &- previous[base + Int(state)])
            }
            user += delta(CPU_STATE_USER)
            system += delta(CPU_STATE_SYSTEM)
            idle += delta(CPU_STATE_IDLE)
            nice += delta(CPU_STATE_NICE)
        }
        let total = user + system + idle + nice
        guard total > 0 else { return CPULoad(user: 0, system: 0, idle: 1) }
        return CPULoad(user: (user + nice) / total, system: system / total, idle: idle / total)
    }
}
