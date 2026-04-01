import Foundation

public enum QuerySubcommand: String, Sendable {
    case events
    case summary
    case compare
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

public enum QueryWeekday: String, Codable, Sendable, CaseIterable {
    case sun
    case mon
    case tue
    case wed
    case thu
    case fri
    case sat

    public var sqliteWeekdayNumber: String {
        switch self {
        case .sun:
            return "0"
        case .mon:
            return "1"
        case .tue:
            return "2"
        case .wed:
            return "3"
        case .thu:
            return "4"
        case .fri:
            return "5"
        case .sat:
            return "6"
        }
    }

    public static let weekdays: [Self] = [.mon, .tue, .wed, .thu, .fri]
    public static let weekend: [Self] = [.sun, .sat]
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
    public let weekdays: [QueryWeekday]
    public let timeOfDay: QueryTimeOfDayRange?
    public let date: String?
    public let hour: String?

    public init(
        window: QueryWindow? = nil,
        cameras: [String] = [],
        kinds: [String] = [],
        weekdays: [QueryWeekday] = [],
        timeOfDay: QueryTimeOfDayRange? = nil,
        date: String? = nil,
        hour: String? = nil
    ) {
        self.window = window
        self.cameras = cameras
        self.kinds = kinds
        self.weekdays = weekdays
        self.timeOfDay = timeOfDay
        self.date = date
        self.hour = hour
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

public enum CompareMode: Sendable, Equatable {
    case explicitWindow(QueryWindowBounds)
    case sameWindowYesterday
    case sameWindowLastWeek
    case windowBefore(Date)
    case windowAfter(Date)
    case priorWindow

    public func resolveComparisonWindow(
        primaryWindow: QueryWindow,
        now: Date,
        calendar: Calendar = .current
    ) throws -> QueryWindow {
        switch self {
        case let .explicitWindow(bounds):
            return try bounds.resolve(now: now)
        case .sameWindowYesterday:
            return try QueryWindow.shiftedByLocalDays(
                primaryWindow,
                days: -1,
                calendar: calendar
            )
        case .sameWindowLastWeek:
            return try QueryWindow.shiftedByLocalDays(
                primaryWindow,
                days: -7,
                calendar: calendar
            )
        case let .windowBefore(boundary):
            let duration = primaryWindow.end.timeIntervalSince(primaryWindow.start)
            return QueryWindow(
                start: boundary.addingTimeInterval(-duration),
                end: boundary
            )
        case let .windowAfter(boundary):
            let duration = primaryWindow.end.timeIntervalSince(primaryWindow.start)
            return QueryWindow(
                start: boundary,
                end: boundary.addingTimeInterval(duration)
            )
        case .priorWindow:
            return QueryWindow.priorWindow(matching: primaryWindow)
        }
    }
}

private extension QueryWindow {
    static func shiftedByLocalDays(
        _ window: QueryWindow,
        days: Int,
        calendar: Calendar = .current
    ) throws -> QueryWindow {
        guard let shiftedStart = calendar.date(byAdding: .day, value: days, to: window.start),
              let shiftedEnd = calendar.date(byAdding: .day, value: days, to: window.end)
        else {
            throw QueryCLIError.invalidWindowRange(start: window.start, end: window.end)
        }

        return QueryWindow(start: shiftedStart, end: shiftedEnd)
    }

    static func priorWindow(matching window: QueryWindow) -> QueryWindow {
        let duration = window.end.timeIntervalSince(window.start)
        return QueryWindow(
            start: window.start.addingTimeInterval(-duration),
            end: window.start
        )
    }
}

public enum QueryCLIError: Error, CustomStringConvertible {
    case missingSubcommand
    case unknownSubcommand(String)
    case unexpectedArgument(String)
    case missingValue(String)
    case invalidInteger(flag: String, value: String)
    case invalidPositiveInteger(flag: String, value: String)
    case invalidTimeBound(flag: String, value: String)
    case invalidTimeOfDay(String)
    case invalidWeekday(String)
    case invalidDate(String)
    case invalidHour(String)
    case invalidOrder(String)
    case invalidGroupBy(String)
    case conflictingWindowFlags
    case conflictingComparisonWindowFlags
    case untilRequiresSince
    case compareRequiresPrimaryWindow
    case compareRequiresExplicitWindow
    case compareMissingMode
    case invalidWindowRange(start: Date, end: Date)

    public var description: String {
        switch self {
        case .missingSubcommand:
            return "expected a subcommand such as 'events', 'summary', or 'compare'"
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
        case let .invalidTimeBound(flag, value):
            return "invalid time value '\(value)' for \(flag), expected ISO 8601 with Z or explicit offset, or local YYYY-MM-DD[ T]HH:MM[:SS]"
        case let .invalidTimeOfDay(value):
            return "invalid time-of-day range '\(value)', expected HH:MM-HH:MM"
        case let .invalidWeekday(value):
            return "invalid value '\(value)' for --day-of-week, expected sun, mon, tue, wed, thu, fri, or sat"
        case let .invalidDate(value):
            return "invalid value '\(value)' for --date, expected local YYYY-MM-DD"
        case let .invalidHour(value):
            return "invalid value '\(value)' for --hour, expected HH:00"
        case let .invalidOrder(value):
            return "invalid value '\(value)' for --order, expected newest or oldest"
        case let .invalidGroupBy(value):
            return "invalid value '\(value)' for --group-by"
        case .conflictingWindowFlags:
            return "use either --last-hours or --since/--until, not both"
        case .conflictingComparisonWindowFlags:
            return "use exactly one compare mode: --vs-since/--vs-until, --vs-same-window-yesterday, --vs-same-window-last-week, --vs-window-before, --vs-window-after, or --vs-prior-window"
        case .untilRequiresSince:
            return "--until requires --since"
        case .compareRequiresPrimaryWindow:
            return "compare requires a primary window via --last-hours or --since/--until"
        case .compareRequiresExplicitWindow:
            return "--vs-since requires --vs-until, and --vs-until requires --vs-since"
        case .compareMissingMode:
            return "compare requires one compare mode: --vs-since/--vs-until, --vs-same-window-yesterday, --vs-same-window-last-week, --vs-window-before, --vs-window-after, or --vs-prior-window"
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

    static func parse(
        _ value: String,
        timeZone: TimeZone = .current,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Date? {
        parseISO8601(value) ?? parseLocal(value, timeZone: timeZone, calendar: calendar)
    }

    static func encode(_ date: Date) -> String {
        makeInternetDateTimeFormatter(fractionalSeconds: false).string(from: date)
    }

    private static func parseISO8601(_ value: String) -> Date? {
        makeInternetDateTimeFormatter(fractionalSeconds: true).date(from: value)
            ?? makeInternetDateTimeFormatter(fractionalSeconds: false).date(from: value)
    }

    private static func parseLocal(_ value: String, timeZone: TimeZone, calendar: Calendar) -> Date? {
        let parts = value.split(separator: " ", omittingEmptySubsequences: false)
        let datePart: String
        let timePart: String?

        switch parts.count {
        case 1:
            let single = String(parts[0])
            if single.contains("T") {
                let dateTimeParts = single.split(separator: "T", omittingEmptySubsequences: false)
                guard dateTimeParts.count == 2 else {
                    return nil
                }
                datePart = String(dateTimeParts[0])
                timePart = String(dateTimeParts[1])
            } else {
                datePart = single
                timePart = nil
            }
        case 2:
            datePart = String(parts[0])
            timePart = String(parts[1])
        default:
            return nil
        }

        guard let date = parseLocalDate(datePart) else {
            return nil
        }

        let time: (hour: Int, minute: Int, second: Int)
        if let timePart {
            guard let parsedTime = parseLocalTime(timePart) else {
                return nil
            }
            time = parsedTime
        } else {
            time = (hour: 0, minute: 0, second: 0)
        }

        var localCalendar = calendar
        localCalendar.timeZone = timeZone
        let components = DateComponents(
            timeZone: timeZone,
            year: date.year,
            month: date.month,
            day: date.day,
            hour: time.hour,
            minute: time.minute,
            second: time.second
        )

        guard let resolved = localCalendar.date(from: components) else {
            return nil
        }

        // Reject local wall-clock values that Foundation normalizes, including DST gaps.
        let resolvedComponents = localCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: resolved
        )
        guard resolvedComponents.year == date.year,
              resolvedComponents.month == date.month,
              resolvedComponents.day == date.day,
              resolvedComponents.hour == time.hour,
              resolvedComponents.minute == time.minute,
              resolvedComponents.second == time.second
        else {
            return nil
        }

        return resolved
    }

    private static func parseLocalDate(_ rawValue: String) -> (year: Int, month: Int, day: Int)? {
        let parts = rawValue.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1...12).contains(month),
              (1...31).contains(day)
        else {
            return nil
        }

        return (year, month, day)
    }

    private static func parseLocalTime(_ rawValue: String) -> (hour: Int, minute: Int, second: Int)? {
        let parts = rawValue.split(separator: ":", omittingEmptySubsequences: false)
        guard (parts.count == 2 || parts.count == 3),
              parts[0].count == 2,
              parts[1].count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute)
        else {
            return nil
        }

        let second: Int
        if parts.count == 3 {
            guard parts[2].count == 2,
                  let parsedSecond = Int(parts[2]),
                  (0...59).contains(parsedSecond)
            else {
                return nil
            }
            second = parsedSecond
        } else {
            second = 0
        }

        return (hour, minute, second)
    }
}

public struct QueryCLI: Sendable {
    public let compareMode: CompareMode?
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
        guard let rawSubcommand = arguments.first else {
            throw QueryCLIError.missingSubcommand
        }
        guard let subcommand = QuerySubcommand(rawValue: rawSubcommand) else {
            throw QueryCLIError.unknownSubcommand(rawSubcommand)
        }
        let remaining = Array(arguments.dropFirst())

        switch subcommand {
        case .events:
            try self.init(command: ProtectCadenceCLIQueryEventsCommand.parse(remaining))
        case .summary:
            try self.init(command: ProtectCadenceCLIQuerySummaryCommand.parse(remaining))
        case .compare:
            try self.init(command: ProtectCadenceCLIQueryCompareCommand.parse(remaining))
        }
    }

    init(command: ProtectCadenceCLIQueryEventsCommand) throws {
        try self.init(
            subcommand: .events,
            databasePathOverride: command.databaseOptions.databasePathOverride,
            configPath: command.configOptions.configPath,
            primaryWindow: command.primaryWindow,
            filterOptions: command.filters,
            limit: command.limit,
            orderRaw: command.order,
            groupByRaw: [],
            compareOptions: nil
        )
    }

    init(command: ProtectCadenceCLIQuerySummaryCommand) throws {
        try self.init(
            subcommand: .summary,
            databasePathOverride: command.databaseOptions.databasePathOverride,
            configPath: command.configOptions.configPath,
            primaryWindow: command.primaryWindow,
            filterOptions: command.filters,
            limit: 50,
            orderRaw: EventOrder.newest.rawValue,
            groupByRaw: command.groupBy,
            compareOptions: nil
        )
    }

    init(command: ProtectCadenceCLIQueryCompareCommand) throws {
        try self.init(
            subcommand: .compare,
            databasePathOverride: command.databaseOptions.databasePathOverride,
            configPath: command.configOptions.configPath,
            primaryWindow: command.primaryWindow,
            filterOptions: command.filters,
            limit: 50,
            orderRaw: EventOrder.newest.rawValue,
            groupByRaw: command.groupBy,
            compareOptions: command.compareMode
        )
    }

    private init(
        subcommand: QuerySubcommand,
        databasePathOverride: String?,
        configPath: String,
        primaryWindow: ProtectCadencePrimaryWindowOptions,
        filterOptions: ProtectCadenceQueryFilterOptions,
        limit: Int,
        orderRaw: String,
        groupByRaw: [String],
        compareOptions: ProtectCadenceCompareModeOptions?
    ) throws {
        let lastHours = try Self.parsePositiveInteger(primaryWindow.lastHours, flag: "--last-hours")
        let explicitSince = try Self.parseTimeBound(primaryWindow.since, flag: "--since")
        let explicitUntil = try Self.parseTimeBound(primaryWindow.until, flag: "--until")

        if lastHours != nil, explicitSince != nil || explicitUntil != nil {
            throw QueryCLIError.conflictingWindowFlags
        }

        if explicitSince == nil, explicitUntil != nil {
            throw QueryCLIError.untilRequiresSince
        }

        let windowBounds: QueryWindowBounds?
        if explicitSince != nil || explicitUntil != nil {
            let bounds = QueryWindowBounds(since: explicitSince, until: explicitUntil)
            if let explicitSince, let explicitUntil, explicitSince >= explicitUntil {
                throw QueryCLIError.invalidWindowRange(start: explicitSince, end: explicitUntil)
            }
            windowBounds = bounds
        } else {
            windowBounds = nil
        }

        let compareMode = try Self.resolveCompareMode(compareOptions)
        let order = try Self.parseOrder(orderRaw)
        let groupBy = try groupByRaw.map(Self.parseGroupBy)

        self.compareMode = compareMode
        self.databasePathOverride = databasePathOverride
        self.configPath = configPath
        self.subcommand = subcommand
        self.filters = try Self.parseFilters(filterOptions)
        self.windowBounds = windowBounds
        self.lastHours = lastHours
        self.limit = try Self.parsePositiveInteger(limit, flag: "--limit") ?? 50
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

    public func compareRequest(now: Date = Date()) throws -> CompareRequest {
        guard windowBounds != nil || lastHours != nil else {
            throw QueryCLIError.compareRequiresPrimaryWindow
        }

        let filters = try resolvedFilters(now: now)
        guard let primaryWindow = filters.window else {
            throw QueryCLIError.compareRequiresPrimaryWindow
        }

        guard let compareMode else {
            throw QueryCLIError.compareMissingMode
        }

        let comparisonWindow = try compareMode.resolveComparisonWindow(
            primaryWindow: primaryWindow,
            now: now
        )

        return CompareRequest(
            filters: filters,
            compareMode: compareMode,
            comparisonWindow: comparisonWindow,
            groupBy: groupBy.isEmpty ? [.camera, .kind] : groupBy
        )
    }

    private func resolvedFilters(now: Date, defaultLastHours: Int? = nil) throws -> QueryFilters {
        if let windowBounds {
            return QueryFilters(
                window: try windowBounds.resolve(now: now),
                cameras: filters.cameras,
                kinds: filters.kinds,
                weekdays: filters.weekdays,
                timeOfDay: filters.timeOfDay,
                date: filters.date,
                hour: filters.hour
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
                weekdays: filters.weekdays,
                timeOfDay: filters.timeOfDay,
                date: filters.date,
                hour: filters.hour
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
            weekdays: filters.weekdays,
            timeOfDay: filters.timeOfDay,
            date: filters.date,
            hour: filters.hour
        )
    }

    private static func uniqueWeekdays(_ weekdays: [QueryWeekday]) -> [QueryWeekday] {
        var seen = Set<QueryWeekday>()
        var unique: [QueryWeekday] = []

        for weekday in weekdays where seen.insert(weekday).inserted {
            unique.append(weekday)
        }

        return unique
    }

    private static func parsePositiveInteger(_ value: Int?, flag: String) throws -> Int? {
        guard let value else {
            return nil
        }
        guard value > 0 else {
            throw QueryCLIError.invalidPositiveInteger(flag: flag, value: String(value))
        }
        return value
    }

    private static func parseTimeBound(_ rawValue: String?, flag: String) throws -> Date? {
        guard let rawValue else {
            return nil
        }
        guard let parsed = QueryDateParser.parse(rawValue) else {
            throw QueryCLIError.invalidTimeBound(flag: flag, value: rawValue)
        }
        return parsed
    }

    private static func parseFilters(_ options: ProtectCadenceQueryFilterOptions) throws -> QueryFilters {
        var weekdays: [QueryWeekday] = []
        for rawValue in options.dayOfWeek {
            guard let parsed = QueryWeekday(rawValue: rawValue) else {
                throw QueryCLIError.invalidWeekday(rawValue)
            }
            weekdays.append(parsed)
        }
        if options.weekday {
            weekdays.append(contentsOf: QueryWeekday.weekdays)
        }
        if options.weekend {
            weekdays.append(contentsOf: QueryWeekday.weekend)
        }

        let timeOfDay: QueryTimeOfDayRange?
        if let rawTimeOfDay = options.timeOfDay {
            guard let parsed = parseTimeOfDayRange(rawTimeOfDay) else {
                throw QueryCLIError.invalidTimeOfDay(rawTimeOfDay)
            }
            timeOfDay = parsed
        } else {
            timeOfDay = nil
        }

        if let date = options.date, !isValidLocalDateBucket(date) {
            throw QueryCLIError.invalidDate(date)
        }

        if let hour = options.hour, !isValidHourBucket(hour) {
            throw QueryCLIError.invalidHour(hour)
        }

        return QueryFilters(
            cameras: options.cameras,
            kinds: options.kinds,
            weekdays: uniqueWeekdays(weekdays),
            timeOfDay: timeOfDay,
            date: options.date,
            hour: options.hour
        )
    }

    private static func parseOrder(_ rawValue: String) throws -> EventOrder {
        guard let parsed = EventOrder(rawValue: rawValue) else {
            throw QueryCLIError.invalidOrder(rawValue)
        }
        return parsed
    }

    private static func parseGroupBy(_ rawValue: String) throws -> SummaryGroupBy {
        guard let parsed = SummaryGroupBy(rawValue: rawValue) else {
            throw QueryCLIError.invalidGroupBy(rawValue)
        }
        return parsed
    }

    private static func resolveCompareMode(_ options: ProtectCadenceCompareModeOptions?) throws -> CompareMode? {
        guard let options else {
            return nil
        }

        let comparisonSince = try parseTimeBound(options.since, flag: "--vs-since")
        let comparisonUntil = try parseTimeBound(options.until, flag: "--vs-until")
        let comparisonWindowBeforeBoundary = try parseTimeBound(options.windowBefore, flag: "--vs-window-before")
        let comparisonWindowAfterBoundary = try parseTimeBound(options.windowAfter, flag: "--vs-window-after")

        var comparisonHelperModes: [CompareMode] = []
        if options.sameWindowYesterday {
            comparisonHelperModes.append(.sameWindowYesterday)
        }
        if options.sameWindowLastWeek {
            comparisonHelperModes.append(.sameWindowLastWeek)
        }
        if options.priorWindow {
            comparisonHelperModes.append(.priorWindow)
        }

        let comparisonBoundaryModeCount = (comparisonWindowBeforeBoundary != nil ? 1 : 0)
            + (comparisonWindowAfterBoundary != nil ? 1 : 0)

        if comparisonHelperModes.count + comparisonBoundaryModeCount > 1
            || ((comparisonWindowBeforeBoundary != nil || comparisonWindowAfterBoundary != nil) && (comparisonSince != nil || comparisonUntil != nil))
            || (!comparisonHelperModes.isEmpty && (comparisonSince != nil || comparisonUntil != nil))
        {
            throw QueryCLIError.conflictingComparisonWindowFlags
        }

        if (comparisonSince == nil) != (comparisonUntil == nil) {
            throw QueryCLIError.compareRequiresExplicitWindow
        }

        if let comparisonSince, let comparisonUntil {
            guard comparisonSince < comparisonUntil else {
                throw QueryCLIError.invalidWindowRange(start: comparisonSince, end: comparisonUntil)
            }
            return .explicitWindow(QueryWindowBounds(since: comparisonSince, until: comparisonUntil))
        }
        if let comparisonWindowBeforeBoundary {
            return .windowBefore(comparisonWindowBeforeBoundary)
        }
        if let comparisonWindowAfterBoundary {
            return .windowAfter(comparisonWindowAfterBoundary)
        }
        return comparisonHelperModes.first
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

    private static func isValidLocalDateBucket(_ rawValue: String) -> Bool {
        let parts = rawValue.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else {
            return false
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = DateComponents(
            timeZone: .current,
            year: year,
            month: month,
            day: day,
            hour: 0,
            minute: 0,
            second: 0
        )

        guard let resolved = calendar.date(from: components) else {
            return false
        }

        let resolvedComponents = calendar.dateComponents([.year, .month, .day], from: resolved)
        return resolvedComponents.year == year
            && resolvedComponents.month == month
            && resolvedComponents.day == day
    }

    private static func isValidHourBucket(_ rawValue: String) -> Bool {
        guard let parsed = parseClock(rawValue) else {
            return false
        }

        return parsed.minute == 0
    }
}

public enum QueryCommandOutput: Encodable, Sendable {
    case events(EventsResponse)
    case summary(SummaryResponse)
    case compare(CompareResponse)

    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .events(response):
            try response.encode(to: encoder)
        case let .summary(response):
            try response.encode(to: encoder)
        case let .compare(response):
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
        case .compare:
            return .compare(try database.fetchCompare(try cli.compareRequest(now: now)))
        }
    }
}
