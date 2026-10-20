import SwiftUI

/// App entry point: main window, menu bar item and Settings scene.
@main
struct DevScrapToolboxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        Window("DevScrapToolbox", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 760, minHeight: 540)
        }
        .commands {
            CommandGroup(after: .pasteboard) {
                Button("Paste and Detect") { model.smartPaste() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra("DevScrapToolbox", systemImage: "wrench.and.screwdriver") {
            MenuBarContent().environmentObject(model)
        }

        Settings { SettingsView() }
    }
}

/// Items in the menu bar menu.
struct MenuBarContent: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open DevScrapToolbox") { open() }
        Button("Paste and Detect") { model.smartPaste(); open() }
        SettingsLink { Text("Settings…") }
        Divider()
        SupportButton()
        Divider()
        Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }

    private func open() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }
}

/// Wires up the global hotkey and auto-detect-on-activation, and keeps the app alive in the menu bar.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        HotKeyManager.shared.onPress = { Task { @MainActor in AppModel.shared.showWindow() } }
        HotKeyManager.shared.register(preset: UserDefaults.standard.object(forKey: "hotkey") as? Int ?? 0)
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                if UserDefaults.standard.object(forKey: "autoDetect") as? Bool ?? true {
                    AppModel.shared.autoDetectIfNeeded()
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
