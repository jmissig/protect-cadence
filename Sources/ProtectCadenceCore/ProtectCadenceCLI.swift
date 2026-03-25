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
    public let action: String
    public let status: String
    public let configPath: String
    public let configExists: Bool
    public let storedPasswordExists: Bool
    public let controllerURL: String?
    public let username: String?
    public let allowInsecureTLS: Bool?
    public let message: String

    public init(
        command: String,
        action: String,
        status: String,
        configPath: String,
        configExists: Bool,
        storedPasswordExists: Bool,
        controllerURL: String?,
        username: String?,
        allowInsecureTLS: Bool?,
        message: String
    ) {
        self.command = command
        self.action = action
        self.status = status
        self.configPath = configPath
        self.configExists = configExists
        self.storedPasswordExists = storedPasswordExists
        self.controllerURL = controllerURL
        self.username = username
        self.allowInsecureTLS = allowInsecureTLS
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
    public static func run(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        prompter: ProtectAuthPrompter = ConsoleProtectAuthPrompter(),
        fileManager: FileManager = .default
    ) throws -> AuthCommandResponse {
        let cli = try AuthCLI(arguments: arguments)

        switch cli.action {
        case .login:
            let status = try ProtectAuthResolver.login(
                overrides: cli.overrides,
                environment: environment,
                configPath: cli.configPath,
                prompter: prompter,
                fileManager: fileManager
            )
            return makeResponse(
                action: cli.action.rawValue,
                state: status,
                status: "configured",
                message: "saved Protect controller credentials in the config file"
            )
        case .status:
            let status = try ProtectAuthResolver.currentStatus(
                overrides: cli.overrides,
                environment: environment,
                configPath: cli.configPath
            )
            let message: String
            if status.configExists, status.storedPasswordExists {
                message = "config file and stored password are available"
            } else if status.configExists {
                message = "config file is available, but the stored password is missing"
            } else {
                message = "config file is missing"
            }

            return makeResponse(
                action: cli.action.rawValue,
                state: status,
                status: "ok",
                message: message
            )
        case .clear:
            let status = try ProtectAuthResolver.clear(
                overrides: cli.overrides,
                environment: environment,
                configPath: cli.configPath,
                force: cli.force,
                prompter: prompter,
                fileManager: fileManager
            )
            return makeResponse(
                action: cli.action.rawValue,
                state: status,
                status: "cleared",
                message: "removed config file"
            )
        }
    }

    private static func makeResponse(
        action: String,
        state: ProtectAuthStatus,
        status: String,
        message: String
    ) -> AuthCommandResponse {
        AuthCommandResponse(
            command: ProtectCadenceCommand.auth.rawValue,
            action: action,
            status: status,
            configPath: state.configPath,
            configExists: state.configExists,
            storedPasswordExists: state.storedPasswordExists,
            controllerURL: state.controllerURL.map(normalizedControllerURLString),
            username: state.username,
            allowInsecureTLS: state.allowInsecureTLS,
            message: message
        )
    }
}

enum AuthAction: String, Sendable {
    case login
    case status
    case clear
}

enum AuthCLIError: Error, CustomStringConvertible {
    case missingValue(String)
    case unexpectedArgument(String)

    var description: String {
        switch self {
        case let .missingValue(flag):
            return "missing value for \(flag)"
        case let .unexpectedArgument(argument):
            return "unexpected argument '\(argument)'"
        }
    }
}

struct AuthCLI: Sendable {
    let action: AuthAction
    let overrides: ProtectAuthOverrides
    let configPath: String
    let force: Bool

    init(arguments: [String]) throws {
        var remaining = arguments
        let action: AuthAction
        if let first = remaining.first, let parsedAction = AuthAction(rawValue: first) {
            action = parsedAction
            remaining.removeFirst()
        } else {
            action = .status
        }

        var controllerURL: String?
        var username: String?
        var password: String?
        var allowInsecureTLS: Bool?
        var configPath = ProtectCadencePaths.defaultConfigPath()
        var force = false

        func popValue(for flag: String) throws -> String {
            guard let index = remaining.firstIndex(of: flag) else {
                throw AuthCLIError.missingValue(flag)
            }
            guard remaining.indices.contains(index + 1) else {
                throw AuthCLIError.missingValue(flag)
            }

            let value = remaining[index + 1]
            remaining.removeSubrange(index...(index + 1))
            return value
        }

        if remaining.contains("--config") {
            configPath = try popValue(for: "--config")
        }

        if remaining.contains("--controller-url") {
            controllerURL = try popValue(for: "--controller-url")
        }

        if remaining.contains("--username") {
            username = try popValue(for: "--username")
        }

        if remaining.contains("--password") {
            password = try popValue(for: "--password")
        }

        if remaining.contains("--allow-insecure-tls") {
            allowInsecureTLS = true
            remaining.removeAll { $0 == "--allow-insecure-tls" }
        }

        if remaining.contains("--force") {
            force = true
            remaining.removeAll { $0 == "--force" }
        }

        if action != .login, password != nil {
            throw AuthCLIError.unexpectedArgument("--password")
        }

        if action != .clear, force {
            throw AuthCLIError.unexpectedArgument("--force")
        }

        if let unexpected = remaining.first {
            throw AuthCLIError.unexpectedArgument(unexpected)
        }

        self.action = action
        self.overrides = ProtectAuthOverrides(
            controllerURL: controllerURL,
            username: username,
            password: password,
            allowInsecureTLS: allowInsecureTLS
        )
        self.configPath = configPath
        self.force = force
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
            return .auth(
                try ProtectCadenceAuthRunner.run(
                    arguments: remainingArguments,
                    environment: environment
                )
            )
        }
    }
}
