import AppKit

/// Opens the settings window. Because the app is an accessory (`LSUIElement`)
/// app, we host the settings view in our own window rather than relying on the
/// SwiftUI `Settings` scene, which is unreliable when there is no Dock presence.
@MainActor
public enum SettingsOpener {
    private static var controller: SettingsWindowController?

    public static func open() {
        let controller = self.controller ?? {
            let created = SettingsWindowController()
            self.controller = created
            return created
        }()
        controller.show(SettingsRootView())
        NSApp.activate(ignoringOtherApps: true)
    }
}