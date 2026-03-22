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
        let windowController = MainWindowController(rootView: rootView)
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
        container.mainViewModel.openSettings()
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
        updateStatusItem()
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
        button.image = bundledMenuBarImage()
        button.title = ""
        button.toolTip = L10n.tr("app.title")
    }

    private func configureMenu() {
        menu.autoenablesItems = false
        menu.addItem(NSMenuItem(
            title: L10n.tr("menu.open"),
            action: #selector(openFeedFromMenu),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: L10n.tr("menu.settings"),
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ","
        ))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: L10n.tr("menu.quit"),
            action: #selector(quitFromMenu),
            keyEquivalent: "q"
        ))
        menu.items.forEach { $0.target = self }
    }

    private func observeUnreadChanges() {
        runtime.mainViewModel.channelsViewModel.objectWillChange
            .sink { [weak self] in
                Task { @MainActor in
                    self?.updateStatusItem()
                }
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        let unreadCount = runtime.mainViewModel.channelsViewModel.channels.reduce(0) { $0 + $1.unreadCount }
        if unreadCount > 0 {
            button.title = unreadCount > 99 ? "99+" : "\(unreadCount)"
        } else {
            button.title = ""
        }
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

    @objc private func openFeedFromMenu() {
        runtime.openHome()
    }

    @objc private func openSettingsFromMenu() {
        runtime.openSettings()
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

    private func bundledMenuBarImage() -> NSImage {
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png", subdirectory: "Assets/Icons"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = false
            return image
        }

        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = false
            return image
        }

        let fallback = NSImage(systemSymbolName: "eye.circle", accessibilityDescription: "Telega") ?? NSImage()
        fallback.isTemplate = true
        return fallback
    }
}

@MainActor
final class TelegaAppDelegate: NSObject, NSApplicationDelegate {
    let runtime = AppRuntime()
    private var menuBarController: MenuBarStatusItemController?
    private let mainMenu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMainMenu()
        runtime.start()
        menuBarController = MenuBarStatusItemController(runtime: runtime)
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime.shutdown()
    }

    @objc private func closeOpenFeedFromMenu() {
        runtime.closeOpenFeedWindow()
    }

    private func configureMainMenu() {
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()

        let closeOpenFeedItem = NSMenuItem(
            title: L10n.tr("sidebar.close"),
            action: #selector(closeOpenFeedFromMenu),
            keyEquivalent: "\u{1b}"
        )
        closeOpenFeedItem.target = self
        appMenu.addItem(closeOpenFeedItem)
        appMenu.addItem(.separator())
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
    }
}
