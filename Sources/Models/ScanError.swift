import Foundation

public struct ScanError: Identifiable, Hashable {
    public let id = UUID()
    public let url: URL
    public let message: String

    public init(url: URL, message: String) {
        self.url = url
        self.message = message
    }

    public static func == (lhs: ScanError, rhs: ScanError) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
