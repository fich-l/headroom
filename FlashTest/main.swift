// XDR Flash Test — automated white-flash / boost detector for the Bright XDR lab app.
//
// Built ONCE and left unchanged: macOS ties Screen Recording + Accessibility permissions of an
// ad-hoc signed app to its exact code signature. It knows nothing about overlay variants; it only
// forwards mode strings to the lab app ("Bright XDR Compare") and records raw per-frame data.
// Analysis happens separately (FlashTest/analyze.py), so it can evolve without rebuilding this.
//
// Launch through LaunchServices so the permissions are attributed to this app:
//   open -W "XDR Flash Test.app" --args --check --out DIR
//   open -W "XDR Flash Test.app" --args --modes "OFF|ORIGINAL|..." --out DIR [--settle 3] [--gap 1.6]
//
// Output: DIR/status.txt ("ok …" / "error …"), DIR/frames.csv
//   F,t,meanY,white90,white99,maxY,format,g0..g639   (32×20 luminance grid, linear)
//   E,t,name                                           (events: mode:X, R1, L1, R2, L2, MCopen, MCclose)
import ApplicationServices
import Cocoa
import CoreMedia
import ScreenCaptureKit

// MARK: arguments / output

let args = CommandLine.arguments
func arg(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}
let outDir = URL(fileURLWithPath: arg("--out") ?? NSHomeDirectory() + "/xdr-flashtest")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
func writeStatus(_ s: String) {
    try? (s + "\n").write(to: outDir.appendingPathComponent("status.txt"), atomically: true, encoding: .utf8)
}
let settle = Double(arg("--settle") ?? "3") ?? 3
let gap = Double(arg("--gap") ?? "1.6") ?? 1.6
let modes = (arg("--modes") ?? "OFF|ORIGINAL").split(separator: "|").map(String.init)

var timebase = mach_timebase_info_data_t()
mach_timebase_info(&timebase)
func machSeconds(_ t: UInt64) -> Double { Double(t) * Double(timebase.numer) / Double(timebase.denom) / 1e9 }
func now() -> Double { machSeconds(mach_absolute_time()) }

// MARK: recorder

final class Recorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "recorder")
    private var lines: [String] = []
    private(set) var format = "?"
    private(set) var frameCount = 0
    var streamError: Error?

    func event(_ name: String) {
        let t = now()
        queue.async { self.lines.append(String(format: "E,%.4f,%@", t, name)) }
    }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first
        else { throw NSError(domain: "flashtest", code: 1, userInfo: [NSLocalizedDescriptionKey: "no display"]) }
        let filter = SCContentFilter(display: display, excludingWindows: [])

        func config(hdr: Bool) -> SCStreamConfiguration {
            let c = SCStreamConfiguration()
            c.width = 320
            c.height = max(2, Int(Double(320) * Double(display.height) / Double(display.width)))
            c.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            c.showsCursor = false
            c.queueDepth = 8
            if hdr, #available(macOS 15.0, *) {
                c.captureDynamicRange = .hdrLocalDisplay
                c.pixelFormat = kCVPixelFormatType_64RGBAHalf
                c.colorSpaceName = CGColorSpace.extendedLinearDisplayP3
            } else {
                c.pixelFormat = kCVPixelFormatType_32BGRA
                c.colorSpaceName = CGColorSpace.sRGB
            }
            return c
        }

        for hdr in [true, false] {
            do {
                let s = SCStream(filter: filter, configuration: config(hdr: hdr), delegate: self)
                try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
                try await s.startCapture()
                stream = s
                format = hdr ? "hdr-linearP3-half" : "sdr-srgb-bgra"
                return
            } catch {
                if !hdr { throw error }
            }
        }
    }

    func stop() async {
        try? await stream?.stopCapture()
    }

    func write(to url: URL) {
        queue.sync { try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { streamError = error }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let atts = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let a = atts.first,
              let rawStatus = a[.status] as? Int, SCFrameStatus(rawValue: rawStatus) == .complete,
              let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        let t = (a[.displayTime] as? UInt64).map(machSeconds) ?? now()
        lines.append(String(format: "F,%.4f,", t) + metrics(pb))
        frameCount += 1
    }

    private func metrics(_ pb: CVPixelBuffer) -> String {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
        let bpr = CVPixelBufferGetBytesPerRow(pb)
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return "0,0,0,0,none" }
        let half = CVPixelBufferGetPixelFormatType(pb) == kCVPixelFormatType_64RGBAHalf
        let gw = 32, gh = 20
        var grid = [Double](repeating: 0, count: gw * gh), gridN = [Int](repeating: 0, count: gw * gh)
        var sum = 0.0, w90 = 0, w99 = 0, maxY = 0.0

        func srgbToLinear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }

        for y in 0..<h {
            let row = base.advanced(by: y * bpr)
            for x in 0..<w {
                var r = 0.0, g = 0.0, b = 0.0
                if half {
                    let p = row.assumingMemoryBound(to: UInt16.self).advanced(by: x * 4)
                    r = Double(Float16(bitPattern: p[0])); g = Double(Float16(bitPattern: p[1])); b = Double(Float16(bitPattern: p[2]))
                } else {
                    let p = row.assumingMemoryBound(to: UInt8.self).advanced(by: x * 4)
                    b = srgbToLinear(Double(p[0]) / 255); g = srgbToLinear(Double(p[1]) / 255); r = srgbToLinear(Double(p[2]) / 255)
                }
                let lum = half ? 0.2290 * r + 0.6917 * g + 0.0793 * b : 0.2126 * r + 0.7152 * g + 0.0722 * b
                sum += lum
                maxY = max(maxY, lum)
                let mn = min(r, g, b)
                if mn >= 0.9 { w90 += 1 }
                if mn >= 0.99 { w99 += 1 }
                let gi = min(gh - 1, y * gh / h) * gw + min(gw - 1, x * gw / w)
                grid[gi] += lum; gridN[gi] += 1
            }
        }
        let n = Double(w * h)
        let g = zip(grid, gridN).map { String(format: "%.4f", $0.1 > 0 ? $0.0 / Double($0.1) : 0) }.joined(separator: ",")
        return String(format: "%.5f,%.5f,%.5f,%.4f,%@,", sum / n, Double(w90) / n, Double(w99) / n, maxY, half ? "hdr" : "sdr") + g
    }
}

// MARK: helpers

/// Keystroke strategies (selectable with --keymode, tested with --probe):
///  A: arrow with ⌃ flag only, HID state source, HID tap (first attempt — ignored by the Dock)
///  B: real ⌃ key down → arrow (⌃+fn+numpad flags) → ⌃ up, HID state source, HID tap
///  C: like B, combined-session source, session tap
///  D: like B but private state source, HID tap
var keyMode = arg("--keymode") ?? "B"
func key(_ code: CGKeyCode, mode: String = keyMode) {
    let ctrl: CGKeyCode = 59
    let arrowFlags: CGEventFlags = [.maskControl, .maskSecondaryFn, .maskNumericPad]
    let srcState: CGEventSourceStateID = mode == "C" ? .combinedSessionState : mode == "D" ? .privateState : .hidSystemState
    let tap: CGEventTapLocation = mode == "C" ? .cgSessionEventTap : .cghidEventTap
    let src = CGEventSource(stateID: srcState)
    func post(_ k: CGKeyCode, _ down: Bool, _ flags: CGEventFlags) {
        let e = CGEvent(keyboardEventSource: src, virtualKey: k, keyDown: down)!
        e.flags = flags
        e.post(tap: tap)
        usleep(40_000)
    }
    if mode == "A" {
        post(code, true, .maskControl); post(code, false, .maskControl)
        return
    }
    let fe = CGEvent(keyboardEventSource: src, virtualKey: ctrl, keyDown: true)!
    fe.type = .flagsChanged; fe.flags = .maskControl; fe.post(tap: tap); usleep(40_000)
    post(code, true, arrowFlags)
    post(code, false, arrowFlags)
    let fu = CGEvent(keyboardEventSource: src, virtualKey: ctrl, keyDown: false)!
    fu.type = .flagsChanged; fu.flags = []; fu.post(tap: tap); usleep(40_000)
}
/// Mission Control: --mc app (launch Mission Control.app, toggles; default) or --mc key (⌃↑).
func openMissionControl() {
    if arg("--mc") == "key" { key(126) }
    else { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app")) }
}
func sleepS(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1e9)) }

/// Tells the lab app which mode to show; waits for its "ready" reply (or times out).
func setLabMode(_ mode: String) async {
    let center = DistributedNotificationCenter.default()
    var ready = false
    let token = center.addObserver(forName: .init("de.fichl.BrightXDR.Compare.ready"), object: nil, queue: .main) { n in
        if (n.object as? String) == mode { ready = true }
    }
    center.postNotificationName(.init("de.fichl.BrightXDR.Compare.set"), object: mode, userInfo: nil, deliverImmediately: true)
    let deadline = now() + 4
    while !ready && now() < deadline { await sleepS(0.05) }
    center.removeObserver(token)
}

/// Full-screen test pattern (dark grey + patches), stays on the Space it was created on.
@MainActor func makePattern(label: String) -> NSWindow {
    let screen = NSScreen.main!
    let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    w.setFrame(screen.frame, display: false)
    w.isReleasedWhenClosed = false
    w.level = .normal
    w.backgroundColor = NSColor(srgbRed: 0.25, green: 0.25, blue: 0.25, alpha: 1)
    let v = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
    let colors: [NSColor] = [
        NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1), NSColor(srgbRed: 0.6, green: 0.2, blue: 0.2, alpha: 1),
        NSColor(srgbRed: 0.2, green: 0.6, blue: 0.2, alpha: 1), NSColor(srgbRed: 0.2, green: 0.2, blue: 0.6, alpha: 1),
        NSColor(srgbRed: 0.65, green: 0.5, blue: 0.4, alpha: 1),
    ]
    let size = screen.frame.width / 8
    for (i, c) in colors.enumerated() {
        let p = NSView(frame: NSRect(x: size * (1 + CGFloat(i) * 1.25), y: screen.frame.height / 2 - size / 2, width: size, height: size))
        p.wantsLayer = true
        p.layer?.backgroundColor = c.cgColor
        v.addSubview(p)
    }
    let text = NSTextField(labelWithString: "XDR Flash Test running – please don't use the Mac (\(label))")
    text.textColor = NSColor(srgbRed: 0.55, green: 0.55, blue: 0.55, alpha: 1)
    text.font = .systemFont(ofSize: 22, weight: .medium)
    text.frame = NSRect(x: 40, y: 60, width: screen.frame.width - 80, height: 34)
    v.addSubview(text)
    w.contentView = v
    w.orderFrontRegardless()
    return w
}

// MARK: main flow

final class Delegate: NSObject, NSApplicationDelegate {
    var spaceChanges = 0
    var patterns: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in self?.spaceChanges += 1 }
        Task { await self.run(); NSApp.terminate(nil) }
    }

    @MainActor func run() async {
        let screenOK = CGPreflightScreenCaptureAccess()
        let axOK = AXIsProcessTrusted()
        if args.contains("--check") || !screenOK || !axOK {
            if !screenOK { _ = CGRequestScreenCaptureAccess() }
            if !axOK { _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary) }
            writeStatus("\(screenOK && axOK ? "ok" : "error") permissions screen=\(screenOK) accessibility=\(axOK)")
            if !(screenOK && axOK) { await sleepS(20) } // keep the prompts visible a moment
            return
        }

        if args.contains("--probe") {
            var result: [String] = []
            for m in ["A", "B", "C", "D"] {
                let before = spaceChanges
                key(124, mode: m)
                await sleepS(1.5)
                let moved = spaceChanges != before
                result.append("\(m)=\(moved ? "yes" : "no")")
                if moved { key(123, mode: m); await sleepS(1.5) }
            }
            // Mission Control via app launch (no keystroke needed)
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
            await sleepS(1.5)
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
            await sleepS(1.0)
            writeStatus("ok probe " + result.joined(separator: " "))
            return
        }

        let recorder = Recorder()
        await setLabMode("OFF")
        // Pattern on this Space and on the Space to the right.
        patterns.append(makePattern(label: "Space 1"))
        await sleepS(0.5)
        let before = spaceChanges
        key(124) // ⌃→
        await sleepS(1.4)
        if spaceChanges == before {
            writeStatus("error space switch via ⌃→ did not happen (need ≥2 desktops on this display, hotkey enabled)")
            patterns.forEach { $0.close() }
            return
        }
        patterns.append(makePattern(label: "Space 2"))
        await sleepS(0.5)
        key(123) // ⌃←
        await sleepS(1.4)

        do { try await recorder.start() } catch {
            writeStatus("error capture: \(error.localizedDescription)")
            patterns.forEach { $0.close() }
            return
        }

        for mode in modes {
            recorder.event("mode:" + mode)
            await setLabMode(mode)
            await sleepS(settle)
            recorder.event("steady")
            await sleepS(0.8)
            for step in ["R1", "L1", "R2", "L2"] {
                recorder.event(step)
                key(step.hasPrefix("R") ? 124 : 123)
                await sleepS(gap)
            }
            recorder.event("MCopen")
            openMissionControl()
            await sleepS(2.0)
            recorder.event("MCclose")
            openMissionControl()
            await sleepS(1.8)
            recorder.event("end:" + mode)
        }

        await recorder.stop()
        recorder.write(to: outDir.appendingPathComponent("frames.csv"))
        await setLabMode("OFF")
        patterns.forEach { $0.close() }
        writeStatus("ok frames=\(recorder.frameCount) format=\(recorder.format) modes=\(modes.count)"
            + (recorder.streamError.map { " streamError=\($0.localizedDescription)" } ?? ""))
    }
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
