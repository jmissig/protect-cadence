import Darwin
import Foundation

public struct ProtectCadenceAuthConfig: Codable, Sendable, Equatable {
    public let controllerURL: String
    public let username: String
    public let password: String?
    public let allowInsecureTLS: Bool

    public init(
        controllerURL: String,
        username: String,
        password: String? = nil,
        allowInsecureTLS: Bool = false
    ) {
        self.controllerURL = controllerURL
        self.username = username
        self.password = password
        self.allowInsecureTLS = allowInsecureTLS
    }
}

public struct ProtectCadenceIngestConfig: Codable, Sendable, Equatable {
    public let databasePath: String

    public init(databasePath: String) {
        self.databasePath = databasePath
    }
}

public struct ProtectCadenceConfig: Codable, Sendable, Equatable {
    public let auth: ProtectCadenceAuthConfig?
    public let ingest: ProtectCadenceIngestConfig?

    public init(
        auth: ProtectCadenceAuthConfig? = nil,
        ingest: ProtectCadenceIngestConfig? = nil
    ) {
        self.auth = auth
        self.ingest = ingest
    }

    public init(
        controllerURL: String,
        username: String,
        password: String? = nil,
        allowInsecureTLS: Bool = false,
        databasePath: String? = nil
    ) {
        self.init(
            auth: ProtectCadenceAuthConfig(
                controllerURL: controllerURL,
                username: username,
                password: password,
                allowInsecureTLS: allowInsecureTLS
            ),
            ingest: databasePath.map(ProtectCadenceIngestConfig.init(databasePath:))
        )
    }

    public func updatingAuth(_ auth: ProtectCadenceAuthConfig?) -> ProtectCadenceConfig {
        ProtectCadenceConfig(auth: auth, ingest: ingest)
    }

    public func updatingIngest(_ ingest: ProtectCadenceIngestConfig?) -> ProtectCadenceConfig {
        ProtectCadenceConfig(auth: auth, ingest: ingest)
    }
}

public enum ProtectCadenceConfigStore {
    public static func load(
        from path: String = ProtectCadencePaths.defaultConfigPath()
    ) throws -> ProtectCadenceConfig? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ProtectCadenceConfig.self, from: data)
    }

    public static func save(
        _ config: ProtectCadenceConfig,
        to path: String = ProtectCadencePaths.defaultConfigPath(),
        fileManager: FileManager = .default
    ) throws {
        let url = URL(fileURLWithPath: path)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: url)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.deletingLastPathComponent().path)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public static func delete(
        at path: String = ProtectCadencePaths.defaultConfigPath(),
        fileManager: FileManager = .default
    ) throws {
        let url = URL(fileURLWithPath: path)
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        try fileManager.removeItem(at: url)
    }
}

public enum ProtectAuthResolutionError: Error, CustomStringConvertible {
    case missingControllerURL
    case missingUsername
    case missingPassword
    case invalidControllerURL(String)
    case inputUnavailable(String)
    case confirmationDeclined

    public var description: String {
        switch self {
        case .missingControllerURL:
            return "missing controller URL; provide --controller-url, PROTECT_CONTROLLER_URL, or run 'protect-cadence auth login'"
        case .missingUsername:
            return "missing Protect username; provide --username, PROTECT_USERNAME, or run 'protect-cadence auth login'"
        case .missingPassword:
            return "missing Protect password; provide --password, PROTECT_PASSWORD, or save it with 'protect-cadence auth login'"
        case let .invalidControllerURL(value):
            return "invalid controller URL '\(value)'"
        case let .inputUnavailable(field):
            return "interactive input unavailable for \(field)"
        case .confirmationDeclined:
            return "auth clear cancelled"
        }
    }
}

public struct ProtectAuthOverrides: Sendable, Equatable {
    public let controllerURL: String?
    public let username: String?
    public let password: String?
    public let allowInsecureTLS: Bool?

    public init(
        controllerURL: String? = nil,
        username: String? = nil,
        password: String? = nil,
        allowInsecureTLS: Bool? = nil
    ) {
        self.controllerURL = controllerURL
        self.username = username
        self.password = password
        self.allowInsecureTLS = allowInsecureTLS
    }
}

public struct ProtectAuthStatus: Sendable, Equatable {
    public let configPath: String
    public let configExists: Bool
    public let controllerURL: URL?
    public let username: String?
    public let allowInsecureTLS: Bool?
    public let storedPasswordExists: Bool

    public init(
        configPath: String,
        configExists: Bool,
        controllerURL: URL?,
        username: String?,
        allowInsecureTLS: Bool?,
        storedPasswordExists: Bool
    ) {
        self.configPath = configPath
        self.configExists = configExists
        self.controllerURL = controllerURL
        self.username = username
        self.allowInsecureTLS = allowInsecureTLS
        self.storedPasswordExists = storedPasswordExists
    }
}

public protocol ProtectAuthPrompter: Sendable {
    func prompt(_ message: String, defaultValue: String?) throws -> String
    func promptPassword(_ message: String) throws -> String
    func confirm(_ message: String) throws -> Bool
}

public struct ConsoleProtectAuthPrompter: ProtectAuthPrompter {
    public init() {}

    public func prompt(_ message: String, defaultValue: String? = nil) throws -> String {
        writePrompt(message, defaultValue: defaultValue)
        guard let line = readLine(strippingNewline: true) else {
            throw ProtectAuthResolutionError.inputUnavailable(message)
        }

        if line.isEmpty, let defaultValue {
            return defaultValue
        }

        return line
    }

    public func promptPassword(_ message: String) throws -> String {
        writePrompt(message, defaultValue: nil)
        let needsEchoReset = isatty(STDIN_FILENO) == 1
        var original = termios()
        if needsEchoReset {
            tcgetattr(STDIN_FILENO, &original)
            var hidden = original
            hidden.c_lflag &= ~tcflag_t(ECHO)
            tcsetattr(STDIN_FILENO, TCSANOW, &hidden)
            fflush(stderr)
        }
        defer {
            if needsEchoReset {
                var restored = original
                tcsetattr(STDIN_FILENO, TCSANOW, &restored)
                FileHandle.standardError.write(Data("\n".utf8))
            }
        }

        guard let line = readLine(strippingNewline: true) else {
            throw ProtectAuthResolutionError.inputUnavailable("password")
        }
        return line
    }

    public func confirm(_ message: String) throws -> Bool {
        let answer = try prompt("\(message) [y/N]", defaultValue: "n")
        switch answer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "y", "yes":
            return true
        default:
            return false
        }
    }

    private func writePrompt(_ message: String, defaultValue: String?) {
        var fullMessage = message
        if let defaultValue, !defaultValue.isEmpty {
            fullMessage += " [\(defaultValue)]"
        }
        fullMessage += ": "
        FileHandle.standardError.write(Data(fullMessage.utf8))
    }
}

public enum ProtectAuthResolver {
    public static func resolveControllerConfiguration(
        overrides: ProtectAuthOverrides = ProtectAuthOverrides(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        configPath: String = ProtectCadencePaths.defaultConfigPath()
    ) throws -> ProtectControllerConfiguration {
        let config = try ProtectCadenceConfigStore.load(from: configPath)
        let status = try currentStatus(
            overrides: overrides,
            environment: environment,
            configPath: configPath,
            config: config
        )

        guard let controllerURL = status.controllerURL else {
            throw ProtectAuthResolutionError.missingControllerURL
        }

        guard let username = status.username, !username.isEmpty else {
            throw ProtectAuthResolutionError.missingUsername
        }

        let password = try resolvedPassword(
            overrides: overrides,
            environment: environment,
            config: config
        )

        return ProtectControllerConfiguration(
            controllerURL: controllerURL,
            username: username,
            password: password,
            allowInsecureTLS: status.allowInsecureTLS ?? false
        )
    }

    public static func currentStatus(
        overrides: ProtectAuthOverrides = ProtectAuthOverrides(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        configPath: String = ProtectCadencePaths.defaultConfigPath(),
        config: ProtectCadenceConfig? = nil
    ) throws -> ProtectAuthStatus {
        let resolvedConfig = try config ?? ProtectCadenceConfigStore.load(from: configPath)
        let configExists = resolvedConfig != nil

        let controllerURLString = firstNonEmpty(
            overrides.controllerURL,
            environment["PROTECT_CONTROLLER_URL"],
            resolvedConfig?.auth?.controllerURL
        )
        let username = firstNonEmpty(
            overrides.username,
            environment["PROTECT_USERNAME"],
            resolvedConfig?.auth?.username
        )
        let allowInsecureTLS = firstBoolean(
            overrides.allowInsecureTLS,
            environment["PROTECT_ALLOW_INSECURE_TLS"].map(parseBooleanString),
            resolvedConfig?.auth?.allowInsecureTLS
        )

        let controllerURL: URL?
        if let controllerURLString {
            guard let parsedURL = URL(string: controllerURLString) else {
                throw ProtectAuthResolutionError.invalidControllerURL(controllerURLString)
            }
            controllerURL = parsedURL
        } else {
            controllerURL = nil
        }

        let storedPasswordExists = controllerURL != nil
            && username?.isEmpty == false
            && resolvedConfig.map(usesStoredConfigPassword) == true

        return ProtectAuthStatus(
            configPath: configPath,
            configExists: configExists,
            controllerURL: controllerURL,
            username: username,
            allowInsecureTLS: allowInsecureTLS,
            storedPasswordExists: storedPasswordExists
        )
    }

    public static func login(
        overrides: ProtectAuthOverrides = ProtectAuthOverrides(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        configPath: String = ProtectCadencePaths.defaultConfigPath(),
        prompter: ProtectAuthPrompter = ConsoleProtectAuthPrompter(),
        fileManager: FileManager = .default
    ) throws -> ProtectAuthStatus {
        let existingConfig = try ProtectCadenceConfigStore.load(from: configPath)
        let existingStatus = try currentStatus(
            overrides: overrides,
            environment: environment,
            configPath: configPath,
            config: existingConfig
        )

        let controllerURLString = try resolvedValue(
            current: existingStatus.controllerURL?.absoluteString,
            prompt: "Protect controller URL",
            prompter: prompter,
            error: .missingControllerURL
        )
        let username = try resolvedValue(
            current: existingStatus.username,
            prompt: "Protect username",
            prompter: prompter,
            error: .missingUsername
        )

        guard let controllerURL = URL(string: controllerURLString) else {
            throw ProtectAuthResolutionError.invalidControllerURL(controllerURLString)
        }

        let password = try resolvedPasswordForLogin(
            overrides: overrides,
            environment: environment,
            prompter: prompter
        )

        let allowInsecureTLS = try resolvedAllowInsecureTLSForLogin(
            overrides: overrides,
            environment: environment,
            prompter: prompter
        )
        let newConfig = (existingConfig ?? ProtectCadenceConfig()).updatingAuth(
            ProtectCadenceAuthConfig(
                controllerURL: normalizedControllerURLString(controllerURL),
                username: username,
                password: password,
                allowInsecureTLS: allowInsecureTLS
            )
        )

        try ProtectCadenceConfigStore.save(newConfig, to: configPath, fileManager: fileManager)

        return try currentStatus(
            environment: environment,
            configPath: configPath,
            config: newConfig
        )
    }

    public static func clear(
        overrides: ProtectAuthOverrides = ProtectAuthOverrides(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        configPath: String = ProtectCadencePaths.defaultConfigPath(),
        force: Bool = false,
        prompter: ProtectAuthPrompter = ConsoleProtectAuthPrompter(),
        fileManager: FileManager = .default
    ) throws -> ProtectAuthStatus {
        let config = try ProtectCadenceConfigStore.load(from: configPath)
        let configExists = config != nil

        if !force {
            let confirmed = try prompter.confirm("Clear \(configPath)?")
            guard confirmed else {
                throw ProtectAuthResolutionError.confirmationDeclined
            }
        }

        if configExists {
            try ProtectCadenceConfigStore.delete(at: configPath, fileManager: fileManager)
        }

        return ProtectAuthStatus(
            configPath: configPath,
            configExists: false,
            controllerURL: nil,
            username: nil,
            allowInsecureTLS: nil,
            storedPasswordExists: false
        )
    }

    static func parseBooleanString(_ value: String?) -> Bool {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }

        switch normalized {
        case "1", "true", "yes", "y", "on":
            return true
        default:
            return false
        }
    }

    private static func resolvedPassword(
        overrides: ProtectAuthOverrides,
        environment: [String: String],
        config: ProtectCadenceConfig?
    ) throws -> String {
        if let password = firstNonEmpty(overrides.password, environment["PROTECT_PASSWORD"]) {
            return password
        }

        if let password = storedPassword(config: config) {
            return password
        }

        throw ProtectAuthResolutionError.missingPassword
    }

    private static func storedPassword(
        config: ProtectCadenceConfig?
    ) -> String? {
        guard let config,
              usesStoredConfigPassword(config),
              let password = config.auth?.password?.trimmingCharacters(in: .whitespacesAndNewlines),
              !password.isEmpty else {
            return nil
        }

        return password
    }

    private static func usesStoredConfigPassword(
        _ config: ProtectCadenceConfig
    ) -> Bool {
        guard let password = config.auth?.password?.trimmingCharacters(in: .whitespacesAndNewlines), !password.isEmpty else {
            return false
        }

        return true
    }

    private static func resolvedPasswordForLogin(
        overrides: ProtectAuthOverrides,
        environment: [String: String],
        prompter: ProtectAuthPrompter
    ) throws -> String {
        if let password = firstNonEmpty(overrides.password, environment["PROTECT_PASSWORD"]) {
            return password
        }

        return try prompter.promptPassword("Protect password")
    }

    private static func resolvedAllowInsecureTLSForLogin(
        overrides: ProtectAuthOverrides,
        environment: [String: String],
        prompter: ProtectAuthPrompter
    ) throws -> Bool {
        if let explicitValue = overrides.allowInsecureTLS {
            return explicitValue
        }

        if let environmentValue = environment["PROTECT_ALLOW_INSECURE_TLS"] {
            return parseBooleanString(environmentValue)
        }

        return try prompter.confirm("Allow insecure TLS for this controller? This disables certificate verification.")
    }

    private static func resolvedValue(
        current: String?,
        prompt: String,
        prompter: ProtectAuthPrompter,
        error: ProtectAuthResolutionError
    ) throws -> String {
        if let current, !current.isEmpty {
            return current
        }

        let value = try prompter.prompt(prompt, defaultValue: nil)
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw error
        }
        return value
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values.first { value in
            guard let value else {
                return false
            }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? nil
    }

    private static func firstBoolean(_ values: Bool?...) -> Bool? {
        values.first { $0 != nil } ?? nil
    }
}

func normalizedControllerURLString(_ controllerURL: URL) -> String {
    var value = controllerURL.absoluteString
    while value.count > 1, value.hasSuffix("/") {
        value.removeLast()
    }
    return value
}
