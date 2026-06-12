import Foundation
import Markdown

public struct TOCEntry: Identifiable, Hashable {
    public let id: String
    public let level: Int
    public let title: String

    public init(id: String, level: Int, title: String) {
        self.id = id
        self.level = level
        self.title = title
    }
}

public struct RenderedMarkdown {
    public let bodyHTML: String
    public let toc: [TOCEntry]
    public let hasMermaid: Bool

    public static let empty = RenderedMarkdown(bodyHTML: "", toc: [], hasMermaid: false)
}

public enum MarkdownHTML {
    public static func render(_ text: String) -> RenderedMarkdown {
        let document = Document(parsing: text)
        var renderer = HTMLRenderer()
        let body = renderer.visit(document)
        return RenderedMarkdown(bodyHTML: body, toc: renderer.toc, hasMermaid: renderer.hasMermaid)
    }
}

func htmlEscape(_ s: String) -> String {
    var out = ""
    out.reserveCapacity(s.count)
    for ch in s {
        switch ch {
        case "&": out += "&amp;"
        case "<": out += "&lt;"
        case ">": out += "&gt;"
        case "\"": out += "&quot;"
        default: out.append(ch)
        }
    }
    return out
}

struct HTMLRenderer: MarkupVisitor {
    typealias Result = String

    var toc: [TOCEntry] = []
    var hasMermaid = false
    private var slugCounts: [String: Int] = [:]
    private var columnAlignments: [Markdown.Table.ColumnAlignment?] = []

    // MARK: - Helpers

    mutating func childrenHTML(_ markup: Markup) -> String {
        var out = ""
        for child in markup.children {
            out += visit(child)
        }
        return out
    }

    func plainText(_ markup: Markup) -> String {
        var out = ""
        for child in markup.children {
            if let text = child as? Markdown.Text {
                out += text.string
            } else if let code = child as? InlineCode {
                out += code.code
            } else {
                out += plainText(child)
            }
        }
        return out
    }

    mutating func slug(for title: String) -> String {
        var s = ""
        for ch in title.lowercased() {
            if ch.isLetter || ch.isNumber {
                s.append(ch)
            } else if ch.isWhitespace || ch == "-" || ch == "_" {
                s.append("-")
            }
        }
        while s.contains("--") { s = s.replacingOccurrences(of: "--", with: "-") }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if s.isEmpty { s = "section" }
        let n = slugCounts[s] ?? 0
        slugCounts[s] = n + 1
        return n == 0 ? s : "\(s)-\(n)"
    }

    // MARK: - Blocks

    mutating func defaultVisit(_ markup: Markup) -> String {
        childrenHTML(markup)
    }

    mutating func visitDocument(_ document: Document) -> String {
        childrenHTML(document)
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        let inner = childrenHTML(heading)
        let title = plainText(heading)
        let anchor = slug(for: title)
        if heading.level <= 4 {
            toc.append(TOCEntry(id: anchor, level: heading.level, title: title))
        }
        return "<h\(heading.level) id=\"\(anchor)\">\(inner)</h\(heading.level)>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        "<p>\(childrenHTML(paragraph))</p>\n"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        "<blockquote>\n\(childrenHTML(blockQuote))</blockquote>\n"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        let lang = (codeBlock.language ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        let code = codeBlock.code
        if lang == "mermaid" {
            hasMermaid = true
            return "<pre class=\"mermaid\">\(htmlEscape(code))</pre>\n"
        }
        let cls = lang.isEmpty ? "" : " class=\"language-\(htmlEscape(lang))\""
        return "<pre><code\(cls)>\(htmlEscape(code))</code></pre>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String {
        "<hr>\n"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String {
        html.rawHTML + "\n"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> String {
        "<ul>\n\(childrenHTML(unorderedList))</ul>\n"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> String {
        let start = orderedList.startIndex
        let attr = start == 1 ? "" : " start=\"\(start)\""
        return "<ol\(attr)>\n\(childrenHTML(orderedList))</ol>\n"
    }

    mutating func visitListItem(_ listItem: ListItem) -> String {
        var cls = ""
        var prefix = ""
        if let checkbox = listItem.checkbox {
            cls = " class=\"task-list-item\""
            let checked = checkbox == .checked ? " checked" : ""
            prefix = "<input type=\"checkbox\" disabled\(checked)>"
        }
        return "<li\(cls)>\(prefix)\(childrenHTML(listItem))</li>\n"
    }

    // MARK: - Tables

    mutating func visitTable(_ table: Markdown.Table) -> String {
        let saved = columnAlignments
        columnAlignments = table.columnAlignments
        defer { columnAlignments = saved }

        var html = "<table>\n<thead>\n<tr>"
        var col = 0
        for case let cell as Markdown.Table.Cell in table.head.children {
            html += cellHTML(cell, tag: "th", column: col)
            col += 1
        }
        html += "</tr>\n</thead>\n<tbody>\n"
        for case let row as Markdown.Table.Row in table.body.children {
            html += "<tr>"
            col = 0
            for case let cell as Markdown.Table.Cell in row.children {
                html += cellHTML(cell, tag: "td", column: col)
                col += 1
            }
            html += "</tr>\n"
        }
        html += "</tbody>\n</table>\n"
        return html
    }

    private mutating func cellHTML(_ cell: Markdown.Table.Cell, tag: String, column: Int) -> String {
        var style = ""
        if column < columnAlignments.count, let alignment = columnAlignments[column] {
            switch alignment {
            case .left: style = " style=\"text-align:left\""
            case .center: style = " style=\"text-align:center\""
            case .right: style = " style=\"text-align:right\""
            }
        }
        return "<\(tag)\(style)>\(childrenHTML(cell))</\(tag)>"
    }

    // MARK: - Inlines

    mutating func visitText(_ text: Markdown.Text) -> String {
        htmlEscape(text.string)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        "<em>\(childrenHTML(emphasis))</em>"
    }

    mutating func visitStrong(_ strong: Strong) -> String {
        "<strong>\(childrenHTML(strong))</strong>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        "<del>\(childrenHTML(strikethrough))</del>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        "<code>\(htmlEscape(inlineCode.code))</code>"
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> String {
        inlineHTML.rawHTML
    }

    mutating func visitLink(_ link: Markdown.Link) -> String {
        let dest = htmlEscape(link.destination ?? "#")
        return "<a href=\"\(dest)\">\(childrenHTML(link))</a>"
    }

    mutating func visitImage(_ image: Markdown.Image) -> String {
        let src = htmlEscape(image.source ?? "")
        let alt = htmlEscape(plainText(image))
        var title = ""
        if let t = image.title, !t.isEmpty {
            title = " title=\"\(htmlEscape(t))\""
        }
        return "<img src=\"\(src)\" alt=\"\(alt)\"\(title)>"
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String {
        "\n"
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String {
        "<br>\n"
    }

    mutating func visitSymbolLink(_ symbolLink: SymbolLink) -> String {
        "<code>\(htmlEscape(symbolLink.destination ?? ""))</code>"
    }
}
