import AppKit
import WebKit

/// Borderless NSWindow that can become key/main and terminates the app on
/// Escape — needed because a normal borderless window does not reliably
/// receive key events when the app never activates (accessory policy).
private final class PinnedWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 { // Escape
            NSApp.terminate(nil)
            return
        }
        super.sendEvent(event)
    }
}

/// Owns the NSWindow + WKWebView that renders the dashboard, plus screen
/// pinning behavior. See DESIGN.md §4.1 and §6.
final class DashboardWindow: NSObject {
    private let window: NSWindow
    private let webView: WKWebView
    private let options: LaunchOptions
    private let pinned: Bool
    private var isReady = false
    private var screenChangeObserver: NSObjectProtocol?
    private var debounceWorkItem: DispatchWorkItem?

    init(options: LaunchOptions, screen: NSScreen?) {
        self.options = options

        let frame: NSRect
        let styleMask: NSWindow.StyleMask
        let pinned: Bool

        if let screen = screen, !options.windowed {
            frame = screen.frame
            styleMask = [.borderless]
            pinned = true
        } else {
            frame = NSRect(x: 0, y: 0, width: 1280, height: 720)
            styleMask = [.titled, .closable, .miniaturizable]
            pinned = false
        }
        self.pinned = pinned

        let window: NSWindow = pinned
            ? PinnedWindow(contentRect: frame, styleMask: styleMask, backing: .buffered, defer: false)
            : NSWindow(contentRect: frame, styleMask: styleMask, backing: .buffered, defer: false)

        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false

        if pinned {
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        } else {
            window.title = "WokyMon"
            window.center()
        }

        let config = WKWebViewConfiguration()
        let disableInteractionScript = WKUserScript(
            source: """
            document.addEventListener('contextmenu', e => e.preventDefault());
            document.documentElement.style.userSelect = 'none';
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(disableInteractionScript)

        let webView = WKWebView(frame: NSRect(origin: .zero, size: frame.size), configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.autoresizingMask = [.width, .height]

        self.window = window
        self.webView = webView

        super.init()

        webView.navigationDelegate = self
        window.contentView = webView

        if pinned {
            observeScreenChanges()
        }

        loadDashboard()
    }

    func show() {
        if pinned {
            window.orderFrontRegardless()
            window.makeKey()
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Pushes a Snapshot into the page via window.wokymon.update(). Only
    /// called once the page has finished its initial load, and always on
    /// the main thread (callers must already be on main).
    func update(with snapshot: Snapshot) {
        guard isReady else { return }
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(snapshot), let json = String(data: data, encoding: .utf8) else {
            return
        }
        webView.evaluateJavaScript("window.wokymon && window.wokymon.update(\(json))", completionHandler: nil)
    }

    private func loadDashboard() {
        guard let url = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "ui") else {
            return
        }
        var target = url
        // Debug hook: WOKYMON_UI_QUERY="noanim=1" appends ?noanim=1 to the page URL.
        if let q = ProcessInfo.processInfo.environment["WOKYMON_UI_QUERY"], !q.isEmpty,
           var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            comps.query = q
            if let u = comps.url { target = u }
        }
        webView.loadFileURL(target, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    private func observeScreenChanges() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleRepin()
        }
    }

    private func scheduleRepin() {
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.repinToTargetScreen()
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func repinToTargetScreen() {
        guard pinned else { return }
        guard let screen = ScreenPinner.findTargetScreen(options: options) else { return }
        window.setFrame(screen.frame, display: true)
    }
}

extension DashboardWindow: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isReady = true
    }
}
