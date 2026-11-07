import Cocoa
import MetalKit

// Brightness boost via the display's gamma (transfer) table — the technique BrightIntosh,
// Illuminate and xdr-lift use:
//   1. A 1×1 EDR window keeps the panel in EDR mode, so values above SDR white are displayable.
//   2. The display's transfer table is multiplied by the boost factor (values > 1.0 map into the
//      EDR headroom).
// The table is applied after window compositing. Unlike the original full-screen multiply
// overlay, it can't be dropped during Space switches or Mission Control → no white screen,
// and the boost stays on during the animations.
// The table is per process: WindowServer restores it when the app quits or crashes.
//
// Credits (details in NOTICE.md):
//   - xdr-lift (MIT, © 2026 Yihan Zhu): 1×1 EDR trigger window setup (shielding level + 1,
//     collection behaviour, top-left pixel, periodic redraw) and the gamma-table approach.
//   - Illuminate (MIT, © 2026 Jonas Fackelmeyer): scaling the captured table linearly by the gain,
//     falling back to an identity ramp for unusable readings.
//   - BrightIntosh (GPL-3, niklasr22) was read as a reference; no code taken.

/// 1×1 Metal view drawing an EDR value, so macOS keeps the panel's headroom open.
final class EDRTriggerView: MTKView, MTKViewDelegate {
    private let queue: MTLCommandQueue

    init?(value: Double) {
        guard let device = MTLCreateSystemDefaultDevice(), let q = device.makeCommandQueue() else { return nil }
        queue = q
        super.init(frame: NSRect(x: 0, y: 0, width: 1, height: 1), device: device)
        colorPixelFormat = .rgba16Float
        colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        autoResizeDrawable = false
        drawableSize = CGSize(width: 1, height: 1)
        (layer as? CAMetalLayer)?.wantsExtendedDynamicRangeContent = true
        layer?.isOpaque = false
        clearColor = MTLClearColor(red: value, green: value, blue: value, alpha: 1)
        preferredFramesPerSecond = 5 // EDR content that stops updating eventually stops counting
        delegate = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pass = currentRenderPassDescriptor, let drawable = currentDrawable,
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

final class GammaBooster {
    typealias Table = (r: [CGGammaValue], g: [CGGammaValue], b: [CGGammaValue])

    /// How a table entry is boosted. Default ("Fix 1", chosen by eye against the original):
    /// the table is multiplied by the factor directly.
    var model: (_ entry: Float, _ factor: Double) -> Float = { v, k in v * Float(k) } {
        didSet { write() }
    }

    /// Boost factor, 1.0 = off.
    var boost: Double = 1.0 {
        didSet {
            if boost <= 1.0 { stop(); return }
            if triggers.isEmpty { start() } else { write() }
        }
    }

    private var triggers: [NSWindow] = []
    private var bases: [CGDirectDisplayID: Table] = [:]
    private var timer: Timer?
    private var builtSignature = ""
    private var pendingRebuild: DispatchWorkItem?

    init() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(scheduleRebuild), name: NSWorkspace.screensDidWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(scheduleRebuild), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    static var hasXDRScreen: Bool { !xdrScreens.isEmpty }
    private static var xdrScreens: [NSScreen] {
        NSScreen.screens.filter { $0.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.0 }
    }
    private static func displayID(_ s: NSScreen) -> CGDirectDisplayID? {
        (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
    /// Only the screen layout — EDR headroom changes also post didChangeScreenParameters.
    private var layoutSignature: String { NSScreen.screens.map { "\($0.frame)" }.joined(separator: "|") }

    func stop() {
        pendingRebuild?.cancel()
        tearDown()
    }

    private func tearDown() {
        timer?.invalidate(); timer = nil
        triggers.forEach { $0.orderOut(nil) }
        let hadTable = !triggers.isEmpty
        triggers.removeAll()
        bases.removeAll()
        if hadTable { CGDisplayRestoreColorSyncSettings() }
    }

    private func start() {
        tearDown()
        CGDisplayRestoreColorSyncSettings() // read the plain profile table, never a boosted one
        builtSignature = layoutSignature
        for screen in Self.xdrScreens {
            guard let id = Self.displayID(screen) else { continue }
            bases[id] = Self.plainTable(id)
            triggers.append(Self.makeTrigger(on: screen))
        }
        write()
        // ColorSync, display reconfiguration or other apps may reset the table: re-assert it.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.write() }
    }

    private func write() {
        guard boost > 1.0 else { return }
        for (id, base) in bases {
            let f = { [model, boost] (v: Float) in model(v, boost) }
            var r = base.r.map(f), g = base.g.map(f), b = base.b.map(f)
            CGSetDisplayTransferByTable(id, UInt32(r.count), &r, &g, &b)
        }
    }

    private static func plainTable(_ id: CGDirectDisplayID) -> Table {
        let n = 256
        var r = [CGGammaValue](repeating: 0, count: n), g = r, b = r
        var count: UInt32 = 0
        if CGGetDisplayTransferByTable(id, UInt32(n), &r, &g, &b, &count) == .success, count > 1,
           let peak = (r + g + b).max(), peak > 0.01, peak <= 1.003 {
            let c = Int(count)
            return (Array(r.prefix(c)), Array(g.prefix(c)), Array(b.prefix(c)))
        }
        let ramp = (0..<n).map { CGGammaValue($0) / CGGammaValue(n - 1) }
        return (ramp, ramp, ramp)
    }

    private static func makeTrigger(on screen: NSScreen) -> NSWindow {
        // Top-left pixel: hidden by the MacBook's rounded display corner.
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - 1, width: 1, height: 1)
        let w = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        w.collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.hidesOnDeactivate = false
        w.isReleasedWhenClosed = false
        w.animationBehavior = .none
        w.sharingType = .none
        if let v = EDRTriggerView(value: 2.0) { w.contentView = v }
        w.orderFrontRegardless()
        return w
    }

    @objc private func screensChanged() {
        if layoutSignature != builtSignature { scheduleRebuild() }
    }

    @objc private func scheduleRebuild() {
        guard !triggers.isEmpty else { return }
        pendingRebuild?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.boost > 1.0 else { return }
            self.start()
        }
        pendingRebuild = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}
