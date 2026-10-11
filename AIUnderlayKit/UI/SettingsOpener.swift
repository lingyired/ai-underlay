import AppKit

/// Opens the settings window. Because the app is an accessory (`LSUIElement`)
/// app, we host the settings view in our own window and explicitly activate.
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
    }
}
