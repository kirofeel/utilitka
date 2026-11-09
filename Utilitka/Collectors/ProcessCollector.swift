import AppKit
import Darwin

struct ProcessRow: Identifiable, Equatable {
    let pid: pid_t
    let name: String
    /// Like Activity Monitor: 1.0 = one full core, so values above 1 are possible.
    let cpu: Double
    /// Physical footprint in bytes (the "Memory" column in Activity Monitor).
    let memory: UInt64
    let canTerminate: Bool
    /// The outermost .app bundle the executable lives in, so helpers show their parent app's icon.
    let appPath: String?

    var id: pid_t { pid }
}

/// Lists processes this user can inspect. Root-owned processes (WindowServer, kernel_task)
/// refuse task info without privileges, so they are skipped until a privileged helper exists.
final class ProcessCollector {
    struct CPUSample: Equatable {
        var time: UInt64   // ns, monotonic
        var nanos: UInt64  // total CPU time the process has used
    }

    /// CPU % is averaged over this window, like Activity Monitor's default 5 s update,
    /// so the list doesn't jump around on every one-second spike.
    static let averagingWindow: UInt64 = 5_000_000_000

    private var history: [pid_t: [CPUSample]] = [:]
    /// Executable paths don't change for a running process, so they are read once per pid.
    private var previousPaths: [pid_t: String?] = [:]
    private let ownPID = getpid()

    /// On Apple Silicon task times are in mach ticks, not nanoseconds.
    private let nanosPerTick: Double = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(timebase.numer) / Double(timebase.denom)
    }()

    private static let protectedNames: Set<String> = [
        "kernel_task", "launchd", "WindowServer", "loginwindow",
    ]

    func sample() -> [ProcessRow] {
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)

        let appNames = Dictionary(
            NSWorkspace.shared.runningApplications.compactMap { app in
                app.localizedName.map { (app.processIdentifier, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )

        var rows: [ProcessRow] = []
        var currentHistory: [pid_t: [CPUSample]] = [:]
        var currentPaths: [pid_t: String?] = [:]
        let taskInfoSize = Int32(MemoryLayout<proc_taskinfo>.stride)

        for pid in Self.allPIDs() where pid > 0 {
            var task = proc_taskinfo()
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, taskInfoSize) == taskInfoSize else { continue }

            let cpuNanos = UInt64(Double(task.pti_total_user + task.pti_total_system) * nanosPerTick)
            let samples = Self.appending(CPUSample(time: now, nanos: cpuNanos), to: history[pid] ?? [])
            currentHistory[pid] = samples
            let usage = Self.averageUsage(samples)

            let path = previousPaths[pid] ?? Self.executablePath(of: pid)
            currentPaths[pid] = path
            let name = appNames[pid] ?? path.map { ($0 as NSString).lastPathComponent } ?? Self.shortName(of: pid)
            rows.append(ProcessRow(
                pid: pid,
                name: name,
                cpu: usage,
                memory: Self.footprint(of: pid) ?? task.pti_resident_size,
                canTerminate: pid != ownPID && !Self.protectedNames.contains(name),
                appPath: path.flatMap { Self.enclosingApp(of: $0) }
            ))
        }

        history = currentHistory
        previousPaths = currentPaths
        return rows
    }

    /// Adds a sample and drops ones that fall out of the window, keeping exactly one sample
    /// at or before the window start so the average always spans the full window.
    /// A counter that went backwards means the pid was reused by a new process: start over.
    static func appending(_ sample: CPUSample, to samples: [CPUSample]) -> [CPUSample] {
        guard let last = samples.last, sample.nanos >= last.nanos, sample.time > last.time else { return [sample] }
        var result = samples + [sample]
        while result.count > 2, sample.time - result[1].time >= averagingWindow {
            result.removeFirst()
        }
        return result
    }

    /// Share of one core used between the oldest and newest sample.
    static func averageUsage(_ samples: [CPUSample]) -> Double {
        guard let first = samples.first, let last = samples.last, last.time > first.time else { return 0 }
        return Double(last.nanos - first.nanos) / Double(last.time - first.time)
    }

    private static func allPIDs() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        return Array(pids.prefix(Int(max(count, 0))))
    }

    /// Same naming as `sample()`, for checking that a pid still belongs to the program we think it does.
    static func currentName(of pid: pid_t) -> String? {
        if let name = NSRunningApplication(processIdentifier: pid)?.localizedName { return name }
        return executablePath(of: pid).map { ($0 as NSString).lastPathComponent }
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
        return path.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    /// "/Applications/Claude.app/Contents/Frameworks/Claude Helper.app/…" → "/Applications/Claude.app".
    static func enclosingApp(of path: String) -> String? {
        guard let range = path.range(of: ".app/") else {
            return path.hasSuffix(".app") ? path : nil
        }
        return String(path[..<range.lowerBound]) + ".app"
    }

    private static func shortName(of pid: pid_t) -> String {
        var short = [CChar](repeating: 0, count: 256)
        if proc_name(pid, &short, UInt32(short.count)) > 0 {
            return short.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        }
        return "PID \(pid)"
    }

    private static func footprint(of pid: pid_t) -> UInt64? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? info.ri_phys_footprint : nil
    }
}
