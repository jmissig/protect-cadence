import Foundation
import GRDB

public enum ProtectCadenceCommand: String, Sendable {
    case ingest = "protect-cadence-ingest"
    case query = "protect-cadence-query"
}

public struct ProtectCadencePaths: Sendable {
    public let databasePath: String

    public init(databasePath: String) {
        self.databasePath = databasePath
    }

    public static func makeDefault(
        fileManager: FileManager = .default,
        currentDirectoryPath: String? = nil
    ) -> ProtectCadencePaths {
        let basePath = currentDirectoryPath ?? fileManager.currentDirectoryPath
        let url = URL(fileURLWithPath: basePath, isDirectory: true)
            .appendingPathComponent("protect-cadence.sqlite")
        return ProtectCadencePaths(databasePath: url.path)
    }
}

public struct EventRow: Codable, FetchableRecord, PersistableRecord, TableRecord, Sendable {
    public static let databaseTableName = "events"

    public let id: Int64?
    public let timeStart: Date
    public let timeEnd: Date?
    public let camera: String
    public let kind: String
    public let eventID: String

    public init(
        id: Int64? = nil,
        timeStart: Date,
        timeEnd: Date? = nil,
        camera: String,
        kind: String,
        eventID: String
    ) {
        self.id = id
        self.timeStart = timeStart
        self.timeEnd = timeEnd
        self.camera = camera
        self.kind = kind
        self.eventID = eventID
    }

    public enum Columns {
        public static let id = Column("id")
        public static let timeStart = Column("time_start")
        public static let timeEnd = Column("time_end")
        public static let camera = Column("camera")
        public static let kind = Column("kind")
        public static let eventID = Column("event_id")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case timeStart
        case timeEnd
        case camera
        case kind
        case eventID
    }

    public init(row: Row) {
        id = row["id"]
        timeStart = row["time_start"]
        timeEnd = row["time_end"]
        camera = row["camera"]
        kind = row["kind"]
        eventID = row["event_id"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["time_start"] = timeStart
        container["time_end"] = timeEnd
        container["camera"] = camera
        container["kind"] = kind
        container["event_id"] = eventID
    }
}

public struct RecentEventsRequest: Sendable {
    public let limit: Int

    public init(limit: Int = 50) {
        self.limit = max(1, limit)
    }
}

public struct RecentEventsResponse: Codable, Sendable {
    public let databasePath: String
    public let events: [EventRow]

    public init(databasePath: String, events: [EventRow]) {
        self.databasePath = databasePath
        self.events = events
    }
}

public final class ProtectCadenceDatabase {
    private let dbQueue: DatabaseQueue
    public let path: String

    public init(path: String) throws {
        self.path = path

        let fileManager = FileManager.default
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        var configuration = Configuration()
        configuration.foreignKeysEnabled = true

        dbQueue = try DatabaseQueue(path: path, configuration: configuration)
        try Self.migrator.migrate(dbQueue)
    }

    public func insert(_ event: EventRow) throws {
        try dbQueue.write { db in
            try event.insert(db)
        }
    }

    public func insertIgnoringDuplicates(_ events: [EventRow]) throws {
        try dbQueue.write { db in
            for event in events {
                try event.insert(db, onConflict: .ignore)
            }
        }
    }

    public func fetchRecent(_ request: RecentEventsRequest = RecentEventsRequest()) throws -> [EventRow] {
        try dbQueue.read { db in
            try EventRow
                .order(EventRow.Columns.timeStart.desc, EventRow.Columns.id.desc)
                .limit(request.limit)
                .fetchAll(db)
        }
    }

    public func fetchRecentResponse(_ request: RecentEventsRequest = RecentEventsRequest()) throws -> RecentEventsResponse {
        RecentEventsResponse(databasePath: path, events: try fetchRecent(request))
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("createEvents") { db in
            guard try !db.tableExists(EventRow.databaseTableName) else {
                return
            }

            try db.create(table: EventRow.databaseTableName) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("ts", .datetime).notNull().indexed()
                table.column("camera", .text).notNull().indexed()
                table.column("kind", .text).notNull().indexed()
                table.column("count", .integer).notNull().defaults(to: 1)
                table.column("sourceEventID", .text).notNull().unique(onConflict: .ignore)
                table.column("rawJSON", .text)
            }
        }

        migrator.registerMigration("reshapeEventsForKindRows") { db in
            guard try db.tableExists(EventRow.databaseTableName) else {
                try createCurrentEventsTable(in: db)
                return
            }

            let columnNames = try db.columns(in: EventRow.databaseTableName).map(\.name)
            let hasCurrentShape = columnNames.contains("time_start")
                && columnNames.contains("time_end")
                && columnNames.contains("event_id")

            guard !hasCurrentShape else {
                return
            }

            try db.create(table: "events_v2") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("time_start", .datetime).notNull().indexed()
                table.column("time_end", .datetime)
                table.column("camera", .text).notNull().indexed()
                table.column("kind", .text).notNull().indexed()
                table.column("event_id", .text).notNull()
            }

            try db.execute(sql: """
                INSERT INTO events_v2 (id, time_start, time_end, camera, kind, event_id)
                SELECT id, ts, NULL, camera, kind, sourceEventID
                FROM events
                """)

            try db.drop(table: EventRow.databaseTableName)
            try db.rename(table: "events_v2", to: EventRow.databaseTableName)
            try db.create(
                index: "events_on_event_id_kind",
                on: EventRow.databaseTableName,
                columns: ["event_id", "kind"],
                unique: true
            )
        }

        return migrator
    }

    private static func createCurrentEventsTable(in db: Database) throws {
        try db.create(table: EventRow.databaseTableName) { table in
            table.autoIncrementedPrimaryKey("id")
            table.column("time_start", .datetime).notNull().indexed()
            table.column("time_end", .datetime)
            table.column("camera", .text).notNull().indexed()
            table.column("kind", .text).notNull().indexed()
            table.column("event_id", .text).notNull()
        }

        try db.create(
            index: "events_on_event_id_kind",
            on: EventRow.databaseTableName,
            columns: ["event_id", "kind"],
            unique: true
        )
    }
}
