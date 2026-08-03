import Foundation

public final class DeveloperCleanerScanner {
    public init() {}

    public static let defaultRules: [CleanerItem] = [
        // Xcode
        CleanerItem(
            id: "xcode-deriveddata",
            title: "Xcode DerivedData",
            path: "~/Library/Developer/Xcode/DerivedData",
            risk: .safe,
            description: "Xcode build cache. Completely safe to clear; Xcode will rebuild it on next run."
        ),
        CleanerItem(
            id: "xcode-archives",
            title: "Xcode Archives",
            path: "~/Library/Developer/Xcode/Archives",
            risk: .caution,
            description: "App archive builds. Review these as you might want to keep release binaries for symbolicating old crashes."
        ),
        CleanerItem(
            id: "xcode-simulators",
            title: "iOS Simulator Devices",
            path: "~/Library/Developer/CoreSimulator/Devices",
            risk: .caution,
            description: "iOS Simulator virtual device configurations. Clearing them deletes simulator app databases and configurations."
        ),
        // Node / JS
        CleanerItem(
            id: "npm-cache",
            title: "npm Cache",
            path: "~/.npm",
            risk: .safe,
            description: "npm global download caches. npm will re-download modules as needed."
        ),
        CleanerItem(
            id: "pnpm-store",
            title: "pnpm Store",
            path: "~/.pnpm-store",
            risk: .safe,
            description: "pnpm shared content addressable store. Deleting will force pnpm to re-fetch packages next time you install."
        ),
        CleanerItem(
            id: "yarn-cache",
            title: "Yarn Cache",
            path: "~/Library/Caches/yarn",
            risk: .safe,
            description: "Yarn package manager cache. Safe to remove."
        ),
        // Go
        CleanerItem(
            id: "go-build",
            title: "Go Build Cache",
            path: "~/Library/Caches/go-build",
            risk: .safe,
            description: "Go compiler build outputs cache. Completely safe to remove."
        ),
        CleanerItem(
            id: "go-modules",
            title: "Go Modules Cache",
            path: "~/go/pkg/mod",
            risk: .caution,
            description: "Downloaded Go package modules. Deleting will force Go to re-download dependencies."
        ),
        // Homebrew
        CleanerItem(
            id: "homebrew-cache",
            title: "Homebrew Cache",
            path: "~/Library/Caches/Homebrew",
            risk: .safe,
            description: "Cached download tarballs of Homebrew formula and casks. Safe to remove."
        ),
        // Gradle
        CleanerItem(
            id: "gradle-cache",
            title: "Gradle Caches",
            path: "~/.gradle/caches",
            risk: .safe,
            description: "Gradle dependencies and compilation cache. Gradle will re-resolve dependencies next build."
        ),
        // VS Code
        CleanerItem(
            id: "vscode-cacheddata",
            title: "VS Code Cached Data",
            path: "~/Library/Application Support/Code/CachedData",
            risk: .safe,
            description: "VS Code cached structures for faster startup. Safe to delete."
        ),
        CleanerItem(
            id: "vscode-workspace-storage",
            title: "VS Code Workspace Storage",
            path: "~/Library/Application Support/Code/User/workspaceStorage",
            risk: .caution,
            description: "VS Code UI states (opened files list, folding states) for workspaces. Safe to delete, but resets workspace layout states."
        ),
        // Docker
        CleanerItem(
            id: "docker-data",
            title: "Docker Virtual Disk",
            path: "~/Library/Containers/com.docker.docker",
            risk: .danger,
            description: "Docker Desktop VM disk image. DO NOT delete if you have active containers or data volume databases you need. Use Docker Desktop's clean options instead."
        ),
        CleanerItem(
            id: "docker-containers",
            title: "Docker Stopped Containers",
            path: "DOCKER_CONTAINERS",
            risk: .safe,
            description: "Stopped Docker containers. Safe to prune; does not affect active running containers."
        ),
        CleanerItem(
            id: "docker-dangling-images",
            title: "Docker Dangling Images",
            path: "DOCKER_DANGLING_IMAGES",
            risk: .safe,
            description: "Untagged (dangling) Docker images. Safe to remove as they are not referenced by any container."
        ),
        CleanerItem(
            id: "docker-build-cache",
            title: "Docker Build Cache",
            path: "DOCKER_BUILD_CACHE",
            risk: .safe,
            description: "Docker builder caches. Safe to clear; build cache will be recreated on next run."
        ),
        CleanerItem(
            id: "docker-unused-images",
            title: "Docker Unused Images",
            path: "DOCKER_UNUSED_IMAGES",
            risk: .caution,
            description: "All unused Docker images (not just dangling ones). Clears images not used by any running container."
        ),
        CleanerItem(
            id: "docker-volumes",
            title: "Docker Unused Volumes",
            path: "DOCKER_VOLUMES",
            risk: .danger,
            description: "Unused Docker local volumes. CAUTION: Removes persistent data volumes not used by active containers. Confirm you don't have database records here."
        )
    ]

    public func scan(
        items: [CleanerItem],
        onProgress: @escaping @Sendable (String, Int64) -> Void
    ) async -> [CleanerItem] {
        return await withTaskGroup(of: CleanerItem.self) { group in
            for item in items {
                group.addTask {
                    if item.path.hasPrefix("DOCKER_") {
                        guard item.exists else {
                            onProgress(item.id, 0)
                            var modified = item
                            modified.detectedSize = 0
                            modified.isScanning = false
                            return modified
                        }
                        
                        let size = await self.getDockerItemSize(for: item.path)
                        onProgress(item.id, size)
                        var modified = item
                        modified.detectedSize = size
                        modified.isScanning = false
                        return modified
                    }

                    let url = item.resolvedURL
                    guard item.exists else {
                        onProgress(item.id, 0)
                        var modified = item
                        modified.detectedSize = 0
                        modified.isScanning = false
                        return modified
                    }

                    let size = await self.calculateFolderSize(at: url)
                    onProgress(item.id, size)

                    var modified = item
                    modified.detectedSize = size
                    modified.isScanning = false
                    return modified
                }
            }

            var updatedItems: [CleanerItem] = []
            for await completedItem in group {
                updatedItems.append(completedItem)
            }

            // Return in the original order
            return items.map { original in
                updatedItems.first(where: { $0.id == original.id }) ?? original
            }
        }
    }

    private func calculateFolderSize(at url: URL) async -> Int64 {
        return await Task.detached(priority: .background) {
            var totalSize: Int64 = 0
            let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileSizeKey, .isDirectoryKey]
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: nil
            ) else {
                return 0
            }

            while let fileURL = enumerator.nextObject() as? URL {
                if Task.isCancelled { break }
                do {
                    let values = try fileURL.resourceValues(forKeys: keys)
                    if !(values.isDirectory ?? false) {
                        totalSize += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                    }
                } catch {
                    // Ignore individual read errors
                }
            }
            return totalSize
        }.value
    }

    // MARK: - Docker CLI Size Utilities

    private func getDockerItemSize(for path: String) async -> Int64 {
        switch path {
        case "DOCKER_CONTAINERS":
            return await getDockerDfSize(for: "Containers")
        case "DOCKER_BUILD_CACHE":
            return await getDockerDfSize(for: "Build Cache")
        case "DOCKER_UNUSED_IMAGES":
            return await getDockerDfSize(for: "Images")
        case "DOCKER_VOLUMES":
            return await getDockerDfSize(for: "Local Volumes")
        case "DOCKER_DANGLING_IMAGES":
            return await getDanglingImagesSize()
        default:
            return 0
        }
    }

    private func getDockerDfSize(for type: String) async -> Int64 {
        return await Task.detached(priority: .background) {
            guard let output = self.runShellCommand("docker system df --format json") else {
                return 0
            }
            
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                guard !line.isEmpty else { continue }
                guard let data = line.data(using: .utf8) else { continue }
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let jsonType = json["Type"] as? String,
                       jsonType == type,
                       let reclaimableStr = json["Reclaimable"] as? String {
                        
                        // Parse reclaimable size e.g. "3.106GB (99%)" -> "3.106GB"
                        var cleanStr = reclaimableStr.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let index = cleanStr.firstIndex(of: "(") {
                            cleanStr = String(cleanStr[..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        return self.parseDockerSize(cleanStr)
                    }
                } catch {
                    // Ignore JSON parsing errors
                }
            }
            return 0
        }.value
    }

    private func getDanglingImagesSize() async -> Int64 {
        return await Task.detached(priority: .background) {
            guard let output = self.runShellCommand("docker images -f \"dangling=true\" --format \"{{.Size}}\"") else {
                return 0
            }
            
            var totalSize: Int64 = 0
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    totalSize += self.parseDockerSize(trimmed)
                }
            }
            return totalSize
        }.value
    }

    private func parseDockerSize(_ string: String) -> Int64 {
        let clean = string.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let digits = clean.filter { "0123456789.".contains($0) }
        guard let number = Double(digits) else { return 0 }
        
        if clean.hasSuffix("GB") {
            return Int64(number * 1024 * 1024 * 1024)
        } else if clean.hasSuffix("MB") {
            return Int64(number * 1024 * 1024)
        } else if clean.hasSuffix("KB") {
            return Int64(number * 1024)
        } else if clean.hasSuffix("TB") {
            return Int64(number * 1024 * 1024 * 1024 * 1024)
        }
        return Int64(number)
    }

    private func runShellCommand(_ command: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
