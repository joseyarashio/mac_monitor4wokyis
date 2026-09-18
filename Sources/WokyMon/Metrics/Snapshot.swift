import Foundation

/// Immutable snapshot of all metrics for one sample tick.
/// Field names/shape mirror DESIGN.md §4.1 exactly — the web dashboard
/// depends on these exact JSON keys.
struct Snapshot: Codable {
    let ts: Double
    let host: HostInfo
    let cpu: CPUInfo
    let gpu: GPUInfo?
    let mem: MemInfo
    let disk: DiskInfo
    let net: NetInfo
}

struct HostInfo: Codable {
    let name: String
    let os: String
    let chip: String
    let uptime: Int
    let load: [Double]
    let procs: Int
}

struct CPUInfo: Codable {
    let total: Double
    let cores: [Double]
    let pcores: Int
    let ecores: Int
    let ecoresFirst: Bool
}

struct GPUInfo: Codable {
    let device: Double
    let renderer: Double
    let tiler: Double
    let memUsed: Int64
}

struct MemInfo: Codable {
    let total: Int64
    let used: Int64
    let app: Int64
    let wired: Int64
    let compressed: Int64
    let swapTotal: Int64
    let swapUsed: Int64
}

struct DiskInfo: Codable {
    let total: Int64
    let used: Int64
    let free: Int64
    let readBps: Double
    let writeBps: Double
}

struct NetInfo: Codable {
    let iface: String
    let rxBps: Double
    let txBps: Double
}
