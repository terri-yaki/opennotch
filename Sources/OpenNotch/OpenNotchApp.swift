import AppKit
import ServiceManagement

@main
struct OpenNotchMain {
    @MainActor
    static func main() {
        LegacyDefaults.migrate() // before the stores read UserDefaults
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // no Dock icon
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let shelf = ShelfStore()
    private let clipboard = ClipboardStore()
    private var notch: NotchController?
    private var statusItem: NSStatusItem?

    private var pinItem: NSMenuItem?
    private var pauseItem: NSMenuItem?
    private var petItem: NSMenuItem?
    private var loginItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = NotchController(shelf: shelf, clipboard: clipboard)
        controller.start()
        notch = controller
        clipboard.start()
        MusicStore.shared.start()
        _ = BatteryMonitor.shared
        setUpStatusItem()
    }

    // MARK: Menu bar item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
               let image = NSImage(contentsOf: url) {
                image.isTemplate = false
                image.size = NSSize(width: 18, height: 18)
                button.image = image
            } else {
                let image = NSImage(systemSymbolName: "tray.and.arrow.down.fill",
                                    accessibilityDescription: "OpenNotch")
                image?.isTemplate = true
                button.image = image
            }
        }

        let menu = NSMenu()
        menu.delegate = self

        let pin = NSMenuItem(title: "Pin Shelf Open", action: #selector(togglePin), keyEquivalent: "")
        let pause = NSMenuItem(title: "Pause Clipboard History", action: #selector(togglePause), keyEquivalent: "")
        let pet = NSMenuItem(title: "Show Liquid Pet", action: #selector(togglePet), keyEquivalent: "")
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        for i in [pin, pause, pet, login] { i.target = self }

        menu.addItem(pin)
        menu.addItem(pause)
        menu.addItem(pet)
        menu.addItem(login)
        menu.addItem(.separator())

        let clearShelf = NSMenuItem(title: "Clear Shelf", action: #selector(clearShelf), keyEquivalent: "")
        let clearClips = NSMenuItem(title: "Clear Clipboard History", action: #selector(clearClipboard), keyEquivalent: "")
        let clearActivity = NSMenuItem(title: "Reset Activity Heatmap", action: #selector(clearActivity), keyEquivalent: "")
        for i in [clearShelf, clearClips, clearActivity] { i.target = self; menu.addItem(i) }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit OpenNotch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
        pinItem = pin
        pauseItem = pause
        petItem = pet
        loginItem = login
    }

    func menuWillOpen(_ menu: NSMenu) {
        pinItem?.state = (notch?.state.pinned ?? false) ? .on : .off
        pauseItem?.state = clipboard.paused ? .on : .off
        petItem?.state = (notch?.state.showPet ?? false) ? .on : .off
        loginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    // MARK: Actions

    @objc private func togglePin() { notch?.setPinned(!(notch?.state.pinned ?? false)) }
    @objc private func togglePause() { clipboard.paused.toggle() }
    @objc private func togglePet() { notch?.setShowPet(!(notch?.state.showPet ?? true)) }
    @objc private func clearShelf() { shelf.clear() }
    @objc private func clearClipboard() { clipboard.clearUnpinned() }
    @objc private func clearActivity() { ActivityStore.shared.clear() }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSSound.beep()
        }
    }
}
