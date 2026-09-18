import Foundation

/// Parsed CLI flags. See DESIGN.md §6.
struct LaunchOptions {
    var windowed = false
    var screenName: String?
    var keepAwake = false
    var interval: TimeInterval = 1.0
    var dump = false

    init(arguments: [String]) {
        var i = 1
        while i < arguments.count {
            let arg = arguments[i]
            switch arg {
            case "--windowed":
                windowed = true
            case "--keep-awake":
                keepAwake = true
            case "--dump":
                dump = true
            case "--screen":
                i += 1
                if i < arguments.count { screenName = arguments[i] }
            case "--interval":
                i += 1
                if i < arguments.count, let value = TimeInterval(arguments[i]) {
                    interval = value
                }
            default:
                break
            }
            i += 1
        }
    }
}
