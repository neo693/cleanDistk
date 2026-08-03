import Foundation

public final class LargeModelCleanerScanner {
    private struct SearchRoot {
        let label: String
        let path: String
    }

    private let fileManager = FileManager.default

    private static let modelExtensions = Set([
        "bin", "ckpt", "gguf", "ggml", "mlmodel", "mlpackage", "onnx", "pb", "pt", "pth", "safetensors", "tflite"
    ])

    private static let modelFileNames = Set([
        "tokenizer.model"
    ])

    private let searchRoots = [
        SearchRoot(label: "Ollama", path: "~/.ollama/models"),
        SearchRoot(label: "Hugging Face", path: "~/.cache/huggingface"),
        SearchRoot(label: "LM Studio", path: "~/.cache/lm-studio/models"),
        SearchRoot(label: "LM Studio", path: "~/Library/Application Support/LM Studio/models"),
        SearchRoot(label: "ModelScope", path: "~/.cache/modelscope"),
        SearchRoot(label: "Torch Hub", path: "~/.cache/torch"),
        SearchRoot(label: "Whisper", path: "~/.cache/whisper"),
        SearchRoot(label: "Core ML", path: "~/Library/Caches/com.apple.CoreML")
    ]

    public init() {}

    public func scan(onProgress: @escaping @Sendable (String, Int64) -> Void) async -> [CleanerItem] {
        await Task.detached(priority: .background) {
            var seen = Set<String>()
            var found: [CleanerItem] = []

            for root in self.searchRoots {
                if Task.isCancelled { break }
                let rootURL = URL(fileURLWithPath: (root.path as NSString).expandingTildeInPath)
                guard self.fileManager.fileExists(atPath: rootURL.path) else { continue }

                let items = self.modelFiles(under: rootURL, label: root.label)
                for item in items where !seen.contains(item.path) {
                    seen.insert(item.path)
                    onProgress(item.id, item.detectedSize ?? 0)
                    found.append(item)
                }
            }

            return found.sorted {
                ($0.detectedSize ?? 0) > ($1.detectedSize ?? 0)
            }
        }.value
    }

    public static func runSelfCheck() {
        assert(isModelFileName("model.gguf"))
        assert(isModelFileName("tokenizer.model"))
        assert(isModelFileName("notes.txt") == false)
        assert(isModelFileName("archive.zip") == false)
    }

    private func modelFiles(under rootURL: URL, label: String) -> [CleanerItem] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: nil
        ) else {
            return []
        }

        var items: [CleanerItem] = []
        for case let url as URL in enumerator {
            if Task.isCancelled { break }
            guard Self.isModelFileName(url.lastPathComponent) else { continue }
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            if values.isDirectory ?? false { continue }

            let size = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            guard size > 0 else { continue }

            items.append(CleanerItem(
                id: "large-model:\(url.path)",
                title: "\(label) - \(url.lastPathComponent)",
                path: url.path,
                risk: .caution,
                description: "Large model/checkpoint file. Removing it frees disk space, but the owning app or library may need to download it again.",
                detectedSize: size,
                isScanning: false
            ))
        }
        return items
    }

    static func isModelFileName(_ name: String) -> Bool {
        let lower = name.lowercased()
        if modelFileNames.contains(lower) { return true }

        let ext = (lower as NSString).pathExtension
        if modelExtensions.contains(ext) { return true }

        // ponytail: Ollama uses extensionless sha256 blobs; upgrade to manifest-aware grouping if per-model names are needed.
        return lower.count == 64 && lower.allSatisfy { $0.isHexDigit }
    }
}
