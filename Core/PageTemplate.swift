import Foundation

public enum PageTemplate {
    static func bundleResource(_ name: String, _ ext: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let data = try? Data(contentsOf: url) else {
            return ""
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Full interactive page for the app: inlined CSS + highlight.js + mermaid,
    /// with a small `mdv` JS API for live updates, theming and TOC navigation.
    public static func appPage(
        body: String,
        themeName: String,
        mermaidTheme: String,
        zoom: Double,
        width: String = "medium",
        font: String = "sans"
    ) -> String {
        let css = bundleResource("theme", "css")
        let hljs = bundleResource("highlight.min", "js")
        let mermaid = bundleResource("mermaid.min", "js")
        return """
        <!doctype html>
        <html data-theme="\(themeName)" data-width="\(width)" data-font="\(font)">
        <head>
        <meta charset="utf-8">
        <style>\(css)</style>
        <script>\(hljs)</script>
        <script>\(mermaid)</script>
        </head>
        <body>
        <article id="content">\(body)</article>
        <script>
        (function () {
          function resolveMermaidTheme(t) {
            if (t === "media") {
              return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches
                ? 'dark' : 'default';
            }
            return t;
          }
          var state = { mermaidTheme: resolveMermaidTheme("\(mermaidTheme)") };

          function render() {
            document.querySelectorAll('#content pre code').forEach(function (el) {
              try { hljs.highlightElement(el); } catch (e) {}
            });
            var nodes = document.querySelectorAll('#content pre.mermaid');
            if (nodes.length > 0) {
              try {
                mermaid.initialize({ startOnLoad: false, theme: state.mermaidTheme, securityLevel: 'loose' });
                mermaid.run({ nodes: nodes });
              } catch (e) {}
            }
          }

          window.mdv = {
            update: function (html, mermaidTheme) {
              var y = window.scrollY;
              state.mermaidTheme = resolveMermaidTheme(mermaidTheme);
              document.getElementById('content').innerHTML = html;
              render();
              requestAnimationFrame(function () { window.scrollTo(0, y); });
            },
            setTheme: function (name) {
              document.documentElement.dataset.theme = name;
            },
            setWidth: function (name) {
              document.documentElement.dataset.width = name;
            },
            setFont: function (name) {
              document.documentElement.dataset.font = name;
            },
            scrollToAnchor: function (anchor) {
              var el = document.getElementById(anchor);
              if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
            }
          };

          render();
        })();
        </script>
        </body>
        </html>
        """
    }

    /// Static page for the QuickLook extension (no JavaScript allowed there).
    /// Uses the "auto" theme so it follows the system appearance via CSS.
    public static func quickLookPage(body: String) -> String {
        let css = bundleResource("theme", "css")
        return """
        <!doctype html>
        <html data-theme="auto">
        <head>
        <meta charset="utf-8">
        <style>\(css)</style>
        </head>
        <body>
        <article id="content">\(body)</article>
        </body>
        </html>
        """
    }
}
