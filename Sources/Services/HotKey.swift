import Carbon

/// Registers one system-wide hotkey via Carbon `RegisterEventHotKey` and calls `onPress` when it fires.
final class HotKeyManager {
    static let shared = HotKeyManager()

    /// Selectable shortcuts shown in Settings; the index is persisted, -1 disables the hotkey.
    static let presets: [(name: String, keyCode: UInt32, modifiers: UInt32)] = [
        ("⌃⌥Space", UInt32(kVK_Space), UInt32(controlKey | optionKey)),
        ("⌘⇧D", UInt32(kVK_ANSI_D), UInt32(cmdKey | shiftKey)),
        ("⌃⌥D", UInt32(kVK_ANSI_D), UInt32(controlKey | optionKey)),
        ("⌘⌥J", UInt32(kVK_ANSI_J), UInt32(cmdKey | optionKey)),
    ]

    var onPress: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func register(preset index: Int) {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        guard Self.presets.indices.contains(index) else { return }
        installHandlerIfNeeded()
        let preset = Self.presets[index]
        let id = EventHotKeyID(signature: OSType(0x4453_5442), id: 1) // "DSTB"
        RegisterEventHotKey(preset.keyCode, preset.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKeyManager.shared.onPress?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }
}
