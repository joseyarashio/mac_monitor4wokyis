import AppKit
import CoreGraphics

/// Finds the Wokyis external display among NSScreen.screens. See DESIGN.md §6.
enum ScreenPinner {
    /// Vendor/model reported by the Wokyis M5 Retro Dock's 5" panel (DESIGN.md §2).
    private static let wokyisVendor: UInt32 = 4691
    private static let wokyisModel: UInt32 = 9557
    private static let wokyisName = "Wokyis"

    /// Returns the target screen to pin to, or nil to fall back to a normal
    /// windowed presentation on the main screen.
    static func findTargetScreen(options: LaunchOptions) -> NSScreen? {
        if let screen = screenByVendorModel() {
            return screen
        }
        if let screen = NSScreen.screens.first(where: { $0.localizedName == wokyisName }) {
            return screen
        }
        if let name = options.screenName,
           let screen = NSScreen.screens.first(where: { $0.localizedName == name }) {
            return screen
        }
        return nil
    }

    private static func screenByVendorModel() -> NSScreen? {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }
            let displayID = CGDirectDisplayID(number.uint32Value)
            let vendor = CGDisplayVendorNumber(displayID)
            let model = CGDisplayModelNumber(displayID)
            if vendor == wokyisVendor && model == wokyisModel {
                return screen
            }
        }
        return nil
    }
}
