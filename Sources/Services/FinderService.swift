import AppKit

public final class FinderService {
    public init() {}

    public func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func openParentFolder(of url: URL) {
        let parent = url.deletingLastPathComponent()
        NSWorkspace.shared.open(parent)
    }

    public func open(url: URL) {
        NSWorkspace.shared.open(url)
    }
}
