import Foundation

public enum CleanerRisk: String, Codable {
    case safe     // Safe to delete, only caches (e.g., Xcode DerivedData)
    case caution  // Rebuild required or potentially deletes local simulator states
    case danger   // Critical dependencies (e.g. Docker, do not delete directly)
}

public struct CleanerItem: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let path: String // Can contain tilde '~' which we'll expand at runtime
    public let risk: CleanerRisk
    public let description: String
    public var detectedSize: Int64? // None if not scanned yet, 0 if empty
    public var isScanning: Bool = false

    public init(
        id: String,
        title: String,
        path: String,
        risk: CleanerRisk,
        description: String,
        detectedSize: Int64? = nil,
        isScanning: Bool = false
    ) {
        self.id = id
        self.title = title
        self.path = path
        self.risk = risk
        self.description = description
        self.detectedSize = detectedSize
        self.isScanning = isScanning
    }

    public var resolvedURL: URL {
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }

    public var isDocker: Bool {
        return path.hasPrefix("DOCKER_")
    }

    public var dockerCommand: String? {
        switch path {
        case "DOCKER_CONTAINERS":
            return "docker container prune"
        case "DOCKER_DANGLING_IMAGES":
            return "docker image prune"
        case "DOCKER_BUILD_CACHE":
            return "docker builder prune"
        case "DOCKER_UNUSED_IMAGES":
            return "docker image prune -a"
        case "DOCKER_VOLUMES":
            return "docker volume prune"
        default:
            return nil
        }
    }

    public var exists: Bool {
        if isDocker {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", "which docker"]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus == 0
            } catch {
                return false
            }
        }
        return FileManager.default.fileExists(atPath: resolvedURL.path)
    }
}
