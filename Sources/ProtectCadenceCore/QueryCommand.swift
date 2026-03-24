import Foundation

public enum QuerySubcommand: String, Sendable {
    case recent
    case summary
}

public enum QueryCLIError: Error, CustomStringConvertible {
    case missingSubcommand
    case unknownSubcommand(String)
    case unexpectedArgument(String)
    case missingValue(String)
    case invalidInteger(flag: String, value: String)
    case invalidPositiveInteger(flag: String, value: String)

    public var description: String {
        switch self {
        case .missingSubcommand:
            return "expected a subcommand such as 'recent' or 'summary'"
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
        }
    }
}

public struct QueryCLI: Sendable {
    public let databasePath: String
    public let limit: Int
    public let lastHours: Int?
    public let subcommand: QuerySubcommand

    public init(arguments: [String]) throws {
        var remaining = arguments
        var databasePath = ProtectCadencePaths.makeDefault().databasePath
        var limit = 50
        var lastHours: Int?

        func popValue(for flag: String) throws -> String {
            guard let index = remaining.firstIndex(of: flag) else {
                throw QueryCLIError.missingValue(flag)
            }
            guard remaining.indices.contains(index + 1) else {
                throw QueryCLIError.missingValue(flag)
            }

            let value = remaining[index + 1]
            remaining.removeSubrange(index...(index + 1))
            return value
        }

        func popInteger(for flag: String) throws -> Int? {
            guard remaining.contains(flag) else {
                return nil
            }

            let rawValue = try popValue(for: flag)
            guard let parsed = Int(rawValue) else {
                throw QueryCLIError.invalidInteger(flag: flag, value: rawValue)
            }
            return parsed
        }

        if remaining.contains("--db") {
            databasePath = try popValue(for: "--db")
        }

        if let parsedLimit = try popInteger(for: "--limit") {
            limit = parsedLimit
        }

        if let parsedLastHours = try popInteger(for: "--last-hours") {
            guard parsedLastHours > 0 else {
                throw QueryCLIError.invalidPositiveInteger(flag: "--last-hours", value: String(parsedLastHours))
            }
            lastHours = parsedLastHours
        }

        guard let rawSubcommand = remaining.first else {
            throw QueryCLIError.missingSubcommand
        }
        guard remaining.count == 1 else {
            throw QueryCLIError.unexpectedArgument(remaining[1])
        }
        guard let subcommand = QuerySubcommand(rawValue: rawSubcommand) else {
            throw QueryCLIError.unknownSubcommand(rawSubcommand)
        }

        self.databasePath = databasePath
        self.limit = limit
        self.lastHours = lastHours
        self.subcommand = subcommand
    }

    public func recentRequest(now: Date = Date()) -> RecentEventsRequest {
        RecentEventsRequest(limit: limit, window: queryWindow(now: now))
    }

    public func summaryRequest(now: Date = Date()) -> SummaryRequest {
        SummaryRequest(window: requiredQueryWindow(now: now, defaultLastHours: 24))
    }

    private func queryWindow(now: Date, defaultLastHours: Int? = nil) -> QueryWindow? {
        guard let hours = lastHours ?? defaultLastHours else {
            return nil
        }

        let start = now.addingTimeInterval(-Double(hours) * 60 * 60)
        return QueryWindow(start: start, end: now)
    }

    private func requiredQueryWindow(now: Date, defaultLastHours: Int) -> QueryWindow {
        queryWindow(now: now, defaultLastHours: defaultLastHours)!
    }
}

public enum QueryCommandOutput: Encodable, Sendable {
    case recent(RecentEventsResponse)
    case summary(SummaryResponse)

    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .recent(response):
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
        let database = try ProtectCadenceDatabase(path: cli.databasePath)

        switch cli.subcommand {
        case .recent:
            return .recent(try database.fetchRecentResponse(cli.recentRequest(now: now)))
        case .summary:
            return .summary(try database.fetchSummary(cli.summaryRequest(now: now)))
        }
    }
}
