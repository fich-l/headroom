import Foundation

// Lab variants of the gamma-table boost (GammaBooster in Sources/Gamma.swift).
// Lab mode string: "GAMMA:<curve>:<k>"
//   curve = "srgb"   encode_sRGB(k · decode_sRGB(v))   (exact linear-light multiply for sRGB-encoded tables)
//         = "p<e>"   v · k^(1/e)                       (pure power-law encoding, e.g. p2.2)
//         = "naive"  v · k                             (BrightIntosh-style)

struct GammaSpec {
    enum Curve { case srgb, power(Double), naive }
    var curve: Curve
    var k: Double

    init?(_ s: String) {
        let p = s.split(separator: ":").map(String.init)
        guard p.count == 3, p[0] == "GAMMA", let k = Double(p[2]), k >= 1 else { return nil }
        switch p[1] {
        case "srgb": curve = .srgb
        case "naive": curve = .naive
        case let c where c.hasPrefix("p"):
            guard let e = Double(c.dropFirst()), e > 0 else { return nil }
            curve = .power(e)
        default: return nil
        }
        self.k = k
    }

    /// Table-entry model for GammaBooster (Sources/Gamma.swift).
    var model: (Float, Double) -> Float {
        let curve = curve
        return { v, k in Self.map(v, k, curve) }
    }

    static func map(_ v: Float, _ k: Double, _ curve: Curve) -> Float {
        switch curve {
        case .naive: return v * Float(k)
        case .power(let e): return v * Float(pow(k, 1 / e))
        case .srgb:
            func dec(_ x: Float) -> Float { x <= 0.04045 ? x / 12.92 : powf((x + 0.055) / 1.055, 2.4) }
            func enc(_ l: Float) -> Float { l <= 0.0031308 ? l * 12.92 : 1.055 * powf(l, 1 / 2.4) - 0.055 }
            return enc(dec(v) * Float(k))
        }
    }
}

