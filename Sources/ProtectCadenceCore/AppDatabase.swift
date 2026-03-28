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
    case events
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
        countSemantics: CountSemantics = .events,
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
    public let fetchedSourceEventCount: Int
    public let normalizedEventCount: Int
    public let insertedEventCount: Int
    public let ignoredSourceEventCount: Int
    public let status: String

    public init(
        command: String,
        databasePath: String,
        window: QueryWindow? = nil,
        fetchedSourceEventCount: Int,
        normalizedEventCount: Int,
        insertedEventCount: Int,
        ignoredSourceEventCount: Int,
        status: String
    ) {
        self.command = command
        self.databasePath = databasePath
        self.window = window
        self.fetchedSourceEventCount = fetchedSourceEventCount
        self.normalizedEventCount = normalizedEventCount
        self.insertedEventCount = insertedEventCount
        self.ignoredSourceEventCount = ignoredSourceEventCount
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
    public let eventCount: Int
    public let sourceEventCount: Int

    public init(group: [String: String], eventCount: Int, sourceEventCount: Int) {
        self.group = group
        self.eventCount = eventCount
        self.sourceEventCount = sourceEventCount
    }
}

public struct SummaryResponse: Codable, Sendable {
    public let command: String
    public let databasePath: String
    public let filters: QueryFilters
    public let countSemantics: CountSemantics
    public let totalEventCount: Int
    public let totalSourceEventCount: Int
    public let groupBy: [SummaryGroupBy]
    public let groups: [SummaryGroup]

    public init(
        command: String,
        databasePath: String,
        filters: QueryFilters,
        countSemantics: CountSemantics = .events,
        totalEventCount: Int,
        totalSourceEventCount: Int,
        groupBy: [SummaryGroupBy],
        groups: [SummaryGroup]
    ) {
        self.command = command
        self.databasePath = databasePath
        self.filters = filters
        self.countSemantics = countSemantics
        self.totalEventCount = totalEventCount
        self.totalSourceEventCount = totalSourceEventCount
        self.groupBy = groupBy
        self.groups = groups
    }
}

public struct CompareRequest: Sendable {
    public let filters: QueryFilters
    public let comparisonWindow: QueryWindow
    public let groupBy: [SummaryGroupBy]

    public init(filters: QueryFilters, comparisonWindow: QueryWindow, groupBy: [SummaryGroupBy] = [.camera, .kind]) {
        self.filters = filters
        self.comparisonWindow = comparisonWindow
        self.groupBy = groupBy
    }
}

public struct CompareCounts: Codable, Sendable, Equatable {
    public let eventCount: Int
    public let sourceEventCount: Int

    public init(eventCount: Int, sourceEventCount: Int) {
        self.eventCount = eventCount
        self.sourceEventCount = sourceEventCount
    }
}

public struct CompareGroup: Codable, Sendable, Equatable {
    public let group: [String: String]
    public let window: CompareCounts
    public let comparisonWindow: CompareCounts
    public let eventCountDelta: Int
    public let sourceEventCountDelta: Int

    public init(
        group: [String: String],
        window: CompareCounts,
        comparisonWindow: CompareCounts,
        eventCountDelta: Int,
        sourceEventCountDelta: Int
    ) {
        self.group = group
        self.window = window
        self.comparisonWindow = comparisonWindow
        self.eventCountDelta = eventCountDelta
        self.sourceEventCountDelta = sourceEventCountDelta
    }
}

public struct CompareResponse: Codable, Sendable {
    public let command: String
    public let databasePath: String
    public let filters: QueryFilters
    public let comparisonWindow: QueryWindow
    public let countSemantics: CountSemantics
    public let groupBy: [SummaryGroupBy]
    public let totals: CompareCounts
    public let comparisonTotals: CompareCounts
    public let totalEventCountDelta: Int
    public let totalSourceEventCountDelta: Int
    public let groups: [CompareGroup]

    public init(
        command: String,
        databasePath: String,
        filters: QueryFilters,
        comparisonWindow: QueryWindow,
        countSemantics: CountSemantics = .events,
        groupBy: [SummaryGroupBy],
        totals: CompareCounts,
        comparisonTotals: CompareCounts,
        totalEventCountDelta: Int,
        totalSourceEventCountDelta: Int,
        groups: [CompareGroup]
    ) {
        self.command = command
        self.databasePath = databasePath
        self.filters = filters
        self.comparisonWindow = comparisonWindow
        self.countSemantics = countSemantics
        self.groupBy = groupBy
        self.totals = totals
        self.comparisonTotals = comparisonTotals
        self.totalEventCountDelta = totalEventCountDelta
        self.totalSourceEventCountDelta = totalSourceEventCountDelta
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

private struct SummarySnapshot {
    let totalEventCount: Int
    let totalSourceEventCount: Int
    let groups: [SummaryGroup]
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
            let snapshot = try fetchSummarySnapshot(
                db: db,
                filters: request.filters,
                groupBy: request.groupBy
            )

            return SummaryResponse(
                command: ProtectCadenceCommand.query.rawValue,
                databasePath: path,
                filters: request.filters,
                totalEventCount: snapshot.totalEventCount,
                totalSourceEventCount: snapshot.totalSourceEventCount,
                groupBy: request.groupBy,
                groups: snapshot.groups
            )
        }
    }

    public func fetchCompare(_ request: CompareRequest) throws -> CompareResponse {
        try dbQueue.read { db in
            let windowSnapshot = try fetchSummarySnapshot(
                db: db,
                filters: request.filters,
                groupBy: request.groupBy
            )
            let comparisonSnapshot = try fetchSummarySnapshot(
                db: db,
                filters: QueryFilters(
                    window: request.comparisonWindow,
                    cameras: request.filters.cameras,
                    kinds: request.filters.kinds,
                    weekdays: request.filters.weekdays,
                    timeOfDay: request.filters.timeOfDay
                ),
                groupBy: request.groupBy
            )

            return CompareResponse(
                command: ProtectCadenceCommand.query.rawValue,
                databasePath: path,
                filters: request.filters,
                comparisonWindow: request.comparisonWindow,
                groupBy: request.groupBy,
                totals: CompareCounts(
                    eventCount: windowSnapshot.totalEventCount,
                    sourceEventCount: windowSnapshot.totalSourceEventCount
                ),
                comparisonTotals: CompareCounts(
                    eventCount: comparisonSnapshot.totalEventCount,
                    sourceEventCount: comparisonSnapshot.totalSourceEventCount
                ),
                totalEventCountDelta: windowSnapshot.totalEventCount - comparisonSnapshot.totalEventCount,
                totalSourceEventCountDelta: windowSnapshot.totalSourceEventCount - comparisonSnapshot.totalSourceEventCount,
                groups: compareGroups(
                    windowGroups: windowSnapshot.groups,
                    comparisonGroups: comparisonSnapshot.groups,
                    groupBy: request.groupBy
                )
            )
        }
    }

    private func fetchSummaryGroups(
        db: Database,
        groupBy: [SummaryGroupBy],
        whereClause: EventWhereClause
    ) throws -> [SummaryGroup] {
        let selectColumns = groupBy.map { "\($0.selectSQL) AS \($0.alias)" }.joined(separator: ", ")
        let groupColumns = groupBy.map(\.alias).joined(separator: ", ")
        let sql = """
            SELECT \(selectColumns), COUNT(*) AS event_count, COUNT(DISTINCT event_id) AS source_event_count
            FROM \(EventRow.databaseTableName)
            \(whereClause.sql)
            GROUP BY \(groupColumns)
            ORDER BY \(groupColumns)
            """

        return try Row.fetchAll(db, sql: sql, arguments: whereClause.arguments).map { row in
            var values: [String: String] = [:]
            for dimension in groupBy {
                values[dimension.rawValue] = row[dimension.alias]
            }
            return SummaryGroup(
                group: values,
                eventCount: row["event_count"],
                sourceEventCount: row["source_event_count"]
            )
        }
    }

    private func fetchSummarySnapshot(
        db: Database,
        filters: QueryFilters,
        groupBy: [SummaryGroupBy]
    ) throws -> SummarySnapshot {
        let whereClause = try eventWhereClause(for: filters)

        let totalEventCount = try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*)
                FROM \(EventRow.databaseTableName)
                \(whereClause.sql)
                """,
            arguments: whereClause.arguments
        ) ?? 0

        let totalSourceEventCount = try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(DISTINCT event_id)
                FROM \(EventRow.databaseTableName)
                \(whereClause.sql)
                """,
            arguments: whereClause.arguments
        ) ?? 0

        return SummarySnapshot(
            totalEventCount: totalEventCount,
            totalSourceEventCount: totalSourceEventCount,
            groups: try fetchSummaryGroups(
                db: db,
                groupBy: groupBy,
                whereClause: whereClause
            )
        )
    }

    private func compareGroups(
        windowGroups: [SummaryGroup],
        comparisonGroups: [SummaryGroup],
        groupBy: [SummaryGroupBy]
    ) -> [CompareGroup] {
        let windowMap = Dictionary(uniqueKeysWithValues: windowGroups.map { (groupKey(for: $0.group, groupBy: groupBy), $0) })
        let comparisonMap = Dictionary(uniqueKeysWithValues: comparisonGroups.map { (groupKey(for: $0.group, groupBy: groupBy), $0) })
        let allKeys = Set(windowMap.keys).union(comparisonMap.keys).sorted()

        return allKeys.map { key in
            let windowGroup = windowMap[key]
            let comparisonGroup = comparisonMap[key]
            let group = windowGroup?.group ?? comparisonGroup?.group ?? [:]
            let windowCounts = CompareCounts(
                eventCount: windowGroup?.eventCount ?? 0,
                sourceEventCount: windowGroup?.sourceEventCount ?? 0
            )
            let comparisonCounts = CompareCounts(
                eventCount: comparisonGroup?.eventCount ?? 0,
                sourceEventCount: comparisonGroup?.sourceEventCount ?? 0
            )

            return CompareGroup(
                group: group,
                window: windowCounts,
                comparisonWindow: comparisonCounts,
                eventCountDelta: windowCounts.eventCount - comparisonCounts.eventCount,
                sourceEventCountDelta: windowCounts.sourceEventCount - comparisonCounts.sourceEventCount
            )
        }
    }

    private func groupKey(for group: [String: String], groupBy: [SummaryGroupBy]) -> String {
        groupBy.map { "\($0.rawValue)=\(group[$0.rawValue] ?? "")" }.joined(separator: "\u{001F}")
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
