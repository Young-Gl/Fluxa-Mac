import AppKit
import IOKit.ps
import ServiceManagement

let wattsBundleID = "local.hanchao.Watts"
let diagnosticName = Notification.Name("local.hanchao.Watts.inspect")
let showName = Notification.Name("local.hanchao.Watts.show")
let hideName = Notification.Name("local.hanchao.Watts.hide")
let detailsName = Notification.Name("local.hanchao.Watts.details")
let clickName = Notification.Name("local.hanchao.Watts.click")
let languageName = Notification.Name("local.hanchao.Watts.language")
let settingsName = Notification.Name("local.hanchao.Watts.settings")
let devicesName = Notification.Name("local.hanchao.Watts.devices")

func diagnosticDirectory() -> URL {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent(wattsBundleID)
}

final class WattsAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let reader = PowerReader()
    private let devices = DeviceBatteryMonitor()
    private var devicePanel: DevicePanelController?
    private var devicePage = false
    private let panel = PowerPanelController()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var powerSource: CFRunLoopSource?
    private var snapshot = PowerSnapshot()
    private var previousFingerprint = ""
    private var lastChanged = Date()
    private var observerTokens: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var sampleCount = 0
    private var totalReadTime: Double = 0
    private var lastReadTime: Double = 0
    private var activity = ActivityState()
    private var paused: Bool { activity.paused }
    private var sampleGate = SamplingGate()
    private var pendingSample: Timer?
    private var lastStatusTitle = ""
    private var lastSymbol = ""
    private var lastConnection: Bool?
    private var awaitingConnectionTelemetry = false
    private var preTransitionFingerprint = ""
    private var transitionUptime: Double = 0
    private let defaults = UserDefaults.standard
    private var activeSettingsMenu: NSMenu?
    private let contactEmail = "yanghanchao2002@outlook.com"

    private var interval: Double {
        let value = defaults.double(forKey: "readInterval")
        return [1.0, 2.0, 5.0].contains(value) ? value : 2.0
    }
    private var showVoltage: Bool { defaults.bool(forKey: "showVoltage") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second click on the app reopens the existing popover instead of creating duplicate menu items.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: wattsBundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty {
            DistributedNotificationCenter.default().postNotificationName(showName, object: nil, userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "WattsPower"
        if let button = statusItem.button {
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.title = " — W"
            button.target = self; button.action = #selector(togglePopover)
            button.imagePosition = .noImage
            button.setAccessibilityLabel("Fluxa, " + L10n.text("点击查看功率详情", "click for power details"))
        }
        popover.contentViewController = panel
        popover.contentSize = NSSize(width: panel.width, height: panel.height)
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        panel.onSettings = { [weak self] button in self?.settingsMenu(button) }
        panel.onRefresh = { [weak self] in self?.sample(force: true) }
        panel.onPageChanged = { [weak self] showingDetails in
            guard let self else { return }
            self.popover.contentSize = NSSize(width: self.panel.width, height: self.panel.height)
            if showingDetails { self.sample(force: true) }
            else { self.reader.stopDetails(); self.snapshot.breakdown = nil }
            self.updatePanel()
        }
        panel.onDevices = { [weak self] in self?.showDevices() }
        devices.onUpdate = { [weak self] archive in
            guard let self else { return }
            if self.popover.isShown && self.devicePage { self.devicePanel?.update(archive, completed: self.devices.lastCompleted) }
        }
        installObservers()
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<WattsAppDelegate>.fromOpaque(context).takeUnretainedValue().sample(force: true)
        }, context)?.takeRetainedValue() {
            powerSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        sample(force: true)
        restartTimer()
        devices.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover(); return false
    }

    private func installObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        for (name, reason) in [(NSWorkspace.willSleepNotification, ActivityState.Reason.systemSleep), (NSWorkspace.screensDidSleepNotification, .displaySleep)] {
            observe(workspace, name) { [weak self] in self?.setActivity(reason, paused: true) }
        }
        for (name, reason) in [(NSWorkspace.didWakeNotification, ActivityState.Reason.systemSleep), (NSWorkspace.screensDidWakeNotification, .displaySleep)] {
            observe(workspace, name) { [weak self] in self?.setActivity(reason, paused: false) }
        }
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(inspect(_:)), name: diagnosticName, object: nil)
        distributed.addObserver(self, selector: #selector(showPopover), name: showName, object: nil)
        distributed.addObserver(self, selector: #selector(hidePopover), name: hideName, object: nil)
        distributed.addObserver(self, selector: #selector(showDetails), name: detailsName, object: nil)
        distributed.addObserver(self, selector: #selector(clickStatus), name: clickName, object: nil)
        distributed.addObserver(self, selector: #selector(changeLanguageNotification(_:)), name: languageName, object: nil)
        distributed.addObserver(self, selector: #selector(showSettings), name: settingsName, object: nil)
        distributed.addObserver(self, selector: #selector(showDevices), name: devicesName, object: nil)
        observe(NotificationCenter.default, NSLocale.currentLocaleDidChangeNotification) { [weak self] in
            self?.sample(force: true); self?.devices.languageChanged(); self?.updatePanel()
        }
    }
    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ handler: @escaping () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in handler() }
        observerTokens.append((center, token))
    }
    private func setActivity(_ reason: ActivityState.Reason, paused value: Bool) {
        guard activity.set(reason, paused: value) else { return }
        devices.setPaused(paused)
        if paused {
            timer?.invalidate(); timer = nil
            pendingSample?.invalidate(); pendingSample = nil
            reader.stopDetails(); snapshot.breakdown = nil
            hidePopover()
        } else {
            sample(force: true); restartTimer()
        }
    }

    private func restartTimer() {
        timer?.invalidate()
        guard !paused else { return }
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.sample() }
        t.tolerance = min(0.2, interval * 0.1)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func sample(force: Bool = false) {
        guard !paused else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        let delay = sampleGate.delay(at: uptime)
        if delay > 0 {
            if force && pendingSample == nil {
                let work = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
                    self?.pendingSample = nil; self?.sample(force: true)
                }
                pendingSample = work
                RunLoop.main.add(work, forMode: .common)
            }
            return
        }
        pendingSample?.invalidate(); pendingSample = nil
        sampleGate.record(at: uptime)
        autoreleasepool { performSample(uptime: uptime) }
    }
    private func performSample(uptime: Double) {
        let start = CFAbsoluteTimeGetCurrent()
        var fresh = reader.read(includeDetails: popover.isShown && !devicePage && panel.detailsShown)
        lastReadTime = CFAbsoluteTimeGetCurrent() - start
        totalReadTime += lastReadTime
        sampleCount += 1
        // After a physical power-source edge, the SMC may keep its preceding snapshot.
        // Hide that stale snapshot until its power fields change, regardless of IsCharging.
        if let old = lastConnection, let new = fresh.connected, old != new {
            preTransitionFingerprint = previousPowerFingerprint(snapshot)
            transitionUptime = uptime
            awaitingConnectionTelemetry = true
        }
        if let new = fresh.connected { lastConnection = new }
        if awaitingConnectionTelemetry {
            let stale = previousPowerFingerprint(fresh) == preTransitionFingerprint
            if !stale && fresh.state != .waiting && fresh.state != .unavailable {
                awaitingConnectionTelemetry = false
            } else if stale || fresh.state == .waiting {
                fresh.inputW = fresh.connected == false ? 0 : nil
                fresh.systemW = nil; fresh.netBatteryW = nil
                fresh.measuredBatteryW = nil; fresh.voltageV = nil; fresh.currentA = nil
                fresh.state = .waiting
                fresh.note = uptime - transitionUptime > 30 ? "系统功率遥测尚未更新；请检查电源连接。" : "电源已切换，等待硬件更新功率读数。"
            }
        }
        snapshot = fresh
        #if !RESOURCE_AUDIT
        devices.updateMac(fresh)
        #endif
        if fresh.fingerprint != previousFingerprint {
            previousFingerprint = fresh.fingerprint; lastChanged = Date()
        }
        updateStatus()
        if popover.isShown { updatePanel() }
    }

    private func previousPowerFingerprint(_ s: PowerSnapshot) -> String {
        "\(s.inputW ?? -999)|\(s.systemW ?? -999)|\(s.measuredBatteryW ?? -999)"
    }

    private func updateStatus() {
        guard let button = statusItem?.button else { return }
        var title = " " + wattText(snapshot.barW)
        if showVoltage, let v = snapshot.voltageV { title += String(format: " / %.1f V", v) }
        if snapshot.estimated, snapshot.barW != nil { title = " ≈" + title.trimmingCharacters(in: .whitespaces) }
        if title != lastStatusTitle { button.title = title; lastStatusTitle = title }
        button.image = nil; lastSymbol = "none"
        button.toolTip = "\(snapshot.state.title)\n\(L10n.text("输入", "Input")) \(wattText(snapshot.inputW)) · \(L10n.text("运行", "System")) \(wattText(snapshot.systemW)) · \(L10n.text("净充电", "Net")) \(wattText(snapshot.netBatteryW, signed: true))"
        button.setAccessibilityLabel(L10n.appName + ", \(snapshot.state.title), \(wattText(snapshot.barW)), " + L10n.text("点击查看详情", "click for details"))
    }
    private func updatePanel() {
        if devicePage {
            let size = NSSize(width: 360, height: 480)
            if popover.contentSize != size { popover.contentSize = size }
            return
        }
        panel.update(snapshot, interval: interval, unchangedSeconds: Date().timeIntervalSince(lastChanged), paused: paused)
        let size = NSSize(width: panel.width, height: panel.height)
        if popover.contentSize != size { popover.contentSize = size }
    }

    @objc private func togglePopover() { popover.isShown ? hidePopover() : showPopover() }
    @objc private func showPopover() {
        guard let button = statusItem?.button else { return }
        sample(force: true); updatePanel()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    @objc private func hidePopover() { activeSettingsMenu?.cancelTracking(); popover.performClose(nil) }
    func popoverDidClose(_ notification: Notification) {
        panel.setDetails(false); reader.stopDetails()
        if devicePage {
            devicePage = false; popover.contentViewController = panel; devicePanel = nil
            popover.contentSize = NSSize(width: panel.width, height: panel.height)
        }
    }
    @objc private func showDevices() {
        panel.setDetails(false); reader.stopDetails()
        if devicePanel == nil {
            let controller = DevicePanelController()
            controller.onBack = { [weak self] in self?.showPowerPage() }
            controller.onRefresh = { [weak self] in self?.devices.refresh() }
            controller.onSettings = { [weak self] button in self?.settingsMenu(button) }
            devicePanel = controller
        }
        devicePage = true
        popover.contentViewController = devicePanel
        popover.contentSize = NSSize(width: 360, height: 480)
        devicePanel?.update(devices.archive, completed: devices.lastCompleted)
        showPopover()
    }
    private func showPowerPage() {
        devicePage = false; popover.contentViewController = panel; devicePanel = nil
        popover.contentSize = NSSize(width: panel.width, height: panel.height)
        sample(force: true); updatePanel()
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        if urls.contains(where: { $0.scheme == "fluxa" && $0.host == "devices" }) { showDevices() }
    }
    @objc private func clickStatus() { statusItem?.button?.performClick(nil) }
    @objc private func showDetails() { showPowerPage(); showPopover(); panel.setDetails(true) }
    @objc private func showSettings() {
        showPopover()
        DispatchQueue.main.async { [weak self] in self?.panel.showSettings() }
    }
    @objc private func changeLanguageNotification(_ notification: Notification) {
        guard let language = notification.object as? String, ["auto", "en", "zh"].contains(language) else { return }
        defaults.set(language, forKey: "languagePreference"); devices.languageChanged(); sample(force: true); updatePanel()
    }

    private func settingsMenu(_ button: NSButton) {
        let menu = makeSettingsMenu()
        activeSettingsMenu = menu
        defer { activeSettingsMenu = nil }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }
    private func makeSettingsMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let heading = NSMenuItem(title: L10n.text("菜单栏显示", "Menu bar"), action: nil, keyEquivalent: "")
        heading.isEnabled = false; menu.addItem(heading)
        let volts = NSMenuItem(title: L10n.text("同时显示电压", "Show voltage"), action: #selector(toggleVoltage), keyEquivalent: "")
        volts.target = self; volts.state = showVoltage ? .on : .off; menu.addItem(volts)
        menu.addItem(.separator())
        let rate = NSMenuItem(title: L10n.text("读取间隔", "Refresh interval"), action: nil, keyEquivalent: "")
        rate.isEnabled = false; menu.addItem(rate)
        for i in [1, 2, 5] {
            let item = NSMenuItem(title: "\(i)\(L10n.text(" 秒", i == 1 ? " second" : " seconds"))\(i == 2 ? L10n.text("（推荐）", " (recommended)") : "")", action: #selector(changeInterval(_:)), keyEquivalent: "")
            item.tag = i; item.target = self; item.state = interval == Double(i) ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let deviceHeading = NSMenuItem(title: L10n.text("设备与小组件", "Devices & widget"), action: nil, keyEquivalent: "")
        deviceHeading.isEnabled = false; menu.addItem(deviceHeading)
        let deviceItem = NSMenuItem(title: L10n.text("查看设备电量", "Device batteries"), action: #selector(showDevices), keyEquivalent: "")
        deviceItem.target = self; menu.addItem(deviceItem)
        let widget = NSMenuItem(title: L10n.text("添加 macOS 小组件…", "Add macOS widget…"), action: #selector(widgetInstructions), keyEquivalent: "")
        widget.target = self; menu.addItem(widget)
        let selection = NSMenuItem(title: L10n.text("小组件显示的设备", "Widget devices"), action: nil, keyEquivalent: "")
        let selectionMenu = NSMenu()
        let selectedIDs = devices.archive.selected.map { $0.id }
        let automatic = NSMenuItem(title: L10n.text("自动选择", "Automatic selection"), action: #selector(resetWidgetDevices), keyEquivalent: "")
        automatic.target = self; automatic.state = devices.archive.usesCustomSelection ? .off : .on
        selectionMenu.addItem(automatic); selectionMenu.addItem(.separator())
        for d in devices.archive.devices {
            let item = NSMenuItem(title: d.name, action: #selector(selectWidgetDevice(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = d.id; item.state = selectedIDs.contains(d.id) ? .on : .off
            item.isEnabled = selectedIDs.contains(d.id) || selectedIDs.count < 8
            selectionMenu.addItem(item)
        }
        selection.submenu = selectionMenu; menu.addItem(selection)
        let deviceRefresh = NSMenuItem(title: L10n.text("刷新设备电量 · 每分钟自动读取", "Refresh batteries · automatic every minute"), action: #selector(refreshDevices), keyEquivalent: "")
        deviceRefresh.target = self; menu.addItem(deviceRefresh)
        menu.addItem(.separator())
        let loginState = SMAppService.mainApp.status
        let login = NSMenuItem(title: loginState == .requiresApproval ? L10n.text("登录时启动（等待系统允许）", "Launch at login (awaiting approval)") : L10n.text("登录时启动", "Launch at login"), action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self; login.state = loginState == .enabled || loginState == .requiresApproval ? .on : .off
        menu.addItem(login)
        if loginState == .requiresApproval {
            let open = NSMenuItem(title: L10n.text("打开登录项设置", "Open Login Items settings"), action: #selector(openLoginSettings), keyEquivalent: "")
            open.target = self; menu.addItem(open)
        }
        menu.addItem(.separator())
        let languages = NSMenuItem(title: L10n.text("语言", "Language"), action: nil, keyEquivalent: "")
        let languageMenu = NSMenu()
        for (code, title) in [("auto", L10n.text("自动 · 跟随系统", "Automatic · system language")), ("zh", "中文"), ("en", "English")] {
            let item = NSMenuItem(title: title, action: #selector(changeLanguageItem(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = code
            item.state = (defaults.string(forKey: "languagePreference") ?? "auto") == code ? .on : .off
            languageMenu.addItem(item)
        }
        languages.submenu = languageMenu; menu.addItem(languages)
        let refresh = NSMenuItem(title: L10n.text("立即刷新", "Refresh now"), action: #selector(refreshNow), keyEquivalent: "")
        refresh.target = self; menu.addItem(refresh)
        menu.addItem(.separator())
        let about = NSMenuItem(title: L10n.text("关于 Fluxa", "About Fluxa"), action: #selector(aboutReadings), keyEquivalent: "")
        about.target = self; menu.addItem(about)
        let quit = NSMenuItem(title: L10n.text("退出 ", "Quit ") + L10n.appName, action: #selector(quitApp), keyEquivalent: "")
        quit.target = self; menu.addItem(quit)
        return menu
    }
    @objc private func widgetInstructions() {
        hidePopover()
        let alert = NSAlert()
        alert.messageText = L10n.text("添加 Fluxa 小组件", "Add a Fluxa widget")
        alert.informativeText = L10n.text("右键桌面 → 编辑小组件，搜索 Fluxa，选择尺寸后添加。", "Right-click the desktop → Edit Widgets, search Fluxa, then choose a size to add.")
        alert.runModal()
    }
    @objc private func refreshDevices() { devices.refresh() }
    @objc private func selectWidgetDevice(_ item: NSMenuItem) { if let id = item.representedObject as? String { devices.select(id) } }
    @objc private func resetWidgetDevices() { devices.resetSelection() }
    @objc private func changeLanguageItem(_ item: NSMenuItem) {
        guard let code = item.representedObject as? String else { return }
        defaults.set(code, forKey: "languagePreference"); devices.languageChanged(); sample(force: true); updatePanel()
    }
    @objc private func refreshNow() { sample(force: true) }
    @objc private func quitApp() { NSApp.terminate(nil) }
    @objc private func toggleVoltage() { defaults.set(!showVoltage, forKey: "showVoltage"); updateStatus() }
    @objc private func changeInterval(_ item: NSMenuItem) {
        defaults.set(Double(item.tag), forKey: "readInterval"); restartTimer(); sample(force: true)
    }
    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                try SMAppService.mainApp.unregister()
            } else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = L10n.text("未能更改登录启动设置", "Could not change login setting")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
    @objc private func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
    @objc private func aboutReadings() {
        let alert = NSAlert()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.4.1"
        alert.messageText = L10n.appName + " " + version
        alert.informativeText = L10n.text(
            "Fluxa 将 Mac 的功率和常用设备的电量放在一处，安静地呈现。\n\n接电时显示输入功率，电池供电时显示运行消耗。净充电功率 = 输入 − 消耗。\n\n数据留在本机；不含广告、统计追踪或电量通知。欢迎将反馈与建议发送至 \(contactEmail)。",
            "Fluxa shows your Mac’s power at a glance, alongside batteries for your connected devices.\n\nOn power: charger input. On battery: system consumption. Net charging is input minus consumption.\n\nReadings stay on your Mac. No ads, analytics or battery alerts. Feedback is welcome at \(contactEmail).")
        alert.runModal()
    }

    @objc private func inspect(_ notification: Notification) {
        guard let nonce = notification.object as? String,
              nonce.count == 36, UUID(uuidString: nonce) != nil else { return }
        // Inspection reads current UI state without altering the power sample timer.
        var d: [String: Any] = [
            "nonce": nonce, "pid": ProcessInfo.processInfo.processIdentifier,
            "inspectedAt": Date().timeIntervalSince1970,
            "sampleCount": sampleCount, "intervalSeconds": interval,
            "averageReadMilliseconds": sampleCount > 0 ? totalReadTime * 1000 / Double(sampleCount) : 0,
            "lastReadMilliseconds": lastReadTime * 1000,
            "timerActive": timer?.isValid ?? false, "paused": paused,
            "pauseReasons": activity.reasons.map { $0.rawValue }.sorted(),
            "pendingSample": pendingSample != nil, "minimumSampleSpacing": sampleGate.minimumSpacing,
            "energySubscriptionActive": reader.energySubscriptionActive,
            "popoverShown": popover.isShown, "barTitle": lastStatusTitle,
            "statusIcon": lastSymbol, "showVoltage": showVoltage,
            "launchAtLogin": SMAppService.mainApp.status == .enabled,
            "bundlePath": Bundle.main.bundlePath,
            "panelWidth": panel.width, "panelHeight": panel.height,
            "visualStyle": panel.visualStyle,
            "detailsShown": panel.detailsShown,
            "language": L10n.chinese ? "zh" : "en",
            "languagePreference": defaults.string(forKey: "languagePreference") ?? "auto",
            "appName": L10n.appName, "contactEmail": contactEmail,
            "settingsTitles": makeSettingsMenu().items.map { $0.title },
            "settingsShown": activeSettingsMenu != nil,
            "visibleTexts": panel.visibleTexts
        ]
        d["devicePage"] = devicePage
        d["deviceMonitor"] = devices.diagnostic
        d["widgetExtensionInstalled"] = FileManager.default.fileExists(atPath: Bundle.main.bundlePath + "/Contents/PlugIns/FluxaWidget.appex")
        if let data = try? JSONEncoder().encode(devices.archive), let object = try? JSONSerialization.jsonObject(with: data) { d["batteries"] = object }
        if let button = statusItem?.button, let window = button.window {
            let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
            d["statusVisible"] = window.isVisible
            d["statusScreenRect"] = ["x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height]
        }
        if let window = popover.contentViewController?.view.window {
            d["popoverWindowNumber"] = window.windowNumber
            d["popoverScreenRect"] = ["x": window.frame.minX, "y": window.frame.minY, "width": window.frame.width, "height": window.frame.height]
        }
        if let screen = statusItem?.button?.window?.screen { d["screenHeight"] = screen.frame.height }
        if let data = try? JSONEncoder().encode(snapshot), let object = try? JSONSerialization.jsonObject(with: data) {
            d["snapshot"] = object
        }
        let directory = diagnosticDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: d, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: directory.appendingPathComponent("diagnostics.json"), options: .atomic)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        devices.stop()
        timer?.invalidate()
        pendingSample?.invalidate(); pendingSample = nil
        reader.stopDetails()
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        observerTokens.forEach { $0.center.removeObserver($0.token) }
        DistributedNotificationCenter.default().removeObserver(self)
    }
}

#if RESOURCE_AUDIT
extension WattsAppDelegate {
    func auditStart() { sample(force: true); restartTimer() }
    func auditRequest() { sample(force: true) }
    func auditRestart() { restartTimer() }
    func auditSetActivity(_ reason: ActivityState.Reason, paused: Bool) { setActivity(reason, paused: paused) }
    func auditPrimeDetails() { _ = reader.read(includeDetails: true) }
    var auditCount: Int { sampleCount }
    var auditPending: Bool { pendingSample != nil }
    var auditTimerActive: Bool { timer?.isValid ?? false }
    var auditPaused: Bool { paused }
    var auditDetailsActive: Bool { reader.energySubscriptionActive }
    func auditStop() { applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification)) }
}
#else
@main
struct WattsMain {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--sample") {
            printSnapshot(PowerReader().read(includeDetails: args.contains("--with-details"))); return
        }
        if let i = args.firstIndex(of: "--watch"), i + 1 < args.count, let count = Int(args[i + 1]) {
            let reader = PowerReader()
            let limit = max(1, min(count, 1000))
            for index in 0..<limit {
                autoreleasepool { printSnapshot(reader.read(includeDetails: args.contains("--with-details"))) }
                if index + 1 < limit { Thread.sleep(forTimeInterval: 2) }
            }
            return
        }
        if args.contains("--inspect") {
            let nonce = UUID().uuidString
            DistributedNotificationCenter.default().postNotificationName(diagnosticName, object: nonce, userInfo: nil, deliverImmediately: true)
            let url = diagnosticDirectory().appendingPathComponent("diagnostics.json")
            for _ in 0..<50 {
                if let data = try? Data(contentsOf: url),
                   let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   object["nonce"] as? String == nonce {
                    print(String(data: data, encoding: .utf8) ?? "{}"); return
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
            fputs("未检测到运行中的 Fluxa 应用。\n", stderr); exit(1)
        }
        if let i = args.firstIndex(of: "--language"), i + 1 < args.count {
            DistributedNotificationCenter.default().postNotificationName(languageName, object: args[i + 1], userInfo: nil, deliverImmediately: true)
            CFRunLoopRunInMode(.defaultMode, 0.2, false)
            return
        }
        for (flag, name) in [("--devices", devicesName), ("--show", showName), ("--hide", hideName), ("--details", detailsName), ("--click", clickName), ("--settings", settingsName)] {
            if args.contains(flag) {
                DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: nil, deliverImmediately: true)
                CFRunLoopRunInMode(.defaultMode, 0.2, false)
                return
            }
        }
        let application = NSApplication.shared
        let delegate = WattsAppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
    private static func printSnapshot(_ snapshot: PowerSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(snapshot), let text = String(data: data, encoding: .utf8) { print(text) }
    }
}
#endif
