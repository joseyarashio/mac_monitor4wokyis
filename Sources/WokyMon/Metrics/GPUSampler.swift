import IOKit
import Foundation

/// GPU utilization via IORegistry class IOAccelerator's "PerformanceStatistics"
/// dictionary. Returns nil (never crashes) if the class or keys are missing.
final class GPUSampler {
    func sample() -> GPUInfo? {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOAccelerator")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var result: GPUInfo?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if result == nil,
               let props = IOKitHelpers.properties(of: service),
               let stats = props["PerformanceStatistics"] as? [String: Any] {
                let device = IOKitHelpers.doubleValue(stats["Device Utilization %"])
                let renderer = IOKitHelpers.doubleValue(stats["Renderer Utilization %"])
                let tiler = IOKitHelpers.doubleValue(stats["Tiler Utilization %"])
                let mem = IOKitHelpers.uint64Value(stats["In use system memory"])
                result = GPUInfo(device: device, renderer: renderer, tiler: tiler, memUsed: Int64(mem))
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return result
    }
}
