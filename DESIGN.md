# WokyMon — Mac 資源監視器(Wokyis 5 吋螢幕專用)

日期:2026-09-18
狀態:v1.2(已通過 correctness 與 risk/simplicity 審查;之後依使用者要求「畫面要夠炫、cyberpunk 風格」改採 Swift 殼 + WKWebView)

## 1. 目標

在 Mac mini M4 上做一個「滿版、帶時鐘」的資源監視器。畫面固定顯示在 Wokyis M5 Retro Dock 的 5 吋內建螢幕上。

必要功能:

- 時鐘(時:分:秒)、日期、星期。
- CPU 使用率(總量 + 每核心)。
- 記憶體使用量。
- 磁碟使用量與讀寫速度。
- 網路上下行速度。
- GPU 使用率。
- 自動把視窗釘在 Wokyis 螢幕上,螢幕拔插後自動回到原位。

第二階段(非必要):CPU 溫度、風扇轉速、前幾名行程、設定檔、主題。

## 2. 已驗證的事實(2026-09-18 在本機量測)

| 項目 | 結果 |
|---|---|
| macOS | 27.0 (26A428),Apple M4 |
| Wokyis 螢幕 | NSScreen 名稱 `Wokyis`,vendor `4691`,model `9557`,1280x720,scale 1.0 |
| 螢幕位置 | frame `(-953, -720, 1280, 720)`,在主螢幕左上方 |
| EDID 回報的實體尺寸 | 290 x 169 mm(錯誤。實機是 5 吋,約 111 x 62 mm) |
| 工具鏈 | 無 Xcode。Command Line Tools 的 SDK 含 SwiftUI、AppKit、IOKit、Charts。Swift 6.4 |
| Python | 3.9.6,無 psutil,無 pyserial |
| sudo | 需要密碼。所以不能用 `powermetrics` |
| GPU 統計 | `ioreg -c IOAccelerator` 有 `PerformanceStatistics` → `Device Utilization %`、`Renderer Utilization %`、`Tiler Utilization %`、`In use system memory` |
| 磁碟統計 | `ioreg -c IOBlockStorageDriver` 有 `Statistics` → `Bytes (Read)`、`Bytes (Write)` |
| 核心數 | `hw.perflevel0.logicalcpu = 4`(Performance),`hw.perflevel1.logicalcpu = 6`(Efficiency),`hw.ncpu = 10` |
| 記憶體 | `hw.memsize = 16 GiB`。量測當下 swap 已用 7.4 / 8 GB,所以 swap 要顯示 |

注意:EDID 尺寸錯誤代表 macOS 以為這是 13 吋螢幕。系統字級在實機上會很小。字級要自己放大,不能靠系統。

## 3. 方案選擇

| 方案 | 優點 | 缺點 | 決定 |
|---|---|---|---|
| A. 原生 Swift app(SwiftPM,AppKit + SwiftUI) | 單一執行檔。CPU 開銷最低 | 光暈、漸層、glitch、補間動畫在 SwiftUI 上費工,難調到「炫」 | 不採用(原本首選,因視覺需求改變) |
| B. 網頁 + 本機 HTTP server | 排版快 | 瀏覽器視窗要手動放到 Wokyis 螢幕。Python 3.9 無 psutil。無法讀 GPU | 不採用 |
| C. Swift 殼 + WKWebView | Swift 讀數據並自動釘視窗;畫面用 HTML/CSS/Canvas,視覺效果最自由。網頁可單獨在瀏覽器用假資料預覽 | 兩套技術。WebKit 常駐記憶體約 100 MB | **採用** |

## 4. 架構

Swift Package `WokyMon`,一個 executable target,三個資料夾:

```
Sources/WokyMon/
  App/        main.swift、AppDelegate、視窗與螢幕釘選、WKWebView 橋接
  Metrics/    每種數據一個 Sampler,合併成 Snapshot(Codable → JSON)
Sources/WokyMon/Resources/ui/
  index.html  儀表板畫面(HTML/CSS/JS,單檔,不用外部資源)
Scripts/
  make-app.sh       把 SwiftPM 產物包成 WokyMon.app
  install-agent.sh  安裝 LaunchAgent,開機自動啟動
mockup/
  index.html        早期靜態排版稿(保留作參考)
```

資料流:

1. `MetricsEngine` 用 `Timer` 每 1 秒跑一次所有 Sampler。
2. 每個 Sampler 回傳目前值。需要差分的項目(CPU tick、網路 bytes、磁碟 bytes)由 Sampler 自己保存上一次的值。
3. 合併成一個不可變的 `Snapshot`,編成 JSON,在主執行緒呼叫 `webView.evaluateJavaScript("window.wokymon.update(<json>)")`。
4. 網頁保存 120 秒歷史(sparkline 用),自己做數字補間與動畫。

原則:採樣在背景 queue 做。網頁不做任何 I/O,只吃 JSON。

### 4.1 Swift ↔ 網頁介面(JSON,每秒一筆)

```json
{
  "ts": 1789700000.0,
  "host": { "name": "mac-mini", "os": "macOS 27.0 (26A428)", "chip": "Apple M4",
            "uptime": 15720, "load": [2.14, 1.83, 1.52], "procs": 612 },
  "cpu":  { "total": 37.2, "cores": [12.0, 8.5, 30.1, 5.0, 22.0, 9.0, 60.2, 45.0, 91.0, 20.0],
            "pcores": 4, "ecores": 6, "ecoresFirst": true },
  "gpu":  { "device": 13, "renderer": 12, "tiler": 13, "memUsed": 988954624 },
  "mem":  { "total": 17179869184, "used": 12026000000, "app": 6900000000,
            "wired": 2100000000, "compressed": 3026000000,
            "swapTotal": 8589934592, "swapUsed": 7751000000 },
  "disk": { "total": 494384795648, "used": 442000000000, "free": 52384795648,
            "readBps": 12400000, "writeBps": 3100000 },
  "net":  { "iface": "en0", "rxBps": 1550000, "txBps": 150000 }
}
```

- 讀不到的區塊給 `null`(例如 `gpu`),網頁顯示 `—`。
- 速度單位一律 bytes/s,網頁自己換算 MB/s 與 Mb/s。
- 網頁若偵測不到 `window.webkit`(直接用瀏覽器開),自動進入 demo 模式,用假資料跑動畫。這讓畫面可以獨立設計與預覽。
- Swift 在 `WKNavigationDelegate.didFinish` 之後才開始推資料。
- WKWebView 用 `loadFileURL(_:allowingReadAccessTo:)` 載入 `Bundle.module` 內的 `ui/index.html`;`setValue(false, forKey: "drawsBackground")` 讓底色由網頁決定;關閉右鍵選單與文字選取。

## 5. 數據來源(全部不需 sudo)

| 數據 | API | 備註 |
|---|---|---|
| 時鐘 | `Date` + `DateFormatter`,locale `zh_TW` | 每秒更新 |
| CPU 總量與每核心 | `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` | 差分 user+system+nice / total。用 `vm_deallocate` 釋放 |
| P/E 核心數 | `sysctl hw.perflevel0.logicalcpu`(P)、`hw.perflevel1.logicalcpu`(E) | M4 為 4P + 6E。**假設**:`host_processor_info` 的核心索引 0..E-1 為 E 核。這是社群工具的觀察,不是 Apple 保證。實作時用背景 QoS 的 `yes` 量測一次,寫進 README。UI 只用來上色,算錯不影響數值 |
| Load average | `getloadavg` | |
| 記憶體 | `host_statistics64(HOST_VM_INFO64)`,總量 `sysctl hw.memsize` | used = (internal − purgeable + wire + compressor) × page size。這是 Activity Monitor「已使用記憶體」的算法(App 記憶體 + 聯動 + 已壓縮)。實測應與其相差 < 0.3 GB |
| Swap | `sysctl vm.swapusage` | |
| 磁碟容量 | `statfs("/")` | APFS 用 `f_bavail` 算可用 |
| 磁碟讀寫速度 | IORegistry `IOBlockStorageDriver` 的 `Statistics` 字典,`Bytes (Read)` / `Bytes (Write)` | 對所有 driver 加總後差分 |
| 網路速度 | `getifaddrs`,`AF_LINK` 的 `if_data.ifi_ibytes / ifi_obytes` | 只算 `en*` 介面。差分 |
| GPU 使用率 | IORegistry class `IOAccelerator` 的 `PerformanceStatistics` → `Device Utilization %` | Apple Silicon 可用。找不到就顯示 `—` |
| 開機時間 | `sysctl kern.boottime` | 算 uptime |
| 行程數 | `proc_listallpids` 回傳筆數 | 給 SYSTEM 面板 |
| 溫度(第二階段,v1 不預留介面) | `IOHIDEventSystemClient` 私有 API,usage page `0xFF00`,usage `5` | 與 macmon、Stats 相同做法。macOS 大版本可能失效,要能優雅降級 |
| 風扇(第二階段) | AppleSMC user client,key `F0Ac` | 需要自寫 SMC client |

## 6. 視窗與螢幕釘選

1. 啟動時掃描 `NSScreen.screens`。優先條件:`CGDisplayVendorNumber == 4691 && CGDisplayModelNumber == 9557`。備援條件:`localizedName == "Wokyis"`。再備援:`--screen <name>` 參數。
2. 都找不到:在主螢幕開一個 1280x720 的普通視窗(方便開發與示範)。
3. 視窗設定(預設,可被覆蓋):`styleMask = .borderless`、`frame = screen.visibleFrame`(避開選單列)、`level = normal − 1`(壓在所有一般視窗之下,其他視窗可拖到它上面,點它也不會浮起)。網頁用 `transform: scale` 把 1280x720 版面縮到視窗大小。加 `--overlay` 才回到 `frame = screen.frame`、`level = mainMenu + 1`(蓋住選單列、浮在最上層)、`collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`、`hidesOnDeactivate = false`。顯示時呼叫 `orderFrontRegardless()`,不依賴 app 取得焦點。
4. 監聽 `NSApplication.didChangeScreenParametersNotification`。螢幕拔插後重新掃描並重設 frame。
5. `NSApp.setActivationPolicy(.accessory)`:不出現在 Dock,不搶焦點。
6. 參數 `--windowed`:強制普通視窗,開發用。
7. 參數 `--keep-awake`:用 `IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep)` 阻止顯示器睡眠。預設關閉,因為 macOS 無法只讓一個螢幕不睡,開了會讓全部螢幕常亮。使用者自行決定。
8. 程式進入點:手動 `NSApplication.shared` + `AppDelegate` + `NSWindow(contentView: NSHostingView(...))` + `app.run()`。不用 SwiftUI `App` / `WindowGroup`,因為它不方便控制視窗釘選。
9. 逃生方式:該螢幕被蓋住是預期行為。要停止 app,一律在主螢幕或終端機執行 `killall WokyMon`(或 `launchctl bootout gui/$UID/local.wokymon`)。

## 7. 畫面設計(1280 x 720,cyberpunk)

實機 5 吋 1280x720 約 294 ppi。1 px 約 0.086 mm。字級規則:

- 最小字級 22 px(實機約 1.9 mm 高)。
- 標籤 24 px,一般數值 32 px,主要數值 64–96 px。
- 字型:`ui-monospace`(macOS WebKit 對應 SF Mono)。數字用 `tabular-nums`。不載入外部字型,離線可用。

視覺風格:cyberpunk / 夜之城 HUD。

- 配色:底色 `#07030F`(近黑帶紫)。霓虹青 `#00F0FF`、霓虹洋紅 `#FF2BD6`、警示黃 `#F9F002`、危險紅 `#FF3B3B`、次要紫灰 `#7C6F9B`。
- 背景:淡紫網格 + 掃描線(CRT 橫紋)+ 暗角;每 6 秒一道掃描光帶由上而下掠過。
- 面板:斜切角(`clip-path` polygon,右上與左下切角)+ 1 px 霓虹邊框 + 外光暈;左上角有小型「編號 + 片假名」裝飾標籤(例:`01 // CPU コア`)。
- 警示:超過 85% 的面板邊框改成黃黑斜條紋(`repeating-linear-gradient`),數字轉紅並輕微 glitch。
- 時鐘:96 px,青色主體,左右各一層洋紅 / 青的色差偏移(chromatic aberration),每 10–20 秒隨機一次 200 ms 的 glitch 抖動。下方一條細進度條顯示本分鐘進度。
- CPU / GPU:270° 弧形儀表(Canvas),青→洋紅漸層描邊 + 外光暈,中央大數字;CPU 下方 10 根核心長條,E 核青、P 核洋紅。
- MEM:分段環(App 青 / Wired 洋紅 / Compressed 黃),旁列 swap。
- DISK:容量長條(切角)+ 讀寫雙線面積圖。
- NET:上下行雙線面積圖(下行青、上行洋紅),線條發光,尖峰處亮點。
- SYSTEM:主機名、macOS、晶片、uptime、load、行程數,右側一個緩慢旋轉的雷達掃描環當裝飾。
- 所有數字用 `requestAnimationFrame` 做 300 ms 補間,不會跳動。

排版(三列):

```
+--------------------------------------------------------------+
| 14:32:07                                  2026-09-18 星期五   |  120 pt
| (96 pt 時鐘)                                      (28 pt)      |
+---------------+---------------+---------------+---------------+
| CPU           | GPU           | MEM           | DISK          |
|  37%  (72pt)  |  12%  (72pt)  | 11.2/16 GB    | 412/460 GB    |  380 pt
|  ~~sparkline~~|  ~~sparkline~~|  ring 70%     |  R 12 MB/s    |
|  10 core bars |               |  swap 0.5 GB  |  W  3 MB/s    |
+---------------+---------------+---------------+---------------+
| NET  ↓ 12.4 Mb/s ~~sparkline~~ | SYSTEM  mac-mini  macOS 27.0  |  220 pt
|      ↑  1.2 Mb/s ~~sparkline~~ | up 4h 22m · load 2.1 1.8 1.5  |
|                                | 612 procs · swap 7.4/8 GB     |
+--------------------------------+-------------------------------+
```

顏色:使用率 < 60% 綠,60–85% 琥珀,> 85% 紅。背景 `#0B0F14`,文字 `#E6EDF3`,次要文字 `#8B98A5`。

圖表全部用 `<canvas>` 2D 繪製。每秒收到新資料才重畫;補間期間最多 30 fps,補間結束後停止重畫。裝飾動畫(掃描線、雷達、glitch)只用 CSS `transform` / `opacity` / `clip-path`,交給 GPU 合成。

## 8. 效能預算

- 目標:App(含 WebKit 行程)CPU 平均 < 10% 單核心(整機 10 核約 1%)。採樣每秒一次;Canvas 只在資料更新與 300 ms 補間期間重畫,上限 20 fps。
- 記憶體 < 180 MB(WebKit 佔大宗)。
- 裝飾動畫只用 CSS transform / opacity,timing 一律 `linear` / `ease`。

實測(2026-09-18,主程序 + 3 個 WebKit 行程,15 秒平均,系統本身負載高所以有雜訊):

| 版本 | 合計 CPU |
|---|---|
| 第一版(`height`/`width` 過渡、Canvas `shadowBlur`、`mix-blend-mode`) | 12.7% |
| 把裝飾動畫改成 `steps()` | 21–22%(更糟) |
| 關掉所有 CSS 動畫的對照組 | 8.7% |
| 過渡改用 `transform: scale`,光暈改用寬半透明描邊,`steps()` 改回 `linear` | 8–10% |
| 再關掉 Canvas 補間的對照組 | 4.8–6% |

教訓:
1. 會觸發 layout 的過渡(`height`、`width`)每秒跑 300 ms,是最大成本。改 `transform` 後歸零。
2. WebKit 的 `steps()` 動畫不走合成器,比 `linear` 貴一倍以上。
3. Canvas `shadowBlur` 很貴;用寬的半透明描邊當光暈,肉眼幾乎無差。
4. 除錯用 `WOKYMON_UI_QUERY="noanim=1"`(或 `notween=1`、`nocanvas=1`)可逐項關閉功能做對照。

## 9. 建置、安裝、啟動

```
swift build -c release
Scripts/make-app.sh              # 產出 build/WokyMon.app(Info.plist 含 LSUIElement=true)
Scripts/install-agent.sh         # 寫入 ~/Library/LaunchAgents/local.wokymon.plist 並 bootstrap
Scripts/install-agent.sh --uninstall   # bootout 並刪除 plist
```

本機建置不需簽章。LaunchAgent 設定:`RunAtLoad = true`、`KeepAlive = { SuccessfulExit = false }`(正常退出不重啟,崩潰才重啟)、`ThrottleInterval = 10`(避免崩潰迴圈洗 log)。

## 10. 風險

| 風險 | 影響 | 對策 |
|---|---|---|
| `IOAccelerator` 的 GPU 統計鍵名改變 | GPU 顯示 `—` | 找不到鍵就降級,不當機 |
| 溫度私有 API 在 macOS 27 失效 | 無溫度 | 列第二階段,預設關閉 |
| 螢幕拔插後 frame 錯位 | 畫面跑到別的螢幕 | 監聽螢幕變更通知重釘 |
| 視窗 level 高於選單列造成該螢幕無法操作 | 該螢幕只能放這個 app | 可接受。提供 `--windowed` |
| App 本身耗資源 | 違背監視器目的 | 效能預算 + `top` 驗證;`WOKYMON_UI_QUERY` 開關做對照實驗 |
| 顯示器自動睡眠,面板變黑 | 監視器沒用 | `--keep-awake` 旗標,或在系統設定把顯示器睡眠設為「永不」 |
| 崩潰迴圈 | CPU 與 log 洗版 | `SuccessfulExit=false` + `ThrottleInterval=10`;`--uninstall` 可一鍵移除 |
| app 無回應 | 該螢幕卡住 | 從主螢幕終端機 `killall WokyMon`;LaunchAgent 會重啟 |

## 11. 驗證方式

1. `swift build -c release` 成功。
2. `open Sources/WokyMon/Resources/ui/index.html`:瀏覽器內 demo 模式跑動畫,排版無溢出。
3. `./.build/release/WokyMon --windowed`:主螢幕出現 1280x720 視窗,時鐘每秒走動,數據為真實值。
4. `./.build/release/WokyMon`:視窗出現在 Wokyis 螢幕,填滿 1280x720。
5. 拔掉再接上 dock:視窗回到 Wokyis 螢幕。
6. 跑 `yes > /dev/null &` 兩個:CPU 數值上升,對應核心變紅。與 Activity Monitor 比對誤差 < 5%。
7. `top` 對主程序與三個 WebKit 行程取 15 秒平均:CPU 合計 < 10%。(實測 8–10%,見第 8 節)
8. 記憶體數值與 Activity Monitor「已使用記憶體」相差 < 0.3 GB。
9. 讓顯示器睡眠再喚醒:面板繼續刷新,時鐘正確。
10. `kill -9 $(pgrep WokyMon)`:LaunchAgent 在 10 秒內重啟;`launchctl bootout` 後不再重啟。

## 12. 分階段

- v1(本次):第 1 節必要功能全部、SYSTEM 面板、`--windowed`、`--keep-awake`、make-app、LaunchAgent(含 uninstall)。
- v2:溫度、風扇、前三名行程、`~/.config/wokymon/config.json`、主題切換。
