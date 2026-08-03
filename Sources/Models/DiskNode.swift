import Foundation

public struct DiskNode: Identifiable, Hashable {
    public let id: UUID
    public let name: String
    public let url: URL
    public var size: Int64
    public var allocatedSize: Int64
    public let isDirectory: Bool
    public var children: [DiskNode]?
    public var fileCount: Int
    public var directoryCount: Int
    public var error: String?
    public var isPackage: Bool
    public var modifiedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        url: URL,
        size: Int64,
        allocatedSize: Int64,
        isDirectory: Bool,
        children: [DiskNode]? = nil,
        fileCount: Int = 0,
        directoryCount: Int = 0,
        error: String? = nil,
        isPackage: Bool = false,
        modifiedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.size = size
        self.allocatedSize = allocatedSize
        self.isDirectory = isDirectory
        self.children = children
        self.fileCount = fileCount
        self.directoryCount = directoryCount
        self.error = error
        self.isPackage = isPackage
        self.modifiedAt = modifiedAt
    }

    public static func == (lhs: DiskNode, rhs: DiskNode) -> Bool {
        lhs.id == rhs.id &&
        lhs.size == rhs.size &&
        lhs.allocatedSize == rhs.allocatedSize &&
        lhs.fileCount == rhs.fileCount &&
        lhs.directoryCount == rhs.directoryCount
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
