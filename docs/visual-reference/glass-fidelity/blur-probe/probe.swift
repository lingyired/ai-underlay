import AppKit

@main
@MainActor
struct BlurSpike {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        guard let screen = NSScreen.main else { return }
        let rect = CGRect(x: screen.frame.minX + 600, y: screen.frame.maxY - 30, width: 320, height: 30)
        let window = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = NSView(frame: CGRect(origin: .zero, size: rect.size))
        window.orderFrontRegardless()
        let effect = NSVisualEffectView(frame: CGRect(origin: .zero, size: rect.size))
        effect.blendingMode = .behindWindow; effect.material = .menu; effect.state = .active
        effect.appearance = NSAppearance(named: .aqua)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { window.contentView = effect }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { effect.appearance = NSAppearance(named: .darkAqua) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { window.orderOut(nil); app.terminate(nil) }
        print("NSVisualEffectView probe: x=600 y=0 width=320 height=30; same desktop-icon+1 level; no global settings changed")
        app.run()
    }
}
