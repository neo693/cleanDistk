import Foundation

public final class AppLeftoverScanner {
    private struct Location {
        let label: String
        let path: String
        let risk: CleanerRisk
        let description: String
    }

    private let fileManager = FileManager.default

    private var locations: [Location] {
        [
            Location(
                label: "Caches",
                path: "~/Library/Caches",
                risk: .safe,
                description: "Cache data for an app that is no longer installed. Usually safe to remove."
            ),
            Location(
                label: "Preferences",
                path: "~/Library/Preferences",
                risk: .safe,
                description: "Preference plist for an app that is no longer installed. Safe to remove, but usually small."
            ),
            Location(
                label: "Saved State",
                path: "~/Library/Saved Application State",
                risk: .safe,
                description: "Window and launch state for an app that is no longer installed."
            ),
            Location(
                label: "HTTP Storage",
                path: "~/Library/HTTPStorages",
                risk: .safe,
                description: "HTTP cache/storage for an app that is no longer installed."
            ),
            Location(
                label: "WebKit",
                path: "~/Library/WebKit",
                risk: .caution,
                description: "WebKit website data for an app that is no longer installed. Review before removing."
            ),
            Location(
                label: "Application Support",
                path: "~/Library/Application Support",
                risk: .caution,
                description: "Support files for an app that is no longer installed. May contain user data."
            ),
            Location(
                label: "Containers",
                path: "~/Library/Containers",
                risk: .caution,
                description: "Sandbox container for an app that is no longer installed. May contain user data."
            ),
            Location(
                label: "Group Containers",
                path: "~/Library/Group Containers",
                risk: .danger,
                description: "Shared app-group data. Do not remove unless you recognize the app group."
            )
        ]
    }

    public init() {}

    public func scan(onProgress: @escaping @Sendable (String, Int64) -> Void) async -> [CleanerItem] {
        let installedBundleIDs = installedApplicationBundleIDs()
        var found: [CleanerItem] = []

        for location in locations {
            if Task.isCancelled { break }

            let baseURL = URL(fileURLWithPath: (location.path as NSString).expandingTildeInPath)
            guard let children = try? fileManager.contentsOfDirectory(
                at: baseURL,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for url in children {
                if Task.isCancelled { break }
                guard let bundleID = Self.bundleIdentifier(from: url, under: location.label) else {
                    continue
                }
                guard !installedBundleIDs.contains(bundleID) else {
                    continue
                }

                let size = await sizeOfItem(at: url)
                guard size > 0 else { continue }

                let id = "app-leftover:\(url.path)"
                onProgress(id, size)
                found.append(CleanerItem(
                    id: id,
                    title: "\(bundleID) - \(location.label)",
                    path: url.path,
                    risk: location.risk,
                    description: "\(location.description) Bundle ID: \(bundleID).",
                    detectedSize: size,
                    isScanning: false
                ))
            }
        }

        return found.sorted {
            if $0.risk != $1.risk {
                return riskSortValue($0.risk) < riskSortValue($1.risk)
            }
            return ($0.detectedSize ?? 0) > ($1.detectedSize ?? 0)
        }
    }

    static func bundleIdentifier(from url: URL, under label: String) -> String? {
        var name = url.lastPathComponent

        if label == "Preferences" {
            guard name.hasSuffix(".plist") else { return nil }
            name.removeLast(".plist".count)
        } else if label == "Saved State" {
            guard name.hasSuffix(".savedState") else { return nil }
            name.removeLast(".savedState".count)
        }

        // ponytail: exact bundle-id names only; app-name fuzzy matching belongs in a reviewed matcher.
        guard looksLikeThirdPartyBundleID(name) else { return nil }
        return name
    }

    static func looksLikeThirdPartyBundleID(_ value: String) -> Bool {
        let parts = value.split(separator: ".")
        guard parts.count >= 3 else { return false }
        guard !value.hasPrefix("com.apple.") else { return false }
        return parts.allSatisfy { part in
            part.range(of: #"^[A-Za-z0-9-]+$"#, options: .regularExpression) != nil
        }
    }

    static func runSelfCheck() {
        assert(bundleIdentifier(
            from: URL(fileURLWithPath: "/tmp/com.example.Tool.plist"),
            under: "Preferences"
        ) == "com.example.Tool")
        assert(bundleIdentifier(
            from: URL(fileURLWithPath: "/tmp/com.example.Tool.savedState"),
            under: "Saved State"
        ) == "com.example.Tool")
        assert(bundleIdentifier(
            from: URL(fileURLWithPath: "/tmp/Example Tool"),
            under: "Application Support"
        ) == nil)
        assert(bundleIdentifier(
            from: URL(fileURLWithPath: "/tmp/com.apple.TextEdit"),
            under: "Caches"
        ) == nil)
    }

    private func installedApplicationBundleIDs() -> Set<String> {
        let roots = [
            "/Applications",
            "~/Applications",
            "/System/Applications",
            "/System/Applications/Utilities"
        ].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }

        var bundleIDs = Set<String>()
        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                if Task.isCancelled { break }
                guard url.pathExtension == "app" else { continue }
                bundleIDs.formUnion(bundleIdentifiers(in: url))
                enumerator.skipDescendants()
            }
        }
        return bundleIDs
    }

    private func bundleIdentifiers(in appURL: URL) -> Set<String> {
        let bundleExtensions = Set(["app", "appex", "xpc", "framework"])
        var bundleIDs = Set<String>()

        if let bundleID = Bundle(url: appURL)?.bundleIdentifier {
            bundleIDs.insert(bundleID)
        }

        guard let enumerator = fileManager.enumerator(
            at: appURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles]
        ) else {
            return bundleIDs
        }

        for case let url as URL in enumerator {
            if Task.isCancelled { break }
            guard bundleExtensions.contains(url.pathExtension) else { continue }
            if let bundleID = Bundle(url: url)?.bundleIdentifier {
                bundleIDs.insert(bundleID)
            }
            enumerator.skipDescendants()
        }

        return bundleIDs
    }

    private func sizeOfItem(at url: URL) async -> Int64 {
        await Task.detached(priority: .background) {
            let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey]
            guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
            if !(values.isDirectory ?? false) {
                return Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            }

            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles],
                errorHandler: nil
            ) else {
                return 0
            }

            var total: Int64 = 0
            while let fileURL = enumerator.nextObject() as? URL {
                if Task.isCancelled { break }
                guard let childValues = try? fileURL.resourceValues(forKeys: keys) else { continue }
                if !(childValues.isDirectory ?? false) {
                    total += Int64(childValues.totalFileAllocatedSize ?? childValues.fileSize ?? 0)
                }
            }
            return total
        }.value
    }

    private func riskSortValue(_ risk: CleanerRisk) -> Int {
        switch risk {
        case .safe: return 0
        case .caution: return 1
        case .danger: return 2
        }
    }
}
