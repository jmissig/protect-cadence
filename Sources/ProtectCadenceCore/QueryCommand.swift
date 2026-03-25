import Foundation

public enum QuerySubcommand: String, Sendable {
    case events
    case summary
}

public enum EventOrder: String, Codable, Sendable {
    case newest
    case oldest
}

public enum SummaryGroupBy: String, Codable, Sendable, CaseIterable {
    case camera
    case kind
    case date
    case hour
    case weekday
}

public struct QueryTimeOfDayRange: Codable, Sendable, Equatable {
    public let startHour: Int
    public let startMinute: Int
    public let endHour: Int
    public let endMinute: Int

    public init(startHour: Int, startMinute: Int, endHour: Int, endMinute: Int) {
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
    }

    public var startMinutes: Int {
        (startHour * 60) + startMinute
    }

    public var endMinutes: Int {
        (endHour * 60) + endMinute
    }

    public var overnight: Bool {
        startMinutes > endMinutes
    }

    public var rawValue: String {
        "\(Self.format(startHour, startMinute))-\(Self.format(endHour, endMinute))"
    }

    private static func format(_ hour: Int, _ minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }
}

public struct QueryFilters: Codable, Sendable, Equatable {
    public let window: QueryWindow?
    public let cameras: [String]
    public let kinds: [String]
    public let timeOfDay: QueryTimeOfDayRange?

    public init(
        window: QueryWindow? = nil,
        cameras: [String] = [],
        kinds: [String] = [],
        timeOfDay: QueryTimeOfDayRange? = nil
    ) {
        self.window = window
        self.cameras = cameras
        self.kinds = kinds
        self.timeOfDay = timeOfDay
    }
}

public struct QueryWindowBounds: Sendable, Equatable {
    public let since: Date?
    public let until: Date?

    public init(since: Date? = nil, until: Date? = nil) {
        self.since = since
        self.until = until
    }

    public var isEmpty: Bool {
        since == nil && until == nil
    }

    public func resolve(now: Date) throws -> QueryWindow {
        let start = since ?? now
        let end = until ?? now

        guard start < end else {
            throw QueryCLIError.invalidWindowRange(start: start, end: end)
        }

        return QueryWindow(start: start, end: end)
    }
}

public enum QueryCLIError: Error, CustomStringConvertible {
    case missingSubcommand
    case unknownSubcommand(String)
    case unexpectedArgument(String)
    case missingValue(String)
    case invalidInteger(flag: String, value: String)
    case invalidPositiveInteger(flag: String, value: String)
    case invalidISO8601(flag: String, value: String)
    case invalidTimeOfDay(String)
    case invalidOrder(String)
    case invalidGroupBy(String)
    case conflictingWindowFlags
    case untilRequiresSince
    case invalidWindowRange(start: Date, end: Date)

    public var description: String {
        switch self {
        case .missingSubcommand:
            return "expected a subcommand such as 'events' or 'summary'"
        case let .unknownSubcommand(command):
            return "unknown subcommand '\(command)'"
        case let .unexpectedArgument(argument):
            return "unexpected argument '\(argument)'"
        case let .missingValue(flag):
            return "missing value for \(flag)"
        case let .invalidInteger(flag, value):
            return "invalid integer '\(value)' for \(flag)"
        case let .invalidPositiveInteger(flag, value):
            return "\(flag) must be greater than zero, got '\(value)'"
        case let .invalidISO8601(flag, value):
            return "invalid ISO8601 value '\(value)' for \(flag)"
        case let .invalidTimeOfDay(value):
            return "invalid time-of-day range '\(value)', expected HH:MM-HH:MM"
        case let .invalidOrder(value):
            return "invalid value '\(value)' for --order, expected newest or oldest"
        case let .invalidGroupBy(value):
            return "invalid value '\(value)' for --group-by"
        case .conflictingWindowFlags:
            return "use either --last-hours or --since/--until, not both"
        case .untilRequiresSince:
            return "--until requires --since"
        case let .invalidWindowRange(start, end):
            return "resolved time window must have start earlier than end, got \(QueryDateParser.encode(start)) to \(QueryDateParser.encode(end))"
        }
    }
}

enum QueryDateParser {
    private static func makeInternetDateTimeFormatter(fractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }

    static func parse(_ value: String) -> Date? {
        makeInternetDateTimeFormatter(fractionalSeconds: true).date(from: value)
            ?? makeInternetDateTimeFormatter(fractionalSeconds: false).date(from: value)
    }

    static func encode(_ date: Date) -> String {
        makeInternetDateTimeFormatter(fractionalSeconds: false).string(from: date)
    }
}

public struct QueryCLI: Sendable {
    public let databasePathOverride: String?
    public let configPath: String
    public let subcommand: QuerySubcommand
    public let filters: QueryFilters
    public let windowBounds: QueryWindowBounds?
    public let lastHours: Int?
    public let limit: Int
    public let order: EventOrder
    public let groupBy: [SummaryGroupBy]

    public init(arguments: [String]) throws {
        var remaining = arguments
        var databasePathOverride: String?
        var configPath = ProtectCadencePaths.defaultConfigPath()
        var limit = 50
        var lastHours: Int?
        var explicitSince: Date?
        var explicitUntil: Date?
        var cameras: [String] = []
        var kinds: [String] = []
        var timeOfDay: QueryTimeOfDayRange?
        var order: EventOrder = .newest
        var groupBy: [SummaryGroupBy] = []

        guard let rawSubcommand = remaining.first else {
            throw QueryCLIError.missingSubcommand
        }
        guard let subcommand = QuerySubcommand(rawValue: rawSubcommand) else {
            throw QueryCLIError.unknownSubcommand(rawSubcommand)
        }
        remaining.removeFirst()

        func popValue(index: inout Int, flag: String) throws -> String {
            let valueIndex = index + 1
            guard remaining.indices.contains(valueIndex) else {
                throw QueryCLIError.missingValue(flag)
            }
            index += 2
            return remaining[valueIndex]
        }

        func parsePositiveInteger(_ rawValue: String, flag: String) throws -> Int {
            guard let parsed = Int(rawValue) else {
                throw QueryCLIError.invalidInteger(flag: flag, value: rawValue)
            }
            guard parsed > 0 else {
                throw QueryCLIError.invalidPositiveInteger(flag: flag, value: rawValue)
            }
            return parsed
        }

        var index = 0
        while index < remaining.count {
            let argument = remaining[index]

            switch argument {
            case "--db":
                databasePathOverride = try popValue(index: &index, flag: argument)
            case "--config":
                configPath = try popValue(index: &index, flag: argument)
            case "--limit":
                limit = try parsePositiveInteger(try popValue(index: &index, flag: argument), flag: argument)
            case "--last-hours":
                lastHours = try parsePositiveInteger(try popValue(index: &index, flag: argument), flag: argument)
            case "--since":
                let rawValue = try popValue(index: &index, flag: argument)
                guard let parsed = QueryDateParser.parse(rawValue) else {
                    throw QueryCLIError.invalidISO8601(flag: argument, value: rawValue)
                }
                explicitSince = parsed
            case "--until":
                let rawValue = try popValue(index: &index, flag: argument)
                guard let parsed = QueryDateParser.parse(rawValue) else {
                    throw QueryCLIError.invalidISO8601(flag: argument, value: rawValue)
                }
                explicitUntil = parsed
            case "--camera":
                cameras.append(try popValue(index: &index, flag: argument))
            case "--kind":
                kinds.append(try popValue(index: &index, flag: argument))
            case "--time-of-day":
                let rawValue = try popValue(index: &index, flag: argument)
                guard let parsed = Self.parseTimeOfDayRange(rawValue) else {
                    throw QueryCLIError.invalidTimeOfDay(rawValue)
                }
                timeOfDay = parsed
            case "--order":
                let rawValue = try popValue(index: &index, flag: argument)
                guard let parsed = EventOrder(rawValue: rawValue) else {
                    throw QueryCLIError.invalidOrder(rawValue)
                }
                order = parsed
            case "--group-by":
                let rawValue = try popValue(index: &index, flag: argument)
                guard let parsed = SummaryGroupBy(rawValue: rawValue) else {
                    throw QueryCLIError.invalidGroupBy(rawValue)
                }
                groupBy.append(parsed)
            default:
                throw QueryCLIError.unexpectedArgument(argument)
            }
        }

        if lastHours != nil, explicitSince != nil || explicitUntil != nil {
            throw QueryCLIError.conflictingWindowFlags
        }

        if explicitSince == nil, explicitUntil != nil {
            throw QueryCLIError.untilRequiresSince
        }

        let windowBounds: QueryWindowBounds?
        if explicitSince != nil || explicitUntil != nil {
            let bounds = QueryWindowBounds(since: explicitSince, until: explicitUntil)
            if let explicitSince, let explicitUntil {
                guard explicitSince < explicitUntil else {
                    throw QueryCLIError.invalidWindowRange(start: explicitSince, end: explicitUntil)
                }
            }
            windowBounds = bounds
        } else {
            windowBounds = nil
        }

        self.databasePathOverride = databasePathOverride
        self.configPath = configPath
        self.subcommand = subcommand
        self.filters = QueryFilters(
            cameras: cameras,
            kinds: kinds,
            timeOfDay: timeOfDay
        )
        self.windowBounds = windowBounds
        self.lastHours = lastHours
        self.limit = limit
        self.order = order
        self.groupBy = groupBy
    }

    public func eventsRequest(now: Date = Date()) throws -> EventsRequest {
        EventsRequest(limit: limit, order: order, filters: try resolvedFilters(now: now))
    }

    public func summaryRequest(now: Date = Date()) throws -> SummaryRequest {
        SummaryRequest(
            filters: try resolvedFilters(now: now, defaultLastHours: 24),
            groupBy: groupBy.isEmpty ? [.camera, .kind] : groupBy
        )
    }

    private func resolvedFilters(now: Date, defaultLastHours: Int? = nil) throws -> QueryFilters {
        if let windowBounds {
            return QueryFilters(
                window: try windowBounds.resolve(now: now),
                cameras: filters.cameras,
                kinds: filters.kinds,
                timeOfDay: filters.timeOfDay
            )
        }

        if let lastHours {
            return QueryFilters(
                window: QueryWindow(
                    start: now.addingTimeInterval(-Double(lastHours) * 60 * 60),
                    end: now
                ),
                cameras: filters.cameras,
                kinds: filters.kinds,
                timeOfDay: filters.timeOfDay
            )
        }

        guard let defaultLastHours else {
            return filters
        }

        return QueryFilters(
            window: QueryWindow(
                start: now.addingTimeInterval(-Double(defaultLastHours) * 60 * 60),
                end: now
            ),
            cameras: filters.cameras,
            kinds: filters.kinds,
            timeOfDay: filters.timeOfDay
        )
    }

    private static func parseTimeOfDayRange(_ rawValue: String) -> QueryTimeOfDayRange? {
        let parts = rawValue.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let start = parseClock(String(parts[0])),
              let end = parseClock(String(parts[1]))
        else {
            return nil
        }

        return QueryTimeOfDayRange(
            startHour: start.hour,
            startMinute: start.minute,
            endHour: end.hour,
            endMinute: end.minute
        )
    }

    private static func parseClock(_ rawValue: String) -> (hour: Int, minute: Int)? {
        let parts = rawValue.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute)
        else {
            return nil
        }

        return (hour, minute)
    }
}

public enum QueryCommandOutput: Encodable, Sendable {
    case events(EventsResponse)
    case summary(SummaryResponse)

    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .events(response):
            try response.encode(to: encoder)
        case let .summary(response):
            try response.encode(to: encoder)
        }
    }
}

public enum ProtectCadenceQueryRunner {
    public static func run(arguments: [String], now: Date = Date()) throws -> QueryCommandOutput {
        try run(cli: QueryCLI(arguments: arguments), now: now)
    }

    public static func run(cli: QueryCLI, now: Date = Date()) throws -> QueryCommandOutput {
        let databasePath = try ProtectCadenceDatabasePathResolver.resolve(
            explicitOverride: cli.databasePathOverride,
            configPath: cli.configPath
        )
        let database = try ProtectCadenceDatabase(path: databasePath)

        switch cli.subcommand {
        case .events:
            return .events(try database.fetchEventsResponse(try cli.eventsRequest(now: now)))
        case .summary:
            return .summary(try database.fetchSummary(try cli.summaryRequest(now: now)))
        }
    }
}
