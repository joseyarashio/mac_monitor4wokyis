import AppKit
import IOKit.pwr_mgt

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options: LaunchOptions
    private var dashboardWindow: DashboardWindow?
    private var metricsEngine: MetricsEngine?
    private var keepAwakeAssertionID: IOPMAssertionID = 0
    private var hasKeepAwakeAssertion = false

    init(options: LaunchOptions) {
        self.options = options
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()

        let screen = ScreenPinner.findTargetScreen(options: options)
        let window = DashboardWindow(options: options, screen: screen)
        dashboardWindow = window
        window.show()

        if options.keepAwake {
            enableKeepAwake()
        }

        let engine = MetricsEngine(interval: options.interval)
        engine.onSnapshot = { [weak window] snapshot in
            window?.update(with: snapshot)
        }
        engine.start()
        metricsEngine = engine
    }

    func applicationWillTerminate(_ notification: Notification) {
        metricsEngine?.stop()
        if hasKeepAwakeAssertion {
            IOPMAssertionRelease(keepAwakeAssertionID)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Minimal menu bar so Cmd+Q works in --windowed mode (DESIGN.md §6).
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit WokyMon", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        NSApp.mainMenu = mainMenu
    }

    private func enableKeepAwake() {
        var assertionID: IOPMAssertionID = 0
        let reason = "WokyMon dashboard display" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )
        if result == kIOReturnSuccess {
            keepAwakeAssertionID = assertionID
            hasKeepAwakeAssertion = true
        }
    }
}
