import Foundation
import Darwin

/// Host / system identity: name, OS version, chip, uptime, load average, process count.
enum HostSampler {
    static func sample() -> HostInfo {
        HostInfo(
            name: hostName(),
            os: Self.osString(),
            chip: Sysctl.string("machdep.cpu.brand_string") ?? "Unknown",
            uptime: uptimeSeconds(),
            load: loadAverage(),
            procs: processCount()
        )
    }

    private static func hostName() -> String {
        let name = ProcessInfo.processInfo.hostName
        if name.hasSuffix(".local") {
            return String(name.dropLast(".local".count))
        }
        return name
    }

    private static func uptimeSeconds() -> Int {
        var boottime = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        let result = mib.withUnsafeMutableBufferPointer { mibPtr -> Int32 in
            sysctl(mibPtr.baseAddress, 2, &boottime, &size, nil, 0)
        }
        guard result == 0 else { return 0 }
        let boot = Double(boottime.tv_sec) + Double(boottime.tv_usec) / 1_000_000
        let now = Date().timeIntervalSince1970
        return max(0, Int(now - boot))
    }

    private static func loadAverage() -> [Double] {
        var loads = [Double](repeating: 0, count: 3)
        let n = getloadavg(&loads, 3)
        guard n == 3 else { return [0, 0, 0] }
        return loads
    }

    /// proc_listallpids's return value is a PID *count*, not a byte count, on
    /// this OS build (confirmed empirically: the nil-buffer call returns a
    /// value not divisible by sizeof(pid_t), and matches `ps aux` counts only
    /// when treated as a plain count). We size the buffer generously and add
    /// headroom since the process list can change between the two calls.
    private static func processCount() -> Int {
        let initialCount = proc_listallpids(nil, 0)
        guard initialCount > 0 else { return 0 }
        let capacity = Int(initialCount) + 128
        var pids = [pid_t](repeating: 0, count: capacity)
        let filledCount = proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.stride))
        guard filledCount > 0 else { return Int(initialCount) }
        return Int(filledCount)
    }

    /// "macOS 27.0 (26A428)" — shorter than operatingSystemVersionString.
    static func osString() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        var ver = "\(v.majorVersion).\(v.minorVersion)"
        if v.patchVersion > 0 { ver += ".\(v.patchVersion)" }
        let build = Sysctl.string("kern.osversion") ?? ""
        return build.isEmpty ? "macOS \(ver)" : "macOS \(ver) (\(build))"
    }
}
