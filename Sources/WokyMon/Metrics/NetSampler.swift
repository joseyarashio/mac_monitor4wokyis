import Darwin
import Foundation

/// Network throughput via getifaddrs/AF_LINK, summed per "en*" interface and
/// delta'd per second. Reports the en* interface with the highest combined
/// traffic in this sample (fallback "en0").
final class NetSampler {
    private var lastByIface: [String: (rx: UInt64, tx: UInt64)] = [:]
    private var lastTimestamp: Date?

    func sample() -> NetInfo {
        let current = readCounters()
        let now = Date()

        defer {
            lastByIface = current
            lastTimestamp = now
        }

        guard let last = lastTimestamp else {
            return NetInfo(iface: "en0", rxBps: 0, txBps: 0)
        }
        let dt = now.timeIntervalSince(last)
        guard dt > 0 else { return NetInfo(iface: "en0", rxBps: 0, txBps: 0) }

        var bestName: String?
        var bestRx: Double = 0
        var bestTx: Double = 0
        var bestTotal: Double = -1

        for (name, cur) in current {
            guard let prev = lastByIface[name] else { continue }
            let drx = max(0, Double(cur.rx) - Double(prev.rx)) / dt
            let dtx = max(0, Double(cur.tx) - Double(prev.tx)) / dt
            let total = drx + dtx
            if total > bestTotal {
                bestTotal = total
                bestName = name
                bestRx = drx
                bestTx = dtx
            }
        }

        guard let name = bestName else {
            return NetInfo(iface: "en0", rxBps: 0, txBps: 0)
        }
        return NetInfo(iface: name, rxBps: bestRx, txBps: bestTx)
    }

    private func readCounters() -> [String: (rx: UInt64, tx: UInt64)] {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else {
            return [:]
        }
        defer { freeifaddrs(ifaddrPtr) }

        var result: [String: (rx: UInt64, tx: UInt64)] = [:]
        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let p = ptr {
            let ifa = p.pointee
            ptr = ifa.ifa_next

            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name.hasPrefix("en") else { continue }
            guard let dataPtr = ifa.ifa_data else { continue }

            let netdata = dataPtr.withMemoryRebound(to: if_data.self, capacity: 1) { $0.pointee }
            let rx = UInt64(netdata.ifi_ibytes)
            let tx = UInt64(netdata.ifi_obytes)

            var existing = result[name] ?? (0, 0)
            existing.rx += rx
            existing.tx += tx
            result[name] = existing
        }
        return result
    }
}
