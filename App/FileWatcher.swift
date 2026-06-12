import Foundation

/// Watches a file for changes (including atomic save/rename, which most
/// editors use) and fires a debounced callback ~50ms after the last event.
final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var debounce: DispatchWorkItem?
    private var retryCount = 0

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        start()
    }

    deinit {
        source?.cancel()
        debounce?.cancel()
    }

    private func start() {
        source?.cancel()
        source = nil

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            scheduleRetry()
            return
        }
        retryCount = 0

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete, .attrib, .link],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            guard let self, let src = self.source else { return }
            let events = src.data
            if events.contains(.delete) || events.contains(.rename) || events.contains(.link) {
                // Atomic save: the inode we watch was replaced. Re-attach to the path.
                self.start()
            }
            self.fire()
        }
        src.setCancelHandler {
            close(fd)
        }
        source = src
        src.resume()
    }

    private func fire() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func scheduleRetry() {
        guard retryCount < 20 else { return }
        retryCount += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.start()
            self?.fire()
        }
    }
}
