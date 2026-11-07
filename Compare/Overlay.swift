import Cocoa
import CoreImage
import IOSurface
import MetalKit

// Full-screen EDR overlay — the original BrightXDR method: a layer filled with a value > 1.0 in
// extended linear Display P3, multiply-blended over everything (out = content × value).
// Pixel-identical to the original (its CIColorControls brightness +1.0 on white → 2.0).
//
// To find a setup that doesn't turn white during Space switches / Mission Control, the overlay
// is configurable along four axes (public API only). Variant id: "placement.level.content.blend".

// MARK: - Variant

struct OverlayVariant: Equatable, CustomStringConvertible {
    enum Placement: String, CaseIterable { case allSpaces, allSpacesStationary, allSpacesTransient, perSpace }
    enum Level: String, CaseIterable { case normal, floating, mainMenu, statusBar, popUpMenu, screenSaver, assistiveTechHigh }
    enum Content: String, CaseIterable { case metal, caLayer, ioSurface, negAlpha }
    enum Blend: String, CaseIterable { case caString, ciFilter, none }

    var placement: Placement
    var level: Level
    var content: Content
    var blend: Blend

    /// The original BrightXDR setup.
    static let original = OverlayVariant(placement: .allSpaces, level: .mainMenu, content: .metal, blend: .caString)

    var description: String { "\(placement.rawValue).\(level.rawValue).\(content.rawValue).\(blend.rawValue)" }

    init(placement: Placement, level: Level, content: Content, blend: Blend) {
        self.placement = placement; self.level = level; self.content = content; self.blend = blend
    }

    init?(_ id: String) {
        let p = id.split(separator: ".").map(String.init)
        guard p.count == 4, let a = Placement(rawValue: p[0]), let b = Level(rawValue: p[1]),
              let c = Content(rawValue: p[2]), let d = Blend(rawValue: p[3]) else { return nil }
        self.init(placement: a, level: b, content: c, blend: d)
    }

    var windowLevel: NSWindow.Level {
        switch level {
        case .normal: return .normal
        case .floating: return .floating
        case .mainMenu: return .mainMenu
        case .statusBar: return .statusBar
        case .popUpMenu: return .popUpMenu
        case .screenSaver: return .screenSaver
        case .assistiveTechHigh: return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
        }
    }

    var collectionBehavior: NSWindow.CollectionBehavior {
        switch placement {
        case .allSpaces: return [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        case .allSpacesStationary: return [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        case .allSpacesTransient: return [.canJoinAllSpaces, .transient, .fullScreenAuxiliary, .ignoresCycle]
        case .perSpace: return [.fullScreenAuxiliary, .ignoresCycle]
        }
    }
}

// MARK: - Content views

protocol OverlayContent: NSView {
    var value: Double { get set }
    func applyBlend()
}

private let edrSpace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!

private func makeBlendFilter(_ blend: OverlayVariant.Blend) -> Any? {
    switch blend {
    case .caString: return "multiplyBlendMode"
    case .ciFilter: return CIFilter(name: "CIMultiplyBlendMode")
    case .none: return nil
    }
}

/// Metal drawable filled with the EDR value (the original's rendering path).
final class MetalOverlayView: MTKView, MTKViewDelegate, OverlayContent {
    private let queue: MTLCommandQueue
    private let blend: OverlayVariant.Blend
    /// Negative-alpha content: premultiplied colour 0, alpha 1 − value. Source-over then gives
    /// 0 + dst·(1 − (1 − value)) = value·dst, and multiply gives dst·(1 + 0 − alpha) = value·dst too.
    private let negAlpha: Bool

    private static func color(_ v: Double, negAlpha: Bool) -> MTLClearColor {
        negAlpha ? MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1 - v) : MTLClearColor(red: v, green: v, blue: v, alpha: 1)
    }

    var value: Double {
        didSet { clearColor = Self.color(value, negAlpha: negAlpha); needsDisplay = true }
    }

    init?(frame: CGRect, value: Double, blend: OverlayVariant.Blend, negAlpha: Bool = false) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.queue = queue
        self.value = value
        self.blend = blend
        self.negAlpha = negAlpha
        super.init(frame: frame, device: device)
        colorPixelFormat = .rgba16Float
        colorspace = edrSpace
        clearColor = Self.color(value, negAlpha: negAlpha)
        framebufferOnly = false
        preferredFramesPerSecond = 3 // same as the original
        autoresizingMask = [.width, .height]
        delegate = self
        applyBlend()
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func applyBlend() {
        guard let layer = layer as? CAMetalLayer else { return }
        layer.wantsExtendedDynamicRangeContent = true
        layer.isOpaque = false
        layer.compositingFilter = makeBlendFilter(blend)
    }

    func draw(in view: MTKView) {
        guard let pass = currentRenderPassDescriptor, let drawable = currentDrawable,
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}

/// Layer-only content: either an EDR background colour, or a static rgba16F IOSurface.
final class LayerOverlayView: NSView, OverlayContent {
    private let kind: OverlayVariant.Content
    private let blend: OverlayVariant.Blend
    private let fill = CALayer()

    var value: Double { didSet { updateContents() } }

    init(frame: CGRect, value: Double, kind: OverlayVariant.Content, blend: OverlayVariant.Blend) {
        self.kind = kind
        self.blend = blend
        self.value = value
        super.init(frame: frame)
        wantsLayer = true
        autoresizingMask = [.width, .height]
        fill.frame = bounds
        fill.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(fill)
        updateContents()
        applyBlend()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func applyBlend() {
        if #available(macOS 14.0, *) { fill.wantsExtendedDynamicRangeContent = true }
        fill.isOpaque = false
        fill.compositingFilter = makeBlendFilter(blend)
    }

    private func updateContents() {
        switch kind {
        case .ioSurface:
            fill.backgroundColor = nil
            fill.contentsFormat = .RGBA16Float
            fill.contents = Self.surface(value: value)
        default:
            fill.contents = nil
            fill.backgroundColor = CGColor(colorSpace: edrSpace, components: [value, value, value, 1])
        }
    }

    /// 16×16 rgba16F IOSurface filled with the value, tagged extended linear Display P3.
    static func surface(value: Double) -> IOSurface? {
        let size = 16
        guard let s = IOSurface(properties: [
            .width: size, .height: size, .bytesPerElement: 8,
            .pixelFormat: kCVPixelFormatType_64RGBAHalf,
        ]) else { return nil }
        s.lock(options: [], seed: nil)
        let v = halfBits(Float(value)), one = halfBits(1)
        for y in 0..<size {
            let row = s.baseAddress.advanced(by: y * s.bytesPerRow).assumingMemoryBound(to: UInt16.self)
            for x in 0..<size { row[x * 4] = v; row[x * 4 + 1] = v; row[x * 4 + 2] = v; row[x * 4 + 3] = one }
        }
        s.unlock(options: [], seed: nil)
        IOSurfaceSetValue(unsafeBitCast(s, to: IOSurfaceRef.self), kIOSurfaceColorSpace,
                          edrSpace.copyPropertyList()!)
        return s
    }
}

/// IEEE half-precision bits for a non-negative float (Float16 isn't available on x86_64).
func halfBits(_ f: Float) -> UInt16 {
    let b = f.bitPattern
    let exp = Int((b >> 23) & 0xFF) - 127 + 15
    if f <= 0 || exp <= 0 { return 0 }
    if exp >= 31 { return 0x7C00 }
    let mant = (b >> 13) & 0x3FF, round = (b >> 12) & 1
    return UInt16(exp << 10) + UInt16(mant) + UInt16(round)
}

// MARK: - Controller

final class OverlayController {
    private var windows: [(window: NSWindow, view: OverlayContent)] = []
    private var builtSignature = ""
    private var pendingRebuild: DispatchWorkItem?

    var variant: OverlayVariant { didSet { if variant != oldValue, !windows.isEmpty { build() } } }

    /// Linear brightness multiplier, 1.0 = off. The original's fixed value is 2.0.
    var boost: Double = 1.0 {
        didSet {
            if boost <= 1.0 { stop(); return }
            if windows.isEmpty { build() } else { windows.forEach { $0.view.value = boost } }
        }
    }

    init(variant: OverlayVariant) {
        self.variant = variant
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        ws.addObserver(self, selector: #selector(scheduleRebuild), name: NSWorkspace.screensDidWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(scheduleRebuild), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    static var hasXDRScreen: Bool { !xdrScreens.isEmpty }
    private static var xdrScreens: [NSScreen] {
        NSScreen.screens.filter { $0.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.0 }
    }

    private var layoutSignature: String { NSScreen.screens.map { "\($0.frame)" }.joined(separator: "|") }

    func stop() {
        pendingRebuild?.cancel()
        windows.forEach { $0.window.orderOut(nil) }
        windows.removeAll()
    }

    private func build() {
        windows.forEach { $0.window.orderOut(nil) }
        windows.removeAll()
        builtSignature = layoutSignature
        for screen in Self.xdrScreens { addWindow(on: screen) }
    }

    private func addWindow(on screen: NSScreen) {
        let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.setFrame(screen.frame, display: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.level = variant.windowLevel
        window.collectionBehavior = variant.collectionBehavior
        guard let content = window.contentView else { return }
        let view: OverlayContent
        switch variant.content {
        case .metal, .negAlpha:
            guard let v = MetalOverlayView(frame: content.bounds, value: boost, blend: variant.blend,
                                           negAlpha: variant.content == .negAlpha) else { return }
            view = v
        case .caLayer, .ioSurface:
            view = LayerOverlayView(frame: content.bounds, value: boost, kind: variant.content, blend: variant.blend)
        }
        content.addSubview(view)
        window.orderFrontRegardless()
        windows.append((window, view))
    }

    @objc private func spaceChanged() {
        guard !windows.isEmpty else { return }
        if variant.placement == .perSpace {
            // One overlay per Space and screen: add one where missing, drop duplicates
            // (e.g. windows macOS moved here after a Space was deleted).
            for screen in Self.xdrScreens {
                let here = windows.filter { $0.window.isOnActiveSpace && $0.window.screen == screen }
                if here.isEmpty { addWindow(on: screen) }
                for extra in here.dropFirst() {
                    extra.window.orderOut(nil)
                    windows.removeAll { $0.window === extra.window }
                }
            }
        }
    }

    @objc private func screensChanged() {
        if layoutSignature != builtSignature { scheduleRebuild() }
    }

    @objc private func scheduleRebuild() {
        guard !windows.isEmpty else { return }
        pendingRebuild?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.build() }
        pendingRebuild = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}
