// Headroom Lab — A/B test (untouched original BrightXDR ⇄ Headroom) and lab for the white-screen fix.
// GPL-3: contains code from starkdmi/BrightXDR (see Compare/LICENSE).
// The notification names keep the "de.fichl.BrightXDR.Compare" prefix the flash-test app was built with.
// ORIGINAL = the unchanged MetalView.swift + window setup of starkdmi/BrightXDR (reference).
// Any OverlayVariant id ("placement.level.content.blend") = the same overlay value (2×) in that setup.
// WINNER entries (if any) are listed in the menu and used by the toggle.
//
// ⌃⌥⌘B  toggle Original ⇄ selected variant      ⌃⌥⌘N  Off      ⌃⌥⌘M  Mission Control
// Scripts: distributed notification "de.fichl.BrightXDR.Compare.set" (object = "ORIGINAL" | "OFF" | variant id),
//          replies "de.fichl.BrightXDR.Compare.ready" (object = same string) once applied.
import Carbon.HIToolbox
import Cocoa

/// Variants offered in the menu: (title, variant id, measured note). Filled in after the search.
let winners: [(title: String, id: String, note: String)] = [
    ("Headroom — Maximum (1.75×)", "GAMMA:p1:1.75", "gamma table · no white measured"),
    ("Headroom — High (1.56×, default)", "GAMMA:p1:1.5625", "gamma table · no white measured"),
    ("Headroom — Medium (1.38×)", "GAMMA:p1:1.375", "gamma table · no white measured"),
]

/// The untouched upstream app (build_original.sh), next to this app in build/.
let upstreamURL = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("BrightXDR Original.app")
let upstreamID = "com.starkdmi.BrightXDR"

final class CompareDelegate: NSObject, NSApplicationDelegate {
    private let overlay = OverlayController(variant: .original)
    private let gamma = GammaBooster()
    private var statusItem: NSStatusItem!
    private var modeItems: [String: NSMenuItem] = [:]
    private var originalWindow: NSWindow?
    private var mode = "OFF"
    private var selected = winners[1].id // High, the Headroom default
    private var hotKeys: [EventHotKeyRef?] = []
    private var relaunchMain = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "de.fichl.Headroom") {
            app.terminate(); relaunchMain = true
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        let header = NSMenuItem(title: "Headroom Lab — Original vs. Headroom", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        addMode(menu, "Original BrightXDR (untouched upstream app)", "UPSTREAM", note: nil)
        for w in winners { addMode(menu, w.title, w.id, note: w.note) }
        addMode(menu, "Off (no boost)", "OFF", note: nil)
        menu.addItem(.separator())
        let mc = NSMenuItem(title: "Open Mission Control (test)", action: #selector(openMissionControl), keyEquivalent: "")
        mc.target = self
        menu.addItem(mc)
        menu.addItem(.separator())
        for tip in ["⌃⌥⌘B  toggle Original ⇄ Current (level picked above)", "⌃⌥⌘N  Off", "⌃⌥⌘M  Mission Control"] {
            let item = NSMenuItem(title: tip, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Headroom Lab", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        DispatchQueue.main.asyncAfter(deadline: .now() + (relaunchMain ? 1.0 : 0)) { self.set(self.selected) }
        registerHotKeys()

        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("de.fichl.BrightXDR.Compare.toggle"), object: nil, queue: .main) { [weak self] _ in
            self?.toggle()
        }
        dnc.addObserver(forName: .init("de.fichl.BrightXDR.Compare.set"), object: nil, queue: .main) { [weak self] n in
            if let s = n.object as? String { self?.set(s) }
        }
    }

    private func addMode(_ menu: NSMenu, _ title: String, _ id: String, note: String?) {
        let item = NSMenuItem(title: title, action: #selector(pick(_:)), keyEquivalent: "")
        item.representedObject = id
        item.target = self
        menu.addItem(item)
        modeItems[id] = item
        if let note {
            let n = NSMenuItem(title: "    " + note, action: nil, keyEquivalent: "")
            n.isEnabled = false
            menu.addItem(n)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlay.stop()
        gamma.stop()
        quitUpstream()
        if relaunchMain, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "de.fichl.Headroom") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    @objc private func pick(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { set(id) }
    }

    @objc func openMissionControl() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
    }

    func toggle() { set(mode == "UPSTREAM" ? selected : "UPSTREAM") }

    func set(_ m: String) {
        let variant = OverlayVariant(m)
        let gspec = GammaSpec(m)
        guard m == "ORIGINAL" || m == "UPSTREAM" || m == "OFF" || variant != nil || gspec != nil else { return }
        mode = m
        if variant != nil || gspec != nil { selected = m }
        if let gspec { gamma.model = gspec.model; gamma.boost = gspec.k } else { gamma.boost = 1.0 }
        if m == "ORIGINAL" { showOriginal() } else { originalWindow?.orderOut(nil) }
        if m == "UPSTREAM" { launchUpstream() } else { quitUpstream() }
        if let variant {
            overlay.boost = 1.0 // tear down, then rebuild in the new setup
            overlay.variant = variant
            overlay.boost = 2.0
        } else {
            overlay.boost = 1.0
        }
        for (key, item) in modeItems { item.state = key == m ? .on : .off }
        let label = m == "UPSTREAM" ? "ORIGINAL" : m == "ORIGINAL" || m == "OFF" ? m
            : (winners.contains { $0.id == m } ? "CURRENT" : "VARIANT")
        // Compact (icon + one letter), so the notch doesn't hide it: O = Original, C = Current, – = Off.
        let short = label == "ORIGINAL" ? "O" : label == "CURRENT" ? "C" : label == "OFF" ? "–" : "V"
        statusItem.button?.image = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "XDR compare")
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.title = short
        statusItem.button?.toolTip = "XDR: \(label)"
        announceReady(m)
    }

    /// Tells the flash-test harness the mode is applied.
    func announceReady(_ name: String) {
        DistributedNotificationCenter.default().postNotificationName(
            .init("de.fichl.BrightXDR.Compare.ready"), object: name, userInfo: nil, deliverImmediately: true)
    }

    private func launchUpstream() {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.openApplication(at: upstreamURL, configuration: config)
    }

    private func quitUpstream() {
        NSRunningApplication.runningApplications(withBundleIdentifier: upstreamID).forEach { $0.terminate() }
    }

    /// Window setup copied 1:1 from the original AppDelegate.swift.
    private func showOriginal() {
        if let w = originalWindow { w.orderFrontRegardless(); return }
        guard let mainScreen = NSScreen.main else { return }
        let rect = NSRect(x: 0, y: 0, width: mainScreen.frame.width, height: mainScreen.frame.height)
        let window = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level.mainMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        guard let view = window.contentView else { return }
        let metalView = MetalView(frame: view.bounds, frameRate: 3, contrast: 1.0, brightness: 1.0)
        metalView.autoresizingMask = [.width, .height]
        view.addSubview(metalView)
        window.orderFrontRegardless()
        originalWindow = window
    }

    // MARK: global hotkeys (Carbon — no Accessibility permission needed)

    private func registerHotKeys() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let me = Unmanaged<CompareDelegate>.fromOpaque(userData!).takeUnretainedValue()
            DispatchQueue.main.async {
                switch id.id {
                case 1: me.toggle()
                case 2: me.set("OFF")
                default: me.openMissionControl()
                }
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)

        let mods = UInt32(cmdKey | optionKey | controlKey)
        for (n, key) in [(UInt32(1), kVK_ANSI_B), (UInt32(2), kVK_ANSI_N), (UInt32(3), kVK_ANSI_M)] {
            var ref: EventHotKeyRef?
            RegisterEventHotKey(UInt32(key), mods, EventHotKeyID(signature: OSType(0x4258_4452), id: n),
                                GetApplicationEventTarget(), 0, &ref)
            hotKeys.append(ref)
        }
    }
}

let app = NSApplication.shared
let delegate = CompareDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
