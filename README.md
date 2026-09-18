**English** | [繁體中文](README.zh-TW.md)

# WokyMon

A resource monitor for the Mac mini M4, pinned full-screen to the 5-inch external display of a Wokyis dock (1280x720). Design details are in `DESIGN.md` (Traditional Chinese).

## Screenshots

Captured on 2026-09-18 on a Mac mini M4, pinned to the Wokyis screen in the default non-overlay mode (menu bar kept):

![WokyMon dashboard](docs/screenshots/wokyis-dashboard.png)

![WokyMon dashboard, a few seconds later](docs/screenshots/wokyis-dashboard-2.png)

Left to right, top to bottom: clock and date, CPU (total plus E/P per-core bars), GPU (render/tiler, VRAM), memory (app/compressed/wired/swap), disk (usage and read/write throughput), network up/down, system info.

## Build

```
swift build -c release
```

Requires macOS 14+ and Swift 5.9+. Command Line Tools are enough; Xcode is not needed.

## Run options

```
.build/release/WokyMon [--windowed] [--overlay] [--screen <name>] [--keep-awake] [--interval <seconds>] [--dump]
```

- `--windowed`: open a normal 1280x720 window on the main display (for development and demos) instead of pinning to a screen.
- `--screen <name>`: fallback display, matched by `NSScreen.localizedName`, used when no Wokyis screen is found.
- `--overlay`: cover the whole Wokyis screen including the menu bar and float above every window, so nothing can cover it. **Off by default**: the default mode sits below all normal windows and avoids the menu bar, so other windows can be dragged over it.
- `--keep-awake`: prevent display idle sleep via `IOPMAssertionCreateWithName`. Off by default, because macOS cannot keep a single display awake; enabling it keeps every display on.
- `--interval <seconds>`: sampling interval, default `1.0`.
- `--dump`: no window. Sample twice (`--interval` seconds apart), print one Snapshot as JSON to stdout and exit 0. The resource bundle resolution for `ui/index.html` is printed to stderr so you can verify `Bundle.module` finds its resources.

Display selection order when none is specified: Wokyis vendor/model (`4691`/`9557`) → `localizedName == "Wokyis"` → the `--screen` argument → otherwise fall back to a normal `--windowed` window.

## Package as a .app

```
Scripts/make-app.sh
```

Produces `build/WokyMon.app` with an ad-hoc signature, then runs `--dump` once to verify the resource bundle resolves inside the `.app`. `Scripts/make-app.sh --install` additionally copies the app to `/Applications/WokyMon.app` (falling back to `~/Applications` if not writable), after which it can be launched from Launchpad / Finder or with `open -a WokyMon`.

## Install / uninstall the login item

```
Scripts/install-agent.sh              # install and start the LaunchAgent (local.wokymon)
Scripts/install-agent.sh --uninstall  # bootout and remove the plist
```

Run `Scripts/make-app.sh` first. The LaunchAgent uses `RunAtLoad=true`, `KeepAlive={SuccessfulExit=false}` (restart only after a crash, not after a clean exit) and `ThrottleInterval=10`. Logs go to `~/Library/Logs/WokyMon/`.

## How to stop it

The pinned screen is fully covered by the app, so it cannot be operated from that screen. From the main display or over SSH:

```
killall WokyMon
```

With the LaunchAgent installed it restarts after 10 seconds; to disable it for good use `Scripts/install-agent.sh --uninstall` or `launchctl bootout gui/$UID/local.wokymon`.

In `--windowed` mode the window has a menu and Cmd+Q quits. When pinned to the Wokyis screen, Esc also quits.

## E/P core index assumption

The per-core array returned by `host_processor_info` is **assumed** to list indices `0..<ecores` as Efficiency cores and the rest as Performance cores (`ecoresFirst = true`). This matches what community tools such as macmon and Stats observe; Apple does not document it. The assumption only affects core colouring in the UI (E cores cyan, P cores magenta). If it is wrong, the CPU usage numbers themselves are unaffected.

## UI debugging

- Open `Sources/WokyMon/Resources/ui/index.html` directly in a browser (optionally with `?demo=1`): if no data arrives from Swift within 3 seconds it enters demo mode and animates with fake data.
- The `WOKYMON_UI_QUERY` environment variable appends a query string to the page URL, useful for performance comparisons:

```
WOKYMON_UI_QUERY="noanim=1" .build/release/WokyMon     # disable all CSS animation
WOKYMON_UI_QUERY="notween=1" .build/release/WokyMon    # no number tweening
WOKYMON_UI_QUERY="nocanvas=1" .build/release/WokyMon   # skip Canvas drawing
```

## Measured overhead

Main process plus three WebKit processes total about 8–10% of one core (about 1% of the whole Mac mini M4) and about 180 MB of memory. See `DESIGN.md` section 8.
