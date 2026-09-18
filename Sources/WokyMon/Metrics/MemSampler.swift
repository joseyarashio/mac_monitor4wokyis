import Darwin

/// Memory usage via host_statistics64(HOST_VM_INFO64) plus sysctl for totals/swap.
/// "used" follows Activity Monitor's "Memory Used" definition: app memory
/// (internal - purgeable) + wired + compressed.
enum MemSampler {
    /// Mirrors the layout of the private XNU `struct xsw_usage` from
    /// <sys/sysctl.h> (vm.swapusage). Not exposed as a named type by the
    /// Darwin module, so we read it as raw bytes via sysctlbyname.
    private struct SwapUsage {
        var total: UInt64 = 0
        var avail: UInt64 = 0
        var used: UInt64 = 0
        var pageSize: UInt32 = 0
        var encrypted: Int32 = 0
    }

    static func sample() -> MemInfo {
        let total = Int64(Sysctl.uint64("hw.memsize") ?? 0)
        let (app, wired, compressed) = vmCounts()
        let used = app + wired + compressed
        let (swapTotal, swapUsed) = swapUsage()
        return MemInfo(
            total: total,
            used: used,
            app: app,
            wired: wired,
            compressed: compressed,
            swapTotal: swapTotal,
            swapUsed: swapUsed
        )
    }

    private static func pageSize() -> UInt64 {
        var pageSize: vm_size_t = 0
        if host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS {
            return UInt64(pageSize)
        }
        return UInt64(vm_kernel_page_size)
    }

    private static func vmCounts() -> (app: Int64, wired: Int64, compressed: Int64) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) { statsPtr -> kern_return_t in
            statsPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return (0, 0, 0) }

        let page = Double(pageSize())
        let internalPages = Double(stats.internal_page_count)
        let purgeablePages = Double(stats.purgeable_count)
        let appPages = max(0, internalPages - purgeablePages)
        let wiredPages = Double(stats.wire_count)
        let compressedPages = Double(stats.compressor_page_count)

        return (
            Int64(appPages * page),
            Int64(wiredPages * page),
            Int64(compressedPages * page)
        )
    }

    private static func swapUsage() -> (total: Int64, used: Int64) {
        var usage = SwapUsage()
        var size = MemoryLayout<SwapUsage>.stride
        let kr = withUnsafeMutablePointer(to: &usage) { ptr -> Int32 in
            sysctlbyname("vm.swapusage", ptr, &size, nil, 0)
        }
        guard kr == 0 else { return (0, 0) }
        return (Int64(usage.total), Int64(usage.used))
    }
}
