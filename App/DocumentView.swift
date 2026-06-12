import SwiftUI
import Combine

enum DocRequest {
    case printPanel
    case exportPDF
}

@MainActor
final class DocModel: ObservableObject {
    @Published var rendered: RenderedMarkdown

    let fileURL: URL?
    let anchorClicks = PassthroughSubject<String, Never>()
    let requests = PassthroughSubject<DocRequest, Never>()

    private var watcher: FileWatcher?
    private var lastText: String

    init(text: String, fileURL: URL?) {
        self.fileURL = fileURL
        self.lastText = text
        self.rendered = MarkdownHTML.render(text)
        startWatching()
    }

    private func startWatching() {
        guard let url = fileURL else { return }
        watcher = FileWatcher(url: url) { [weak self] in
            self?.reload()
        }
    }

    func reload() {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return }
        let text = String(decoding: data, as: UTF8.self)
        guard text != lastText else { return }
        lastText = text
        rendered = MarkdownHTML.render(text)
    }
}

struct DocumentView: View {
    @StateObject private var model: DocModel
    @AppStorage("docTheme") private var themeRaw: String = DocTheme.auto.rawValue
    @AppStorage("pageZoom") private var zoom: Double = 1.0
    @AppStorage("sidebarVisible") private var sidebarVisible: Bool = true
    @AppStorage("contentWidth") private var widthRaw: String = ContentWidth.medium.rawValue
    @AppStorage("bodyFont") private var fontRaw: String = BodyFont.sans.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @State private var columns: NavigationSplitViewVisibility = .automatic

    private let fileURL: URL?

    init(initialText: String, fileURL: URL?) {
        self.fileURL = fileURL
        _model = StateObject(wrappedValue: DocModel(text: initialText, fileURL: fileURL))
    }

    private var theme: DocTheme {
        DocTheme(rawValue: themeRaw) ?? .auto
    }

    /// Window title: the document's top-level heading when it has one,
    /// otherwise the file name.
    private var windowTitle: String {
        if let first = model.rendered.toc.first, first.level == 1 {
            return first.title
        }
        return fileURL?.lastPathComponent ?? "stimd"
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            TOCSidebar(entries: model.rendered.toc) { anchor in
                model.anchorClicks.send(anchor)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 230, max: 360)
        } detail: {
            MarkdownWebView(
                model: model,
                theme: theme,
                zoom: zoom == 0 ? 1.0 : zoom,
                systemDark: colorScheme == .dark,
                width: ContentWidth(rawValue: widthRaw) ?? .medium,
                font: BodyFont(rawValue: fontRaw) ?? .sans
            )
        }
        .background(WindowTitleSetter(title: windowTitle))
        .onAppear {
            columns = sidebarVisible ? .all : .detailOnly
        }
        .onChange(of: columns) { _, newValue in
            if newValue != .automatic {
                sidebarVisible = newValue != .detailOnly
            }
        }
        .focusedSceneValue(\.docModel, model)
    }
}

/// DocumentGroup ignores .navigationTitle, so set the NSWindow title directly.
/// The titlebar proxy icon (and its path menu) still reflects the real file.
private struct WindowTitleSetter: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> TitleView {
        TitleView(title: title)
    }

    func updateNSView(_ view: TitleView, context: Context) {
        view.apply(title)
    }

    final class TitleView: NSView {
        private var pending: String
        private var titleObservation: NSKeyValueObservation?

        init(title: String) {
            pending = title
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            titleObservation = nil
            guard let window else { return }

            apply(pending)
            // DocumentGroup re-asserts the file name whenever it likes;
            // watch the title and put ours back. apply() only writes when the
            // value differs, so this cannot loop.
            titleObservation = window.observe(\.title, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async {
                    self.map { $0.apply($0.pending) }
                }
            }
        }

        func apply(_ title: String) {
            pending = title
            if let window, window.title != title {
                window.title = title
            }
        }
    }
}

struct TOCSidebar: View {
    let entries: [TOCEntry]
    let onSelect: (String) -> Void

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Headings",
                    systemImage: "list.bullet.indent",
                    description: Text("Headings in the document appear here.")
                )
            } else {
                List(entries) { entry in
                    Button {
                        onSelect(entry.id)
                    } label: {
                        Text(entry.title)
                            .font(entry.level == 1 ? .callout.weight(.semibold) : .callout)
                            .foregroundStyle(entry.level <= 2 ? .primary : .secondary)
                            .lineLimit(2)
                            .padding(.leading, CGFloat(max(0, entry.level - 1)) * 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.sidebar)
            }
        }
        .navigationTitle("Contents")
    }
}
