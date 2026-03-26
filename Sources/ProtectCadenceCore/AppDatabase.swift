import Foundation
import GRDB

public enum ProtectCadenceCommand: String, Sendable {
    case ingest = "protect-cadence ingest"
    case query = "protect-cadence query"
    case auth = "protect-cadence auth"
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

    public static func defaultConfigPath(
        fileManager: FileManager = .default,
        homeDirectoryURL: URL? = nil
    ) -> String {
        defaultSupportDirectory(fileManager: fileManager, homeDirectoryURL: homeDirectoryURL)
            .appendingPathComponent("config.json")
            .path
    }

    public static func defaultSupportDirectory(
        fileManager: FileManager = .default,
        homeDirectoryURL: URL? = nil
    ) -> URL {
        let homeDirectory = homeDirectoryURL ?? fileManager.homeDirectoryForCurrentUser
        return homeDirectory
            .appendingPathComponent("Library/Application Support/protect-cadence", isDirectory: true)
    }

    public static func defaultManagedDatabasePath(
        fileManager: FileManager = .default,
        homeDirectoryURL: URL? = nil
    ) -> String {
        defaultSupportDirectory(fileManager: fileManager, homeDirectoryURL: homeDirectoryURL)
            .appendingPathComponent("protect-cadence.sqlite")
            .path
    }
}

public enum ProtectCadenceDatabasePathResolver {
    public static func resolve(
        explicitOverride: String?,
        configPath: String = ProtectCadencePaths.defaultConfigPath()
    ) throws -> String {
        let config = try ProtectCadenceConfigStore.load(from: configPath)
        return firstNonEmpty(
            explicitOverride,
            config?.databasePath,
            ProtectCadencePaths.makeDefault().databasePath
        )!
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values.first { value in
            guard let value else {
                return false
            }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? nil
    }
}

public struct EventRow: Codable, FetchableRecord, PersistableRecord, TableRecord, Sendable {
    public static let databaseTableName = "events"

    public let id: Int64?
    public let timeStart: Date
    public let timeEnd: Date?
    public let cameraID: String?
    public let camera: String
    public let eventType: String?
    public let kind: String
    public let eventID: String

    public init(
        id: Int64? = nil,
        timeStart: Date,
        timeEnd: Date? = nil,
        cameraID: String? = nil,
        camera: String,
        eventType: String? = nil,
        kind: String,
        eventID: String
    ) {
        self.id = id
        self.timeStart = timeStart
        self.timeEnd = timeEnd
        self.cameraID = cameraID
        self.camera = camera
        self.eventType = eventType
        self.kind = kind
        self.eventID = eventID
    }

    public enum Columns {
        public static let id = Column("id")
        public static let timeStart = Column("time_start")
        public static let timeEnd = Column("time_end")
        public static let cameraID = Column("camera_id")
        public static let camera = Column("camera")
        public static let eventType = Column("event_type")
        public static let kind = Column("kind")
        public static let eventID = Column("event_id")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case timeStart
        case timeEnd
        case cameraID
        case camera
        case eventType
        case kind
        case eventID
    }

    public init(row: Row) {
        id = row["id"]
        timeStart = row["time_start"]
        timeEnd = row["time_end"]
        cameraID = row["camera_id"]
        camera = row["camera"]
        eventType = row["event_type"]
        kind = row["kind"]
        eventID = row["event_id"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["time_start"] = timeStart
        container["time_end"] = timeEnd
        container["camera_id"] = cameraID
        container["camera"] = camera
        container["event_type"] = eventType
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

public enum CountSemantics: String, Codable, Sendable {
    case rows
}

public struct EventsRequest: Sendable {
    public let limit: Int
    public let order: EventOrder
    public let filters: QueryFilters

    public init(limit: Int = 50, order: EventOrder = .newest, filters: QueryFilters = QueryFilters()) {
        self.limit = max(1, limit)
        self.order = order
        self.filters = filters
    }
}

public typealias RecentEventsRequest = EventsRequest

public struct EventsResponse: Codable, Sendable {
    public let command: String
    public let databasePath: String
    public let filters: QueryFilters
    public let countSemantics: CountSemantics
    public let events: [EventRow]

    public init(
        command: String,
        databasePath: String,
        filters: QueryFilters,
        countSemantics: CountSemantics = .rows,
        events: [EventRow]
    ) {
        self.command = command
        self.databasePath = databasePath
        self.filters = filters
        self.countSemantics = countSemantics
        self.events = events
    }
}

public typealias RecentEventsResponse = EventsResponse

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
    public let filters: QueryFilters
    public let groupBy: [SummaryGroupBy]

    public init(filters: QueryFilters, groupBy: [SummaryGroupBy] = [.camera, .kind]) {
        self.filters = filters
        self.groupBy = groupBy
    }
}

public struct SummaryGroup: Codable, Sendable, Equatable {
    public let group: [String: String]
    public let rowCount: Int

    public init(group: [String: String], rowCount: Int) {
        self.group = group
        self.rowCount = rowCount
    }
}

public struct SummaryResponse: Codable, Sendable {
    public let command: String
    public let databasePath: String
    public let filters: QueryFilters
    public let countSemantics: CountSemantics
    public let totalRows: Int
    public let distinctEventCount: Int
    public let groupBy: [SummaryGroupBy]
    public let groups: [SummaryGroup]

    public init(
        command: String,
        databasePath: String,
        filters: QueryFilters,
        countSemantics: CountSemantics = .rows,
        totalRows: Int,
        distinctEventCount: Int,
        groupBy: [SummaryGroupBy],
        groups: [SummaryGroup]
    ) {
        self.command = command
        self.databasePath = databasePath
        self.filters = filters
        self.countSemantics = countSemantics
        self.totalRows = totalRows
        self.distinctEventCount = distinctEventCount
        self.groupBy = groupBy
        self.groups = groups
    }
}

private struct EventWhereClause {
    let sql: String
    let arguments: StatementArguments
}

private extension SummaryGroupBy {
    var alias: String {
        "group_\(rawValue)"
    }

    var selectSQL: String {
        switch self {
        case .camera:
            return "camera"
        case .kind:
            return "kind"
        case .date:
            return "strftime('%Y-%m-%d', time_start, 'localtime')"
        case .hour:
            return "strftime('%H:00', time_start, 'localtime')"
        case .weekday:
            return """
                CASE strftime('%w', time_start, 'localtime')
                WHEN '0' THEN 'sun'
                WHEN '1' THEN 'mon'
                WHEN '2' THEN 'tue'
                WHEN '3' THEN 'wed'
                WHEN '4' THEN 'thu'
                WHEN '5' THEN 'fri'
                ELSE 'sat'
                END
                """
        }
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

    public func fetchEvents(_ request: EventsRequest = EventsRequest()) throws -> [EventRow] {
        try dbQueue.read { db in
            let whereClause = try eventWhereClause(for: request.filters)
            let orderClause: String
            switch request.order {
            case .newest:
                orderClause = "time_start DESC, id DESC"
            case .oldest:
                orderClause = "time_start ASC, id ASC"
            }

            var arguments = whereClause.arguments
            arguments += [request.limit]

            return try EventRow.fetchAll(
                db,
                sql: """
                    SELECT *
                    FROM \(EventRow.databaseTableName)
                    \(whereClause.sql)
                    ORDER BY \(orderClause)
                    LIMIT ?
                    """,
                arguments: arguments
            )
        }
    }

    public func fetchEventsResponse(_ request: EventsRequest = EventsRequest()) throws -> EventsResponse {
        EventsResponse(
            command: ProtectCadenceCommand.query.rawValue,
            databasePath: path,
            filters: request.filters,
            events: try fetchEvents(request)
        )
    }

    public func fetchRecent(_ request: EventsRequest = EventsRequest()) throws -> [EventRow] {
        try fetchEvents(request)
    }

    public func fetchRecentResponse(_ request: EventsRequest = EventsRequest()) throws -> EventsResponse {
        try fetchEventsResponse(request)
    }

    public func fetchSummary(_ request: SummaryRequest) throws -> SummaryResponse {
        try dbQueue.read { db in
            let whereClause = try eventWhereClause(for: request.filters)

            let totalRows = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*)
                    FROM \(EventRow.databaseTableName)
                    \(whereClause.sql)
                    """,
                arguments: whereClause.arguments
            ) ?? 0

            let distinctEventCount = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(DISTINCT event_id)
                    FROM \(EventRow.databaseTableName)
                    \(whereClause.sql)
                    """,
                arguments: whereClause.arguments
            ) ?? 0

            let groups = try fetchSummaryGroups(db: db, request: request, whereClause: whereClause)

            return SummaryResponse(
                command: ProtectCadenceCommand.query.rawValue,
                databasePath: path,
                filters: request.filters,
                totalRows: totalRows,
                distinctEventCount: distinctEventCount,
                groupBy: request.groupBy,
                groups: groups
            )
        }
    }

    private func fetchSummaryGroups(
        db: Database,
        request: SummaryRequest,
        whereClause: EventWhereClause
    ) throws -> [SummaryGroup] {
        let selectColumns = request.groupBy.map { "\($0.selectSQL) AS \($0.alias)" }.joined(separator: ", ")
        let groupColumns = request.groupBy.map(\.alias).joined(separator: ", ")
        let sql = """
            SELECT \(selectColumns), COUNT(*) AS row_count
            FROM \(EventRow.databaseTableName)
            \(whereClause.sql)
            GROUP BY \(groupColumns)
            ORDER BY \(groupColumns)
            """

        return try Row.fetchAll(db, sql: sql, arguments: whereClause.arguments).map { row in
            var values: [String: String] = [:]
            for dimension in request.groupBy {
                values[dimension.rawValue] = row[dimension.alias]
            }
            return SummaryGroup(group: values, rowCount: row["row_count"])
        }
    }

    private func eventWhereClause(for filters: QueryFilters) throws -> EventWhereClause {
        var clauses: [String] = []
        var arguments = StatementArguments()

        if let window = filters.window {
            clauses.append("time_start >= ? AND time_start < ?")
            arguments += [window.start, window.end]
        }

        if !filters.cameras.isEmpty {
            clauses.append("camera IN (\(Self.bindVariables(count: filters.cameras.count)))")
            for camera in filters.cameras {
                arguments += [camera]
            }
        }

        if !filters.kinds.isEmpty {
            clauses.append("kind IN (\(Self.bindVariables(count: filters.kinds.count)))")
            for kind in filters.kinds {
                arguments += [kind]
            }
        }

        if !filters.weekdays.isEmpty {
            clauses.append("strftime('%w', time_start, 'localtime') IN (\(Self.bindVariables(count: filters.weekdays.count)))")
            for weekday in filters.weekdays {
                arguments += [weekday.sqliteWeekdayNumber]
            }
        }

        if let timeOfDay = filters.timeOfDay {
            let comparator = timeOfDay.overnight ? "OR" : "AND"
            clauses.append("(\(Self.timeOfDayMinutesSQL) >= ? \(comparator) \(Self.timeOfDayMinutesSQL) < ?)")
            arguments += [timeOfDay.startMinutes, timeOfDay.endMinutes]
        }

        let sql = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
        return EventWhereClause(sql: sql, arguments: arguments)
    }

    private static func bindVariables(count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }

    private static let timeOfDayMinutesSQL = """
        ((CAST(strftime('%H', time_start, 'localtime') AS INTEGER) * 60) + CAST(strftime('%M', time_start, 'localtime') AS INTEGER))
        """

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
                && columnNames.contains("camera_id")
                && columnNames.contains("event_type")
                && columnNames.contains("event_id")

            guard !hasCurrentShape else {
                return
            }

            let hasLegacyBootstrapShape = columnNames.contains("ts") && columnNames.contains("sourceEventID")
            let hasPreHardeningCurrentShape = columnNames.contains("time_start")
                && columnNames.contains("time_end")
                && columnNames.contains("event_id")

            try db.create(table: "events_v2") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("time_start", .datetime).notNull().indexed()
                table.column("time_end", .datetime)
                table.column("camera_id", .text).indexed()
                table.column("camera", .text).notNull().indexed()
                table.column("event_type", .text)
                table.column("kind", .text).notNull().indexed()
                table.column("event_id", .text).notNull()
            }

            if hasLegacyBootstrapShape {
                try db.execute(sql: """
                    INSERT INTO events_v2 (id, time_start, time_end, camera_id, camera, event_type, kind, event_id)
                    SELECT id, ts, NULL, NULL, camera, NULL, kind, sourceEventID
                    FROM events
                    """)
            } else if hasPreHardeningCurrentShape {
                try db.execute(sql: """
                    INSERT INTO events_v2 (id, time_start, time_end, camera_id, camera, event_type, kind, event_id)
                    SELECT id, time_start, time_end, NULL, camera, NULL, kind, event_id
                    FROM events
                    """)
            } else {
                throw DatabaseError(
                    resultCode: .SQLITE_ERROR,
                    message: "unsupported existing events table shape during reshapeEventsForKindRows"
                )
            }

            try db.drop(table: EventRow.databaseTableName)
            try db.rename(table: "events_v2", to: EventRow.databaseTableName)
            try db.create(
                index: "events_on_event_id_kind",
                on: EventRow.databaseTableName,
                columns: ["event_id", "kind"],
                unique: true
            )
        }

        migrator.registerMigration("addCameraIDAndEventType") { db in
            guard try db.tableExists(EventRow.databaseTableName) else {
                try createCurrentEventsTable(in: db)
                return
            }

            let columnNames = Set(try db.columns(in: EventRow.databaseTableName).map(\.name))

            if !columnNames.contains("camera_id") {
                try db.alter(table: EventRow.databaseTableName) { table in
                    table.add(column: "camera_id", .text)
                }
                try db.execute(sql: """
                    CREATE INDEX IF NOT EXISTS events_on_camera_id
                    ON \(EventRow.databaseTableName) (camera_id)
                    """)
            }

            if !columnNames.contains("event_type") {
                try db.alter(table: EventRow.databaseTableName) { table in
                    table.add(column: "event_type", .text)
                }
            }
        }

        return migrator
    }

    private static func createCurrentEventsTable(in db: Database) throws {
        try db.create(table: EventRow.databaseTableName) { table in
            table.autoIncrementedPrimaryKey("id")
            table.column("time_start", .datetime).notNull().indexed()
            table.column("time_end", .datetime)
            table.column("camera_id", .text).indexed()
            table.column("camera", .text).notNull().indexed()
            table.column("event_type", .text)
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
