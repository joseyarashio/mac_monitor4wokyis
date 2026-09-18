import Darwin

/// Per-core and total CPU usage via host_processor_info(PROCESSOR_CPU_LOAD_INFO).
/// Keeps the previous tick counts to compute deltas across samples.
final class CPUSampler {
    let pcores: Int
    let ecores: Int

    /// Assumption (not an Apple guarantee, observed by community tools such as
    /// macmon/Stats): host_processor_info reports E-cores first, i.e. logical
    /// core indices 0..<ecores are Efficiency cores and the remainder are
    /// Performance cores. This is only used by the UI to color-code cores;
    /// getting it wrong does not affect the numeric usage values.
    let ecoresFirst = true

    private var previousTicks: [Int32] = []

    init() {
        pcores = Int(Sysctl.int32("hw.perflevel0.logicalcpu") ?? 4)
        ecores = Int(Sysctl.int32("hw.perflevel1.logicalcpu") ?? 6)
    }

    struct Result {
        let total: Double
        let cores: [Double]
    }

    func sample() -> Result {
        var numCPUsU: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0

        let kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUsU, &cpuInfo, &numCpuInfo)
        guard kr == KERN_SUCCESS, let cpuInfo = cpuInfo else {
            return Result(total: 0, cores: [])
        }
        defer {
            let size = vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: cpuInfo)), size)
        }

        let numCPUs = Int(numCPUsU)
        let stateCount = Int(CPU_STATE_MAX)
        var newTicks = [Int32](repeating: 0, count: numCPUs * 4)
        var cores: [Double] = []
        var totalActiveDelta: Double = 0
        var totalTicksDelta: Double = 0
        let havePrevious = previousTicks.count == numCPUs * 4

        for i in 0..<numCPUs {
            let offset = i * stateCount
            let user = cpuInfo[offset + Int(CPU_STATE_USER)]
            let system = cpuInfo[offset + Int(CPU_STATE_SYSTEM)]
            let idle = cpuInfo[offset + Int(CPU_STATE_IDLE)]
            let nice = cpuInfo[offset + Int(CPU_STATE_NICE)]

            newTicks[i * 4 + 0] = user
            newTicks[i * 4 + 1] = system
            newTicks[i * 4 + 2] = idle
            newTicks[i * 4 + 3] = nice

            if havePrevious {
                let du = Double(user &- previousTicks[i * 4 + 0])
                let ds = Double(system &- previousTicks[i * 4 + 1])
                let di = Double(idle &- previousTicks[i * 4 + 2])
                let dn = Double(nice &- previousTicks[i * 4 + 3])
                let active = du + ds + dn
                let totalTicks = active + di
                let pct = totalTicks > 0 ? max(0, min(100, (active / totalTicks) * 100)) : 0
                cores.append(pct)
                totalActiveDelta += max(0, active)
                totalTicksDelta += max(0, totalTicks)
            } else {
                cores.append(0)
            }
        }

        previousTicks = newTicks
        let total = totalTicksDelta > 0 ? max(0, min(100, (totalActiveDelta / totalTicksDelta) * 100)) : 0
        return Result(total: total, cores: cores)
    }
}
