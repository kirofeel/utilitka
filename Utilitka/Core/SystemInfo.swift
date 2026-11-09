import Foundation

enum SystemInfo {
    static let chipName: String = sysctlString("machdep.cpu.brand_string") ?? "Mac"
    static let coreCount = ProcessInfo.processInfo.processorCount

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    static let bootDate: Date? = {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &bootTime, &size, nil, 0) == 0 else { return nil }
        return Date(timeIntervalSince1970: Double(bootTime.tv_sec) + Double(bootTime.tv_usec) / 1_000_000)
    }()
}

enum Format {
    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
    }

    static func storage(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private static let rateFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false // "0 КБ", not "Нуль КБ"
        return formatter
    }()

    static func rate(_ bytesPerSecond: Double) -> String {
        rateFormatter.string(fromByteCount: Int64(bytesPerSecond.rounded())) + "/с"
    }

    /// "Brave Browser Helper (Renderer)" → "Brave Browser · Renderer", so helpers read as their app.
    static func processName(_ name: String) -> String {
        guard let range = name.range(of: " Helper") else { return name }
        let app = name[..<range.lowerBound]
        let kind = name[range.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: " ()"))
        return kind.isEmpty ? "\(app) · помічник" : "\(app) · \(kind)"
    }

    /// "7 дн 3 год".
    static func duration(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = interval >= 86_400 ? [.day, .hour] : [.hour, .minute]
        formatter.maximumUnitCount = 2
        return formatter.string(from: interval) ?? ""
    }

    /// 1.0 = 100 %.
    static func percent(_ fraction: Double, digits: Int = 1) -> String {
        fraction.formatted(.percent.precision(.fractionLength(digits)))
    }
}
