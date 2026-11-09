import AppKit

enum ProcessKiller {
    /// Apps get a polite quit (they may ask to save documents); background processes get a signal.
    static func terminate(pid: pid_t, force: Bool) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            _ = force ? app.forceTerminate() : app.terminate()
        } else {
            _ = kill(pid, force ? SIGKILL : SIGTERM)
        }
    }
}
