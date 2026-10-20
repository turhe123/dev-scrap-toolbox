import SwiftUI
import ServiceManagement

/// Preferences: global hotkey, editor font size, auto-detect on activation, launch at login, support link.
struct SettingsView: View {
    @AppStorage("hotkey") private var hotkey = 0
    @AppStorage("fontSize") private var fontSize = 13.0
    @AppStorage("autoDetect") private var autoDetect = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Picker("Global hotkey", selection: $hotkey) {
                Text("Off").tag(-1)
                ForEach(Array(HotKeyManager.presets.enumerated()), id: \.offset) { Text($0.element.name).tag($0.offset) }
            }
            .onChange(of: hotkey) { _, newValue in HotKeyManager.shared.register(preset: newValue) }

            Picker("Font size", selection: $fontSize) {
                ForEach([11.0, 13.0, 15.0, 18.0, 22.0], id: \.self) { Text("\(Int($0)) pt").tag($0) }
            }

            Toggle("Paste and Detect automatically when the app becomes active", isOn: $autoDetect)

            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        loginError = nil
                    } catch {
                        loginError = "Could not update login item: \(error.localizedDescription). You can manage it in System Settings › General › Login Items."
                    }
                }
            if let loginError {
                Text(loginError).foregroundStyle(.red).font(.caption)
            }

            Section {
                HStack {
                    Text("DevScrapToolbox is free, open source and works fully offline.")
                    Spacer()
                    SupportButton()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The donation button, shared by Settings and the menu bar menu.
struct SupportButton: View {
    var body: some View {
        Button("Support / Donate ❤️") {
            NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
        }
    }
}
