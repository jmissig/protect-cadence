import Foundation

public enum ProtectCadenceSubcommand: String, Sendable {
    case ingest
    case query
    case auth
}

public enum ProtectCadenceCLIError: Error, CustomStringConvertible {
    case missingSubcommand
    case unknownSubcommand(String)
    case unexpectedArgument(String)

    public var description: String {
        switch self {
        case .missingSubcommand:
            return "expected a subcommand such as 'ingest', 'query', or 'auth'"
        case let .unknownSubcommand(command):
            return "unknown subcommand '\(command)'"
        case let .unexpectedArgument(argument):
            return "unexpected argument '\(argument)'"
        }
    }
}

public struct AuthCommandResponse: Codable, Sendable, Equatable {
    public let command: String
    public let status: String
    public let message: String

    public init(command: String, status: String, message: String) {
        self.command = command
        self.status = status
        self.message = message
    }
}

public enum ProtectCadenceCLIOutput: Encodable, Sendable {
    case ingest(IngestResponse)
    case query(QueryCommandOutput)
    case auth(AuthCommandResponse)

    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .ingest(response):
            try response.encode(to: encoder)
        case let .query(response):
            try response.encode(to: encoder)
        case let .auth(response):
            try response.encode(to: encoder)
        }
    }
}

public enum ProtectCadenceAuthRunner {
    public static func run(arguments: [String]) throws -> AuthCommandResponse {
        if let first = arguments.first, first != "status" {
            throw ProtectCadenceCLIError.unexpectedArgument(first)
        }

        if arguments.count > 1 {
            throw ProtectCadenceCLIError.unexpectedArgument(arguments[1])
        }

        return AuthCommandResponse(
            command: ProtectCadenceCommand.auth.rawValue,
            status: "stub",
            message: "auth is not built out yet; use per-user config and Keychain-backed setup when this surface lands"
        )
    }
}

public enum ProtectCadenceCLIRunner {
    public static func run(
        arguments: [String],
        now: Date = Date(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async throws -> ProtectCadenceCLIOutput {
        guard let rawSubcommand = arguments.first else {
            throw ProtectCadenceCLIError.missingSubcommand
        }

        guard let subcommand = ProtectCadenceSubcommand(rawValue: rawSubcommand) else {
            throw ProtectCadenceCLIError.unknownSubcommand(rawSubcommand)
        }

        let remainingArguments = Array(arguments.dropFirst())

        switch subcommand {
        case .ingest:
            return .ingest(
                try await ProtectCadenceIngestRunner.run(
                    arguments: remainingArguments,
                    now: now,
                    environment: environment
                )
            )
        case .query:
            return .query(try ProtectCadenceQueryRunner.run(arguments: remainingArguments, now: now))
        case .auth:
            return .auth(try ProtectCadenceAuthRunner.run(arguments: remainingArguments))
        }
    }
}
