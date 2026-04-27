import Foundation

public enum ProtectCadenceSubcommand: String, Sendable {
    case ingest
    case query
    case model
    case auth
    case setup
    case validate
}

public enum ProtectCadenceCLIError: Error, CustomStringConvertible {
    case missingSubcommand
    case unknownSubcommand(String)
    case unexpectedArgument(String)

    public var description: String {
        switch self {
        case .missingSubcommand:
            return "expected a subcommand such as 'ingest', 'query', 'model', 'auth', 'setup', or 'validate'"
        case let .unknownSubcommand(command):
            return "unknown subcommand '\(command)'"
        case let .unexpectedArgument(argument):
            return "unexpected argument '\(argument)'"
        }
    }
}

public enum ProtectCadenceCLIOutput: Encodable, Sendable {
    case ingest(IngestResponse)
    case query(QueryCommandOutput)
    case model(ModelCommandOutput)
    case auth(AuthCommandResponse)
    case validate(ProtectControllerValidationResponse)

    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .ingest(response):
            try response.encode(to: encoder)
        case let .query(response):
            try response.encode(to: encoder)
        case let .model(response):
            try response.encode(to: encoder)
        case let .auth(response):
            try response.encode(to: encoder)
        case let .validate(response):
            try response.encode(to: encoder)
        }
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
        case .model:
            return .model(try ProtectCadenceModelRunner.run(arguments: remainingArguments, now: now))
        case .auth:
            return .auth(
                try ProtectCadenceAuthRunner.run(
                    arguments: remainingArguments,
                    environment: environment
                )
            )
        case .setup:
            return .auth(
                try ProtectCadenceAuthRunner.run(
                    arguments: [AuthAction.login.rawValue] + remainingArguments,
                    environment: environment
                )
            )
        case .validate:
            return .validate(
                try await ProtectCadenceValidateRunner.run(
                    arguments: remainingArguments,
                    now: now,
                    environment: environment
                )
            )
        }
    }
}
