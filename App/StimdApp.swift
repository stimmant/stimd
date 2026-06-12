import SwiftUI
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let wantsCLI = UserDefaults.standard.object(forKey: "installCLI") as? Bool ?? true
        if wantsCLI {
            CLIInstaller.installIfNeeded()
        }
    }
}

@main
struct StimdApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { config in
            DocumentView(initialText: config.document.text, fileURL: config.fileURL)
        }
        // Markdown is a document: default to a portrait, page-like window.
        .defaultSize(width: 840, height: 1020)
        .commands {
            SidebarCommands()
            StimdCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

struct SettingsView: View {
    @AppStorage("contentWidth") private var widthRaw: String = ContentWidth.medium.rawValue
    @AppStorage("bodyFont") private var fontRaw: String = BodyFont.sans.rawValue
    @AppStorage("installCLI") private var installCLI: Bool = true
    @State private var isDefaultViewer = false

    var body: some View {
        Form {
            Section("Appearance") {
                ThemePicker()
                Picker("Content Width", selection: $widthRaw) {
                    ForEach(ContentWidth.allCases) { width in
                        Text(width.displayName).tag(width.rawValue)
                    }
                }
                Picker("Font", selection: $fontRaw) {
                    ForEach(BodyFont.allCases) { font in
                        Text(font.displayName).tag(font.rawValue)
                    }
                }
            }
            Section("System") {
                LabeledContent("Markdown Files") {
                    if isDefaultViewer {
                        Label("stimd is the default viewer", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Use stimd for Markdown Files") {
                            makeDefaultViewer()
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Install command-line tool", isOn: $installCLI)
                    Text("`stimd <file>` opens files; pipe output to `stimd` to render it. Installed at \(CLIInstaller.destination.path).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: refreshDefaultViewerState)
        .onChange(of: installCLI) { _, wanted in
            if wanted {
                CLIInstaller.installIfNeeded()
            } else {
                CLIInstaller.uninstall()
            }
        }
    }

    private func refreshDefaultViewerState() {
        guard let current = NSWorkspace.shared.urlForApplication(toOpen: UTType.markdownDoc) else {
            isDefaultViewer = false
            return
        }
        isDefaultViewer = Bundle(url: current)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    private func makeDefaultViewer() {
        NSWorkspace.shared.setDefaultApplication(
            at: Bundle.main.bundleURL,
            toOpen: UTType.markdownDoc
        ) { _ in
            DispatchQueue.main.async {
                refreshDefaultViewerState()
            }
        }
    }
}

struct StimdCommands: Commands {
    @FocusedValue(\.docModel) private var model

    var body: some Commands {
        CommandGroup(replacing: .printItem) {
            Button("Export as PDF…") { model?.requests.send(.exportPDF) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(model == nil)
            Button("Print…") { model?.requests.send(.printPanel) }
                .keyboardShortcut("p")
                .disabled(model == nil)
        }
        CommandGroup(after: .toolbar) {
            Button("Actual Size") { ZoomControl.reset() }
                .keyboardShortcut("0")
            Button("Zoom In") { ZoomControl.step(1.1) }
                .keyboardShortcut("+")
            Button("Zoom Out") { ZoomControl.step(1 / 1.1) }
                .keyboardShortcut("-")
            Divider()
            Button("Reload") { model?.reload() }
                .keyboardShortcut("r")
                .disabled(model == nil)
        }
    }
}

struct ThemePicker: View {
    @AppStorage("docTheme") private var themeRaw: String = DocTheme.auto.rawValue

    var body: some View {
        Picker("Theme", selection: $themeRaw) {
            ForEach(DocTheme.allCases) { theme in
                Text(theme.displayName).tag(theme.rawValue)
            }
        }
    }
}

enum ZoomControl {
    static let minZoom = 0.5
    static let maxZoom = 3.0

    static var current: Double {
        let v = UserDefaults.standard.object(forKey: "pageZoom") as? Double ?? 1.0
        return v == 0 ? 1.0 : v
    }

    static func step(_ factor: Double) {
        set(current * factor)
    }

    static func reset() {
        set(1.0)
    }

    static func set(_ value: Double) {
        UserDefaults.standard.set(min(maxZoom, max(minZoom, value)), forKey: "pageZoom")
    }
}

struct DocModelKey: FocusedValueKey {
    typealias Value = DocModel
}

extension FocusedValues {
    var docModel: DocModel? {
        get { self[DocModelKey.self] }
        set { self[DocModelKey.self] = newValue }
    }
}
