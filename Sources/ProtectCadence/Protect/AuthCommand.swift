import Foundation

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

public enum ProtectCadenceAuthRunner {
    public static func run(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        prompter: ProtectAuthPrompter = ConsoleProtectAuthPrompter(),
        fileManager: FileManager = .default
    ) throws -> AuthCommandResponse {
        try run(
            cli: AuthCLI(arguments: arguments),
            environment: environment,
            prompter: prompter,
            fileManager: fileManager
        )
    }

    static func run(
        cli: AuthCLI,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        prompter: ProtectAuthPrompter = ConsoleProtectAuthPrompter(),
        fileManager: FileManager = .default
    ) throws -> AuthCommandResponse {
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
        try self.init(command: ProtectCadenceCLIAuthCommand.parse(arguments))
    }

    init(
        action: AuthAction,
        overrides: ProtectAuthOverrides,
        configPath: String,
        force: Bool
    ) {
        self.action = action
        self.overrides = overrides
        self.configPath = configPath
        self.force = force
    }

    init(command: ProtectCadenceCLIAuthCommand) throws {
        let action: AuthAction
        if let rawAction = command.action {
            guard let parsedAction = AuthAction(rawValue: rawAction) else {
                throw AuthCLIError.unexpectedArgument(rawAction)
            }
            action = parsedAction
        } else {
            action = .status
        }

        if action != .login, command.authOverrides.password != nil {
            throw AuthCLIError.unexpectedArgument("--password")
        }

        if action != .clear, command.force {
            throw AuthCLIError.unexpectedArgument("--force")
        }

        self.action = action
        self.overrides = ProtectAuthOverrides(
            controllerURL: command.authOverrides.controllerURL,
            username: command.authOverrides.username,
            password: command.authOverrides.password,
            allowInsecureTLS: command.authOverrides.allowInsecureTLS ? true : nil
        )
        self.configPath = command.configOptions.configPath
        self.force = command.force
    }
}
