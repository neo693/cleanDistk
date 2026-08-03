import Foundation

public struct ScanProgress: Equatable {
    public var filesScanned: Int = 0
    public var directoriesScanned: Int = 0
    public var currentScanningPath: String = ""
    public var sizeScanned: Int64 = 0

    public init(
        filesScanned: Int = 0,
        directoriesScanned: Int = 0,
        currentScanningPath: String = "",
        sizeScanned: Int64 = 0
    ) {
        self.filesScanned = filesScanned
        self.directoriesScanned = directoriesScanned
        self.currentScanningPath = currentScanningPath
        self.sizeScanned = sizeScanned
    }
}

public struct ScanOptions {
    public var skipHiddenFiles: Bool = true
    public var skipPackages: Bool = true
    public var skipSymbolicLinks: Bool = true
    public var maxChildrenPerDirectory: Int = 300
    public var minDisplaySize: Int64 = 1024 * 1024 // 1 MB
    public var ignoredPaths: [String] = []

    public init(
        skipHiddenFiles: Bool = true,
        skipPackages: Bool = true,
        skipSymbolicLinks: Bool = true,
        maxChildrenPerDirectory: Int = 300,
        minDisplaySize: Int64 = 1024 * 1024,
        ignoredPaths: [String] = []
    ) {
        self.skipHiddenFiles = skipHiddenFiles
        self.skipPackages = skipPackages
        self.skipSymbolicLinks = skipSymbolicLinks
        self.maxChildrenPerDirectory = maxChildrenPerDirectory
        self.minDisplaySize = minDisplaySize
        self.ignoredPaths = ignoredPaths
    }
}

public final class DiskScanner {
    private let fileManager = FileManager.default
    private var progressCallback: ((ScanProgress) -> Void)?
    private var errorCallback: ((ScanError) -> Void)?

    // Throttling state
    private var filesScannedSinceLastUpdate = 0
    private var lastUpdateTime = Date.distantPast
    private var currentProgress = ScanProgress()

    public init() {}

    public func scan(
        url: URL,
        options: ScanOptions,
        onProgress: @escaping (ScanProgress) -> Void,
        onError: @escaping (ScanError) -> Void
    ) async -> DiskNode {
        self.progressCallback = onProgress
        self.errorCallback = onError
        self.filesScannedSinceLastUpdate = 0
        self.lastUpdateTime = Date()
        self.currentProgress = ScanProgress(currentScanningPath: url.path)

        return await scanNode(url: url, options: options)
    }

    private func scanNode(url: URL, options: ScanOptions) async -> DiskNode {
        // Support cancellation
        if Task.isCancelled {
            return DiskNode(name: url.lastPathComponent, url: url, size: 0, allocatedSize: 0, isDirectory: false)
        }

        let isHidden = url.lastPathComponent.hasPrefix(".")
        if options.skipHiddenFiles && isHidden && url.lastPathComponent != "." && url.lastPathComponent != ".." {
            return DiskNode(name: url.lastPathComponent, url: url, size: 0, allocatedSize: 0, isDirectory: false)
        }

        // Check ignored paths
        let path = url.path
        if options.ignoredPaths.contains(where: { path.hasPrefix($0) }) {
            return DiskNode(name: url.lastPathComponent, url: url, size: 0, allocatedSize: 0, isDirectory: false)
        }

        var isDirectory = false
        var isPackage = false
        var isSymLink = false
        var size: Int64 = 0
        var allocatedSize: Int64 = 0
        var modifiedAt: Date?

        do {
            let keys: Set<URLResourceKey> = [
                .isDirectoryKey,
                .isPackageKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
                .totalFileAllocatedSizeKey,
                .contentModificationDateKey
            ]
            let values = try url.resourceValues(forKeys: keys)

            isDirectory = values.isDirectory ?? false
            isPackage = values.isPackage ?? false
            isSymLink = values.isSymbolicLink ?? false
            size = Int64(values.fileSize ?? 0)
            allocatedSize = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            modifiedAt = values.contentModificationDate
        } catch {
            let scanError = ScanError(url: url, message: error.localizedDescription)
            errorCallback?(scanError)
            return DiskNode(
                name: url.lastPathComponent,
                url: url,
                size: 0,
                allocatedSize: 0,
                isDirectory: false,
                error: error.localizedDescription
            )
        }

        if isSymLink && options.skipSymbolicLinks {
            return DiskNode(name: url.lastPathComponent, url: url, size: 0, allocatedSize: 0, isDirectory: false)
        }

        // Increment count and update progress
        throttleProgressUpdate(path: path, size: isDirectory ? 0 : allocatedSize, isDirectory: isDirectory)

        // Package treatment
        if isPackage && options.skipPackages {
            // Treat package as a single file, don't dive in
            return DiskNode(
                name: url.lastPathComponent,
                url: url,
                size: size,
                allocatedSize: allocatedSize,
                isDirectory: false,
                isPackage: true,
                modifiedAt: modifiedAt
            )
        }

        if !isDirectory {
            return DiskNode(
                name: url.lastPathComponent,
                url: url,
                size: size,
                allocatedSize: allocatedSize,
                isDirectory: false,
                isPackage: isPackage,
                modifiedAt: modifiedAt
            )
        }

        // Directory traversal
        var childrenNodes: [DiskNode] = []
        var totalSize: Int64 = 0
        var totalAllocatedSize: Int64 = 0
        var fileCount = 0
        var dirCount = 0
        var errorString: String? = nil

        do {
            let properties: [URLResourceKey] = [.nameKey, .isDirectoryKey]
            let contents = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: properties,
                options: [.skipsSubdirectoryDescendants]
            )

            // Recursively scan children
            var rawChildren: [DiskNode] = []
            for childURL in contents {
                if Task.isCancelled { break }
                let childNode = await scanNode(url: childURL, options: options)
                if childNode.size > 0 || childNode.allocatedSize > 0 || childNode.isDirectory || childNode.error != nil {
                    rawChildren.append(childNode)
                }
            }

            // Aggregate metrics
            for child in rawChildren {
                totalSize += child.size
                totalAllocatedSize += child.allocatedSize
                if child.isDirectory {
                    dirCount += 1 + child.directoryCount
                    fileCount += child.fileCount
                } else {
                    fileCount += 1
                }
            }

            // Sort by allocated size descending
            rawChildren.sort { $0.allocatedSize > $1.allocatedSize }

            // Apply size threshold filtering / grouping
            var displayedChildren: [DiskNode] = []
            var smallFilesSize: Int64 = 0
            var smallFilesAllocatedSize: Int64 = 0
            var smallFilesCount = 0

            for child in rawChildren {
                if !child.isDirectory && child.allocatedSize < options.minDisplaySize {
                    smallFilesSize += child.size
                    smallFilesAllocatedSize += child.allocatedSize
                    smallFilesCount += 1
                } else {
                    displayedChildren.append(child)
                }
            }

            // If we have small files, add a virtual node
            if smallFilesCount > 0 {
                let virtualNode = DiskNode(
                    name: "[\(smallFilesCount) Small Files]",
                    url: url.appendingPathComponent("VirtualSmallFilesGroupNode"),
                    size: smallFilesSize,
                    allocatedSize: smallFilesAllocatedSize,
                    isDirectory: false,
                    fileCount: smallFilesCount
                )
                displayedChildren.append(virtualNode)
            }

            // Re-sort displays
            displayedChildren.sort { $0.allocatedSize > $1.allocatedSize }

            // Cap items list per directory to keep UI fast
            if displayedChildren.count > options.maxChildrenPerDirectory {
                let keep = Array(displayedChildren.prefix(options.maxChildrenPerDirectory))
                let extra = Array(displayedChildren.suffix(displayedChildren.count - options.maxChildrenPerDirectory))
                let extraSize = extra.reduce(0) { $0 + $1.size }
                let extraAllocated = extra.reduce(0) { $0 + $1.allocatedSize }
                let extraFiles = extra.reduce(0) { $0 + ($1.isDirectory ? $1.fileCount : 1) }

                var finalChildren = keep
                let otherNode = DiskNode(
                    name: "[Other (\(extra.count) items)]",
                    url: url.appendingPathComponent("VirtualOtherGroupNode"),
                    size: extraSize,
                    allocatedSize: extraAllocated,
                    isDirectory: false,
                    fileCount: extraFiles
                )
                finalChildren.append(otherNode)
                childrenNodes = finalChildren
            } else {
                childrenNodes = displayedChildren
            }

        } catch {
            errorString = error.localizedDescription
            let scanError = ScanError(url: url, message: error.localizedDescription)
            errorCallback?(scanError)
        }

        return DiskNode(
            name: url.lastPathComponent,
            url: url,
            size: totalSize,
            allocatedSize: totalAllocatedSize,
            isDirectory: true,
            children: childrenNodes.isEmpty ? nil : childrenNodes,
            fileCount: fileCount,
            directoryCount: dirCount,
            error: errorString,
            isPackage: isPackage,
            modifiedAt: modifiedAt
        )
    }

    private func throttleProgressUpdate(path: String, size: Int64, isDirectory: Bool) {
        currentProgress.filesScanned += isDirectory ? 0 : 1
        currentProgress.directoriesScanned += isDirectory ? 1 : 0
        currentProgress.sizeScanned += size
        currentProgress.currentScanningPath = path

        filesScannedSinceLastUpdate += 1

        let now = Date()
        let timePassed = now.timeIntervalSince(lastUpdateTime)

        // Throttle updates: update progress callback at most once every 100ms or 500 files
        if timePassed >= 0.1 || filesScannedSinceLastUpdate >= 500 {
            let progress = currentProgress
            filesScannedSinceLastUpdate = 0
            lastUpdateTime = now
            // Schedule callback on MainActor
            DispatchQueue.main.async { [weak self] in
                self?.progressCallback?(progress)
            }
        }
    }
}
