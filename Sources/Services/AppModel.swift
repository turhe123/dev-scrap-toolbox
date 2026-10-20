import AppKit
import SwiftUI

/// Shared app state: selected tool, input/output, errors, and the actions behind the toolbar.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var tool: Tool? = .json { didSet { if tool != oldValue { schedule() } } }
    @Published var input = "" { didSet { if input != oldValue { schedule() } } }
    @Published private var modes: [Tool: Int] = [:]
    @Published private(set) var output = ""
    @Published private(set) var binary: Data?
    @Published private(set) var error: ToolError?
    @Published private(set) var isWorking = false

    /// Set by a SwiftUI view so non-view code (hotkey, menu) can reopen the main window.
    var openMainWindow: (() -> Void)?
    private var task: Task<Void, Never>?
    private var lastChangeCount = -1

    var current: Tool { tool ?? .json }

    var mode: Int {
        get { modes[current] ?? 0 }
        set { modes[current] = newValue; schedule() }
    }

    /// Runs the current tool off the main thread, debounced; shows progress for large inputs.
    func schedule() {
        task?.cancel()
        let tool = current, mode = self.mode, input = self.input
        guard !input.isEmpty else {
            output = ""; binary = nil; error = nil; isWorking = false
            return
        }
        isWorking = input.utf8.count > 250_000
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .userInitiated) {
                Converters.run(tool, mode: mode, input: input)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.apply(result)
        }
    }

    private func apply(_ result: Result<ToolOutput, ToolError>) {
        isWorking = false
        switch result {
        case .success(let out): output = out.text; binary = out.binary; error = nil
        case .failure(let err): output = ""; binary = nil; error = err
        }
    }

    func hashFile(_ url: URL) {
        tool = .hash
        input = ""
        task?.cancel()
        isWorking = true
        task = Task { [weak self] in
            let result: Result<ToolOutput, ToolError> = await Task.detached(priority: .userInitiated) {
                do { return .success(ToolOutput(text: try Converters.hashFile(at: url))) } catch {
                    return .failure(ToolError(message: "Could not read file: \(error.localizedDescription)"))
                }
            }.value
            guard !Task.isCancelled, let self else { return }
            self.apply(result)
        }
    }

    func chooseFileToHash() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { hashFile(url) }
    }

    /// Reads the clipboard, guesses its type and opens the matching tool pre-filled.
    func smartPaste() {
        lastChangeCount = NSPasteboard.general.changeCount
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let guess = Detector.detect(text)
        modes[guess.tool] = guess.mode
        tool = guess.tool
        input = text
        schedule()
    }

    /// Smart-pastes only when the clipboard changed since the last detection.
    func autoDetectIfNeeded() {
        guard NSPasteboard.general.changeCount != lastChangeCount else { return }
        smartPaste()
    }

    func swap() {
        guard !output.isEmpty, binary == nil else { return }
        let out = output
        if current.isTwoWay { modes[current] = mode == 0 ? 1 : 0 }
        input = out
        schedule()
    }

    func clear() { input = "" }

    func copyOutput() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
    }

    func saveBinary() {
        guard let binary else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "decoded.bin"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try binary.write(to: url) } catch {
            self.error = ToolError(message: "Could not save file: \(error.localizedDescription)")
        }
    }

    func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openMainWindow?()
    }
}
