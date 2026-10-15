// Offscreen probe: how long does each phase of a discrete `contents` keyframe
// animation actually stay on screen?
//
// The curtain in `GlassSpectrumRenderer` is one `CAKeyframeAnimation` over a
// rasterised phase sequence, so the shape of the timeline matters:
//
//   * `legacy` — key times 0/n … (n-1)/n, the sequence as first shipped. The
//     last key time is below 1.0, so Core Animation falls back to the layer's
//     model value for the rest of the cycle.
//   * `closed` — key times 0/n … n/n, with the first phase repeated as the
//     final value, so every phase holds exactly one step.
//
// Measured on macOS 27.0.1 (Apple silicon): `legacy` never presents the final
// phase and stretches the frame before the seam to two steps — a hitch once
// per cycle. `closed` presents the whole sequence with uniform holds.
//
// The phase bitmaps here are generated for the probe only: it measures Core
// Animation's discrete-keyframe behaviour, not the renderer's artwork.
//
// usage: swiftc -O timeline-probe.swift -o /tmp/timeline-probe && \
//        /tmp/timeline-probe closed 24 1.42857
//
import AppKit
import QuartzCore

func solid(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGImage {
    let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    return ctx.makeImage()!
}

let scheme = CommandLine.arguments[1]
let frameCount = Int(CommandLine.arguments[2])!
let cycle = CommandLine.arguments.count > 3 ? Double(CommandLine.arguments[3])! : 1.0

// Distinct, far-apart colours per phase, so a downscaled sample still
// identifies the frame unambiguously.
var palette: [(CGFloat, CGFloat, CGFloat)] = []
for i in 0..<frameCount {
    let hue = CGFloat(i) / CGFloat(frameCount)
    func channel(_ n: CGFloat) -> CGFloat {
        let k = (n + hue * 6).truncatingRemainder(dividingBy: 6)
        return max(0, min(1, min(k, 4 - k)))
    }
    palette.append((channel(5), channel(3), channel(1)))
}
let frames = palette.map { solid($0.0, $0.1, $0.2) }

func classify(_ any: Any?) -> Int {
    guard let any else { return -1 }
    let image = any as! CGImage
    let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
    let observed = (CGFloat(p[0]) / 255, CGFloat(p[1]) / 255, CGFloat(p[2]) / 255)
    var best = -1
    var bestDistance = CGFloat.greatestFiniteMagnitude
    for (index, color) in palette.enumerated() {
        let d = pow(color.0 - observed.0, 2) + pow(color.1 - observed.1, 2) + pow(color.2 - observed.2, 2)
        if d < bestDistance { bestDistance = d; best = index }
    }
    return best
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let window = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 32, height: 32),
                      styleMask: [.borderless], backing: .buffered, defer: false)
window.level = .statusBar
window.ignoresMouseEvents = true
window.backgroundColor = .clear
let layer = CALayer()
layer.frame = CGRect(x: 0, y: 0, width: 32, height: 32)
window.contentView?.wantsLayer = true
window.contentView?.layer?.addSublayer(layer)
window.orderFrontRegardless()
layer.contents = frames[0]

let animation = CAKeyframeAnimation(keyPath: "contents")
switch scheme {
case "closed":   // the fix: timeline ends at 1.0 with the first phase again
    animation.values = frames + [frames[0]]
    animation.keyTimes = (0...frameCount).map { NSNumber(value: Double($0) / Double(frameCount)) }
case "legacy":   // shipped: last key time is (n-1)/n
    animation.values = frames
    animation.keyTimes = (0..<frameCount).map { NSNumber(value: Double($0) / Double(frameCount)) }
default:
    fatalError("unknown scheme \(scheme)")
}
animation.calculationMode = .discrete
animation.duration = cycle
animation.repeatCount = .infinity
animation.beginTime = CACurrentMediaTime()
layer.add(animation, forKey: "curtainFrames")

let start = CACurrentMediaTime()
let step = cycle / Double(frameCount)
var transitions: [(frame: Int, time: Double)] = []
var previous = -2
func tick() {
    let now = CACurrentMediaTime() - start
    let frame = classify(layer.presentation()?.contents)
    if frame >= 0, frame != previous {
        transitions.append((frame, now))
        previous = frame
    }
    if now > cycle * 2.0 {
        // Second cycle only: measure the real hold of every phase.
        let second = transitions.filter { $0.time > cycle - step / 2 }
        var holds: [Double] = []
        for (index, entry) in second.enumerated() where index + 1 < second.count {
            // Skip a repeat of the opening phase at the cycle boundary.
            holds.append((second[index + 1].time - entry.time) / step)
        }
        let distinct = Set(transitions.map(\.frame))
        print(String(format: "scheme=%@ frames=%d cycle=%.2fs step=%.1fms", scheme, frameCount, cycle, step * 1000))
        print("  distinct phases presented: \(distinct.count)/\(frameCount)  missing: \(Set(0..<frameCount).subtracting(distinct).sorted())")
        print("  hold per transition, in steps: " + holds.map { String(format: "%.2f", $0) }.joined(separator: " "))
        if let maxHold = holds.max(), let minHold = holds.min() {
            print(String(format: "  min %.2f steps, max %.2f steps, spread %.2f", minHold, maxHold, maxHold - minHold))
        }
        exit(0)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { tick() }
}
tick()
app.run()
