import Cocoa
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let controller = GammaBooster()
    private var statusItem: NSStatusItem!
    private var levelItems: [NSMenuItem] = []
    private var loginItem: NSMenuItem!

    private let levels: [(title: String, boost: Double)] = [
        ("Off", 1.0),
        // Gamma-table factors, evenly spaced up to Maximum 1.75× (the former High).
        ("Low", 1.1875),
        ("Medium", 1.375),
        ("High", 1.5625),
        ("Maximum", 1.75),
    ]
    private let defaultsKey = "boostLevel"
    /// High (1.56×): closest to the chosen sweet spot of 1.5×, slightly brighter than the original BrightXDR (starkdmi).
    private let defaultLevel = 3

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self

        let header = NSMenuItem(title: "Headroom", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if !GammaBooster.hasXDRScreen {
            let warn = NSMenuItem(title: "No XDR display detected", action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
        }
        menu.addItem(.separator())

        for (index, level) in levels.enumerated() {
            let item = NSMenuItem(title: level.title, action: #selector(selectLevel(_:)), keyEquivalent: "\(index)")
            item.tag = index
            item.target = self
            menu.addItem(item)
            levelItems.append(item)
        }

        menu.addItem(.separator())
        loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Headroom", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        // Restore the last level chosen, including Off; High on first launch.
        let saved = UserDefaults.standard.object(forKey: defaultsKey) as? Int ?? defaultLevel
        setLevel(saved >= 0 && saved < levels.count ? saved : defaultLevel)

    }

    /// Clicked in the Dock / Launchpad while running: open the menu.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        DispatchQueue.main.async { self.statusItem.button?.performClick(nil) }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func selectLevel(_ sender: NSMenuItem) { setLevel(sender.tag) }

    private func setLevel(_ index: Int) {
        UserDefaults.standard.set(index, forKey: defaultsKey)
        for item in levelItems { item.state = item.tag == index ? .on : .off }
        controller.boost = levels[index].boost
        let symbol = index == 0 ? "sun.min" : "sun.max.fill"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Headroom")
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change login item"
            alert.informativeText = "\(error.localizedDescription)\n\nTip: move Headroom to the Applications folder first."
            alert.runModal()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
