import AppKit
import Foundation

let options = LaunchOptions(arguments: CommandLine.arguments)

if options.dump {
    runDumpMode(options: options)
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate(options: options)
app.delegate = delegate
app.run()
