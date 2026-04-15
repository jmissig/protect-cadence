import Foundation
import GRDB

public enum ModelSubcommand: String, Sendable {
    case rebuild
    case episodes
    case findings
}

public enum ModelFindingType: String, Codable, Sendable, CaseIterable {
    case unexpectedPresence = "unexpected_presence"
    case unexpectedTransition = "unexpected_transition"
    case unusualDuration = "unusual_duration"
}

public enum ModelDayClass: String, Codable, Sendable {
    case weekday
    case weekend
}

public struct ModelBuildParameters: Codable, Sendable, Equatable {
    public let quietGapSeconds: Int
    public let modelVersion: String
    public let unexpectedPresenceMinimumStateCount: Int
    public let unexpectedTransitionMinimumPairCount: Int
    public let unusualDurationMinimumBucketCount: Int
    public let unusualDurationRatioThreshold: Double
    public let unusualDurationMinimumDeltaSeconds: Int

    public init(
        quietGapSeconds: Int,
        modelVersion: String,
        unexpectedPresenceMinimumStateCount: Int,
        unexpectedTransitionMinimumPairCount: Int,
        unusualDurationMinimumBucketCount: Int,
        unusualDurationRatioThreshold: Double,
        unusualDurationMinimumDeltaSeconds: Int
    ) {
        self.quietGapSeconds = quietGapSeconds
        self.modelVersion = modelVersion
        self.unexpectedPresenceMinimumStateCount = unexpectedPresenceMinimumStateCount
        self.unexpectedTransitionMinimumPairCount = unexpectedTransitionMinimumPairCount
        self.unusualDurationMinimumBucketCount = unusualDurationMinimumBucketCount
        self.unusualDurationRatioThreshold = unusualDurationRatioThreshold
        self.unusualDurationMinimumDeltaSeconds = unusualDurationMinimumDeltaSeconds
    }
}

public struct ModelBuildMetadata: Codable, Sendable, Equatable {
    public let runID: Int64
    public let builtAt: Date
    public let sourceDatabasePath: String
    public let sourceEventCount: Int
    public let sourceWindow: QueryWindow?
    public let parameters: ModelBuildParameters

    public init(
        runID: Int64,
        builtAt: Date,
        sourceDatabasePath: String,
        sourceEventCount: Int,
        sourceWindow: QueryWindow?,
        parameters: ModelBuildParameters
    ) {
        self.runID = runID
        self.builtAt = builtAt
        self.sourceDatabasePath = sourceDatabasePath
        self.sourceEventCount = sourceEventCount
        self.sourceWindow = sourceWindow
        self.parameters = parameters
    }
}

public struct ModelEpisodeKind: Codable, Sendable, Equatable {
    public let kind: String
    public let occurrenceCount: Int
    public let isPrimary: Bool

    public init(kind: String, occurrenceCount: Int, isPrimary: Bool) {
        self.kind = kind
        self.occurrenceCount = occurrenceCount
        self.isPrimary = isPrimary
    }
}

public struct ModelEpisode: Codable, Sendable, Equatable {
    public let id: Int64
    public let camera: String
    public let cameraID: String?
    public let primaryKind: String
    public let stateKey: String
    public let startTime: Date
    public let endTime: Date
    public let durationSeconds: Int
    public let eventCount: Int
    public let sourceEventCount: Int
    public let containsUnsettled: Bool
    public let hourOfDay: Int
    public let dayClass: ModelDayClass
    public let kinds: [ModelEpisodeKind]
    public let eventRowIDs: [Int64]
    public let sourceEventIDs: [String]

    public init(
        id: Int64,
        camera: String,
        cameraID: String?,
        primaryKind: String,
        stateKey: String,
        startTime: Date,
        endTime: Date,
        durationSeconds: Int,
        eventCount: Int,
        sourceEventCount: Int,
        containsUnsettled: Bool,
        hourOfDay: Int,
        dayClass: ModelDayClass,
        kinds: [ModelEpisodeKind],
        eventRowIDs: [Int64],
        sourceEventIDs: [String]
    ) {
        self.id = id
        self.camera = camera
        self.cameraID = cameraID
        self.primaryKind = primaryKind
        self.stateKey = stateKey
        self.startTime = startTime
        self.endTime = endTime
        self.durationSeconds = durationSeconds
        self.eventCount = eventCount
        self.sourceEventCount = sourceEventCount
        self.containsUnsettled = containsUnsettled
        self.hourOfDay = hourOfDay
        self.dayClass = dayClass
        self.kinds = kinds
        self.eventRowIDs = eventRowIDs
        self.sourceEventIDs = sourceEventIDs
    }
}

public struct ModelFinding: Codable, Sendable, Equatable {
    public let id: Int64
    public let findingType: ModelFindingType
    public let camera: String
    public let primaryKind: String
    public let stateKey: String
    public let episodeID: Int64
    public let episodeStartTime: Date
    public let episodeEndTime: Date
    public let hourOfDay: Int
    public let dayClass: ModelDayClass
    public let score: Double
    public let bucketEpisodeCount: Int
    public let stateEpisodeCount: Int
    public let observedDurationSeconds: Int?
    public let expectedDurationSeconds: Double?
    public let durationDirection: String?
    public let previousEpisodeID: Int64?
    public let previousPrimaryKind: String?
    public let previousStateKey: String?
    public let transitionBucketCount: Int?
    public let transitionPairCount: Int?
    public let observedGapSeconds: Int?
    public let expectedGapSeconds: Double?
    public let linkedEpisodeIDs: [Int64]

    public init(
        id: Int64,
        findingType: ModelFindingType,
        camera: String,
        primaryKind: String,
        stateKey: String,
        episodeID: Int64,
        episodeStartTime: Date,
        episodeEndTime: Date,
        hourOfDay: Int,
        dayClass: ModelDayClass,
        score: Double,
        bucketEpisodeCount: Int,
        stateEpisodeCount: Int,
        observedDurationSeconds: Int?,
        expectedDurationSeconds: Double?,
        durationDirection: String?,
        previousEpisodeID: Int64?,
        previousPrimaryKind: String?,
        previousStateKey: String?,
        transitionBucketCount: Int?,
        transitionPairCount: Int?,
        observedGapSeconds: Int?,
        expectedGapSeconds: Double?,
        linkedEpisodeIDs: [Int64]
    ) {
        self.id = id
        self.findingType = findingType
        self.camera = camera
        self.primaryKind = primaryKind
        self.stateKey = stateKey
        self.episodeID = episodeID
        self.episodeStartTime = episodeStartTime
        self.episodeEndTime = episodeEndTime
        self.hourOfDay = hourOfDay
        self.dayClass = dayClass
        self.score = score
        self.bucketEpisodeCount = bucketEpisodeCount
        self.stateEpisodeCount = stateEpisodeCount
        self.observedDurationSeconds = observedDurationSeconds
        self.expectedDurationSeconds = expectedDurationSeconds
        self.durationDirection = durationDirection
        self.previousEpisodeID = previousEpisodeID
        self.previousPrimaryKind = previousPrimaryKind
        self.previousStateKey = previousStateKey
        self.transitionBucketCount = transitionBucketCount
        self.transitionPairCount = transitionPairCount
        self.observedGapSeconds = observedGapSeconds
        self.expectedGapSeconds = expectedGapSeconds
        self.linkedEpisodeIDs = linkedEpisodeIDs
    }
}

public struct ModelRebuildResponse: Codable, Sendable, Equatable {
    public let command: String
    public let action: String
    public let sourceDatabasePath: String
    public let modelDatabasePath: String
    public let build: ModelBuildMetadata
    public let episodeCount: Int
    public let stateBucketStatCount: Int
    public let stateTransitionStatCount: Int
    public let findingCount: Int
    public let rebuildDurationSeconds: Double
    public let status: String

    public init(
        command: String,
        action: String,
        sourceDatabasePath: String,
        modelDatabasePath: String,
        build: ModelBuildMetadata,
        episodeCount: Int,
        stateBucketStatCount: Int,
        stateTransitionStatCount: Int,
        findingCount: Int,
        rebuildDurationSeconds: Double,
        status: String
    ) {
        self.command = command
        self.action = action
        self.sourceDatabasePath = sourceDatabasePath
        self.modelDatabasePath = modelDatabasePath
        self.build = build
        self.episodeCount = episodeCount
        self.stateBucketStatCount = stateBucketStatCount
        self.stateTransitionStatCount = stateTransitionStatCount
        self.findingCount = findingCount
        self.rebuildDurationSeconds = rebuildDurationSeconds
        self.status = status
    }
}

public struct ModelEpisodesResponse: Codable, Sendable, Equatable {
    public let command: String
    public let action: String
    public let sourceDatabasePath: String
    public let modelDatabasePath: String
    public let build: ModelBuildMetadata
    public let window: QueryWindow?
    public let cameras: [String]
    public let kinds: [String]
    public let stateKeys: [String]
    public let limit: Int
    public let order: EventOrder
    public let episodes: [ModelEpisode]

    public init(
        command: String,
        action: String,
        sourceDatabasePath: String,
        modelDatabasePath: String,
        build: ModelBuildMetadata,
        window: QueryWindow?,
        cameras: [String],
        kinds: [String],
        stateKeys: [String],
        limit: Int,
        order: EventOrder,
        episodes: [ModelEpisode]
    ) {
        self.command = command
        self.action = action
        self.sourceDatabasePath = sourceDatabasePath
        self.modelDatabasePath = modelDatabasePath
        self.build = build
        self.window = window
        self.cameras = cameras
        self.kinds = kinds
        self.stateKeys = stateKeys
        self.limit = limit
        self.order = order
        self.episodes = episodes
    }
}

public struct ModelFindingsResponse: Codable, Sendable, Equatable {
    public let command: String
    public let action: String
    public let sourceDatabasePath: String
    public let modelDatabasePath: String
    public let build: ModelBuildMetadata
    public let window: QueryWindow?
    public let cameras: [String]
    public let kinds: [String]
    public let findingTypes: [ModelFindingType]
    public let limit: Int
    public let findings: [ModelFinding]

    public init(
        command: String,
        action: String,
        sourceDatabasePath: String,
        modelDatabasePath: String,
        build: ModelBuildMetadata,
        window: QueryWindow?,
        cameras: [String],
        kinds: [String],
        findingTypes: [ModelFindingType],
        limit: Int,
        findings: [ModelFinding]
    ) {
        self.command = command
        self.action = action
        self.sourceDatabasePath = sourceDatabasePath
        self.modelDatabasePath = modelDatabasePath
        self.build = build
        self.window = window
        self.cameras = cameras
        self.kinds = kinds
        self.findingTypes = findingTypes
        self.limit = limit
        self.findings = findings
    }
}

public enum ModelCommandOutput: Encodable, Sendable {
    case rebuild(ModelRebuildResponse)
    case episodes(ModelEpisodesResponse)
    case findings(ModelFindingsResponse)

    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .rebuild(response):
            try response.encode(to: encoder)
        case let .episodes(response):
            try response.encode(to: encoder)
        case let .findings(response):
            try response.encode(to: encoder)
        }
    }
}

public enum ModelCLIError: Error, CustomStringConvertible {
    case missingSubcommand
    case unknownSubcommand(String)
    case invalidPositiveInteger(flag: String, value: String)
    case invalidTimeBound(flag: String, value: String)
    case invalidWindowRange(start: Date, end: Date)
    case invalidOrder(String)
    case invalidFindingType(String)
    case conflictingWindowFlags
    case untilRequiresSince
    case noBuildAvailable(String)

    public var description: String {
        switch self {
        case .missingSubcommand:
            return "expected a subcommand such as 'rebuild', 'episodes', or 'findings'"
        case let .unknownSubcommand(command):
            return "unknown subcommand '\(command)'"
        case let .invalidPositiveInteger(flag, value):
            return "\(flag) must be greater than zero, got '\(value)'"
        case let .invalidTimeBound(flag, value):
            return "invalid time value '\(value)' for \(flag), expected ISO 8601 with Z or explicit offset, or local YYYY-MM-DD[ T]HH:MM[:SS]"
        case let .invalidWindowRange(start, end):
            return "resolved time window must have start earlier than end, got \(QueryDateParser.encode(start)) to \(QueryDateParser.encode(end))"
        case let .invalidOrder(value):
            return "invalid value '\(value)' for --order, expected newest or oldest"
        case let .invalidFindingType(value):
            return "invalid value '\(value)' for --finding-type, expected unexpected_presence, unexpected_transition, or unusual_duration"
        case .conflictingWindowFlags:
            return "use either --last-hours or --since/--until, not both"
        case .untilRequiresSince:
            return "--until requires --since"
        case let .noBuildAvailable(path):
            return "no model build is available at \(path); run `protect-cadence model rebuild` first"
        }
    }
}

public struct ModelEpisodeFilters: Sendable, Equatable {
    public let window: QueryWindow?
    public let cameras: [String]
    public let kinds: [String]
    public let stateKeys: [String]

    public init(
        window: QueryWindow? = nil,
        cameras: [String] = [],
        kinds: [String] = [],
        stateKeys: [String] = []
    ) {
        self.window = window
        self.cameras = cameras
        self.kinds = kinds
        self.stateKeys = stateKeys
    }
}

public struct ModelEpisodesRequest: Sendable, Equatable {
    public let filters: ModelEpisodeFilters
    public let limit: Int
    public let order: EventOrder

    public init(filters: ModelEpisodeFilters, limit: Int, order: EventOrder) {
        self.filters = filters
        self.limit = limit
        self.order = order
    }
}

public struct ModelFindingsRequest: Sendable, Equatable {
    public let filters: ModelEpisodeFilters
    public let findingTypes: [ModelFindingType]
    public let limit: Int

    public init(filters: ModelEpisodeFilters, findingTypes: [ModelFindingType], limit: Int) {
        self.filters = filters
        self.findingTypes = findingTypes
        self.limit = limit
    }
}

public struct ModelCLI: Sendable {
    public let subcommand: ModelSubcommand
    public let configPath: String
    public let sourceDatabasePathOverride: String?
    public let modelDatabasePathOverride: String?
    public let windowBounds: QueryWindowBounds?
    public let lastHours: Int?
    public let cameras: [String]
    public let kinds: [String]
    public let stateKeys: [String]
    public let findingTypes: [ModelFindingType]
    public let limit: Int
    public let order: EventOrder

    public init(arguments: [String]) throws {
        guard let rawSubcommand = arguments.first else {
            throw ModelCLIError.missingSubcommand
        }
        guard let subcommand = ModelSubcommand(rawValue: rawSubcommand) else {
            throw ModelCLIError.unknownSubcommand(rawSubcommand)
        }

        switch subcommand {
        case .rebuild:
            try self.init(command: ProtectCadenceCLIModelRebuildCommand.parse(Array(arguments.dropFirst())))
        case .episodes:
            try self.init(command: ProtectCadenceCLIModelEpisodesCommand.parse(Array(arguments.dropFirst())))
        case .findings:
            try self.init(command: ProtectCadenceCLIModelFindingsCommand.parse(Array(arguments.dropFirst())))
        }
    }

    init(command: ProtectCadenceCLIModelRebuildCommand) throws {
        self.subcommand = .rebuild
        self.configPath = command.configOptions.configPath
        self.sourceDatabasePathOverride = command.databaseOptions.databasePathOverride
        self.modelDatabasePathOverride = command.modelDatabaseOptions.modelDatabasePathOverride
        self.windowBounds = nil
        self.lastHours = nil
        self.cameras = []
        self.kinds = []
        self.stateKeys = []
        self.findingTypes = []
        self.limit = 0
        self.order = .newest
    }

    init(command: ProtectCadenceCLIModelEpisodesCommand) throws {
        let windowResolution = try Self.resolveWindow(
            primaryWindow: command.primaryWindow,
            defaultWindowHours: nil
        )
        self.subcommand = .episodes
        self.configPath = command.configOptions.configPath
        self.sourceDatabasePathOverride = command.databaseOptions.databasePathOverride
        self.modelDatabasePathOverride = command.modelDatabaseOptions.modelDatabasePathOverride
        self.windowBounds = windowResolution.bounds
        self.lastHours = windowResolution.lastHours
        self.cameras = command.filters.cameras
        self.kinds = command.filters.kinds
        self.stateKeys = command.filters.stateKeys
        self.findingTypes = []
        self.limit = try Self.parsePositiveInteger(command.limit, flag: "--limit") ?? 50
        self.order = try Self.parseOrder(command.order)
    }

    init(command: ProtectCadenceCLIModelFindingsCommand) throws {
        let windowResolution = try Self.resolveWindow(
            primaryWindow: command.primaryWindow,
            defaultWindowHours: nil
        )
        self.subcommand = .findings
        self.configPath = command.configOptions.configPath
        self.sourceDatabasePathOverride = command.databaseOptions.databasePathOverride
        self.modelDatabasePathOverride = command.modelDatabaseOptions.modelDatabasePathOverride
        self.windowBounds = windowResolution.bounds
        self.lastHours = windowResolution.lastHours
        self.cameras = command.filters.cameras
        self.kinds = command.filters.kinds
        self.stateKeys = command.filters.stateKeys
        self.findingTypes = try command.findingTypes.map(Self.parseFindingType)
        self.limit = try Self.parsePositiveInteger(command.limit, flag: "--limit") ?? 50
        self.order = .newest
    }

    public func resolvedWindow(now: Date = Date()) throws -> QueryWindow? {
        if let windowBounds {
            return try windowBounds.resolve(now: now)
        }
        guard let lastHours else {
            return nil
        }
        return QueryWindow(
            start: now.addingTimeInterval(-Double(lastHours) * 60 * 60),
            end: now
        )
    }

    public func episodesRequest(now: Date = Date()) throws -> ModelEpisodesRequest {
        ModelEpisodesRequest(
            filters: ModelEpisodeFilters(
                window: try resolvedWindow(now: now),
                cameras: cameras,
                kinds: kinds,
                stateKeys: stateKeys
            ),
            limit: limit,
            order: order
        )
    }

    public func findingsRequest(now: Date = Date()) throws -> ModelFindingsRequest {
        ModelFindingsRequest(
            filters: ModelEpisodeFilters(
                window: try resolvedWindow(now: now),
                cameras: cameras,
                kinds: kinds,
                stateKeys: stateKeys
            ),
            findingTypes: findingTypes,
            limit: limit
        )
    }

    private static func resolveWindow(
        primaryWindow: ProtectCadencePrimaryWindowOptions,
        defaultWindowHours: Int?
    ) throws -> (bounds: QueryWindowBounds?, lastHours: Int?) {
        let lastHours = try parsePositiveInteger(primaryWindow.lastHours, flag: "--last-hours")
        let explicitSince = try parseTimeBound(primaryWindow.since, flag: "--since")
        let explicitUntil = try parseTimeBound(primaryWindow.until, flag: "--until")

        if lastHours != nil, explicitSince != nil || explicitUntil != nil {
            throw ModelCLIError.conflictingWindowFlags
        }
        if explicitSince == nil, explicitUntil != nil {
            throw ModelCLIError.untilRequiresSince
        }

        if let explicitSince, let explicitUntil, explicitSince >= explicitUntil {
            throw ModelCLIError.invalidWindowRange(start: explicitSince, end: explicitUntil)
        }

        if explicitSince != nil || explicitUntil != nil {
            return (QueryWindowBounds(since: explicitSince, until: explicitUntil), nil)
        }
        if let lastHours {
            return (nil, lastHours)
        }
        if let defaultWindowHours {
            return (nil, defaultWindowHours)
        }
        return (nil, nil)
    }

    private static func parsePositiveInteger(_ value: Int?, flag: String) throws -> Int? {
        guard let value else {
            return nil
        }
        guard value > 0 else {
            throw ModelCLIError.invalidPositiveInteger(flag: flag, value: String(value))
        }
        return value
    }

    private static func parseTimeBound(_ rawValue: String?, flag: String) throws -> Date? {
        guard let rawValue else {
            return nil
        }
        guard let parsed = QueryDateParser.parse(rawValue) else {
            throw ModelCLIError.invalidTimeBound(flag: flag, value: rawValue)
        }
        return parsed
    }

    private static func parseOrder(_ rawValue: String) throws -> EventOrder {
        guard let parsed = EventOrder(rawValue: rawValue) else {
            throw ModelCLIError.invalidOrder(rawValue)
        }
        return parsed
    }

    private static func parseFindingType(_ rawValue: String) throws -> ModelFindingType {
        guard let parsed = ModelFindingType(rawValue: rawValue) else {
            throw ModelCLIError.invalidFindingType(rawValue)
        }
        return parsed
    }
}

private struct ModeledEpisodeSeed: Sendable {
    let camera: String
    let cameraID: String?
    let primaryKind: String
    let stateKey: String
    let startTime: Date
    let endTime: Date
    let durationSeconds: Int
    let eventCount: Int
    let sourceEventCount: Int
    let containsUnsettled: Bool
    let hourOfDay: Int
    let dayClass: ModelDayClass
    let kinds: [ModelEpisodeKind]
    let eventLinks: [EpisodeEventLink]
    let eventRowIDs: [Int64]
    let sourceEventIDs: [String]
}

private struct EpisodeEventLink: Sendable {
    let eventRowID: Int64
    let sourceEventID: String
}

private struct StateBucketStatSeed: Sendable {
    let stateKey: String
    let camera: String
    let primaryKind: String
    let hourOfDay: Int
    let dayClass: ModelDayClass
    let episodeCount: Int
    let stateEpisodeCount: Int
    let averageDurationSeconds: Double
    let minDurationSeconds: Int
    let maxDurationSeconds: Int
}

private struct StateTransitionStatSeed: Sendable {
    let camera: String
    let fromPrimaryKind: String
    let fromStateKey: String
    let toPrimaryKind: String
    let toStateKey: String
    let hourOfDay: Int
    let dayClass: ModelDayClass
    let transitionCount: Int
    let pairTransitionCount: Int
    let averageGapSeconds: Double
    let minGapSeconds: Int
    let maxGapSeconds: Int
}

private struct ModelFindingSeed: Sendable {
    let findingType: ModelFindingType
    let camera: String
    let primaryKind: String
    let stateKey: String
    let episodeIndex: Int
    let episodeStartTime: Date
    let episodeEndTime: Date
    let hourOfDay: Int
    let dayClass: ModelDayClass
    let score: Double
    let bucketEpisodeCount: Int
    let stateEpisodeCount: Int
    let observedDurationSeconds: Int?
    let expectedDurationSeconds: Double?
    let durationDirection: String?
    let previousEpisodeIndex: Int?
    let previousPrimaryKind: String?
    let previousStateKey: String?
    let transitionBucketCount: Int?
    let transitionPairCount: Int?
    let observedGapSeconds: Int?
    let expectedGapSeconds: Double?
}

private struct ModeledBuild: Sendable {
    let builtAt: Date
    let sourceDatabasePath: String
    let sourceEventCount: Int
    let sourceWindow: QueryWindow?
    let parameters: ModelBuildParameters
    let episodes: [ModeledEpisodeSeed]
    let stateBucketStats: [StateBucketStatSeed]
    let stateTransitionStats: [StateTransitionStatSeed]
    let findings: [ModelFindingSeed]
}

private struct ModeledEpisodeTransitionSeed: Sendable {
    let camera: String
    let fromPrimaryKind: String
    let fromStateKey: String
    let toPrimaryKind: String
    let toStateKey: String
    let fromEpisodeIndex: Int
    let toEpisodeIndex: Int
    let hourOfDay: Int
    let dayClass: ModelDayClass
    let gapSeconds: Int
}

private struct ModelRunRow {
    let id: Int64
    let builtAt: Date
    let sourceDatabasePath: String
    let sourceEventCount: Int
    let sourceWindowStart: Date?
    let sourceWindowEnd: Date?
    let parameters: ModelBuildParameters

    init(row: Row) {
        id = row["id"]
        builtAt = row["built_at"]
        sourceDatabasePath = row["source_database_path"]
        sourceEventCount = row["source_event_count"]
        sourceWindowStart = row["source_window_start"]
        sourceWindowEnd = row["source_window_end"]
        parameters = ModelBuildParameters(
            quietGapSeconds: row["quiet_gap_seconds"],
            modelVersion: row["model_version"],
            unexpectedPresenceMinimumStateCount: row["unexpected_presence_min_state_count"],
            unexpectedTransitionMinimumPairCount: row["unexpected_transition_min_pair_count"],
            unusualDurationMinimumBucketCount: row["unusual_duration_min_bucket_count"],
            unusualDurationRatioThreshold: row["unusual_duration_ratio_threshold"],
            unusualDurationMinimumDeltaSeconds: row["unusual_duration_min_delta_seconds"]
        )
    }

    var metadata: ModelBuildMetadata {
        ModelBuildMetadata(
            runID: id,
            builtAt: builtAt,
            sourceDatabasePath: sourceDatabasePath,
            sourceEventCount: sourceEventCount,
            sourceWindow: {
                guard let sourceWindowStart, let sourceWindowEnd else {
                    return nil
                }
                return QueryWindow(start: sourceWindowStart, end: sourceWindowEnd)
            }(),
            parameters: parameters
        )
    }
}

public final class ProtectCadenceModelDatabase {
    private let dbQueue: DatabaseQueue
    public let path: String

    public init(path: String) throws {
        self.path = path

        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        dbQueue = try DatabaseQueue(path: path, configuration: configuration)
        try Self.migrator.migrate(dbQueue)
    }

    fileprivate func replace(with build: ModeledBuild) throws -> ModelBuildMetadata {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM model_runs")

            try db.execute(
                sql: """
                    INSERT INTO model_runs (
                        built_at,
                        model_version,
                        source_database_path,
                        source_event_count,
                        source_window_start,
                        source_window_end,
                        quiet_gap_seconds,
                        unexpected_presence_min_state_count,
                        unexpected_transition_min_pair_count,
                        unusual_duration_min_bucket_count,
                        unusual_duration_ratio_threshold,
                        unusual_duration_min_delta_seconds
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    build.builtAt,
                    build.parameters.modelVersion,
                    build.sourceDatabasePath,
                    build.sourceEventCount,
                    build.sourceWindow?.start,
                    build.sourceWindow?.end,
                    build.parameters.quietGapSeconds,
                    build.parameters.unexpectedPresenceMinimumStateCount,
                    build.parameters.unexpectedTransitionMinimumPairCount,
                    build.parameters.unusualDurationMinimumBucketCount,
                    build.parameters.unusualDurationRatioThreshold,
                    build.parameters.unusualDurationMinimumDeltaSeconds,
                ]
            )
            let runID = db.lastInsertedRowID

            var persistedEpisodeIDs: [Int64] = []
            for episode in build.episodes {
                try db.execute(
                    sql: """
                        INSERT INTO episodes (
                            run_id,
                            camera,
                            camera_id,
                            primary_kind,
                            state_key,
                            start_time,
                            end_time,
                            duration_seconds,
                            event_count,
                            source_event_count,
                            contains_unsettled,
                            hour_of_day,
                            day_class
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        runID,
                        episode.camera,
                        episode.cameraID,
                        episode.primaryKind,
                        episode.stateKey,
                        episode.startTime,
                        episode.endTime,
                        episode.durationSeconds,
                        episode.eventCount,
                        episode.sourceEventCount,
                        episode.containsUnsettled ? 1 : 0,
                        episode.hourOfDay,
                        episode.dayClass.rawValue,
                    ]
                )
                let episodeID = db.lastInsertedRowID
                persistedEpisodeIDs.append(episodeID)

                for (ordinal, eventLink) in episode.eventLinks.enumerated() {
                    try db.execute(
                        sql: """
                            INSERT INTO episode_events (episode_id, event_row_id, source_event_id, ordinal)
                            VALUES (?, ?, ?, ?)
                            """,
                        arguments: [
                            episodeID,
                            eventLink.eventRowID,
                            eventLink.sourceEventID,
                            ordinal,
                        ]
                    )
                }

                for kind in episode.kinds {
                    try db.execute(
                        sql: """
                            INSERT INTO episode_kinds (episode_id, kind, occurrence_count, is_primary)
                            VALUES (?, ?, ?, ?)
                            """,
                        arguments: [
                            episodeID,
                            kind.kind,
                            kind.occurrenceCount,
                            kind.isPrimary ? 1 : 0,
                        ]
                    )
                }
            }

            for stat in build.stateBucketStats {
                try db.execute(
                    sql: """
                        INSERT INTO state_bucket_stats (
                            run_id,
                            state_key,
                            camera,
                            primary_kind,
                            hour_of_day,
                            day_class,
                            episode_count,
                            state_episode_count,
                            average_duration_seconds,
                            min_duration_seconds,
                            max_duration_seconds
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        runID,
                        stat.stateKey,
                        stat.camera,
                        stat.primaryKind,
                        stat.hourOfDay,
                        stat.dayClass.rawValue,
                        stat.episodeCount,
                        stat.stateEpisodeCount,
                        stat.averageDurationSeconds,
                        stat.minDurationSeconds,
                        stat.maxDurationSeconds,
                    ]
                )
            }

            for stat in build.stateTransitionStats {
                try db.execute(
                    sql: """
                        INSERT INTO state_transition_stats (
                            run_id,
                            camera,
                            from_primary_kind,
                            from_state_key,
                            to_primary_kind,
                            to_state_key,
                            hour_of_day,
                            day_class,
                            transition_count,
                            pair_transition_count,
                            average_gap_seconds,
                            min_gap_seconds,
                            max_gap_seconds
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        runID,
                        stat.camera,
                        stat.fromPrimaryKind,
                        stat.fromStateKey,
                        stat.toPrimaryKind,
                        stat.toStateKey,
                        stat.hourOfDay,
                        stat.dayClass.rawValue,
                        stat.transitionCount,
                        stat.pairTransitionCount,
                        stat.averageGapSeconds,
                        stat.minGapSeconds,
                        stat.maxGapSeconds,
                    ]
                )
            }

            for finding in build.findings {
                let episodeID = persistedEpisodeIDs[finding.episodeIndex]
                try db.execute(
                    sql: """
                        INSERT INTO attention_findings (
                            run_id,
                            finding_type,
                            camera,
                            primary_kind,
                            state_key,
                            episode_id,
                            episode_start_time,
                            episode_end_time,
                            hour_of_day,
                            day_class,
                            score,
                            bucket_episode_count,
                            state_episode_count,
                            observed_duration_seconds,
                            expected_duration_seconds,
                            duration_direction,
                            previous_primary_kind,
                            previous_state_key,
                            transition_bucket_count,
                            transition_pair_count,
                            observed_gap_seconds,
                            expected_gap_seconds
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        runID,
                        finding.findingType.rawValue,
                        finding.camera,
                        finding.primaryKind,
                        finding.stateKey,
                        episodeID,
                        finding.episodeStartTime,
                        finding.episodeEndTime,
                        finding.hourOfDay,
                        finding.dayClass.rawValue,
                        finding.score,
                        finding.bucketEpisodeCount,
                        finding.stateEpisodeCount,
                        finding.observedDurationSeconds,
                        finding.expectedDurationSeconds,
                        finding.durationDirection,
                        finding.previousPrimaryKind,
                        finding.previousStateKey,
                        finding.transitionBucketCount,
                        finding.transitionPairCount,
                        finding.observedGapSeconds,
                        finding.expectedGapSeconds,
                    ]
                )
                let findingID = db.lastInsertedRowID
                try db.execute(
                    sql: """
                        INSERT INTO attention_finding_episodes (finding_id, episode_id, relation)
                        VALUES (?, ?, ?)
                        """,
                    arguments: [findingID, episodeID, "observed"]
                )
                if let previousEpisodeIndex = finding.previousEpisodeIndex {
                    try db.execute(
                        sql: """
                            INSERT INTO attention_finding_episodes (finding_id, episode_id, relation)
                            VALUES (?, ?, ?)
                            """,
                        arguments: [findingID, persistedEpisodeIDs[previousEpisodeIndex], "previous"]
                    )
                }
            }

            return ModelBuildMetadata(
                runID: runID,
                builtAt: build.builtAt,
                sourceDatabasePath: build.sourceDatabasePath,
                sourceEventCount: build.sourceEventCount,
                sourceWindow: build.sourceWindow,
                parameters: build.parameters
            )
        }
    }

    public func latestBuildMetadata() throws -> ModelBuildMetadata {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT *
                    FROM model_runs
                    ORDER BY id DESC
                    LIMIT 1
                    """
            ) else {
                throw ModelCLIError.noBuildAvailable(path)
            }
            return ModelRunRow(row: row).metadata
        }
    }

    public func fetchEpisodes(_ request: ModelEpisodesRequest) throws -> [ModelEpisode] {
        try dbQueue.read { db in
            let run = try latestRunRow(db: db)
            let whereClause = episodeWhereClause(filters: request.filters, includeStateKeys: true)
            let orderClause: String
            switch request.order {
            case .newest:
                orderClause = "start_time DESC, id DESC"
            case .oldest:
                orderClause = "start_time ASC, id ASC"
            }

            var arguments = StatementArguments([run.id])
            arguments += whereClause.arguments
            arguments += [request.limit]

            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT *
                    FROM episodes
                    WHERE run_id = ?
                    \(whereClause.sql)
                    ORDER BY \(orderClause)
                    LIMIT ?
                    """,
                arguments: arguments
            )

            return try rows.map { row in
                let episodeID: Int64 = row["id"]
                let kinds = try fetchKinds(forEpisodeID: episodeID, db: db)
                let eventLinkRows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT event_row_id, source_event_id
                        FROM episode_events
                        WHERE episode_id = ?
                        ORDER BY ordinal ASC
                        """,
                    arguments: [episodeID]
                )

                return ModelEpisode(
                    id: episodeID,
                    camera: row["camera"],
                    cameraID: row["camera_id"],
                    primaryKind: row["primary_kind"],
                    stateKey: row["state_key"],
                    startTime: row["start_time"],
                    endTime: row["end_time"],
                    durationSeconds: row["duration_seconds"],
                    eventCount: row["event_count"],
                    sourceEventCount: row["source_event_count"],
                    containsUnsettled: (row["contains_unsettled"] as Int64) == 1,
                    hourOfDay: row["hour_of_day"],
                    dayClass: ModelDayClass(rawValue: row["day_class"]) ?? .weekday,
                    kinds: kinds,
                    eventRowIDs: eventLinkRows.map { $0["event_row_id"] },
                    sourceEventIDs: orderedUnique(eventLinkRows.map { $0["source_event_id"] })
                )
            }
        }
    }

    public func fetchFindings(_ request: ModelFindingsRequest) throws -> [ModelFinding] {
        try dbQueue.read { db in
            let run = try latestRunRow(db: db)
            let whereClause = findingWhereClause(request: request)
            var arguments = StatementArguments([run.id])
            arguments += whereClause.arguments
            arguments += [request.limit]

            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT *
                    FROM attention_findings
                    WHERE run_id = ?
                    \(whereClause.sql)
                    ORDER BY score DESC, episode_start_time DESC, id DESC
                    LIMIT ?
                    """,
                arguments: arguments
            )

            return try rows.map { row in
                let findingID: Int64 = row["id"]
                let linkedEpisodeRows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT episode_id, relation
                        FROM attention_finding_episodes
                        WHERE finding_id = ?
                        ORDER BY relation ASC, episode_id ASC
                        """,
                    arguments: [findingID]
                )
                let previousEpisodeID = linkedEpisodeRows.first { ($0["relation"] as String) == "previous" }.map { $0["episode_id"] as Int64 }

                guard let findingType = ModelFindingType(rawValue: row["finding_type"]) else {
                    throw DatabaseError(resultCode: .SQLITE_ERROR, message: "unexpected finding_type")
                }

                return ModelFinding(
                    id: findingID,
                    findingType: findingType,
                    camera: row["camera"],
                    primaryKind: row["primary_kind"],
                    stateKey: row["state_key"],
                    episodeID: row["episode_id"],
                    episodeStartTime: row["episode_start_time"],
                    episodeEndTime: row["episode_end_time"],
                    hourOfDay: row["hour_of_day"],
                    dayClass: ModelDayClass(rawValue: row["day_class"]) ?? .weekday,
                    score: row["score"],
                    bucketEpisodeCount: row["bucket_episode_count"],
                    stateEpisodeCount: row["state_episode_count"],
                    observedDurationSeconds: row["observed_duration_seconds"],
                    expectedDurationSeconds: row["expected_duration_seconds"],
                    durationDirection: row["duration_direction"],
                    previousEpisodeID: previousEpisodeID,
                    previousPrimaryKind: row["previous_primary_kind"],
                    previousStateKey: row["previous_state_key"],
                    transitionBucketCount: row["transition_bucket_count"],
                    transitionPairCount: row["transition_pair_count"],
                    observedGapSeconds: row["observed_gap_seconds"],
                    expectedGapSeconds: row["expected_gap_seconds"],
                    linkedEpisodeIDs: linkedEpisodeRows.map { $0["episode_id"] }
                )
            }
        }
    }

    public func latestCounts() throws -> (episodeCount: Int, stateBucketStatCount: Int, stateTransitionStatCount: Int, findingCount: Int) {
        try dbQueue.read { db in
            let run = try latestRunRow(db: db)
            let episodeCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM episodes WHERE run_id = ?",
                arguments: [run.id]
            ) ?? 0
            let stateBucketStatCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM state_bucket_stats WHERE run_id = ?",
                arguments: [run.id]
            ) ?? 0
            let stateTransitionStatCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM state_transition_stats WHERE run_id = ?",
                arguments: [run.id]
            ) ?? 0
            let findingCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM attention_findings WHERE run_id = ?",
                arguments: [run.id]
            ) ?? 0
            return (episodeCount, stateBucketStatCount, stateTransitionStatCount, findingCount)
        }
    }

    private func latestRunRow(db: Database) throws -> ModelRunRow {
        guard let row = try Row.fetchOne(
            db,
            sql: """
                SELECT *
                FROM model_runs
                ORDER BY id DESC
                LIMIT 1
                """
        ) else {
            throw ModelCLIError.noBuildAvailable(path)
        }
        return ModelRunRow(row: row)
    }

    private func fetchKinds(forEpisodeID episodeID: Int64, db: Database) throws -> [ModelEpisodeKind] {
        try Row.fetchAll(
            db,
            sql: """
                SELECT kind, occurrence_count, is_primary
                FROM episode_kinds
                WHERE episode_id = ?
                ORDER BY is_primary DESC, occurrence_count DESC, kind ASC
                """,
            arguments: [episodeID]
        ).map { row in
            ModelEpisodeKind(
                kind: row["kind"],
                occurrenceCount: row["occurrence_count"],
                isPrimary: (row["is_primary"] as Int64) == 1
            )
        }
    }

    private func episodeWhereClause(
        filters: ModelEpisodeFilters,
        includeStateKeys: Bool
    ) -> (sql: String, arguments: StatementArguments) {
        var clauses: [String] = []
        var arguments = StatementArguments()

        if let window = filters.window {
            clauses.append("start_time >= ? AND start_time < ?")
            arguments += [window.start, window.end]
        }
        if !filters.cameras.isEmpty {
            clauses.append("camera IN (\(Self.bindVariables(count: filters.cameras.count)))")
            for camera in filters.cameras {
                arguments += [camera]
            }
        }
        if !filters.kinds.isEmpty {
            clauses.append("primary_kind IN (\(Self.bindVariables(count: filters.kinds.count)))")
            for kind in filters.kinds {
                arguments += [kind]
            }
        }
        if includeStateKeys, !filters.stateKeys.isEmpty {
            clauses.append("state_key IN (\(Self.bindVariables(count: filters.stateKeys.count)))")
            for stateKey in filters.stateKeys {
                arguments += [stateKey]
            }
        }

        let sql = clauses.isEmpty ? "" : "AND " + clauses.joined(separator: " AND ")
        return (sql, arguments)
    }

    private func findingWhereClause(request: ModelFindingsRequest) -> (sql: String, arguments: StatementArguments) {
        var clauses: [String] = []
        var arguments = StatementArguments()

        if let window = request.filters.window {
            clauses.append("episode_start_time >= ? AND episode_start_time < ?")
            arguments += [window.start, window.end]
        }
        if !request.filters.cameras.isEmpty {
            clauses.append("camera IN (\(Self.bindVariables(count: request.filters.cameras.count)))")
            for camera in request.filters.cameras {
                arguments += [camera]
            }
        }
        if !request.filters.kinds.isEmpty {
            clauses.append("primary_kind IN (\(Self.bindVariables(count: request.filters.kinds.count)))")
            for kind in request.filters.kinds {
                arguments += [kind]
            }
        }
        if !request.filters.stateKeys.isEmpty {
            clauses.append("state_key IN (\(Self.bindVariables(count: request.filters.stateKeys.count)))")
            for stateKey in request.filters.stateKeys {
                arguments += [stateKey]
            }
        }
        if !request.findingTypes.isEmpty {
            clauses.append("finding_type IN (\(Self.bindVariables(count: request.findingTypes.count)))")
            for findingType in request.findingTypes {
                arguments += [findingType.rawValue]
            }
        }

        let sql = clauses.isEmpty ? "" : "AND " + clauses.joined(separator: " AND ")
        return (sql, arguments)
    }

    private static func bindVariables(count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("createModelTables") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS model_runs (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    built_at DATETIME NOT NULL,
                    model_version TEXT NOT NULL,
                    source_database_path TEXT NOT NULL,
                    source_event_count INTEGER NOT NULL,
                    source_window_start DATETIME,
                    source_window_end DATETIME,
                    quiet_gap_seconds INTEGER NOT NULL,
                    unexpected_presence_min_state_count INTEGER NOT NULL,
                    unexpected_transition_min_pair_count INTEGER NOT NULL,
                    unusual_duration_min_bucket_count INTEGER NOT NULL,
                    unusual_duration_ratio_threshold REAL NOT NULL,
                    unusual_duration_min_delta_seconds INTEGER NOT NULL
                );

                CREATE TABLE IF NOT EXISTS episodes (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    run_id INTEGER NOT NULL REFERENCES model_runs(id) ON DELETE CASCADE,
                    camera TEXT NOT NULL,
                    camera_id TEXT,
                    primary_kind TEXT NOT NULL,
                    state_key TEXT NOT NULL,
                    start_time DATETIME NOT NULL,
                    end_time DATETIME NOT NULL,
                    duration_seconds INTEGER NOT NULL,
                    event_count INTEGER NOT NULL,
                    source_event_count INTEGER NOT NULL,
                    contains_unsettled INTEGER NOT NULL,
                    hour_of_day INTEGER NOT NULL,
                    day_class TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS episode_events (
                    episode_id INTEGER NOT NULL REFERENCES episodes(id) ON DELETE CASCADE,
                    event_row_id INTEGER NOT NULL,
                    source_event_id TEXT NOT NULL,
                    ordinal INTEGER NOT NULL,
                    PRIMARY KEY (episode_id, event_row_id)
                );

                CREATE TABLE IF NOT EXISTS episode_kinds (
                    episode_id INTEGER NOT NULL REFERENCES episodes(id) ON DELETE CASCADE,
                    kind TEXT NOT NULL,
                    occurrence_count INTEGER NOT NULL,
                    is_primary INTEGER NOT NULL,
                    PRIMARY KEY (episode_id, kind)
                );

                CREATE TABLE IF NOT EXISTS state_bucket_stats (
                    run_id INTEGER NOT NULL REFERENCES model_runs(id) ON DELETE CASCADE,
                    state_key TEXT NOT NULL,
                    camera TEXT NOT NULL,
                    primary_kind TEXT NOT NULL,
                    hour_of_day INTEGER NOT NULL,
                    day_class TEXT NOT NULL,
                    episode_count INTEGER NOT NULL,
                    state_episode_count INTEGER NOT NULL,
                    average_duration_seconds REAL NOT NULL,
                    min_duration_seconds INTEGER NOT NULL,
                    max_duration_seconds INTEGER NOT NULL,
                    PRIMARY KEY (run_id, state_key, hour_of_day, day_class)
                );

                CREATE TABLE IF NOT EXISTS attention_findings (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    run_id INTEGER NOT NULL REFERENCES model_runs(id) ON DELETE CASCADE,
                    finding_type TEXT NOT NULL,
                    camera TEXT NOT NULL,
                    primary_kind TEXT NOT NULL,
                    state_key TEXT NOT NULL,
                    episode_id INTEGER NOT NULL REFERENCES episodes(id) ON DELETE CASCADE,
                    episode_start_time DATETIME NOT NULL,
                    episode_end_time DATETIME NOT NULL,
                    hour_of_day INTEGER NOT NULL,
                    day_class TEXT NOT NULL,
                    score REAL NOT NULL,
                    bucket_episode_count INTEGER NOT NULL,
                    state_episode_count INTEGER NOT NULL,
                    observed_duration_seconds INTEGER,
                    expected_duration_seconds REAL,
                    duration_direction TEXT,
                    previous_primary_kind TEXT,
                    previous_state_key TEXT,
                    transition_bucket_count INTEGER,
                    transition_pair_count INTEGER,
                    observed_gap_seconds INTEGER,
                    expected_gap_seconds REAL
                );

                CREATE TABLE IF NOT EXISTS state_transition_stats (
                    run_id INTEGER NOT NULL REFERENCES model_runs(id) ON DELETE CASCADE,
                    camera TEXT NOT NULL,
                    from_primary_kind TEXT NOT NULL,
                    from_state_key TEXT NOT NULL,
                    to_primary_kind TEXT NOT NULL,
                    to_state_key TEXT NOT NULL,
                    hour_of_day INTEGER NOT NULL,
                    day_class TEXT NOT NULL,
                    transition_count INTEGER NOT NULL,
                    pair_transition_count INTEGER NOT NULL,
                    average_gap_seconds REAL NOT NULL,
                    min_gap_seconds INTEGER NOT NULL,
                    max_gap_seconds INTEGER NOT NULL,
                    PRIMARY KEY (run_id, from_state_key, to_state_key, hour_of_day, day_class)
                );

                CREATE TABLE IF NOT EXISTS attention_finding_episodes (
                    finding_id INTEGER NOT NULL REFERENCES attention_findings(id) ON DELETE CASCADE,
                    episode_id INTEGER NOT NULL REFERENCES episodes(id) ON DELETE CASCADE,
                    relation TEXT NOT NULL,
                    PRIMARY KEY (finding_id, episode_id, relation)
                );

                CREATE INDEX IF NOT EXISTS episodes_on_run_start_time
                ON episodes (run_id, start_time);

                CREATE INDEX IF NOT EXISTS episodes_on_run_camera_kind
                ON episodes (run_id, camera, primary_kind);

                CREATE INDEX IF NOT EXISTS state_bucket_stats_on_run_camera
                ON state_bucket_stats (run_id, camera, primary_kind, hour_of_day, day_class);

                CREATE INDEX IF NOT EXISTS state_transition_stats_on_run_from_to
                ON state_transition_stats (run_id, camera, from_state_key, to_state_key, hour_of_day, day_class);

                CREATE INDEX IF NOT EXISTS attention_findings_on_run_type
                ON attention_findings (run_id, finding_type, score DESC);
                """)
        }

        migrator.registerMigration("addTransitionStatsAndFindingFields") { db in
            if try !db.columns(in: "model_runs").contains(where: { $0.name == "unexpected_transition_min_pair_count" }) {
                try db.execute(sql: """
                    ALTER TABLE model_runs
                    ADD COLUMN unexpected_transition_min_pair_count INTEGER NOT NULL DEFAULT 3
                    """)
            }

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS state_transition_stats (
                    run_id INTEGER NOT NULL REFERENCES model_runs(id) ON DELETE CASCADE,
                    camera TEXT NOT NULL,
                    from_primary_kind TEXT NOT NULL,
                    from_state_key TEXT NOT NULL,
                    to_primary_kind TEXT NOT NULL,
                    to_state_key TEXT NOT NULL,
                    hour_of_day INTEGER NOT NULL,
                    day_class TEXT NOT NULL,
                    transition_count INTEGER NOT NULL,
                    pair_transition_count INTEGER NOT NULL,
                    average_gap_seconds REAL NOT NULL,
                    min_gap_seconds INTEGER NOT NULL,
                    max_gap_seconds INTEGER NOT NULL,
                    PRIMARY KEY (run_id, from_state_key, to_state_key, hour_of_day, day_class)
                );

                CREATE INDEX IF NOT EXISTS state_transition_stats_on_run_from_to
                ON state_transition_stats (run_id, camera, from_state_key, to_state_key, hour_of_day, day_class);
                """)

            let attentionFindingColumns = try db.columns(in: "attention_findings").map(\.name)
            if !attentionFindingColumns.contains("previous_primary_kind") {
                try db.execute(sql: """
                    ALTER TABLE attention_findings
                    ADD COLUMN previous_primary_kind TEXT
                    """)
            }
            if !attentionFindingColumns.contains("previous_state_key") {
                try db.execute(sql: """
                    ALTER TABLE attention_findings
                    ADD COLUMN previous_state_key TEXT
                    """)
            }
            if !attentionFindingColumns.contains("transition_bucket_count") {
                try db.execute(sql: """
                    ALTER TABLE attention_findings
                    ADD COLUMN transition_bucket_count INTEGER
                    """)
            }
            if !attentionFindingColumns.contains("transition_pair_count") {
                try db.execute(sql: """
                    ALTER TABLE attention_findings
                    ADD COLUMN transition_pair_count INTEGER
                    """)
            }
            if !attentionFindingColumns.contains("observed_gap_seconds") {
                try db.execute(sql: """
                    ALTER TABLE attention_findings
                    ADD COLUMN observed_gap_seconds INTEGER
                    """)
            }
            if !attentionFindingColumns.contains("expected_gap_seconds") {
                try db.execute(sql: """
                    ALTER TABLE attention_findings
                    ADD COLUMN expected_gap_seconds REAL
                    """)
            }
        }

        return migrator
    }
}

private enum ProtectCadenceModeler {
    static let parameters = ModelBuildParameters(
        quietGapSeconds: 5 * 60,
        modelVersion: "episode-gap-transition-v2",
        unexpectedPresenceMinimumStateCount: 3,
        unexpectedTransitionMinimumPairCount: 3,
        unusualDurationMinimumBucketCount: 2,
        unusualDurationRatioThreshold: 2.0,
        unusualDurationMinimumDeltaSeconds: 5 * 60
    )

    static func build(
        from events: [EventRow],
        sourceDatabasePath: String,
        builtAt: Date = Date(),
        calendar: Calendar = .current
    ) -> ModeledBuild {
        let episodes = materializeEpisodes(from: events, calendar: calendar, quietGapSeconds: parameters.quietGapSeconds)
        let transitions = buildEpisodeTransitions(from: episodes)
        let stateBucketStats = buildStateBucketStats(from: episodes)
        let stateTransitionStats = buildStateTransitionStats(from: transitions)
        let findings = buildFindings(
            episodes: episodes,
            transitions: transitions,
            stateBucketStats: stateBucketStats,
            stateTransitionStats: stateTransitionStats,
            parameters: parameters
        )

        return ModeledBuild(
            builtAt: builtAt,
            sourceDatabasePath: sourceDatabasePath,
            sourceEventCount: events.count,
            sourceWindow: {
                guard let first = events.first, let last = events.last else {
                    return nil
                }
                return QueryWindow(
                    start: first.timeStart,
                    end: max(last.timeEnd ?? last.timeStart, last.timeStart)
                )
            }(),
            parameters: parameters,
            episodes: episodes,
            stateBucketStats: stateBucketStats,
            stateTransitionStats: stateTransitionStats,
            findings: findings
        )
    }

    static func materializeEpisodes(
        from events: [EventRow],
        calendar: Calendar = .current,
        quietGapSeconds: Int
    ) -> [ModeledEpisodeSeed] {
        let sortedEvents = events.sorted { lhs, rhs in
            let leftEnd = lhs.timeEnd ?? lhs.timeStart
            let rightEnd = rhs.timeEnd ?? rhs.timeStart
            return (lhs.camera, lhs.timeStart, leftEnd, lhs.kind, lhs.id ?? 0)
                < (rhs.camera, rhs.timeStart, rightEnd, rhs.kind, rhs.id ?? 0)
        }

        var builders: [EpisodeBuilder] = []
        var current: EpisodeBuilder?

        for event in sortedEvents {
            if let current, current.canInclude(event, quietGapSeconds: quietGapSeconds) {
                current.include(event)
            } else {
                if let current {
                    builders.append(current)
                }
                current = EpisodeBuilder(firstEvent: event)
            }
        }
        if let current {
            builders.append(current)
        }

        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = .current
        return builders.map { $0.makeSeed(calendar: localCalendar) }
    }

    private static func buildStateBucketStats(from episodes: [ModeledEpisodeSeed]) -> [StateBucketStatSeed] {
        let totalsByState = Dictionary(grouping: episodes, by: \.stateKey).mapValues(\.count)
        let grouped = Dictionary(grouping: episodes) {
            "\($0.stateKey)\u{001F}\($0.hourOfDay)\u{001F}\($0.dayClass.rawValue)"
        }

        return grouped.values.map { bucketEpisodes in
            let first = bucketEpisodes[0]
            let durations = bucketEpisodes.map(\.durationSeconds)
            let durationSum = durations.reduce(0, +)
            return StateBucketStatSeed(
                stateKey: first.stateKey,
                camera: first.camera,
                primaryKind: first.primaryKind,
                hourOfDay: first.hourOfDay,
                dayClass: first.dayClass,
                episodeCount: bucketEpisodes.count,
                stateEpisodeCount: totalsByState[first.stateKey] ?? bucketEpisodes.count,
                averageDurationSeconds: Double(durationSum) / Double(bucketEpisodes.count),
                minDurationSeconds: durations.min() ?? 0,
                maxDurationSeconds: durations.max() ?? 0
            )
        }
        .sorted {
            ($0.camera, $0.primaryKind, $0.dayClass.rawValue, $0.hourOfDay)
                < ($1.camera, $1.primaryKind, $1.dayClass.rawValue, $1.hourOfDay)
        }
    }

    private static func buildEpisodeTransitions(from episodes: [ModeledEpisodeSeed]) -> [ModeledEpisodeTransitionSeed] {
        let indexedEpisodes = Array(episodes.enumerated())
        let grouped = Dictionary(grouping: indexedEpisodes, by: { $0.element.camera })

        return grouped.values
            .flatMap { cameraEpisodes in
                let ordered = cameraEpisodes.sorted {
                    ($0.element.startTime, $0.element.endTime, $0.offset)
                        < ($1.element.startTime, $1.element.endTime, $1.offset)
                }
                guard ordered.count >= 2 else {
                    return [ModeledEpisodeTransitionSeed]()
                }

                return zip(ordered, ordered.dropFirst()).map { previous, current in
                    ModeledEpisodeTransitionSeed(
                        camera: current.element.camera,
                        fromPrimaryKind: previous.element.primaryKind,
                        fromStateKey: previous.element.stateKey,
                        toPrimaryKind: current.element.primaryKind,
                        toStateKey: current.element.stateKey,
                        fromEpisodeIndex: previous.offset,
                        toEpisodeIndex: current.offset,
                        hourOfDay: current.element.hourOfDay,
                        dayClass: current.element.dayClass,
                        gapSeconds: max(0, Int(current.element.startTime.timeIntervalSince(previous.element.endTime)))
                    )
                }
            }
            .sorted {
                ($0.camera, $0.dayClass.rawValue, $0.hourOfDay, $0.fromStateKey, $0.toStateKey, $0.toEpisodeIndex)
                    < ($1.camera, $1.dayClass.rawValue, $1.hourOfDay, $1.fromStateKey, $1.toStateKey, $1.toEpisodeIndex)
            }
    }

    private static func buildStateTransitionStats(from transitions: [ModeledEpisodeTransitionSeed]) -> [StateTransitionStatSeed] {
        let totalsByPair = Dictionary(grouping: transitions, by: {
            transitionPairKey(fromStateKey: $0.fromStateKey, toStateKey: $0.toStateKey)
        }).mapValues(\.count)
        let grouped = Dictionary(grouping: transitions) {
            transitionBucketKey(
                fromStateKey: $0.fromStateKey,
                toStateKey: $0.toStateKey,
                hourOfDay: $0.hourOfDay,
                dayClass: $0.dayClass
            )
        }

        return grouped.values.map { bucketTransitions in
            let first = bucketTransitions[0]
            let gaps = bucketTransitions.map(\.gapSeconds)
            let gapSum = gaps.reduce(0, +)
            return StateTransitionStatSeed(
                camera: first.camera,
                fromPrimaryKind: first.fromPrimaryKind,
                fromStateKey: first.fromStateKey,
                toPrimaryKind: first.toPrimaryKind,
                toStateKey: first.toStateKey,
                hourOfDay: first.hourOfDay,
                dayClass: first.dayClass,
                transitionCount: bucketTransitions.count,
                pairTransitionCount: totalsByPair[
                    transitionPairKey(fromStateKey: first.fromStateKey, toStateKey: first.toStateKey)
                ] ?? bucketTransitions.count,
                averageGapSeconds: Double(gapSum) / Double(bucketTransitions.count),
                minGapSeconds: gaps.min() ?? 0,
                maxGapSeconds: gaps.max() ?? 0
            )
        }
        .sorted {
            ($0.camera, $0.fromPrimaryKind, $0.toPrimaryKind, $0.dayClass.rawValue, $0.hourOfDay)
                < ($1.camera, $1.fromPrimaryKind, $1.toPrimaryKind, $1.dayClass.rawValue, $1.hourOfDay)
        }
    }

    private static func buildFindings(
        episodes: [ModeledEpisodeSeed],
        transitions: [ModeledEpisodeTransitionSeed],
        stateBucketStats: [StateBucketStatSeed],
        stateTransitionStats: [StateTransitionStatSeed],
        parameters: ModelBuildParameters
    ) -> [ModelFindingSeed] {
        let statByKey = Dictionary(uniqueKeysWithValues: stateBucketStats.map { stat in
            (stateBucketKey(stateKey: stat.stateKey, hourOfDay: stat.hourOfDay, dayClass: stat.dayClass), stat)
        })
        let transitionStatByKey = Dictionary(uniqueKeysWithValues: stateTransitionStats.map { stat in
            (
                transitionBucketKey(
                    fromStateKey: stat.fromStateKey,
                    toStateKey: stat.toStateKey,
                    hourOfDay: stat.hourOfDay,
                    dayClass: stat.dayClass
                ),
                stat
            )
        })

        var findings: [ModelFindingSeed] = []
        for (episodeIndex, episode) in episodes.enumerated() {
            guard let stat = statByKey[stateBucketKey(stateKey: episode.stateKey, hourOfDay: episode.hourOfDay, dayClass: episode.dayClass)] else {
                continue
            }

            if stat.stateEpisodeCount >= parameters.unexpectedPresenceMinimumStateCount,
               stat.episodeCount == 1
            {
                findings.append(
                    ModelFindingSeed(
                        findingType: .unexpectedPresence,
                        camera: episode.camera,
                        primaryKind: episode.primaryKind,
                        stateKey: episode.stateKey,
                        episodeIndex: episodeIndex,
                        episodeStartTime: episode.startTime,
                        episodeEndTime: episode.endTime,
                        hourOfDay: episode.hourOfDay,
                        dayClass: episode.dayClass,
                        score: 1.0 - (1.0 / Double(stat.stateEpisodeCount)),
                        bucketEpisodeCount: stat.episodeCount,
                        stateEpisodeCount: stat.stateEpisodeCount,
                        observedDurationSeconds: episode.durationSeconds,
                        expectedDurationSeconds: nil,
                        durationDirection: nil,
                        previousEpisodeIndex: nil,
                        previousPrimaryKind: nil,
                        previousStateKey: nil,
                        transitionBucketCount: nil,
                        transitionPairCount: nil,
                        observedGapSeconds: nil,
                        expectedGapSeconds: nil
                    )
                )
            }

            if stat.episodeCount >= parameters.unusualDurationMinimumBucketCount,
               stat.averageDurationSeconds > 0
            {
                let observed = Double(episode.durationSeconds)
                let ratio = max(observed / stat.averageDurationSeconds, stat.averageDurationSeconds / observed)
                let delta = abs(observed - stat.averageDurationSeconds)

                if observed > stat.averageDurationSeconds,
                   ratio >= parameters.unusualDurationRatioThreshold,
                   delta >= Double(parameters.unusualDurationMinimumDeltaSeconds)
                {
                    findings.append(
                        ModelFindingSeed(
                            findingType: .unusualDuration,
                            camera: episode.camera,
                            primaryKind: episode.primaryKind,
                            stateKey: episode.stateKey,
                            episodeIndex: episodeIndex,
                            episodeStartTime: episode.startTime,
                            episodeEndTime: episode.endTime,
                            hourOfDay: episode.hourOfDay,
                            dayClass: episode.dayClass,
                            score: ratio,
                            bucketEpisodeCount: stat.episodeCount,
                            stateEpisodeCount: stat.stateEpisodeCount,
                            observedDurationSeconds: episode.durationSeconds,
                            expectedDurationSeconds: stat.averageDurationSeconds,
                            durationDirection: "longer",
                            previousEpisodeIndex: nil,
                            previousPrimaryKind: nil,
                            previousStateKey: nil,
                            transitionBucketCount: nil,
                            transitionPairCount: nil,
                            observedGapSeconds: nil,
                            expectedGapSeconds: nil
                        )
                    )
                }
            }
        }

        for transition in transitions {
            let key = transitionBucketKey(
                fromStateKey: transition.fromStateKey,
                toStateKey: transition.toStateKey,
                hourOfDay: transition.hourOfDay,
                dayClass: transition.dayClass
            )
            guard let stat = transitionStatByKey[key] else {
                continue
            }

            if stat.pairTransitionCount >= parameters.unexpectedTransitionMinimumPairCount,
               stat.transitionCount == 1
            {
                let episode = episodes[transition.toEpisodeIndex]
                findings.append(
                    ModelFindingSeed(
                        findingType: .unexpectedTransition,
                        camera: episode.camera,
                        primaryKind: episode.primaryKind,
                        stateKey: episode.stateKey,
                        episodeIndex: transition.toEpisodeIndex,
                        episodeStartTime: episode.startTime,
                        episodeEndTime: episode.endTime,
                        hourOfDay: episode.hourOfDay,
                        dayClass: episode.dayClass,
                        score: 1.0 - (1.0 / Double(stat.pairTransitionCount)),
                        bucketEpisodeCount: 1,
                        stateEpisodeCount: stat.pairTransitionCount,
                        observedDurationSeconds: nil,
                        expectedDurationSeconds: nil,
                        durationDirection: nil,
                        previousEpisodeIndex: transition.fromEpisodeIndex,
                        previousPrimaryKind: transition.fromPrimaryKind,
                        previousStateKey: transition.fromStateKey,
                        transitionBucketCount: stat.transitionCount,
                        transitionPairCount: stat.pairTransitionCount,
                        observedGapSeconds: transition.gapSeconds,
                        expectedGapSeconds: stat.averageGapSeconds
                    )
                )
            }
        }

        return findings.sorted {
            ($0.score, $0.episodeStartTime, $0.findingType.rawValue)
                > ($1.score, $1.episodeStartTime, $1.findingType.rawValue)
        }
    }

    private static func stateBucketKey(stateKey: String, hourOfDay: Int, dayClass: ModelDayClass) -> String {
        "\(stateKey)\u{001F}\(hourOfDay)\u{001F}\(dayClass.rawValue)"
    }

    private static func transitionPairKey(fromStateKey: String, toStateKey: String) -> String {
        "\(fromStateKey)\u{001F}\(toStateKey)"
    }

    private static func transitionBucketKey(
        fromStateKey: String,
        toStateKey: String,
        hourOfDay: Int,
        dayClass: ModelDayClass
    ) -> String {
        "\(transitionPairKey(fromStateKey: fromStateKey, toStateKey: toStateKey))\u{001F}\(hourOfDay)\u{001F}\(dayClass.rawValue)"
    }
}

private final class EpisodeBuilder: @unchecked Sendable {
    private let camera: String
    private var cameraID: String?
    private var startTime: Date
    private var endTime: Date
    private var eventCount = 0
    private var containsUnsettled = false
    private var kindCounts: [String: Int] = [:]
    private var firstSeenByKind: [String: Date] = [:]
    private var eventLinks: [EpisodeEventLink] = []
    private var eventRowIDs: [Int64] = []
    private var sourceEventIDs: [String] = []
    private var sourceEventIDSet: Set<String> = []

    init(firstEvent: EventRow) {
        camera = firstEvent.camera
        cameraID = firstEvent.cameraID
        startTime = firstEvent.timeStart
        endTime = firstEvent.timeEnd ?? firstEvent.timeStart
        include(firstEvent)
    }

    func canInclude(_ event: EventRow, quietGapSeconds: Int) -> Bool {
        guard event.camera == camera else {
            return false
        }
        return event.timeStart.timeIntervalSince(endTime) <= Double(quietGapSeconds)
    }

    func include(_ event: EventRow) {
        startTime = min(startTime, event.timeStart)
        endTime = max(endTime, event.timeEnd ?? event.timeStart)
        if cameraID == nil {
            cameraID = event.cameraID
        }
        eventCount += 1
        containsUnsettled = containsUnsettled || event.timeEnd == nil
        kindCounts[event.kind, default: 0] += 1
        firstSeenByKind[event.kind] = min(firstSeenByKind[event.kind] ?? event.timeStart, event.timeStart)
        if let rowID = event.id {
            eventLinks.append(EpisodeEventLink(eventRowID: rowID, sourceEventID: event.eventID))
            eventRowIDs.append(rowID)
        }
        if sourceEventIDSet.insert(event.eventID).inserted {
            sourceEventIDs.append(event.eventID)
        }
    }

    func makeSeed(calendar: Calendar) -> ModeledEpisodeSeed {
        let sortedKinds = kindCounts.keys.sorted { lhs, rhs in
            let leftCount = kindCounts[lhs] ?? 0
            let rightCount = kindCounts[rhs] ?? 0
            if leftCount != rightCount {
                return leftCount > rightCount
            }
            let leftSeen = firstSeenByKind[lhs] ?? startTime
            let rightSeen = firstSeenByKind[rhs] ?? startTime
            if leftSeen != rightSeen {
                return leftSeen < rightSeen
            }
            return lhs < rhs
        }
        let primaryKind = sortedKinds.first ?? "unknown"
        let kinds = sortedKinds.map { kind in
            ModelEpisodeKind(
                kind: kind,
                occurrenceCount: kindCounts[kind] ?? 0,
                isPrimary: kind == primaryKind
            )
        }
        let hourOfDay = calendar.component(.hour, from: startTime)
        let weekday = calendar.component(.weekday, from: startTime)
        let dayClass: ModelDayClass = (weekday == 1 || weekday == 7) ? .weekend : .weekday

        return ModeledEpisodeSeed(
            camera: camera,
            cameraID: cameraID,
            primaryKind: primaryKind,
            stateKey: "\(camera):\(primaryKind)",
            startTime: startTime,
            endTime: endTime,
            durationSeconds: max(0, Int(endTime.timeIntervalSince(startTime))),
            eventCount: eventCount,
            sourceEventCount: sourceEventIDs.count,
            containsUnsettled: containsUnsettled,
            hourOfDay: hourOfDay,
            dayClass: dayClass,
            kinds: kinds,
            eventLinks: eventLinks,
            eventRowIDs: eventRowIDs,
            sourceEventIDs: sourceEventIDs
        )
    }
}

private func orderedUnique<T: Hashable>(_ values: [T]) -> [T] {
    var seen = Set<T>()
    var ordered: [T] = []
    for value in values where seen.insert(value).inserted {
        ordered.append(value)
    }
    return ordered
}

public enum ProtectCadenceModelRunner {
    public static func run(arguments: [String], now: Date = Date()) throws -> ModelCommandOutput {
        try run(cli: ModelCLI(arguments: arguments), now: now)
    }

    public static func run(cli: ModelCLI, now: Date = Date()) throws -> ModelCommandOutput {
        let sourceDatabasePath = try ProtectCadenceDatabasePathResolver.resolve(
            explicitOverride: cli.sourceDatabasePathOverride,
            configPath: cli.configPath
        )
        let modelDatabasePath = try ProtectCadenceModelDatabasePathResolver.resolve(
            explicitModelOverride: cli.modelDatabasePathOverride,
            sourceDatabaseOverride: cli.sourceDatabasePathOverride,
            configPath: cli.configPath
        )

        switch cli.subcommand {
        case .rebuild:
            let rebuildStartedAt = Date()
            let sourceDatabase = try ProtectCadenceDatabase(path: sourceDatabasePath)
            let events = try sourceDatabase.fetchAllEvents(order: .oldest)
            let build = ProtectCadenceModeler.build(
                from: events,
                sourceDatabasePath: sourceDatabasePath,
                builtAt: now
            )
            let modelDatabase = try ProtectCadenceModelDatabase(path: modelDatabasePath)
            let metadata = try modelDatabase.replace(with: build)
            let counts = try modelDatabase.latestCounts()
            let rebuildDurationSeconds = Date().timeIntervalSince(rebuildStartedAt)
            return .rebuild(
                ModelRebuildResponse(
                    command: ProtectCadenceCommand.model.rawValue,
                    action: ModelSubcommand.rebuild.rawValue,
                    sourceDatabasePath: sourceDatabasePath,
                    modelDatabasePath: modelDatabasePath,
                    build: metadata,
                    episodeCount: counts.episodeCount,
                    stateBucketStatCount: counts.stateBucketStatCount,
                    stateTransitionStatCount: counts.stateTransitionStatCount,
                    findingCount: counts.findingCount,
                    rebuildDurationSeconds: rebuildDurationSeconds,
                    status: "ok"
                )
            )
        case .episodes:
            let modelDatabase = try ProtectCadenceModelDatabase(path: modelDatabasePath)
            let metadata = try modelDatabase.latestBuildMetadata()
            return .episodes(
                ModelEpisodesResponse(
                    command: ProtectCadenceCommand.model.rawValue,
                    action: ModelSubcommand.episodes.rawValue,
                    sourceDatabasePath: metadata.sourceDatabasePath,
                    modelDatabasePath: modelDatabasePath,
                    build: metadata,
                    window: try cli.resolvedWindow(now: now),
                    cameras: cli.cameras,
                    kinds: cli.kinds,
                    stateKeys: cli.stateKeys,
                    limit: cli.limit,
                    order: cli.order,
                    episodes: try modelDatabase.fetchEpisodes(try cli.episodesRequest(now: now))
                )
            )
        case .findings:
            let modelDatabase = try ProtectCadenceModelDatabase(path: modelDatabasePath)
            let metadata = try modelDatabase.latestBuildMetadata()
            return .findings(
                ModelFindingsResponse(
                    command: ProtectCadenceCommand.model.rawValue,
                    action: ModelSubcommand.findings.rawValue,
                    sourceDatabasePath: metadata.sourceDatabasePath,
                    modelDatabasePath: modelDatabasePath,
                    build: metadata,
                    window: try cli.resolvedWindow(now: now),
                    cameras: cli.cameras,
                    kinds: cli.kinds,
                    findingTypes: cli.findingTypes,
                    limit: cli.limit,
                    findings: try modelDatabase.fetchFindings(try cli.findingsRequest(now: now))
                )
            )
        }
    }
}
