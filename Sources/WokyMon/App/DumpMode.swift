import Foundation

/// `--dump`: prints one Snapshot as JSON to stdout after 2 samples and exits,
/// without touching AppKit/NSApplication/WKWebView at all. Debug/verification aid.
///
/// Also resolves the SwiftPM resource bundle (ui/index.html) via
/// Bundle.module and reports the result on stderr. This lets
/// `WokyMon.app/Contents/MacOS/WokyMon --dump` double as the proof that the
/// resource bundle resolves correctly from inside the packaged .app
/// (Scripts/make-app.sh uses it for exactly that).
func runDumpMode(options: LaunchOptions) {
    let engine = MetricsEngine(interval: options.interval)

    // First sample seeds delta-based counters (CPU ticks, disk/net bytes);
    // the second sample (after `interval` seconds) yields real deltas.
    _ = engine.buildSnapshot()
    Thread.sleep(forTimeInterval: options.interval)
    let snapshot = engine.buildSnapshot()

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(snapshot), let json = String(data: data, encoding: .utf8) else {
        FileHandle.standardError.write("wokymon: failed to encode Snapshot as JSON\n".data(using: .utf8)!)
        exit(1)
    }
    print(json)

    if let url = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "ui") {
        FileHandle.standardError.write("wokymon: resource bundle OK: \(url.path)\n".data(using: .utf8)!)
    } else {
        FileHandle.standardError.write("wokymon: resource bundle FAILED (Bundle.module could not resolve ui/index.html)\n".data(using: .utf8)!)
        exit(1)
    }
}
