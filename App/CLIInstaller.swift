import AppKit

/// Installs (and keeps current) the `stimd` command-line shim in ~/.local/bin
/// on every launch. The shim opens files in the app by bundle id, and accepts
/// piped stdin by spooling it to a temp .md file.
enum CLIInstaller {
    static let script = #"""
    #!/bin/sh
    # stimd — open Markdown in the stimd viewer.
    # Usage: stimd <file.md ...>   or   some-command | stimd
    BUNDLE_ID="com.stimma.stimd"
    if [ $# -gt 0 ]; then
        exec open -b "$BUNDLE_ID" "$@"
    fi
    if [ -t 0 ]; then
        echo "usage: stimd <file.md ...>   (or pipe markdown to stimd)" >&2
        exit 64
    fi
    dir=$(mktemp -d "${TMPDIR:-/tmp}/stimd.XXXXXX") || exit 1
    tmp="$dir/Piped at $(date '+%-I.%M %p').md"
    cat > "$tmp"
    # Name the file after the document's # title when it has one.
    title=$(sed -n 's/^#[[:space:]][[:space:]]*//p' "$tmp" | head -n 1 | cut -c1-60 | tr '/:' '--')
    if [ -n "$title" ]; then
        mv "$tmp" "$dir/$title.md"
        tmp="$dir/$title.md"
    fi
    exec open -b "$BUNDLE_ID" "$tmp"

    """#

    static var destination: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/stimd")
    }

    static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: destination.path)
    }

    static func installIfNeeded() {
        let dest = destination

        if let existing = try? String(contentsOf: dest, encoding: .utf8), existing == script {
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: dest.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try script.write(to: dest, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: dest.path
            )
            NSLog("stimd: installed CLI shim at %@", dest.path)
        } catch {
            NSLog("stimd: CLI shim install failed: %@", error.localizedDescription)
        }
    }

    /// Removes the shim, but only if it's actually ours.
    static func uninstall() {
        let dest = destination
        guard let existing = try? String(contentsOf: dest, encoding: .utf8),
              existing.hasPrefix("#!/bin/sh\n# stimd — open Markdown") else {
            return
        }
        try? FileManager.default.removeItem(at: dest)
        NSLog("stimd: removed CLI shim at %@", dest.path)
    }
}
