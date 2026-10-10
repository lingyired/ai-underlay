import AppKit

/// Opens the SwiftUI settings window from the status item. Uses the standard
/// `showSettingsWindow:` action on modern macOS, falling back to activating the
/// app and its settings scene.
@MainActor
public enum SettingsOpener {
    public static func open() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}