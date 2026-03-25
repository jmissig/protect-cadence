import Foundation

public enum IngestCLIError: Error, CustomStringConvertible {
    case missingValue(String)
    case invalidInteger(flag: String, value: String)
    case invalidPositiveInteger(flag: String, value: String)
    case conflictingModes
    case unexpectedArgument(String)

    public var description: String {
        switch self {
        case let .missingValue(flag):
            return "missing value for \(flag)"
        case let .invalidInteger(flag, value):
            return "invalid integer '\(value)' for \(flag)"
        case let .invalidPositiveInteger(flag, value):
            return "\(flag) must be greater than zero, got '\(value)'"
        case .conflictingModes:
            return "choose only one ingest source: --last-hours or --event-json"
        case let .unexpectedArgument(argument):
            return "unexpected argument '\(argument)'"
        }
    }
}

public struct IngestCLI: Sendable {
    public let databasePath: String
    public let eventJSONPath: String?
    public let cameraJSONPath: String?
    public let cameraName: String?
    public let lastHours: Int?
    public let snapshotDirectoryPath: String?
    public let controllerURL: String?
    public let username: String?
    public let password: String?
    public let allowInsecureTLS: Bool?
    public let configPath: String

    public init(arguments: [String]) throws {
        var remaining = arguments
        var databasePath = ProtectCadencePaths.makeDefault().databasePath
        var eventJSONPath: String?
        var cameraJSONPath: String?
        var cameraName: String?
        var lastHours: Int?
        var snapshotDirectoryPath: String?
        var controllerURL: String?
        var username: String?
        var password: String?
        var allowInsecureTLS: Bool?
        var configPath = ProtectCadencePaths.defaultConfigPath()

        func popValue(for flag: String) throws -> String {
            guard let index = remaining.firstIndex(of: flag) else {
                throw IngestCLIError.missingValue(flag)
            }
            guard remaining.indices.contains(index + 1) else {
                throw IngestCLIError.missingValue(flag)
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
                throw IngestCLIError.invalidInteger(flag: flag, value: rawValue)
            }
            return parsed
        }

        if remaining.contains("--db") {
            databasePath = try popValue(for: "--db")
        }

        if remaining.contains("--config") {
            configPath = try popValue(for: "--config")
        }

        if remaining.contains("--event-json") {
            eventJSONPath = try popValue(for: "--event-json")
        }

        if remaining.contains("--camera-json") {
            cameraJSONPath = try popValue(for: "--camera-json")
        }

        if remaining.contains("--camera-name") {
            cameraName = try popValue(for: "--camera-name")
        }

        if let parsedLastHours = try popInteger(for: "--last-hours") {
            guard parsedLastHours > 0 else {
                throw IngestCLIError.invalidPositiveInteger(flag: "--last-hours", value: String(parsedLastHours))
            }
            lastHours = parsedLastHours
        }

        if remaining.contains("--write-api-snapshot-dir") {
            snapshotDirectoryPath = try popValue(for: "--write-api-snapshot-dir")
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

        if eventJSONPath != nil, lastHours != nil {
            throw IngestCLIError.conflictingModes
        }

        if cameraJSONPath != nil, eventJSONPath == nil {
            throw IngestCLIError.unexpectedArgument("--camera-json")
        }

        if cameraName != nil, eventJSONPath == nil {
            throw IngestCLIError.unexpectedArgument("--camera-name")
        }

        if snapshotDirectoryPath != nil, lastHours == nil {
            throw IngestCLIError.unexpectedArgument("--write-api-snapshot-dir")
        }

        if (controllerURL != nil || username != nil || password != nil || allowInsecureTLS != nil), lastHours == nil {
            if controllerURL != nil {
                throw IngestCLIError.unexpectedArgument("--controller-url")
            }
            if username != nil {
                throw IngestCLIError.unexpectedArgument("--username")
            }
            if password != nil {
                throw IngestCLIError.unexpectedArgument("--password")
            }
            throw IngestCLIError.unexpectedArgument("--allow-insecure-tls")
        }

        if let unexpected = remaining.first {
            throw IngestCLIError.unexpectedArgument(unexpected)
        }

        self.databasePath = databasePath
        self.eventJSONPath = eventJSONPath
        self.cameraJSONPath = cameraJSONPath
        self.cameraName = cameraName
        self.lastHours = lastHours
        self.snapshotDirectoryPath = snapshotDirectoryPath
        self.controllerURL = controllerURL
        self.username = username
        self.password = password
        self.allowInsecureTLS = allowInsecureTLS
        self.configPath = configPath
    }

    public func queryWindow(now: Date = Date()) -> QueryWindow? {
        guard let lastHours else {
            return nil
        }

        let start = now.addingTimeInterval(-Double(lastHours) * 60 * 60)
        return QueryWindow(start: start, end: now)
    }
}

public enum ProtectCadenceIngestRunner {
    public static func run(
        arguments: [String],
        now: Date = Date(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        passwordStore: ProtectPasswordStore = MacOSKeychainPasswordStore(),
        clientFactory: @Sendable (ProtectControllerConfiguration) -> ProtectControllerClient = { configuration in
            ProtectControllerClient(configuration: configuration)
        }
    ) async throws -> IngestResponse {
        let cli = try IngestCLI(arguments: arguments)
        let database = try ProtectCadenceDatabase(path: cli.databasePath)

        let response: IngestResponse
        let service: ProtectIngestService

        if let window = cli.queryWindow(now: now) {
            let configuration = try ProtectAuthResolver.resolveControllerConfiguration(
                overrides: ProtectAuthOverrides(
                    controllerURL: cli.controllerURL,
                    username: cli.username,
                    password: cli.password,
                    allowInsecureTLS: cli.allowInsecureTLS
                ),
                environment: environment,
                configPath: cli.configPath,
                passwordStore: passwordStore
            )
            let client = clientFactory(configuration)
            service = ProtectIngestService(database: database, client: client)
            let snapshotDirectory = cli.snapshotDirectoryPath.map(URL.init(fileURLWithPath:))
            response = try await service.ingestControllerEvents(
                window: window,
                snapshotDirectory: snapshotDirectory
            )
        } else {
            service = ProtectIngestService(database: database)

            if let eventJSONPath = cli.eventJSONPath {
                let data = try Data(contentsOf: URL(fileURLWithPath: eventJSONPath))
                let cameraData = try cli.cameraJSONPath.map {
                    try Data(contentsOf: URL(fileURLWithPath: $0))
                }
                response = try service.ingestFixtureEvents(
                    from: data,
                    cameraLookupData: cameraData,
                    fallbackCameraName: cli.cameraName
                )
            } else {
                response = service.readyResponse()
            }
        }

        return response
    }
}
