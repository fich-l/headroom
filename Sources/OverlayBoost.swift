import Cocoa
import MetalKit

// Overlay fallback for Macs whose display ignores the gamma table.
//
// On M5 Pro and M5 Max, CGSetDisplayTransferByTable returns success and reads back correctly,
// but nothing changes on screen (Apple FB22273730, documented by Illuminate). Because the
// readback succeeds, this can't be detected at runtime: the chip name decides.
//
// The overlay is a full-screen window per XDR display whose only content is a 1×1 rgba16Float
// EDR drawable, stretched by the compositor. Default content ("negative alpha"): premultiplied
// colour 0 and alpha 1 − f with f > 1. Source-over then gives 0 + dst · (1 − (1 − f)) = f · dst.
// During Space switches and Mission Control, macOS flattens windows into SDR snapshots with
// alpha clamped to 0…1, so the overlay turns transparent instead of white: the boost pauses for
// the animation, but the screen never flashes white (measured with the negative-alpha variant of
// the lab, see DEVELOPMENT.md).
//
// Credits (details in NOTICE.md):
//   - Illuminate (MIT, © 2026 Jonas Fackelmeyer): the M5 Pro/Max gamma bug and its detection by
//     chip name; shielding window level for the overlay; keep presenting a few frames per second,
//     because WindowServer promotes an idle window to direct scan-out and drops its compositing
//     filter; don't exclude a multiply window from capture (screenshots would come out black).

/// How the brightness boost is applied.
enum BoostMethod: String {
    /// Scaled display gamma table (default; survives Space switches without a pause).
    case gamma
    /// Full-screen EDR overlay (M5 Pro / M5 Max, where macOS ignores gamma tables).
    case overlay

    /// The method for this Mac. `defaults write de.fichl.Headroom method gamma|overlay` overrides
    /// the automatic choice (for testing; restart Headroom after changing it).
    static var current: BoostMethod {
        if let s = UserDefaults.standard.string(forKey: "method"), let m = BoostMethod(rawValue: s) { return m }
        return Chip.ignoresGammaTables ? .overlay : .gamma
    }
}

enum Chip {
    /// e.g. "Apple M5 Max".
    static let brand: String = {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }()

    /// M5 Pro and M5 Max (not M5, not M15 Pro).
    static func ignoresGammaTables(brand: String) -> Bool {
        let words = brand.split(separator: " ")
        guard let chip = words.firstIndex(of: "M5"), chip + 1 < words.count else { return false }
        return words[chip + 1] == "Pro" || words[chip + 1] == "Max"
    }

    static var ignoresGammaTables: Bool { ignoresGammaTables(brand: brand) }
}

/// Overlay content and blending. `defaults write de.fichl.Headroom overlayStyle <style>`
/// switches it for testing (restart Headroom after changing it).
enum OverlayStyle: String {
    /// Colour 0, alpha 1 − f, plain source-over. Default: no white flash.
    case negAlpha
    /// The same content with the multiply compositing filter.
    case negAlphaMultiply
    /// Colour f, alpha 1, multiply filter (BrightXDR's look). Turns white during Space switches.
    case multiply

    static var current: OverlayStyle {
        UserDefaults.standard.string(forKey: "overlayStyle").flatMap(OverlayStyle.init) ?? .negAlpha
    }

    var usesMultiplyFilter: Bool { self != .negAlpha }

    func color(gain f: Double) -> MTLClearColor {
        switch self {
        case .negAlpha, .negAlphaMultiply: return MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1 - f)
        case .multiply: return MTLClearColor(red: f, green: f, blue: f, alpha: 1)
        }
    }
}

enum OverlayBoost {
    /// The menu levels are gamma-table factors; the overlay multiplies linear light, so it needs
    /// a larger factor for the same look. gain = boost ^ exponent; 1.7 puts High (1.5625) at
    /// about 2.1×, slightly above BrightXDR's 2.0 like the gamma-table High.
    /// `defaults write de.fichl.Headroom overlayExponent -float 2.2` tunes it (restart afterwards).
    static var exponent: Double {
        let e = UserDefaults.standard.double(forKey: "overlayExponent")
        return e > 0 ? e : 1.7
    }

    static func gain(for boost: Double) -> Double { pow(boost, exponent) }

    static func makeWindow(on screen: NSScreen, style: OverlayStyle, gain: Double) -> (window: NSWindow, view: EDRView)? {
        let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.setFrame(screen.frame, display: false)
        // Shielding level keeps the overlay above full-screen apps and the menu bar; the trigger
        // pixel sits one level higher.
        w.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.hidesOnDeactivate = false
        w.isReleasedWhenClosed = false
        w.animationBehavior = .none
        w.isExcludedFromWindowsMenu = true
        // Source-over: leave the overlay out of screenshots, so they show the normal image.
        // Multiply: an excluded multiply window still multiplies the capture against black.
        if !style.usesMultiplyFilter { w.sharingType = .none }
        guard let content = w.contentView,
              let view = EDRView(frame: content.bounds, color: style.color(gain: gain)) else { return nil }
        view.autoresizingMask = [.width, .height]
        if style.usesMultiplyFilter { view.layer?.compositingFilter = "multiplyBlendMode" }
        content.addSubview(view)
        w.orderFrontRegardless()
        return (w, view)
    }
}
