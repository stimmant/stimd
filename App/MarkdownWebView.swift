import SwiftUI
import WebKit
import Combine
import UniformTypeIdentifiers

struct MarkdownWebView: NSViewRepresentable {
    @ObservedObject var model: DocModel
    let theme: DocTheme
    let zoom: Double
    let systemDark: Bool
    let width: ContentWidth
    let font: BodyFont

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Allow the loadHTMLString page (based at the document's directory) to
        // load relative images and other local resources referenced by the doc.
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsMagnification = true
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator

        context.coordinator.webView = webView
        context.coordinator.bind(model: model)
        context.coordinator.installScrollZoomMonitor()
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.apply(
            model: model, theme: theme, zoom: zoom, systemDark: systemDark,
            width: width, font: font
        )
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?

        private var cancellables: Set<AnyCancellable> = []
        private var scrollMonitor: Any?
        private var pageLoaded = false
        private var pendingJS: [String] = []

        private var lastBody: String?
        private var lastThemeName: String?
        private var lastMermaidTheme: String?
        private var lastZoom: Double?
        private var lastWidth: ContentWidth?
        private var lastFont: BodyFont?
        private var baseURL: URL?

        func bind(model: DocModel) {
            cancellables.removeAll()
            model.anchorClicks
                .sink { [weak self] anchor in
                    self?.runJS("window.mdv.scrollToAnchor(\(jsString(anchor)));")
                }
                .store(in: &cancellables)
            model.requests
                .sink { [weak self] request in
                    switch request {
                    case .printPanel: self?.runPrintPanel()
                    case .exportPDF: self?.exportPDF()
                    }
                }
                .store(in: &cancellables)
        }

        func teardown() {
            cancellables.removeAll()
            if let monitor = scrollMonitor {
                NSEvent.removeMonitor(monitor)
                scrollMonitor = nil
            }
        }

        // MARK: - Content / theme / zoom application

        func apply(
            model: DocModel, theme: DocTheme, zoom: Double, systemDark: Bool,
            width: ContentWidth, font: BodyFont
        ) {
            guard let webView else { return }
            let themeName = theme.rawValue
            let mermaidTheme = theme.mermaidTheme(systemDark: systemDark)
            let body = model.rendered.bodyHTML

            if lastBody == nil {
                // First load: full page with everything inlined.
                baseURL = model.fileURL?.deletingLastPathComponent()
                let page = PageTemplate.appPage(
                    body: body,
                    themeName: themeName,
                    mermaidTheme: mermaidTheme,
                    zoom: zoom,
                    width: width.rawValue,
                    font: font.rawValue
                )
                webView.pageZoom = zoom
                webView.loadHTMLString(page, baseURL: baseURL)
                lastBody = body
                lastThemeName = themeName
                lastMermaidTheme = mermaidTheme
                lastZoom = zoom
                lastWidth = width
                lastFont = font
                return
            }

            if zoom != lastZoom {
                webView.pageZoom = zoom
                lastZoom = zoom
            }

            if themeName != lastThemeName {
                runJS("window.mdv.setTheme(\(jsString(themeName)));")
                lastThemeName = themeName
            }

            if width != lastWidth {
                runJS("window.mdv.setWidth(\(jsString(width.rawValue)));")
                lastWidth = width
            }

            if font != lastFont {
                runJS("window.mdv.setFont(\(jsString(font.rawValue)));")
                lastFont = font
            }

            if body != lastBody || mermaidTheme != lastMermaidTheme {
                runJS("window.mdv.update(\(jsString(body)), \(jsString(mermaidTheme)));")
                lastBody = body
                lastMermaidTheme = mermaidTheme
            }
        }

        private func runJS(_ script: String) {
            guard pageLoaded else {
                pendingJS.append(script)
                return
            }
            webView?.evaluateJavaScript(script, completionHandler: nil)
        }

        nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pageLoaded = true
                let queued = self.pendingJS
                self.pendingJS = []
                for js in queued {
                    self.webView?.evaluateJavaScript(js, completionHandler: nil)
                }
            }
        }

        // MARK: - Link handling

        nonisolated func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            // Same-document anchor navigation stays in the web view.
            if url.fragment != nil,
               let current = navigationAction.request.mainDocumentURL,
               url.absoluteString.hasPrefix(current.absoluteString.components(separatedBy: "#")[0]) {
                decisionHandler(.allow)
                return
            }

            decisionHandler(.cancel)
            DispatchQueue.main.async {
                if url.isFileURL {
                    if ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn"].contains(url.pathExtension.lowercased()) {
                        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
                    } else {
                        NSWorkspace.shared.open(url)
                    }
                } else {
                    NSWorkspace.shared.open(url)
                }
            }
        }

        // MARK: - ⌘+scroll zoom

        func installScrollZoomMonitor() {
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let webView = self.webView,
                      event.modifierFlags.contains(.command),
                      event.window === webView.window else {
                    return event
                }
                let point = webView.convert(event.locationInWindow, from: nil)
                guard webView.bounds.contains(point) else { return event }

                let delta = event.scrollingDeltaY
                if delta != 0 {
                    ZoomControl.step(delta > 0 ? 1.04 : 1 / 1.04)
                }
                return nil
            }
        }

        // MARK: - Print / PDF export

        func runPrintPanel() {
            guard let webView, let window = webView.window else { return }
            let printInfo = NSPrintInfo()
            printInfo.horizontalPagination = .fit
            printInfo.verticalPagination = .automatic
            printInfo.isHorizontallyCentered = true
            printInfo.isVerticallyCentered = false
            printInfo.topMargin = 36
            printInfo.bottomMargin = 36
            printInfo.leftMargin = 32
            printInfo.rightMargin = 32

            let operation = webView.printOperation(with: printInfo)
            operation.showsPrintPanel = true
            operation.showsProgressPanel = true
            // WKWebView's print view needs a nonzero frame or pages come out blank.
            operation.view?.frame = NSRect(x: 0, y: 0, width: 612, height: 792)
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        }

        func exportPDF() {
            guard let webView, let window = webView.window else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            let docName = webView.title?.isEmpty == false ? webView.title! : "Document"
            panel.nameFieldStringValue = (window.title.isEmpty ? docName : window.title) + ".pdf"
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                webView.createPDF { result in
                    switch result {
                    case .success(let data):
                        try? data.write(to: url)
                    case .failure(let error):
                        let alert = NSAlert(error: error)
                        alert.runModal()
                    }
                }
            }
        }
    }
}

private func jsString(_ s: String) -> String {
    guard let data = try? JSONEncoder().encode([s]),
          let json = String(data: data, encoding: .utf8) else {
        return "\"\""
    }
    return String(json.dropFirst().dropLast())
}
