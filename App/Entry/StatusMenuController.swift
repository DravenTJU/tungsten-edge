import AppKit

private enum StatusMenuLayout {
    static let textInsetX: CGFloat = 28
    static let trailingInsetX: CGFloat = 14
}

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let store: AppSettingsStore
    private let launchAtLoginService: LaunchAtLoginServicing
    private let nativeDockPreferencesService: NativeDockPreferencesServicing
    private let onShowDebugConsole: () -> Void
    private let onExportDebugSnapshot: () -> Void
    private let onQuit: () -> Void

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let launchAtLoginItem = NSMenuItem(title: "登录时启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let openLoginItemsSettingsItem = NSMenuItem(title: "打开登录项设置…", action: #selector(openLoginItemsSettings), keyEquivalent: "")
    private let nativeDockSliderView: PreferenceSliderMenuItemView
    private let edgeSliderView: PreferenceSliderMenuItemView

    init(store: AppSettingsStore,
         launchAtLoginService: LaunchAtLoginServicing,
         nativeDockPreferencesService: NativeDockPreferencesServicing,
         onShowDebugConsole: @escaping () -> Void,
         onExportDebugSnapshot: @escaping () -> Void,
         onQuit: @escaping () -> Void) {
        self.store = store
        self.launchAtLoginService = launchAtLoginService
        self.nativeDockPreferencesService = nativeDockPreferencesService
        self.onShowDebugConsole = onShowDebugConsole
        self.onExportDebugSnapshot = onExportDebugSnapshot
        self.onQuit = onQuit
        nativeDockSliderView = PreferenceSliderMenuItemView(title: "系统 Dock", subtitle: "⌘⌥D 显示/隐藏")
        edgeSliderView = PreferenceSliderMenuItemView(title: "Tungsten Edge 钨极")
        super.init()
        configureStatusItem()
        configureMenu()
        refreshCheckmarks()
        nativeDockSliderView.sync(delay: store.nativeDockAutoHideDelay)
        edgeSliderView.sync(delay: store.edgeAutoHideDelay)
    }

    private func configureStatusItem() {
        let image = NSImage(named: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "rectangle.3.offgrid.fill", accessibilityDescription: "Tungsten Edge")
        image?.isTemplate = true
        image?.accessibilityDescription = "Tungsten Edge"
        statusItem.button?.image = image
        statusItem.menu = menu
    }

    private func configureMenu() {
        menu.delegate = self

        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)
        openLoginItemsSettingsItem.target = self
        menu.addItem(openLoginItemsSettingsItem)
        menu.addItem(.separator())

        nativeDockSliderView.onDelayChange = { [weak store] delay in
            store?.setNativeDockAutoHideDelay(delay)
        }
        nativeDockSliderView.onDelayCommit = { [weak self] _ in
            self?.scheduleNativeDockPreferencesConfirmation()
        }
        let nativeDockItem = NSMenuItem()
        nativeDockItem.view = nativeDockSliderView
        menu.addItem(nativeDockItem)

        edgeSliderView.onDelayChange = { [weak store] delay in
            store?.setEdgeAutoHideDelay(delay)
        }
        let edgeItem = NSMenuItem()
        edgeItem.view = edgeSliderView
        menu.addItem(edgeItem)

        #if DEBUG
        menu.addItem(.separator())
        let debugMenu = NSMenu()
        let showDebug = NSMenuItem(title: "显示调试台", action: #selector(showDebugConsole), keyEquivalent: "")
        showDebug.target = self
        debugMenu.addItem(showDebug)
        let exportSnapshot = NSMenuItem(title: "导出任务条快照", action: #selector(exportDebugSnapshot), keyEquivalent: "")
        exportSnapshot.target = self
        debugMenu.addItem(exportSnapshot)
        let debugItem = NSMenuItem(title: "调试", action: nil, keyEquivalent: "")
        debugItem.submenu = debugMenu
        menu.addItem(debugItem)
        menu.addItem(.separator())
        #endif

        let quitItem = NSMenuItem(title: "退出 Tungsten Edge 钨极", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshCheckmarks()
        nativeDockSliderView.sync(delay: store.nativeDockAutoHideDelay)
        edgeSliderView.sync(delay: store.edgeAutoHideDelay)
    }

    private func refreshCheckmarks() {
        refreshLaunchAtLoginState()
    }

    private func refreshLaunchAtLoginState() {
        let presentation = LaunchAtLoginMenuPresentation(state: launchAtLoginService.state)
        launchAtLoginItem.title = presentation.title
        launchAtLoginItem.state = presentation.isChecked ? .on : .off
        launchAtLoginItem.isEnabled = presentation.isEnabled
        openLoginItemsSettingsItem.isHidden = !presentation.showsSettingsItem
    }

    @objc private func toggleLaunchAtLogin() {
        guard let enable = LaunchAtLoginMenuModel.requestedEnabledValue(afterSelecting: launchAtLoginService.state) else { return }
        do {
            try launchAtLoginService.setEnabled(enable)
            store.setLaunchAtLogin(enable)
        } catch {
            presentError(title: "登录时启动设置失败", message: error.localizedDescription)
        }
        refreshCheckmarks()
    }

    @objc private func openLoginItemsSettings() {
        launchAtLoginService.openSystemSettings()
    }

    private func scheduleNativeDockPreferencesConfirmation() {
        menu.cancelTrackingWithoutAnimation()
        DispatchQueue.main.async { [weak self] in
            self?.confirmAndApplyNativeDockPreferences()
        }
    }

    private func confirmAndApplyNativeDockPreferences() {
        guard nativeDockPreferencesService.isAvailable else {
            presentError(title: "系统 Dock 设置失败", message: NativeDockPreferencesError.sandboxed.localizedDescription)
            return
        }

        do {
            try nativeDockPreferencesService.apply(delay: store.nativeDockAutoHideDelay)
        } catch {
            presentError(title: "系统 Dock 设置失败", message: error.localizedDescription)
        }
    }

    private func presentError(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    @objc private func showDebugConsole() { onShowDebugConsole() }
    @objc private func exportDebugSnapshot() { onExportDebugSnapshot() }
    @objc private func quit() { onQuit() }
}

@MainActor
final class PreferenceSliderMenuItemView: NSView {
    var onDelayChange: ((Double) -> Void)?
    var onDelayCommit: ((Double) -> Void)?

    private let title: String
    private let subtitle: String?
    private let titleVerticalOffset: CGFloat
    private var delay = 0.0
    private var commitTracker = PreferenceSliderCommitTracker()
    private var displayString = "0.0s"
    private let leftEndpointDot = EndpointDotView()
    private let rightEndpointDot = EndpointDotView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let delayLabel = NSTextField(labelWithString: "")
    private let slider = MenuTrackingSlider()

    init(title: String, subtitle: String? = nil, titleVerticalOffset: CGFloat = 0) {
        self.title = title
        self.subtitle = subtitle
        self.titleVerticalOffset = titleVerticalOffset
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 82))
        autoresizingMask = [.width]
        configureSubviews()
        updateDisplay()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func accessibilityValue() -> Any? {
        displayString
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let width = window?.frame.width, width > frame.width {
            frame.size.width = width
        }
    }

    func sync(delay: Double) {
        let index = AppSettingsStore.sliderIndexFromDelay(delay)
        self.delay = AppSettingsStore.delayFromSliderIndex(index)
        slider.integerValue = index
        updateDisplay()
    }

    private func configureSubviews() {
        wantsLayer = true

        leftEndpointDot.setAccessibilityElement(false)
        addSubview(leftEndpointDot)

        rightEndpointDot.setAccessibilityElement(false)
        addSubview(rightEndpointDot)

        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 10)
        subtitleLabel.textColor = .tertiaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.isHidden = subtitle == nil
        addSubview(subtitleLabel)

        delayLabel.font = .systemFont(ofSize: 11)
        delayLabel.textColor = .secondaryLabelColor
        delayLabel.alignment = .center
        addSubview(delayLabel)

        slider.minValue = 0
        slider.maxValue = Double(AppSettingsStore.sliderIndexMax)
        slider.integerValue = AppSettingsStore.sliderIndexFromDelay(delay)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.onTrackingStarted = { [weak self] in
            guard let self else { return }
            self.commitTracker.begin(currentDelay: self.delay)
        }
        slider.onTrackingEnded = { [weak self] in
            self?.commitDelayIfChanged()
        }
        addSubview(slider)

        setAccessibilityRole(.group)
    }

    override func layout() {
        super.layout()
        let dotSize: CGFloat = 8
        let hasSubtitle = subtitle != nil
        let contentX = StatusMenuLayout.textInsetX
        let contentWidth = bounds.width - contentX - StatusMenuLayout.trailingInsetX
        let titleY = bounds.height - 30 + titleVerticalOffset
        let labelY = bounds.height - 54
        let sliderY: CGFloat = 10
        if hasSubtitle {
            let titleWidth = min(contentWidth, max(ceil(titleLabel.intrinsicContentSize.width), 76))
            let subtitleGap: CGFloat = 2
            let subtitleX = contentX + titleWidth + subtitleGap
            titleLabel.frame = NSRect(x: contentX, y: titleY, width: titleWidth, height: 20)
            subtitleLabel.frame = NSRect(x: subtitleX, y: titleY, width: max(0, contentWidth - titleWidth - subtitleGap), height: 18)
        } else {
            titleLabel.frame = NSRect(x: contentX, y: titleY, width: contentWidth, height: 20)
            subtitleLabel.frame = NSRect(x: contentX, y: titleY, width: 0, height: 18)
        }

        let sliderSideInset: CGFloat = 34
        let sliderX = contentX + sliderSideInset
        let sliderWidth = max(0, contentWidth - sliderSideInset * 2)
        delayLabel.frame = NSRect(x: sliderX, y: labelY, width: sliderWidth, height: 14)

        let dotY = sliderY + 6
        leftEndpointDot.frame = NSRect(x: contentX + 14, y: dotY, width: dotSize, height: dotSize)
        slider.frame = NSRect(x: sliderX, y: sliderY, width: sliderWidth, height: 20)
        rightEndpointDot.frame = NSRect(x: slider.frame.maxX + 12, y: dotY, width: dotSize, height: dotSize)
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        let index = min(max(Int(sender.doubleValue.rounded()), 0), AppSettingsStore.sliderIndexMax)
        sender.integerValue = index
        delay = AppSettingsStore.delayFromSliderIndex(index)
        updateDisplay()
        onDelayChange?(delay)
    }

    private func commitDelayIfChanged() {
        guard let committedDelay = commitTracker.commitIfChanged(currentDelay: delay) else { return }
        onDelayCommit?(committedDelay)
    }

    private func updateDisplay() {
        let index = slider.integerValue
        displayString = displayString(for: index)
        delay = AppSettingsStore.delayFromSliderIndex(index)
        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle ?? ""
        delayLabel.stringValue = displayString
        leftEndpointDot.isOn = index == 0
        rightEndpointDot.isOn = index == AppSettingsStore.sliderIndexMax
        var accessibilityParts = [title]
        if let subtitle {
            accessibilityParts.append(subtitle)
        }
        accessibilityParts.append(displayString)
        setAccessibilityLabel(accessibilityParts.joined(separator: "，"))
        setAccessibilityValue(displayString)
        slider.displayString = displayString
    }

    private func displayString(for index: Int) -> String {
        switch index {
        case 0:
            return "常驻"
        case AppSettingsStore.sliderIndexMax:
            return "不唤醒"
        default:
            return String(format: "%.1fs", AppSettingsStore.delayFromSliderIndex(index))
        }
    }
}

final class EndpointDotView: NSView {
    var isOn = false {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds.insetBy(dx: 0.75, dy: 0.75)
        let path = NSBezierPath(ovalIn: rect)
        (isOn ? NSColor.controlAccentColor : .clear).setFill()
        path.fill()
        (isOn ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor).setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }
}

final class MenuTrackingSlider: NSSlider {
    var displayString = "0.0s"
    var onTrackingStarted: (() -> Void)?
    var onTrackingEnded: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onTrackingStarted?()
        super.mouseDown(with: event)
        onTrackingEnded?()
    }

    override func accessibilityValue() -> Any? {
        displayString
    }
}

struct PreferenceSliderCommitTracker {
    private var startDelay: Double?

    mutating func begin(currentDelay: Double) {
        startDelay = currentDelay
    }

    mutating func commitIfChanged(currentDelay: Double) -> Double? {
        defer { startDelay = nil }
        guard let startDelay, startDelay != currentDelay else { return nil }
        return currentDelay
    }
}
