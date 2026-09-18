import Darwin
import IOKit
import Foundation

/// Disk capacity via statfs("/") and read/write throughput summed across all
/// IOBlockStorageDriver instances in the IORegistry, delta'd per second.
final class DiskSampler {
    private var lastBytesRead: UInt64 = 0
    private var lastBytesWrite: UInt64 = 0
    private var lastTimestamp: Date?
    private var hasPrevious = false

    func sample() -> DiskInfo {
        let (total, used, free) = capacity()
        let (readBps, writeBps) = throughput()
        return DiskInfo(total: total, used: used, free: free, readBps: readBps, writeBps: writeBps)
    }

    private func capacity() -> (Int64, Int64, Int64) {
        var stat = statfs()
        guard statfs("/", &stat) == 0 else { return (0, 0, 0) }
        let total = Int64(stat.f_blocks) * Int64(stat.f_bsize)
        let free = Int64(stat.f_bavail) * Int64(stat.f_bsize)
        let used = max(0, total - free)
        return (total, used, free)
    }

    private func throughput() -> (Double, Double) {
        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0

        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOBlockStorageDriver")
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        if kr == KERN_SUCCESS {
            var service = IOIteratorNext(iterator)
            while service != 0 {
                if let props = IOKitHelpers.properties(of: service),
                   let stats = props["Statistics"] as? [String: Any] {
                    totalRead += IOKitHelpers.uint64Value(stats["Bytes (Read)"])
                    totalWrite += IOKitHelpers.uint64Value(stats["Bytes (Write)"])
                }
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }

        let now = Date()
        defer {
            lastBytesRead = totalRead
            lastBytesWrite = totalWrite
            lastTimestamp = now
            hasPrevious = true
        }

        guard hasPrevious, let last = lastTimestamp else { return (0, 0) }
        let dt = now.timeIntervalSince(last)
        guard dt > 0 else { return (0, 0) }

        let dr = max(0, Double(totalRead) - Double(lastBytesRead)) / dt
        let dw = max(0, Double(totalWrite) - Double(lastBytesWrite)) / dt
        return (dr, dw)
    }
}
