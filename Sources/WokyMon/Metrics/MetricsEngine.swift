import Foundation

/// Drives all samplers on a 1 Hz (configurable) background timer and
/// delivers each completed Snapshot via a callback on the main thread.
final class MetricsEngine {
    private let queue = DispatchQueue(label: "local.wokymon.metrics", qos: .utility)
    private var timer: DispatchSourceTimer?
    private let interval: TimeInterval

    private let cpuSampler = CPUSampler()
    private let diskSampler = DiskSampler()
    private let netSampler = NetSampler()
    private let gpuSampler = GPUSampler()

    /// Called on the main thread with each new Snapshot once start() has been called.
    var onSnapshot: ((Snapshot) -> Void)?

    init(interval: TimeInterval = 1.0) {
        self.interval = interval
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        let snapshot = buildSnapshot()
        DispatchQueue.main.async { [weak self] in
            self?.onSnapshot?(snapshot)
        }
    }

    /// Builds one Snapshot synchronously on the calling thread/queue. Used
    /// directly by --dump mode (no timer/run loop involved) and internally
    /// by the timer tick.
    func buildSnapshot() -> Snapshot {
        let ts = Date().timeIntervalSince1970
        let host = HostSampler.sample()
        let cpuResult = cpuSampler.sample()
        let cpu = CPUInfo(
            total: cpuResult.total,
            cores: cpuResult.cores,
            pcores: cpuSampler.pcores,
            ecores: cpuSampler.ecores,
            ecoresFirst: cpuSampler.ecoresFirst
        )
        let gpu = gpuSampler.sample()
        let mem = MemSampler.sample()
        let disk = diskSampler.sample()
        let net = netSampler.sample()
        return Snapshot(ts: ts, host: host, cpu: cpu, gpu: gpu, mem: mem, disk: disk, net: net)
    }
}
