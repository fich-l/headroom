// Pixel-equivalence test: the new overlay must write exactly the same EDR pixel values as the
// original BrightXDR, so colours on screen are identical (same value, same colour space, same
// multiply blend). Renders both on the GPU into rgba16Float textures and compares the bits.
import CoreImage
import Foundation
import AppKit
import Metal
import QuartzCore

let device = MTLCreateSystemDefaultDevice()!
let queue = device.makeCommandQueue()!
let cs = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!

func makeTexture() -> MTLTexture {
    let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 8, height: 8, mipmapped: false)
    d.usage = [.renderTarget, .shaderWrite, .shaderRead]
    d.storageMode = .shared
    return device.makeTexture(descriptor: d)!
}

func readPixel(_ t: MTLTexture) -> [Float] {
    var raw = [UInt16](repeating: 0, count: 8 * 8 * 4)
    t.getBytes(&raw, bytesPerRow: 8 * 8, from: MTLRegionMake2D(0, 0, 8, 8), mipmapLevel: 0)
    return raw[0..<4].map { Float(Float16(bitPattern: $0)) }
}

/// Original BrightXDR pipeline (MetalView.swift): white → CIColorControls → CIContext render.
func originalPixel(contrast: Float, brightness: Float) -> [Float] {
    let context = CIContext(mtlCommandQueue: queue, options: [
        .workingColorSpace: cs, .workingFormat: CIFormat.RGBAf, .cacheIntermediates: true, .allowLowPower: false,
    ])
    let filter = CIFilter(name: "CIColorControls")!
    filter.setValue(contrast, forKey: kCIInputContrastKey)
    filter.setValue(brightness, forKey: kCIInputBrightnessKey)
    filter.setValue(CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1, colorSpace: cs)!), forKey: kCIInputImageKey)
    let tex = makeTexture()
    let buffer = queue.makeCommandBuffer()!
    context.render(filter.outputImage!, to: tex, commandBuffer: buffer, bounds: CGRect(x: 0, y: 0, width: 8, height: 8), colorSpace: cs)
    buffer.commit(); buffer.waitUntilCompleted()
    return readPixel(tex)
}

/// New overlay (Overlay.swift): clear colour = boost.
func newPixel(boost: Double) -> [Float] {
    let tex = makeTexture()
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = tex
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = MTLClearColor(red: boost, green: boost, blue: boost, alpha: 1)
    let buffer = queue.makeCommandBuffer()!
    buffer.makeRenderCommandEncoder(descriptor: pass)!.endEncoding()
    buffer.commit(); buffer.waitUntilCompleted()
    return readPixel(tex)
}

// Layer-based variants (caLayer / ioSurface) can't be rendered offscreen (CARenderer draws nothing
// here); their look is checked on the real compositor by the flash test (steady state vs. Original).
var failures = 0
print("Pixel equivalence vs. original BrightXDR overlay\n")
func fmt(_ p: [Float]) -> String { p.map { String(format: "%.3f", $0) }.joined(separator: ",") }
for boost in [1.25, 1.5, 1.75, 2.0] {
    let o = originalPixel(contrast: 1, brightness: Float(boost - 1))
    let candidates: [(String, [Float])] = [
        ("metal", newPixel(boost: boost)),
    ]
    let tag = boost == 2.0 ? "  ← Maximum = original app" : ""
    print(String(format: "%.2f×: original %@%@", boost, fmt(o), tag))
    for (name, n) in candidates {
        let same = zip(o, n).allSatisfy { abs($0 - $1) < 1e-3 }
        if !same { failures += 1 }
        print("   \(same ? "PASS" : "FAIL")  \(name.padding(toLength: 9, withPad: " ", startingAt: 0)) \(fmt(n))")
    }
}
print(failures == 0 ? "\n✓ overlay pixels identical to the original" : "\n✗ \(failures) mismatch(es)")
exit(failures == 0 ? 0 : 1)
