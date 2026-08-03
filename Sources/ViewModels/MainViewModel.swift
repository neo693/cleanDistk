import Foundation
import Combine
import SwiftUI

public enum SidebarSelection: Hashable {
    case home
    case downloads
    case desktop
    case developerCleaner
    case browserCleaner
    case largeModelCleaner
    case appLeftovers
    case settings
    case customFolder(URL)
}

public enum ViewMode: String, CaseIterable, Identifiable {
    case fileList = "FileList"
    case tree = "Tree"
    case treemap = "Treemap"

    public var id: String { self.rawValue }
}

@MainActor
public final class MainViewModel: ObservableObject {
    // UI state
    @Published var sidebarSelection: SidebarSelection = .home {
        didSet {
            selectedNode = nil
            cancelScan()
            if let url = selectedFolderURL {
                rootNode = scanResults[url]
            } else {
                rootNode = nil
            }
        }
    }
    @Published var viewMode: ViewMode = .fileList
    @Published var selectedNode: DiskNode?

    // Cache for folder scan results
    private var scanResults: [URL: DiskNode] = [:]

    // Active FSEvents watchers by watched URL
    private var watchers: [URL: FileSystemWatcher] = [:]

    // Scanning state
    @Published var isScanning = false
    @Published var scanProgress = ScanProgress()
    @Published var scanErrors: [ScanError] = []
    @Published var rootNode: DiskNode?
    private var scanTask: Task<Void, Never>?

    // Developer cache states
    @Published var developerItems: [CleanerItem] = DeveloperCleanerScanner.defaultRules
    @Published var isScanningDeveloper = false
    @Published var selectedDeveloperItem: CleanerItem?
    private var devScanTask: Task<Void, Never>?

    // Browser cache states
    @Published var browserItems: [CleanerItem] = BrowserCleanerScanner.defaultRules
    @Published var isScanningBrowser = false
    private var browserScanTask: Task<Void, Never>?

    // Large model states
    @Published var largeModelItems: [CleanerItem] = []
    @Published var isScanningLargeModels = false
    private var largeModelScanTask: Task<Void, Never>?

    // Uninstalled app leftover states
    @Published var appLeftoverItems: [CleanerItem] = []
    @Published var isScanningAppLeftovers = false
    private var appLeftoverScanTask: Task<Void, Never>?

    // Settings (UserDefaults backed)
    @Published var skipHiddenFiles: Bool {
        didSet {
            UserDefaults.standard.set(skipHiddenFiles, forKey: "skipHiddenFiles")
            saveOptions()
        }
    }
    @Published var skipPackages: Bool {
        didSet {
            UserDefaults.standard.set(skipPackages, forKey: "skipPackages")
            saveOptions()
        }
    }
    @Published var minDisplaySize: Int64 {
        didSet {
            UserDefaults.standard.set(minDisplaySize, forKey: "minDisplaySize")
            saveOptions()
        }
    }
    @Published var customIgnorePaths: [String] {
        didSet {
            UserDefaults.standard.set(customIgnorePaths, forKey: "customIgnorePaths")
            saveOptions()
        }
    }

    public var scanOptions = ScanOptions()

    // Services
    private let scanner = DiskScanner()
    private let trashManager = TrashManager()
    private let finderService = FinderService()
    private let devScanner = DeveloperCleanerScanner()
    private let largeModelScanner = LargeModelCleanerScanner()
    private let appLeftoverScanner = AppLeftoverScanner()

    public init() {
        // Load settings from UserDefaults or default
        UserDefaults.standard.register(defaults: [
            "skipHiddenFiles": true,
            "skipPackages": true,
            "minDisplaySize": Int64(1024 * 1024), // 1MB
            "customIgnorePaths": [
                "/System", "/private", "/Volumes", "/Network", "/usr", "/bin", "/sbin", "/dev"
            ]
        ])

        self.skipHiddenFiles = UserDefaults.standard.bool(forKey: "skipHiddenFiles")
        self.skipPackages = UserDefaults.standard.bool(forKey: "skipPackages")
        self.minDisplaySize = Int64(UserDefaults.standard.integer(forKey: "minDisplaySize"))
        self.customIgnorePaths = UserDefaults.standard.stringArray(forKey: "customIgnorePaths") ?? []

        saveOptions()

        #if DEBUG
        runSelfCheck()
        #endif
    }

    private func saveOptions() {
        self.scanOptions = ScanOptions(
            skipHiddenFiles: skipHiddenFiles,
            skipPackages: skipPackages,
            skipSymbolicLinks: true,
            maxChildrenPerDirectory: 300,
            minDisplaySize: minDisplaySize,
            ignoredPaths: customIgnorePaths
        )
    }

    // MARK: - Actions

    public func startScan(for url: URL) {
        cancelScan()
        isScanning = true
        rootNode = nil
        selectedNode = nil
        scanErrors.removeAll()
        scanProgress = ScanProgress(currentScanningPath: url.path)

        scanTask = Task {
            let result = await scanner.scan(
                url: url,
                options: scanOptions,
                onProgress: { [weak self] progress in
                    guard let self = self else { return }
                    self.scanProgress = progress
                },
                onError: { [weak self] error in
                    guard let self = self else { return }
                    self.scanErrors.append(error)
                }
            )

            if !Task.isCancelled {
                self.scanResults[url] = result
                if self.selectedFolderURL == url {
                    self.rootNode = result
                }
                self.isScanning = false
                self.startWatching(url: url)
            }
        }
    }

    public func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    public func startScanDeveloper() {
        devScanTask?.cancel()
        isScanningDeveloper = true
        selectedDeveloperItem = nil

        // Set scanning status on items
        for i in 0..<developerItems.count {
            developerItems[i].isScanning = true
        }

        devScanTask = Task {
            let updated = await devScanner.scan(items: developerItems) { [weak self] itemId, size in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    if let index = self.developerItems.firstIndex(where: { $0.id == itemId }) {
                        self.developerItems[index].detectedSize = size
                        self.developerItems[index].isScanning = false
                    }
                }
            }

            if !Task.isCancelled {
                self.developerItems = updated
                self.isScanningDeveloper = false
            }
        }
    }

    public func cancelScanDeveloper() {
        devScanTask?.cancel()
        devScanTask = nil
        isScanningDeveloper = false
        for i in 0..<developerItems.count {
            developerItems[i].isScanning = false
        }
    }

    public func startScanBrowser() {
        browserScanTask?.cancel()
        isScanningBrowser = true

        for i in 0..<browserItems.count {
            browserItems[i].isScanning = true
        }

        browserScanTask = Task {
            let updated = await devScanner.scan(items: browserItems) { [weak self] itemId, size in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    if let index = self.browserItems.firstIndex(where: { $0.id == itemId }) {
                        self.browserItems[index].detectedSize = size
                        self.browserItems[index].isScanning = false
                    }
                }
            }

            if !Task.isCancelled {
                self.browserItems = updated
                self.isScanningBrowser = false
            }
        }
    }

    public func cancelScanBrowser() {
        browserScanTask?.cancel()
        browserScanTask = nil
        isScanningBrowser = false
        for i in 0..<browserItems.count {
            browserItems[i].isScanning = false
        }
    }

    public func startScanLargeModels() {
        largeModelScanTask?.cancel()
        isScanningLargeModels = true
        largeModelItems.removeAll()

        largeModelScanTask = Task {
            let updated = await largeModelScanner.scan { [weak self] itemId, size in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    if let index = self.largeModelItems.firstIndex(where: { $0.id == itemId }) {
                        self.largeModelItems[index].detectedSize = size
                        self.largeModelItems[index].isScanning = false
                    }
                }
            }

            if !Task.isCancelled {
                self.largeModelItems = updated
                self.isScanningLargeModels = false
            }
        }
    }

    public func cancelScanLargeModels() {
        largeModelScanTask?.cancel()
        largeModelScanTask = nil
        isScanningLargeModels = false
        for i in 0..<largeModelItems.count {
            largeModelItems[i].isScanning = false
        }
    }

    public func startScanAppLeftovers() {
        appLeftoverScanTask?.cancel()
        isScanningAppLeftovers = true
        appLeftoverItems.removeAll()

        appLeftoverScanTask = Task {
            let updated = await appLeftoverScanner.scan { [weak self] itemId, size in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    if let index = self.appLeftoverItems.firstIndex(where: { $0.id == itemId }) {
                        self.appLeftoverItems[index].detectedSize = size
                        self.appLeftoverItems[index].isScanning = false
                    }
                }
            }

            if !Task.isCancelled {
                self.appLeftoverItems = updated
                self.isScanningAppLeftovers = false
            }
        }
    }

    public func cancelScanAppLeftovers() {
        appLeftoverScanTask?.cancel()
        appLeftoverScanTask = nil
        isScanningAppLeftovers = false
        for i in 0..<appLeftoverItems.count {
            appLeftoverItems[i].isScanning = false
        }
    }

    // MARK: - Operations

    public func revealInFinder(url: URL) {
        finderService.reveal(url)
    }

    public func openParentFolder(of url: URL) {
        finderService.openParentFolder(of: url)
    }

    public func recycleNode(_ node: DiskNode) async throws {
        // Prevent deleting virtual group nodes
        if node.name.hasPrefix("[") && node.name.hasSuffix("]") {
            return
        }

        try await trashManager.recycle([node.url])

        // Instantly update tree in UI
        if let root = rootNode {
            let updated = removeNode(withId: node.id, from: root)
            rootNode = updated
            if let url = selectedFolderURL {
                scanResults[url] = updated
            }
        }

        // If selected node was the one deleted, deselect it
        if selectedNode?.id == node.id {
            selectedNode = nil
        }
    }

    public func recycleNodes(_ nodes: [DiskNode]) async throws {
        let targets = nodes.filter { node in
            !(node.name.hasPrefix("[") && node.name.hasSuffix("]"))
        }
        guard !targets.isEmpty else { return }

        try await trashManager.recycle(targets.map(\.url))

        if let root = rootNode {
            var updatedRoot: DiskNode? = root
            for node in targets {
                if let currentRoot = updatedRoot {
                    updatedRoot = removeNode(withId: node.id, from: currentRoot)
                }
            }
            rootNode = updatedRoot
            if let url = selectedFolderURL {
                scanResults[url] = updatedRoot
            }
        }

        if let selectedNode, targets.contains(where: { $0.id == selectedNode.id }) {
            self.selectedNode = nil
        }
    }

    public func recycleDeveloperItem(_ item: CleanerItem) async throws {
        if item.isDocker {
            let commandString: String
            switch item.path {
            case "DOCKER_CONTAINERS":
                commandString = "docker container prune -f"
            case "DOCKER_DANGLING_IMAGES":
                commandString = "docker image prune -f"
            case "DOCKER_BUILD_CACHE":
                commandString = "docker builder prune -f"
            case "DOCKER_UNUSED_IMAGES":
                commandString = "docker image prune -a -f"
            case "DOCKER_VOLUMES":
                commandString = "docker volume prune -f"
            default:
                return
            }

            try await Task.detached(priority: .background) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-c", commandString]
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    throw NSError(
                        domain: "DockerError",
                        code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: "Docker command failed with exit code \(process.terminationStatus)"]
                    )
                }
            }.value

            // Update item size in UI
            if let index = developerItems.firstIndex(where: { $0.id == item.id }) {
                developerItems[index].detectedSize = 0
            }
            if selectedDeveloperItem?.id == item.id {
                selectedDeveloperItem?.detectedSize = 0
            }
            return
        }

        guard item.exists else { return }
        try await trashManager.recycle([item.resolvedURL])

        // Update item size in UI
        if let index = developerItems.firstIndex(where: { $0.id == item.id }) {
            developerItems[index].detectedSize = 0
        }
        if selectedDeveloperItem?.id == item.id {
            selectedDeveloperItem?.detectedSize = 0
        }
    }

    public func recycleBrowserItem(_ item: CleanerItem) async throws {
        guard item.exists else { return }
        try await trashManager.recycle([item.resolvedURL])

        if let index = browserItems.firstIndex(where: { $0.id == item.id }) {
            browserItems[index].detectedSize = 0
        }
    }

    public func recycleLargeModelItem(_ item: CleanerItem) async throws {
        guard item.exists else { return }
        try await trashManager.recycle([item.resolvedURL])

        largeModelItems.removeAll { $0.id == item.id }
    }

    public func recycleAppLeftoverItem(_ item: CleanerItem) async throws {
        guard item.exists else { return }
        try await trashManager.recycle([item.resolvedURL])

        if let index = appLeftoverItems.firstIndex(where: { $0.id == item.id }) {
            appLeftoverItems[index].detectedSize = 0
        }
    }

    // Helper to recursively remove a deleted node from tree and update sizes
    private func removeNode(withId id: UUID, from parent: DiskNode) -> DiskNode? {
        removeNodeAndStats(withId: id, from: parent).node
    }

    private func removeNodeAndStats(
        withId id: UUID,
        from node: DiskNode
    ) -> (node: DiskNode?, size: Int64, allocatedSize: Int64, files: Int, directories: Int, changed: Bool) {
        if node.id == id {
            return (
                nil,
                node.size,
                node.allocatedSize,
                node.isDirectory ? node.fileCount : 1,
                node.isDirectory ? node.directoryCount + 1 : 0,
                true
            )
        }

        guard let children = node.children else {
            return (node, 0, 0, 0, 0, false)
        }

        var updatedChildren: [DiskNode] = []
        var removedSize: Int64 = 0
        var removedAllocatedSize: Int64 = 0
        var removedFiles = 0
        var removedDirectories = 0
        var changed = false

        for child in children {
            let result = removeNodeAndStats(withId: id, from: child)
            if let updatedChild = result.node {
                updatedChildren.append(updatedChild)
            }
            removedSize += result.size
            removedAllocatedSize += result.allocatedSize
            removedFiles += result.files
            removedDirectories += result.directories
            changed = changed || result.changed
        }

        guard changed else {
            return (node, 0, 0, 0, 0, false)
        }

        var updated = node
        updated.children = updatedChildren.isEmpty ? nil : updatedChildren
        updated.size = max(0, updated.size - removedSize)
        updated.allocatedSize = max(0, updated.allocatedSize - removedAllocatedSize)
        updated.fileCount = max(0, updated.fileCount - removedFiles)
        updated.directoryCount = max(0, updated.directoryCount - removedDirectories)

        return (updated, removedSize, removedAllocatedSize, removedFiles, removedDirectories, true)
    }

    // MARK: - Utility

    public var selectedFolderURL: URL? {
        switch sidebarSelection {
        case .home:
            return URL(fileURLWithPath: NSHomeDirectory())
        case .downloads:
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        case .desktop:
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        case .customFolder(let url):
            return url
        default:
            return nil
        }
    }

    // MARK: - FSEvents Real-time Synchronization

    private func startWatching(url: URL) {
        // Stop any old watcher on this path
        watchers[url]?.stop()

        let watcher = FileSystemWatcher(path: url.path) { [weak self] changedPath in
            guard let self = self else { return }
            Task { @MainActor in
                await self.handleFileChange(at: changedPath, underRoot: url)
            }
        }
        watcher.start()
        watchers[url] = watcher
    }

    private func handleFileChange(at changedPath: String, underRoot rootURL: URL) async {
        let changedURL = URL(fileURLWithPath: changedPath)
        
        guard isPath(changedURL.path, insideOrEqualTo: rootURL.path) else { return }

        var parentURL = changedURL
        var isDir: ObjCBool = false
        while !FileManager.default.fileExists(atPath: parentURL.path, isDirectory: &isDir) || !isDir.boolValue {
            if parentURL.path == rootURL.path {
                break
            }
            parentURL.deleteLastPathComponent()
        }

        guard isPath(parentURL.path, insideOrEqualTo: rootURL.path) else { return }

        // Perform local re-scan
        let localScanner = DiskScanner()
        let updatedSubtree = await localScanner.scan(
            url: parentURL,
            options: self.scanOptions,
            onProgress: { _ in },
            onError: { _ in }
        )

        // Sync the updated subtree into our overall tree state
        self.updateSubtree(at: parentURL, with: updatedSubtree, underRoot: rootURL)
    }

    private func updateSubtree(at targetURL: URL, with newSubtree: DiskNode, underRoot rootURL: URL) {
        guard let currentRoot = scanResults[rootURL] else { return }

        // If target directory is the root itself, replace rootNode
        if targetURL.path == rootURL.path {
            scanResults[rootURL] = newSubtree
            if selectedFolderURL == rootURL {
                self.rootNode = newSubtree
            }
            return
        }

        // Find the old subtree node to calculate size differences
        guard let oldNode = findNode(withURL: targetURL, in: currentRoot) else {
            if targetURL.path != rootURL.path {
                // ponytail: fallback full-root rescan for omitted/truncated nodes; upgrade to path-indexed nodes if scans get too slow.
                Task {
                    let localScanner = DiskScanner()
                    let updatedRoot = await localScanner.scan(
                        url: rootURL,
                        options: self.scanOptions,
                        onProgress: { _ in },
                        onError: { _ in }
                    )
                    self.scanResults[rootURL] = updatedRoot
                    if self.selectedFolderURL == rootURL {
                        self.rootNode = updatedRoot
                    }
                }
            }
            return
        }
        
        let sizeDelta = newSubtree.size - oldNode.size
        let allocatedSizeDelta = newSubtree.allocatedSize - oldNode.allocatedSize
        let fileDelta = newSubtree.fileCount - oldNode.fileCount
        let dirDelta = newSubtree.directoryCount - oldNode.directoryCount

        // Bubble up changes
        if let updatedRoot = applyUpdateAndBubble(
            root: currentRoot,
            targetURL: targetURL,
            newSubtree: newSubtree,
            sizeDelta: sizeDelta,
            allocatedSizeDelta: allocatedSizeDelta,
            fileDelta: fileDelta,
            dirDelta: dirDelta
        ) {
            scanResults[rootURL] = updatedRoot
            if selectedFolderURL == rootURL {
                self.rootNode = updatedRoot
            }
        }
    }

    private func findNode(withURL url: URL, in root: DiskNode) -> DiskNode? {
        if root.url.path == url.path {
            return root
        }
        guard let children = root.children else { return nil }
        for child in children {
            if isPath(url.path, insideOrEqualTo: child.url.path) || isPath(child.url.path, insideOrEqualTo: url.path) {
                if let found = findNode(withURL: url, in: child) {
                    return found
                }
            }
        }
        return nil
    }

    private func applyUpdateAndBubble(
        root: DiskNode,
        targetURL: URL,
        newSubtree: DiskNode,
        sizeDelta: Int64,
        allocatedSizeDelta: Int64,
        fileDelta: Int,
        dirDelta: Int
    ) -> DiskNode? {
        if root.url.path == targetURL.path {
            return newSubtree
        }

        if isPath(targetURL.path, insideOrEqualTo: root.url.path) {
            guard let children = root.children else { return root }
            var updatedChildren: [DiskNode] = []
            var modified = false

            for child in children {
                if isPath(targetURL.path, insideOrEqualTo: child.url.path) || child.url.path == targetURL.path {
                    if let updatedChild = applyUpdateAndBubble(
                        root: child,
                        targetURL: targetURL,
                        newSubtree: newSubtree,
                        sizeDelta: sizeDelta,
                        allocatedSizeDelta: allocatedSizeDelta,
                        fileDelta: fileDelta,
                        dirDelta: dirDelta
                    ) {
                        updatedChildren.append(updatedChild)
                        modified = true
                    } else {
                        updatedChildren.append(child)
                    }
                } else {
                    updatedChildren.append(child)
                }
            }

            if modified {
                var updated = root
                updated.children = updatedChildren.sorted { $0.allocatedSize > $1.allocatedSize }
                updated.size = max(0, updated.size + sizeDelta)
                updated.allocatedSize = max(0, updated.allocatedSize + allocatedSizeDelta)
                updated.fileCount = max(0, updated.fileCount + fileDelta)
                updated.directoryCount = max(0, updated.directoryCount + dirDelta)
                return updated
            }
        }

        return nil
    }

    private func isPath(_ path: String, insideOrEqualTo rootPath: String) -> Bool {
        if path == rootPath { return true }
        let normalizedRoot = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return path.hasPrefix(normalizedRoot)
    }

    private func runSelfCheck() {
        let fileID = UUID()
        let file = DiskNode(
            id: fileID,
            name: "file.bin",
            url: URL(fileURLWithPath: "/tmp/root/child/file.bin"),
            size: 10,
            allocatedSize: 10,
            isDirectory: false
        )
        let child = DiskNode(
            name: "child",
            url: URL(fileURLWithPath: "/tmp/root/child"),
            size: 10,
            allocatedSize: 10,
            isDirectory: true,
            children: [file],
            fileCount: 1,
            directoryCount: 0
        )
        let root = DiskNode(
            name: "root",
            url: URL(fileURLWithPath: "/tmp/root"),
            size: 10,
            allocatedSize: 10,
            isDirectory: true,
            children: [child],
            fileCount: 1,
            directoryCount: 1
        )

        let updated = removeNode(withId: fileID, from: root)
        assert(updated?.allocatedSize == 0)
        assert(updated?.fileCount == 0)
        assert(isPath("/tmp/rooted/file", insideOrEqualTo: "/tmp/root") == false)
    }
}
