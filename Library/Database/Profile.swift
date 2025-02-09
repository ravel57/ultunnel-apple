import Foundation
import GRDB
import Network

public class Profile: Record, Identifiable, ObservableObject, Codable {
    public var id: Int64?
    public var mustID: Int64 {
        id!
    }

    @Published public var name: String
    public var order: UInt32
    public var type: ProfileType
    public var path: String
    @Published public var remoteURL: String?
    @Published public var autoUpdate: Bool
    @Published public var autoUpdateInterval: Int32
    public var lastUpdated: Date?

    public init(id: Int64? = nil, name: String, order: UInt32 = 0, type: ProfileType, path: String, remoteURL: String? = nil, autoUpdate: Bool = false, autoUpdateInterval: Int32 = 0, lastUpdated: Date? = nil) {
        self.id = id
        self.name = name
        self.order = order
        self.type = type
        self.path = path
        self.remoteURL = remoteURL
        self.autoUpdate = autoUpdate
        self.autoUpdateInterval = autoUpdateInterval
        self.lastUpdated = lastUpdated
        super.init()
    }

    override public class var databaseTableName: String {
        "profiles"
    }

    enum Columns: String, ColumnExpression {
        case id, name, order, type, path, remoteURL, autoUpdate, autoUpdateInterval, lastUpdated, userAgent
    }

    required init(row: Row) throws {
        id = row[Columns.id]
        name = row[Columns.name] ?? ""
        order = row[Columns.order] ?? 0
        type = ProfileType(rawValue: row[Columns.type] ?? ProfileType.local.rawValue) ?? .local
        path = row[Columns.path] ?? ""
        remoteURL = row[Columns.remoteURL] ?? ""
        autoUpdate = row[Columns.autoUpdate] ?? false
        autoUpdateInterval = row[Columns.autoUpdateInterval] ?? 0
        lastUpdated = row[Columns.lastUpdated] ?? Date()
        try super.init(row: row)
    }

    override public func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.name] = name
        container[Columns.order] = order
        container[Columns.type] = type.rawValue
        container[Columns.path] = path
        container[Columns.remoteURL] = remoteURL
        container[Columns.autoUpdate] = autoUpdate
        container[Columns.autoUpdateInterval] = autoUpdateInterval
        container[Columns.lastUpdated] = lastUpdated
    }

    override public func didInsert(_ inserted: InsertionSuccess) {
        super.didInsert(inserted)
        id = inserted.rowID
    }

    enum CodingKeys: String, CodingKey {
        case id, name, order, type, path, remoteURL, autoUpdate, autoUpdateInterval, lastUpdated
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(order, forKey: .order)
        try container.encode(type.rawValue, forKey: .type)
        try container.encode(path, forKey: .path)
        try container.encode(remoteURL, forKey: .remoteURL)
        try container.encode(autoUpdate, forKey: .autoUpdate)
        try container.encode(autoUpdateInterval, forKey: .autoUpdateInterval)
        try container.encode(lastUpdated, forKey: .lastUpdated)
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int64.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        order = try container.decode(UInt32.self, forKey: .order)
        type = ProfileType(rawValue: try container.decode(Int.self, forKey: .type)) ?? .local
        path = try container.decode(String.self, forKey: .path)
        remoteURL = try container.decodeIfPresent(String.self, forKey: .remoteURL)
        autoUpdate = try container.decode(Bool.self, forKey: .autoUpdate)
        autoUpdateInterval = try container.decode(Int32.self, forKey: .autoUpdateInterval)
        lastUpdated = try container.decodeIfPresent(Date.self, forKey: .lastUpdated)
        super.init()
    }
}

public struct ProfilePreview: Identifiable, Hashable {
    public let id: Int64
    public let name: String
    public var order: UInt32
    public let type: ProfileType
    public let path: String
    public let remoteURL: String?
    public let autoUpdate: Bool
    public let autoUpdateInterval: Int32
    public let lastUpdated: Date?
    public let origin: Profile

    public init(_ profile: Profile) {
        id = profile.mustID
        name = profile.name
        order = profile.order
        type = profile.type
        path = profile.path
        remoteURL = profile.remoteURL
        autoUpdate = profile.autoUpdate
        autoUpdateInterval = profile.autoUpdateInterval
        lastUpdated = profile.lastUpdated
        origin = profile
    }
}

public enum ProfileType: Int, Codable {
    case local = 0, icloud, remote
}
