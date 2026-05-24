import AppKit
import Carbon
import Combine

private final class GlobalHotKeyManager {
    private let hotKeyID = EventHotKeyID(signature: OSType(0x544C4741), id: 1)
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let action: @MainActor () -> Void

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    func register() {
        unregister()

        let eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let handlerResult = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let userData else { return noErr }

                let hotKeyManager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                hotKeyManager.handleHotKey(eventRef)
                return noErr
            },
            1,
            [eventSpec],
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard handlerResult == noErr else {
            return
        }

        let modifiers = UInt32(cmdKey | optionKey)
        let keyCode = UInt32(kVK_ANSI_1)
        let registerResult = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerResult != noErr {
            unregister()
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func handleHotKey(_ eventRef: EventRef?) {
        DispatchQueue.main.async { [action] in
            action()
        }
    }
}

@MainActor
final class AppRuntime: ObservableObject {
    let container = AppContainer()
    private var windowController: MainWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var globalHotKeyManager: GlobalHotKeyManager?
    private var localKeyboardMonitor: Any?

    var mainViewModel: MainViewModel {
        container.mainViewModel
    }

    func configureWindowIfNeeded() {
        guard windowController == nil else {
            return
        }

        let rootView = MainContentView(viewModel: container.mainViewModel)
        let windowController = MainWindowController(
            rootView: rootView,
            initialFrame: container.mainViewModel.windowFrame
        )
        windowController.onPersistWindowFrame = { [weak mainViewModel = container.mainViewModel] frame in
            mainViewModel?.updateWindowFrame(frame)
        }
        self.windowController = windowController

        container.mainViewModel.showWindow = { [weak windowController] in
            windowController?.showWindowAndActivate()
        }
    }

    func start() {
        configureWindowIfNeeded()
        configureHiddenHotKeysIfNeeded()
        configureKeyboardMonitorIfNeeded()
        Task {
            await container.mainViewModel.start()
        }
    }

    func shutdown() {
        windowController?.saveWindowFrame()
        globalHotKeyManager?.unregister()
        globalHotKeyManager = nil
        if let localKeyboardMonitor {
            NSEvent.removeMonitor(localKeyboardMonitor)
            self.localKeyboardMonitor = nil
        }
        Task {
            await container.mainViewModel.shutdown()
        }
    }

    func openHome() {
        container.mainViewModel.openHome()
    }

    func openSettings() {
        configureSettingsWindowIfNeeded()
        settingsWindowController?.showWindowAndActivate()
    }

    func openAddChannel() {
        configureWindowIfNeeded()
        container.mainViewModel.isSidebarPresented = true
        container.mainViewModel.showWindow?()
    }

    func refreshSelectedChannel() async {
        await container.mainViewModel.refreshSelectedChannel()
    }

    func closeOpenFeedWindow() {
        windowController?.window?.performClose(nil)
    }

    func quit() {
        NSApp.terminate(nil)
    }

    private func configureHiddenHotKeysIfNeeded() {
        guard globalHotKeyManager == nil else {
            return
        }

        let manager = GlobalHotKeyManager { [weak self] in
            self?.openHome()
        }
        manager.register()
        globalHotKeyManager = manager
    }

    private func configureKeyboardMonitorIfNeeded() {
        guard localKeyboardMonitor == nil else {
            return
        }

        localKeyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }

            guard event.keyCode == 53 else {
                return event
            }

            self.windowController?.window?.performClose(nil)
            return nil
        }
    }

    private func configureSettingsWindowIfNeeded() {
        guard settingsWindowController == nil else {
            return
        }

        settingsWindowController = SettingsWindowController(viewModel: container.mainViewModel)
    }
}

@MainActor
final class MenuBarStatusItemController: NSObject {
    private let runtime: AppRuntime
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var cancellables = Set<AnyCancellable>()

    init(runtime: AppRuntime) {
        self.runtime = runtime
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
        configureMenu()
        observeUnreadChanges()
        refreshAppearance()
    }

    func invalidate() {
        NSStatusBar.system.removeStatusItem(statusItem)
        cancellables.removeAll()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.title = ""
        button.toolTip = L10n.tr("app.title")
        refreshAppearance()
    }

    private func configureMenu() {
        menu.autoenablesItems = false
        menu.addItem(NSMenuItem(
            title: L10n.tr("menu.addChannel"),
            action: #selector(addChannelFromMenu),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: L10n.tr("feed.refresh"),
            action: #selector(refreshFromMenu),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: L10n.tr("menu.settings"),
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ","
        ))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: L10n.tr("menu.closeFeed"),
            action: #selector(closeFeedFromMenu),
            keyEquivalent: "\u{1b}"
        ))
        menu.addItem(NSMenuItem(
            title: L10n.tr("menu.quit"),
            action: #selector(quitFromMenu),
            keyEquivalent: "q"
        ))
        menu.items.forEach { $0.target = self }
    }

    private func observeUnreadChanges() {
        runtime.mainViewModel.feedViewModel.objectWillChange
            .sink { [weak self] in
                Task { @MainActor in
                    self?.refreshAppearance()
                }
            }
            .store(in: &cancellables)

        runtime.mainViewModel.$settings
            .map(\.menuBarIconStyle)
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshAppearance()
                }
            }
            .store(in: &cancellables)
    }

    private func refreshAppearance() {
        guard let button = statusItem.button else {
            return
        }

        let newerCount = runtime.mainViewModel.feedViewModel.newerThanViewedCount
        if newerCount > 0 {
            button.title = newerCount > 99 ? "99+" : "\(newerCount)"
        } else {
            button.title = ""
        }

        button.image = menuBarImage()
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        let eventType = NSApp.currentEvent?.type
        switch eventType {
        case .rightMouseDown, .rightMouseUp:
            showMenu()
        default:
            runtime.openHome()
        }
    }

    @objc private func addChannelFromMenu() {
        runtime.openAddChannel()
    }

    @objc private func refreshFromMenu() {
        Task {
            await runtime.refreshSelectedChannel()
        }
    }

    @objc private func openSettingsFromMenu() {
        runtime.openSettings()
    }

    @objc private func closeFeedFromMenu() {
        if runtime.mainViewModel.closeSidebar() {
            return
        }
        runtime.closeOpenFeedWindow()
    }

    @objc private func quitFromMenu() {
        runtime.quit()
    }

    private func showMenu() {
        guard let button = statusItem.button else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        let location = NSPoint(x: 0, y: button.bounds.height)
        menu.popUp(positioning: nil, at: location, in: button)
    }

    private func menuBarImage() -> NSImage {
        let font = NSFont(name: "AvenirNextCondensed-DemiBold", size: 15) ?? NSFont.systemFont(ofSize: 15, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let label = NSAttributedString(string: "News", attributes: attributes)
        let textSize = label.size()
        let imageSize = NSSize(width: ceil(textSize.width), height: 18)
        let image = NSImage(size: imageSize)

        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: imageSize).fill()
        let drawRect = NSRect(
            x: 0,
            y: floor((imageSize.height - textSize.height) / 2) + 1,
            width: imageSize.width,
            height: textSize.height
        )
        label.draw(in: drawRect)
        image.unlockFocus()

        image.isTemplate = true
        return image
    }
}

@MainActor
final class TeleFeedAppDelegate: NSObject, NSApplicationDelegate {
    let runtime = AppRuntime()
    private var menuBarController: MenuBarStatusItemController?
    private let mainMenu = NSMenu()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()
        applyDockIconVisibility(runtime.mainViewModel.settings.showDockIcon)
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }
        runtime.start()
        updateMenuBarVisibility(runtime.mainViewModel.settings.showMenuBarIcon)
        observePresentationSettings()
        runtime.openHome()
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime.shutdown()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag == false {
            runtime.openHome()
        }
        return true
    }

    private func observePresentationSettings() {
        runtime.mainViewModel.$settings
            .map(\.showDockIcon)
            .removeDuplicates()
            .sink { [weak self] showDockIcon in
                Task { @MainActor in
                    self?.applyDockIconVisibility(showDockIcon)
                }
            }
            .store(in: &cancellables)

        runtime.mainViewModel.$settings
            .map(\.showMenuBarIcon)
            .removeDuplicates()
            .sink { [weak self] showMenuBarIcon in
                Task { @MainActor in
                    self?.updateMenuBarVisibility(showMenuBarIcon)
                }
            }
            .store(in: &cancellables)
    }

    private func applyDockIconVisibility(_ isVisible: Bool) {
        NSApp.setActivationPolicy(isVisible ? .regular : .accessory)
    }

    private func updateMenuBarVisibility(_ isVisible: Bool) {
        if isVisible {
            if menuBarController == nil {
                menuBarController = MenuBarStatusItemController(runtime: runtime)
            }
        } else {
            menuBarController?.invalidate()
            menuBarController = nil
        }
    }

    private func configureMainMenu() {
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()

        let addChannelItem = NSMenuItem(
            title: L10n.tr("menu.addChannel"),
            action: #selector(addChannelFromMenu),
            keyEquivalent: ""
        )
        addChannelItem.target = self
        appMenu.addItem(addChannelItem)

        let refreshItem = NSMenuItem(
            title: L10n.tr("feed.refresh"),
            action: #selector(refreshFromMenu),
            keyEquivalent: ""
        )
        refreshItem.target = self
        appMenu.addItem(refreshItem)

        let settingsItem = NSMenuItem(
            title: L10n.tr("menu.settings"),
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ","
        )
        settingsItem.target = self
        appMenu.addItem(settingsItem)

        appMenu.addItem(.separator())

        let closeFeedItem = NSMenuItem(
            title: L10n.tr("menu.closeFeed"),
            action: #selector(closeFeedFromMenu),
            keyEquivalent: "\u{1b}"
        )
        closeFeedItem.target = self
        appMenu.addItem(closeFeedItem)
        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: L10n.tr("menu.quit"),
            action: #selector(quitFromMenu),
            keyEquivalent: "q"
        )
        quitItem.target = self
        appMenu.addItem(quitItem)

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: L10n.tr("menu.edit"))

        let cutItem = NSMenuItem(title: L10n.tr("menu.cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(cutItem)

        let copyItem = NSMenuItem(title: L10n.tr("menu.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(copyItem)

        let pasteItem = NSMenuItem(title: L10n.tr("menu.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(pasteItem)

        editMenu.addItem(.separator())

        let selectAllItem = NSMenuItem(title: L10n.tr("menu.select_all"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(selectAllItem)

        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        NSApp.mainMenu = mainMenu
    }

    @objc private func addChannelFromMenu() {
        runtime.openAddChannel()
    }

    @objc private func refreshFromMenu() {
        Task {
            await runtime.refreshSelectedChannel()
        }
    }

    @objc private func openSettingsFromMenu() {
        runtime.openSettings()
    }

    @objc private func closeFeedFromMenu() {
        if runtime.mainViewModel.closeSidebar() {
            return
        }
        runtime.closeOpenFeedWindow()
    }

    @objc private func quitFromMenu() {
        runtime.quit()
    }
}
