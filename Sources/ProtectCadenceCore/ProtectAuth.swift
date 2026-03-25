import Darwin
import Foundation
import Security

public struct ProtectCadenceConfig: Codable, Sendable, Equatable {
    public let controllerURL: String
    public let username: String
    public let allowInsecureTLS: Bool

    public init(controllerURL: String, username: String, allowInsecureTLS: Bool = false) {
        self.controllerURL = controllerURL
        self.username = username
        self.allowInsecureTLS = allowInsecureTLS
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

public protocol ProtectPasswordStore: Sendable {
    func readPassword(controllerURL: URL, username: String) throws -> String?
    func savePassword(_ password: String, controllerURL: URL, username: String) throws
    func deletePassword(controllerURL: URL, username: String) throws
}

public enum ProtectPasswordStoreError: Error, CustomStringConvertible {
    case unexpectedStatus(OSStatus, String)
    case invalidPasswordEncoding

    public var description: String {
        switch self {
        case let .unexpectedStatus(status, operation):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "Keychain \(operation) failed: \(message)"
        case .invalidPasswordEncoding:
            return "password could not be decoded from Keychain data"
        }
    }
}

public struct MacOSKeychainPasswordStore: ProtectPasswordStore {
    private static let service = "protect-cadence"

    public init() {}

    public func readPassword(controllerURL: URL, username: String) throws -> String? {
        var query = baseQuery(controllerURL: controllerURL, username: username)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let password = String(data: data, encoding: .utf8) else {
                throw ProtectPasswordStoreError.invalidPasswordEncoding
            }
            return password
        case errSecItemNotFound:
            return nil
        default:
            throw ProtectPasswordStoreError.unexpectedStatus(status, "read")
        }
    }

    public func savePassword(_ password: String, controllerURL: URL, username: String) throws {
        let data = Data(password.utf8)
        let query = baseQuery(controllerURL: controllerURL, username: username)
        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var createQuery = query
            createQuery[kSecValueData as String] = data
            let createStatus = SecItemAdd(createQuery as CFDictionary, nil)
            guard createStatus == errSecSuccess else {
                throw ProtectPasswordStoreError.unexpectedStatus(createStatus, "save")
            }
        default:
            throw ProtectPasswordStoreError.unexpectedStatus(updateStatus, "save")
        }
    }

    public func deletePassword(controllerURL: URL, username: String) throws {
        let status = SecItemDelete(baseQuery(controllerURL: controllerURL, username: username) as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw ProtectPasswordStoreError.unexpectedStatus(status, "delete")
        }
    }

    private func baseQuery(controllerURL: URL, username: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.keychainAccount(controllerURL: controllerURL, username: username),
        ]
    }

    static func keychainAccount(controllerURL: URL, username: String) -> String {
        "\(username)@\(normalizedControllerURLString(controllerURL))"
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
            return "missing Protect password; provide --password, PROTECT_PASSWORD, or run 'protect-cadence auth login'"
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
    public let keychainSecretExists: Bool

    public init(
        configPath: String,
        configExists: Bool,
        controllerURL: URL?,
        username: String?,
        allowInsecureTLS: Bool?,
        keychainSecretExists: Bool
    ) {
        self.configPath = configPath
        self.configExists = configExists
        self.controllerURL = controllerURL
        self.username = username
        self.allowInsecureTLS = allowInsecureTLS
        self.keychainSecretExists = keychainSecretExists
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
        configPath: String = ProtectCadencePaths.defaultConfigPath(),
        passwordStore: ProtectPasswordStore = MacOSKeychainPasswordStore()
    ) throws -> ProtectControllerConfiguration {
        let config = try ProtectCadenceConfigStore.load(from: configPath)
        let status = try currentStatus(
            overrides: overrides,
            environment: environment,
            configPath: configPath,
            config: config,
            passwordStore: passwordStore
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
            controllerURL: controllerURL,
            username: username,
            passwordStore: passwordStore
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
        config: ProtectCadenceConfig? = nil,
        passwordStore: ProtectPasswordStore = MacOSKeychainPasswordStore()
    ) throws -> ProtectAuthStatus {
        let resolvedConfig = try config ?? ProtectCadenceConfigStore.load(from: configPath)
        let configExists = resolvedConfig != nil

        let controllerURLString = firstNonEmpty(
            overrides.controllerURL,
            environment["PROTECT_CONTROLLER_URL"],
            resolvedConfig?.controllerURL
        )
        let username = firstNonEmpty(
            overrides.username,
            environment["PROTECT_USERNAME"],
            resolvedConfig?.username
        )
        let allowInsecureTLS = firstBoolean(
            overrides.allowInsecureTLS,
            environment["PROTECT_ALLOW_INSECURE_TLS"].map(parseBooleanString),
            resolvedConfig?.allowInsecureTLS
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

        let keychainSecretExists: Bool
        if let controllerURL, let username, !username.isEmpty {
            keychainSecretExists = try passwordStore.readPassword(controllerURL: controllerURL, username: username) != nil
        } else {
            keychainSecretExists = false
        }

        return ProtectAuthStatus(
            configPath: configPath,
            configExists: configExists,
            controllerURL: controllerURL,
            username: username,
            allowInsecureTLS: allowInsecureTLS,
            keychainSecretExists: keychainSecretExists
        )
    }

    public static func login(
        overrides: ProtectAuthOverrides = ProtectAuthOverrides(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        configPath: String = ProtectCadencePaths.defaultConfigPath(),
        passwordStore: ProtectPasswordStore = MacOSKeychainPasswordStore(),
        prompter: ProtectAuthPrompter = ConsoleProtectAuthPrompter(),
        fileManager: FileManager = .default
    ) throws -> ProtectAuthStatus {
        let existingConfig = try ProtectCadenceConfigStore.load(from: configPath)
        let existingStatus = try currentStatus(
            overrides: overrides,
            environment: environment,
            configPath: configPath,
            config: existingConfig,
            passwordStore: passwordStore
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

        let allowInsecureTLS = existingStatus.allowInsecureTLS ?? false
        let newConfig = ProtectCadenceConfig(
            controllerURL: normalizedControllerURLString(controllerURL),
            username: username,
            allowInsecureTLS: allowInsecureTLS
        )

        if let existingConfig,
           existingConfig.controllerURL != newConfig.controllerURL || existingConfig.username != newConfig.username,
           let existingURL = URL(string: existingConfig.controllerURL) {
            try passwordStore.deletePassword(controllerURL: existingURL, username: existingConfig.username)
        }

        try ProtectCadenceConfigStore.save(newConfig, to: configPath, fileManager: fileManager)
        try passwordStore.savePassword(password, controllerURL: controllerURL, username: username)

        return try currentStatus(
            environment: environment,
            configPath: configPath,
            config: newConfig,
            passwordStore: passwordStore
        )
    }

    public static func clear(
        overrides: ProtectAuthOverrides = ProtectAuthOverrides(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        configPath: String = ProtectCadencePaths.defaultConfigPath(),
        force: Bool = false,
        passwordStore: ProtectPasswordStore = MacOSKeychainPasswordStore(),
        prompter: ProtectAuthPrompter = ConsoleProtectAuthPrompter(),
        fileManager: FileManager = .default
    ) throws -> ProtectAuthStatus {
        let config = try ProtectCadenceConfigStore.load(from: configPath)
        let configExists = config != nil

        let controllerURLString = firstNonEmpty(
            config?.controllerURL,
            overrides.controllerURL,
            environment["PROTECT_CONTROLLER_URL"]
        )
        let username = firstNonEmpty(
            config?.username,
            overrides.username,
            environment["PROTECT_USERNAME"]
        )

        if !force {
            var targetDescription = configPath
            if let username {
                targetDescription += " and stored password for \(username)"
            }

            let confirmed = try prompter.confirm("Clear \(targetDescription)?")
            guard confirmed else {
                throw ProtectAuthResolutionError.confirmationDeclined
            }
        }

        if let controllerURLString,
           let controllerURL = URL(string: controllerURLString),
           let username,
           !username.isEmpty {
            try passwordStore.deletePassword(controllerURL: controllerURL, username: username)
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
            keychainSecretExists: false
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
        controllerURL: URL,
        username: String,
        passwordStore: ProtectPasswordStore
    ) throws -> String {
        if let password = firstNonEmpty(overrides.password, environment["PROTECT_PASSWORD"]) {
            return password
        }

        if let password = try passwordStore.readPassword(controllerURL: controllerURL, username: username), !password.isEmpty {
            return password
        }

        throw ProtectAuthResolutionError.missingPassword
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
