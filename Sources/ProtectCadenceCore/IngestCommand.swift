import Foundation

public enum IngestCLIError: Error, CustomStringConvertible {
    case missingValue(String)
    case invalidInteger(flag: String, value: String)
    case invalidPositiveInteger(flag: String, value: String)
    case conflictingModes
    case missingMode
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
        case .missingMode:
            return "no ingest mode selected; try --last-hours <n> or --event-json <file>"
        case let .unexpectedArgument(argument):
            return "unexpected argument '\(argument)'"
        }
    }
}

public struct IngestCLI: Sendable {
    public let databasePathOverride: String?
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
        try self.init(command: ProtectCadenceCLIIngestCommand.parse(arguments))
    }

    public init(command: ProtectCadenceCLIIngestCommand) throws {
        let lastHours: Int?
        if let parsedLastHours = command.lastHours {
            guard parsedLastHours > 0 else {
                throw IngestCLIError.invalidPositiveInteger(flag: "--last-hours", value: String(parsedLastHours))
            }
            lastHours = parsedLastHours
        } else {
            lastHours = nil
        }

        if command.eventJSONPath != nil, lastHours != nil {
            throw IngestCLIError.conflictingModes
        }

        if command.cameraJSONPath != nil, command.eventJSONPath == nil {
            throw IngestCLIError.unexpectedArgument("--camera-json")
        }

        if command.cameraName != nil, command.eventJSONPath == nil {
            throw IngestCLIError.unexpectedArgument("--camera-name")
        }

        if command.snapshotDirectoryPath != nil, lastHours == nil {
            throw IngestCLIError.unexpectedArgument("--write-api-snapshot-dir")
        }

        let allowInsecureTLS = command.authOverrides.allowInsecureTLS ? true : nil
        if (command.authOverrides.controllerURL != nil
            || command.authOverrides.username != nil
            || command.authOverrides.password != nil
            || allowInsecureTLS != nil), lastHours == nil
        {
            if command.authOverrides.controllerURL != nil {
                throw IngestCLIError.unexpectedArgument("--controller-url")
            }
            if command.authOverrides.username != nil {
                throw IngestCLIError.unexpectedArgument("--username")
            }
            if command.authOverrides.password != nil {
                throw IngestCLIError.unexpectedArgument("--password")
            }
            throw IngestCLIError.unexpectedArgument("--allow-insecure-tls")
        }

        self.databasePathOverride = command.databaseOptions.databasePathOverride
        self.eventJSONPath = command.eventJSONPath
        self.cameraJSONPath = command.cameraJSONPath
        self.cameraName = command.cameraName
        self.lastHours = lastHours
        self.snapshotDirectoryPath = command.snapshotDirectoryPath
        self.controllerURL = command.authOverrides.controllerURL
        self.username = command.authOverrides.username
        self.password = command.authOverrides.password
        self.allowInsecureTLS = allowInsecureTLS
        self.configPath = command.configOptions.configPath
    }

    public func queryWindow(now: Date = Date()) -> QueryWindow? {
        guard let lastHours else {
            return nil
        }

        let start = now.addingTimeInterval(-Double(lastHours) * 60 * 60)
        return QueryWindow(start: start, end: now)
    }

    public var isBareCommand: Bool {
        eventJSONPath == nil
            && cameraJSONPath == nil
            && cameraName == nil
            && lastHours == nil
            && snapshotDirectoryPath == nil
            && controllerURL == nil
            && username == nil
            && password == nil
            && allowInsecureTLS == nil
            && databasePathOverride == nil
    }
}

public enum ProtectCadenceIngestRunner {
    public static func run(
        arguments: [String],
        now: Date = Date(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        prompter: ProtectAuthPrompter = ConsoleProtectAuthPrompter(),
        fileManager: FileManager = .default,
        statusOutput: @escaping @Sendable (String) -> Void = { line in
            FileHandle.standardError.write(Data("\(line)\n".utf8))
        },
        clientFactory: @Sendable (ProtectControllerConfiguration) -> ProtectControllerClient = { configuration in
            ProtectControllerClient(configuration: configuration)
        }
    ) async throws -> IngestResponse {
        try await run(
            cli: IngestCLI(arguments: arguments),
            now: now,
            environment: environment,
            prompter: prompter,
            fileManager: fileManager,
            statusOutput: statusOutput,
            clientFactory: clientFactory
        )
    }

    public static func run(
        cli: IngestCLI,
        now: Date = Date(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        prompter: ProtectAuthPrompter = ConsoleProtectAuthPrompter(),
        fileManager: FileManager = .default,
        statusOutput: @escaping @Sendable (String) -> Void = { line in
            FileHandle.standardError.write(Data("\(line)\n".utf8))
        },
        clientFactory: @Sendable (ProtectControllerConfiguration) -> ProtectControllerClient = { configuration in
            ProtectControllerClient(configuration: configuration)
        }
    ) async throws -> IngestResponse {
        let config = try ProtectCadenceConfigStore.load(from: cli.configPath)

        if cli.isBareCommand, requiresInteractiveSetup(config: config) {
            return try await runInteractiveFirstRunFlow(
                cli: cli,
                now: now,
                environment: environment,
                config: config,
                prompter: prompter,
                fileManager: fileManager,
                statusOutput: statusOutput,
                clientFactory: clientFactory
            )
        }

        let databasePath = try ProtectCadenceDatabasePathResolver.resolve(
            explicitOverride: cli.databasePathOverride,
            configPath: cli.configPath
        )
        let database = try ProtectCadenceDatabase(path: databasePath)

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
                configPath: cli.configPath
            )
            let client = clientFactory(configuration)
            service = ProtectIngestService(database: database, client: client)
            let snapshotDirectory = cli.snapshotDirectoryPath.map(URL.init(fileURLWithPath:))
            response = try await service.ingestControllerEvents(
                window: window,
                snapshotDirectory: snapshotDirectory,
                phaseReporter: nil
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
                throw IngestCLIError.missingMode
            }
        }

        return response
    }

    private static func requiresInteractiveSetup(
        config: ProtectCadenceConfig?
    ) -> Bool {
        let hasAuth = !storedAuthNeedsSetup(config: config)
        let hasDatabasePath = firstNonEmpty(config?.databasePath) != nil
        return !hasAuth || !hasDatabasePath
    }

    private static func storedAuthNeedsSetup(config: ProtectCadenceConfig?) -> Bool {
        let authConfig = config?.auth
        let controllerURL = firstNonEmpty(authConfig?.controllerURL)
        let username = firstNonEmpty(authConfig?.username)
        let password = firstNonEmpty(authConfig?.password)
        return controllerURL == nil || username == nil || password == nil
    }

    private static func runInteractiveFirstRunFlow(
        cli: IngestCLI,
        now: Date,
        environment: [String: String],
        config: ProtectCadenceConfig?,
        prompter: ProtectAuthPrompter,
        fileManager: FileManager,
        statusOutput: @escaping @Sendable (String) -> Void,
        clientFactory: @Sendable (ProtectControllerConfiguration) -> ProtectControllerClient
    ) async throws -> IngestResponse {
        statusOutput("First-run setup for protect-cadence.")

        var workingConfig = config ?? ProtectCadenceConfig()

        if storedAuthNeedsSetup(config: workingConfig) {
            statusOutput("Collecting Protect controller auth...")
            _ = try ProtectAuthResolver.login(
                environment: environment,
                configPath: cli.configPath,
                prompter: prompter,
                fileManager: fileManager
            )
            workingConfig = try ProtectCadenceConfigStore.load(from: cli.configPath) ?? workingConfig
        }

        let databasePath: String
        if let existingDatabasePath = firstNonEmpty(workingConfig.databasePath) {
            databasePath = existingDatabasePath
        } else {
            statusOutput("Choosing a local database path...")
            databasePath = try resolvedDatabasePathForSetup(prompter: prompter)
            workingConfig = workingConfig.updatingDatabasePath(databasePath)
            try ProtectCadenceConfigStore.save(workingConfig, to: cli.configPath, fileManager: fileManager)
        }

        let shouldSeed = try prompter.confirm("Import recent Protect data now?")
        if !shouldSeed {
            let database = try ProtectCadenceDatabase(path: databasePath)
            statusOutput("Saved config. Next time, run something like: `protect-cadence ingest --last-hours 6`")
            return ProtectIngestService(database: database).readyResponse()
        }

        let hours = try resolvedSeedHours(prompter: prompter)
        let window = QueryWindow(start: now.addingTimeInterval(-Double(hours) * 60 * 60), end: now)

        let database = try ProtectCadenceDatabase(path: databasePath)
        let configuration = try ProtectAuthResolver.resolveControllerConfiguration(
            environment: environment,
            configPath: cli.configPath
        )
        let client = clientFactory(configuration)
        let response = try await ProtectIngestService(database: database, client: client).ingestControllerEvents(
            window: window,
            snapshotDirectory: nil,
            phaseReporter: { phase in
                statusOutput(phase.message)
            }
        )

        statusOutput("Next time, run something like: `protect-cadence ingest --last-hours 6`")
        return response
    }

    private static func resolvedDatabasePathForSetup(
        prompter: ProtectAuthPrompter
    ) throws -> String {
        let path = try prompter.prompt(
            "Database path for the local event store",
            defaultValue: ProtectCadencePaths.defaultManagedDatabasePath()
        )
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ProtectCadencePaths.defaultManagedDatabasePath()
        }
        return trimmed
    }

    private static func resolvedSeedHours(
        prompter: ProtectAuthPrompter
    ) throws -> Int {
        let rawValue = try prompter.prompt(
            "How many hours of recent Protect data should be imported?",
            defaultValue: "24"
        )
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hours = Int(trimmed), hours > 0 else {
            throw IngestCLIError.invalidPositiveInteger(flag: "seed hours", value: trimmed)
        }
        return hours
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values.first { value in
            guard let value else {
                return false
            }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? nil
    }
}
