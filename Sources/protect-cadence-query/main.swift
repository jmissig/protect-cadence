import Foundation
import ProtectCadenceCore

enum QueryCLIError: Error, CustomStringConvertible {
    case missingSubcommand
    case unknownSubcommand(String)
    case missingValue(String)
    case invalidInteger(String)

    var description: String {
        switch self {
        case .missingSubcommand:
            return "expected a subcommand such as 'recent'"
        case let .unknownSubcommand(command):
            return "unknown subcommand '\(command)'"
        case let .missingValue(flag):
            return "missing value for \(flag)"
        case let .invalidInteger(value):
            return "invalid integer '\(value)'"
        }
    }
}

struct QueryCLI {
    let databasePath: String
    let limit: Int
    let subcommand: String

    init(arguments: [String]) throws {
        var remaining = arguments
        var databasePath = ProtectCadencePaths.makeDefault().databasePath
        var limit = 50

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

        if remaining.contains("--db") {
            databasePath = try popValue(for: "--db")
        }

        if remaining.contains("--limit") {
            let rawLimit = try popValue(for: "--limit")
            guard let parsedLimit = Int(rawLimit) else {
                throw QueryCLIError.invalidInteger(rawLimit)
            }
            limit = parsedLimit
        }

        guard let subcommand = remaining.first else {
            throw QueryCLIError.missingSubcommand
        }

        self.databasePath = databasePath
        self.limit = limit
        self.subcommand = subcommand
    }
}

do {
    let cli = try QueryCLI(arguments: Array(CommandLine.arguments.dropFirst()))
    let database = try ProtectCadenceDatabase(path: cli.databasePath)

    switch cli.subcommand {
    case "recent":
        let response = try database.fetchRecentResponse(RecentEventsRequest(limit: cli.limit))
        print(try JSONOutput.encode(response))
    default:
        throw QueryCLIError.unknownSubcommand(cli.subcommand)
    }
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
