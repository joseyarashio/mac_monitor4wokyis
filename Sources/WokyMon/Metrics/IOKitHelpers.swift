import IOKit
import Foundation

/// Shared helpers for reading IORegistry entry properties, used by
/// DiskSampler (IOBlockStorageDriver) and GPUSampler (IOAccelerator).
enum IOKitHelpers {
    static func properties(of service: io_object_t) -> [String: Any]? {
        var unmanagedProps: Unmanaged<CFMutableDictionary>?
        let kr = IORegistryEntryCreateCFProperties(service, &unmanagedProps, kCFAllocatorDefault, 0)
        guard kr == KERN_SUCCESS, let props = unmanagedProps?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return props
    }

    static func doubleValue(_ any: Any?) -> Double {
        if let n = any as? NSNumber { return n.doubleValue }
        return 0
    }

    static func uint64Value(_ any: Any?) -> UInt64 {
        if let n = any as? NSNumber { return n.uint64Value }
        return 0
    }
}
