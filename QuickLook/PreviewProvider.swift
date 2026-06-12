import QuickLookUI
import UniformTypeIdentifiers

/// Data-based QuickLook preview: returns themed HTML that QuickLook renders
/// with its own WebKit instance — which executes the inlined highlight.js and
/// mermaid, so previews are full-fidelity. (A WKWebView cannot run inside a
/// QuickLook extension; its web content process is killed by the sandbox.)
/// The "media" mermaid theme resolves light/dark via prefers-color-scheme.
class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let data = try Data(contentsOf: request.fileURL)
        let text = String(decoding: data, as: UTF8.self)
        let rendered = MarkdownHTML.render(text)
        let html = PageTemplate.appPage(
            body: rendered.bodyHTML,
            themeName: "auto",
            mermaidTheme: "media",
            zoom: 1.0
        )

        return QLPreviewReply(
            dataOfContentType: .html,
            contentSize: CGSize(width: 820, height: 900)
        ) { reply in
            reply.title = request.fileURL.lastPathComponent
            reply.stringEncoding = .utf8
            return Data(html.utf8)
        }
    }
}
