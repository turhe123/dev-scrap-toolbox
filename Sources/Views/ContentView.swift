import SwiftUI

/// Main window: a sidebar of tools and the selected tool's input/output panes.
struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage("fontSize") private var fontSize = 13.0

    var body: some View {
        NavigationSplitView {
            List(selection: $model.tool) {
                ForEach(Tool.allCases) { tool in
                    Label(tool.title, systemImage: tool.symbol).tag(tool)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            ToolView(tool: model.current, fontSize: fontSize)
        }
        .toolbar {
            ToolbarItemGroup {
                Button { model.smartPaste() } label: { Label("Paste and Detect", systemImage: "doc.on.clipboard") }
                    .help("Read the clipboard and open the matching tool")
                Button { model.swap() } label: { Label("Swap", systemImage: "arrow.up.arrow.down") }
                    .help("Move the output into the input")
                Button { model.clear() } label: { Label("Clear", systemImage: "xmark.circle") }
                    .help("Clear the input")
            }
        }
        .onAppear { model.openMainWindow = { openWindow(id: "main") } }
    }
}

/// One tool's UI: mode picker, input editor with hint and error line, and output with copy/save.
struct ToolView: View {
    @EnvironmentObject private var model: AppModel
    let tool: Tool
    let fontSize: Double

    private var font: Font { .system(size: fontSize, design: .monospaced) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(tool.title, systemImage: tool.symbol).font(.title2.bold())
                Spacer()
                if tool == .hash {
                    Button("Choose File…") { model.chooseFileToHash() }
                }
                if !tool.modes.isEmpty {
                    Picker("Mode", selection: Binding(get: { model.mode }, set: { model.mode = $0 })) {
                        ForEach(Array(tool.modes.enumerated()), id: \.offset) { Text($0.element).tag($0.offset) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            if tool == .jwt {
                Label("Decoding only — this does not verify the token's signature. Never trust an unverified JWT.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }

            pane(title: "Input") {
                TextEditor(text: $model.input)
                    .font(font)
                    .overlay(alignment: .topLeading) {
                        if model.input.isEmpty {
                            Text(tool.hint)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .allowsHitTesting(false)
                        }
                    }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first, url.isFileURL else { return false }
                model.hashFile(url)
                return true
            }

            if let error = model.error {
                Label(error.description, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            pane(title: "Output") {
                ZStack {
                    TextEditor(text: .constant(model.output)).font(font)
                    if model.isWorking { ProgressView("Processing…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)) }
                }
            } accessory: {
                if model.binary != nil {
                    Button("Save to File…") { model.saveBinary() }
                }
                Button { model.copyOutput() } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .disabled(model.output.isEmpty)
            }
        }
        .padding()
    }

    private func pane<Content: View, Accessory: View>(
        title: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.headline).foregroundStyle(.secondary)
                Spacer()
                accessory()
            }
            content()
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
        }
    }
}
