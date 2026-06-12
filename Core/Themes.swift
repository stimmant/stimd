import Foundation

public enum DocTheme: String, CaseIterable, Identifiable {
    case auto = "auto"
    case githubLight = "github-light"
    case githubDark = "github-dark"
    case dracula = "dracula"
    case nord = "nord"
    case solarizedLight = "solarized-light"
    case solarizedDark = "solarized-dark"
    case oneDark = "one-dark"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto: return "Auto (System)"
        case .githubLight: return "GitHub Light"
        case .githubDark: return "GitHub Dark"
        case .dracula: return "Dracula"
        case .nord: return "Nord"
        case .solarizedLight: return "Solarized Light"
        case .solarizedDark: return "Solarized Dark"
        case .oneDark: return "One Dark"
        }
    }

    public func isDark(systemDark: Bool) -> Bool {
        switch self {
        case .auto: return systemDark
        case .githubLight, .solarizedLight: return false
        case .githubDark, .dracula, .nord, .solarizedDark, .oneDark: return true
        }
    }

    public func mermaidTheme(systemDark: Bool) -> String {
        isDark(systemDark: systemDark) ? "dark" : "default"
    }
}

public enum ContentWidth: String, CaseIterable, Identifiable {
    case narrow, medium, wide, full

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .narrow: return "Narrow"
        case .medium: return "Medium"
        case .wide: return "Wide"
        case .full: return "Full Width"
        }
    }
}

public enum BodyFont: String, CaseIterable, Identifiable {
    case sans, serif, mono

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .sans: return "System Sans"
        case .serif: return "Serif"
        case .mono: return "Monospace"
        }
    }
}
