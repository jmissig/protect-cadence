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

public struct QueryWindow: Codable, Sendable, Equatable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

public struct RecentEventsRequest: Sendable {
    public let limit: Int
    public let window: QueryWindow?

    public init(limit: Int = 50, window: QueryWindow? = nil) {
        self.limit = max(1, limit)
        self.window = window
    }
}

public struct RecentEventsResponse: Codable, Sendable {
    public let databasePath: String
    public let window: QueryWindow?
    public let events: [EventRow]

    public init(databasePath: String, window: QueryWindow? = nil, events: [EventRow]) {
        self.databasePath = databasePath
        self.window = window
        self.events = events
    }
}

public struct IngestResponse: Codable, Sendable {
    public let command: String
    public let databasePath: String
    public let window: QueryWindow?
    public let fetchedEventCount: Int
    public let normalizedRowCount: Int
    public let insertedRowCount: Int
    public let ignoredEventCount: Int
    public let status: String

    public init(
        command: String,
        databasePath: String,
        window: QueryWindow? = nil,
        fetchedEventCount: Int,
        normalizedRowCount: Int,
        insertedRowCount: Int,
        ignoredEventCount: Int,
        status: String
    ) {
        self.command = command
        self.databasePath = databasePath
        self.window = window
        self.fetchedEventCount = fetchedEventCount
        self.normalizedRowCount = normalizedRowCount
        self.insertedRowCount = insertedRowCount
        self.ignoredEventCount = ignoredEventCount
        self.status = status
    }
}

public struct SummaryRequest: Sendable {
    public let window: QueryWindow

    public init(window: QueryWindow) {
        self.window = window
    }
}

public struct SummaryGroup: Codable, FetchableRecord, Sendable, Equatable {
    public let camera: String
    public let kind: String
    public let rowCount: Int

    public init(camera: String, kind: String, rowCount: Int) {
        self.camera = camera
        self.kind = kind
        self.rowCount = rowCount
    }

    enum CodingKeys: String, CodingKey {
        case camera
        case kind
        case rowCount
    }

    public init(row: Row) {
        camera = row["camera"]
        kind = row["kind"]
        rowCount = row["row_count"]
    }
}

public struct SummaryResponse: Codable, Sendable {
    public let command: String
    public let databasePath: String
    public let window: QueryWindow
    public let totalRows: Int
    public let distinctEventCount: Int
    public let groups: [SummaryGroup]

    public init(
        command: String,
        databasePath: String,
        window: QueryWindow,
        totalRows: Int,
        distinctEventCount: Int,
        groups: [SummaryGroup]
    ) {
        self.command = command
        self.databasePath = databasePath
        self.window = window
        self.totalRows = totalRows
        self.distinctEventCount = distinctEventCount
        self.groups = groups
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

    public func insertIgnoringDuplicates(_ events: [EventRow]) throws -> Int {
        try dbQueue.write { db in
            var insertedCount = 0
            for event in events {
                try event.insert(db, onConflict: .ignore)
                insertedCount += db.changesCount
            }
            return insertedCount
        }
    }

    public func fetchRecent(_ request: RecentEventsRequest = RecentEventsRequest()) throws -> [EventRow] {
        try dbQueue.read { db in
            var query = EventRow
                .order(EventRow.Columns.timeStart.desc, EventRow.Columns.id.desc)
            
            if let window = request.window {
                query = query.filter(
                    sql: "\(EventRow.Columns.timeStart.name) >= ? AND \(EventRow.Columns.timeStart.name) < ?",
                    arguments: [window.start, window.end]
                )
            }

            return try query
                .limit(request.limit)
                .fetchAll(db)
        }
    }

    public func fetchRecentResponse(_ request: RecentEventsRequest = RecentEventsRequest()) throws -> RecentEventsResponse {
        RecentEventsResponse(databasePath: path, window: request.window, events: try fetchRecent(request))
    }

    public func fetchSummary(_ request: SummaryRequest) throws -> SummaryResponse {
        try dbQueue.read { db in
            let arguments: StatementArguments = [request.window.start, request.window.end]

            let totalRows = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*)
                    FROM \(EventRow.databaseTableName)
                    WHERE time_start >= ? AND time_start < ?
                    """,
                arguments: arguments
            ) ?? 0

            let distinctEventCount = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(DISTINCT event_id)
                    FROM \(EventRow.databaseTableName)
                    WHERE time_start >= ? AND time_start < ?
                    """,
                arguments: arguments
            ) ?? 0

            let groups = try SummaryGroup.fetchAll(
                db,
                sql: """
                    SELECT camera, kind, COUNT(*) AS row_count
                    FROM \(EventRow.databaseTableName)
                    WHERE time_start >= ? AND time_start < ?
                    GROUP BY camera, kind
                    ORDER BY camera ASC, kind ASC
                    """,
                arguments: arguments
            )

            return SummaryResponse(
                command: ProtectCadenceCommand.query.rawValue,
                databasePath: path,
                window: request.window,
                totalRows: totalRows,
                distinctEventCount: distinctEventCount,
                groups: groups
            )
        }
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
