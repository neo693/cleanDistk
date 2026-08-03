import Foundation

public struct FileSizeFormatter {
    private static let formatter: ByteCountFormatter = {
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        bcf.countStyle = .file
        bcf.includesUnit = true
        bcf.isAdaptive = true
        return bcf
    }()

    public static func format(_ bytes: Int64) -> String {
        guard bytes >= 0 else { return "0 bytes" }
        return formatter.string(fromByteCount: bytes)
    }
}
