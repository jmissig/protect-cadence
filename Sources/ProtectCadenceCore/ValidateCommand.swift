import Foundation

public enum ValidateCLIError: Error, CustomStringConvertible {
    case missingValue(String)
    case invalidInteger(flag: String, value: String)
    case invalidPositiveInteger(flag: String, value: String)
    case unexpectedArgument(String)

    public var description: String {
        switch self {
        case let .missingValue(flag):
            return "missing value for \(flag)"
        case let .invalidInteger(flag, value):
            return "invalid integer '\(value)' for \(flag)"
        case let .invalidPositiveInteger(flag, value):
            return "\(flag) must be greater than zero, got '\(value)'"
        case let .unexpectedArgument(argument):
            return "unexpected argument '\(argument)'"
        }
    }
}

public struct ValidateCLI: Sendable {
    public let lastHours: Int
    public let sampleLimit: Int
    public let snapshotDirectoryPath: String?
    public let controllerURL: String?
    public let username: String?
    public let password: String?
    public let allowInsecureTLS: Bool?
    public let configPath: String

    public init(arguments: [String]) throws {
        var remaining = arguments
        var lastHours = 6
        var sampleLimit = 10
        var snapshotDirectoryPath: String?
        var controllerURL: String?
        var username: String?
        var password: String?
        var allowInsecureTLS: Bool?
        var configPath = ProtectCadencePaths.defaultConfigPath()

        func popValue(for flag: String) throws -> String {
            guard let index = remaining.firstIndex(of: flag) else {
                throw ValidateCLIError.missingValue(flag)
            }
            guard remaining.indices.contains(index + 1) else {
                throw ValidateCLIError.missingValue(flag)
            }

            let value = remaining[index + 1]
            remaining.removeSubrange(index...(index + 1))
            return value
        }

        func popPositiveInteger(for flag: String) throws -> Int? {
            guard remaining.contains(flag) else {
                return nil
            }

            let rawValue = try popValue(for: flag)
            guard let parsed = Int(rawValue) else {
                throw ValidateCLIError.invalidInteger(flag: flag, value: rawValue)
            }
            guard parsed > 0 else {
                throw ValidateCLIError.invalidPositiveInteger(flag: flag, value: rawValue)
            }
            return parsed
        }

        if let parsedLastHours = try popPositiveInteger(for: "--last-hours") {
            lastHours = parsedLastHours
        }

        if let parsedSampleLimit = try popPositiveInteger(for: "--sample-limit") {
            sampleLimit = parsedSampleLimit
        }

        if remaining.contains("--write-api-snapshot-dir") {
            snapshotDirectoryPath = try popValue(for: "--write-api-snapshot-dir")
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

        if let unexpected = remaining.first {
            throw ValidateCLIError.unexpectedArgument(unexpected)
        }

        self.lastHours = lastHours
        self.sampleLimit = sampleLimit
        self.snapshotDirectoryPath = snapshotDirectoryPath
        self.controllerURL = controllerURL
        self.username = username
        self.password = password
        self.allowInsecureTLS = allowInsecureTLS
        self.configPath = configPath
    }

    public func queryWindow(now: Date = Date()) -> QueryWindow {
        let start = now.addingTimeInterval(-Double(lastHours) * 60 * 60)
        return QueryWindow(start: start, end: now)
    }
}

public struct ProtectControllerValidationCounts: Codable, Sendable, Equatable {
    public let eventCount: Int
    public let detectedAtChosenCount: Int
    public let startFallbackCount: Int
    public let missingTimeStartCount: Int
    public let detectedAtDiffersFromStartCount: Int

    public init(
        eventCount: Int,
        detectedAtChosenCount: Int,
        startFallbackCount: Int,
        missingTimeStartCount: Int,
        detectedAtDiffersFromStartCount: Int
    ) {
        self.eventCount = eventCount
        self.detectedAtChosenCount = detectedAtChosenCount
        self.startFallbackCount = startFallbackCount
        self.missingTimeStartCount = missingTimeStartCount
        self.detectedAtDiffersFromStartCount = detectedAtDiffersFromStartCount
    }
}

public struct ProtectControllerValidationEventSample: Codable, Sendable, Equatable {
    public let sourceEventID: String?
    public let sourceEventIDField: String?
    public let camera: String?
    public let cameraID: String?
    public let type: String?
    public let start: Date?
    public let detectedAt: Date?
    public let selectedTimeStart: Date?
    public let timeStartSource: String?
    public let timeStartDeltaSeconds: Double?
    public let end: Date?
    public let isSettled: Bool
    public let normalizedKinds: [String]
    public let normalizesForIngest: Bool

    public init(
        sourceEventID: String?,
        sourceEventIDField: String?,
        camera: String?,
        cameraID: String?,
        type: String?,
        start: Date?,
        detectedAt: Date?,
        selectedTimeStart: Date?,
        timeStartSource: String?,
        timeStartDeltaSeconds: Double?,
        end: Date?,
        isSettled: Bool,
        normalizedKinds: [String],
        normalizesForIngest: Bool
    ) {
        self.sourceEventID = sourceEventID
        self.sourceEventIDField = sourceEventIDField
        self.camera = camera
        self.cameraID = cameraID
        self.type = type
        self.start = start
        self.detectedAt = detectedAt
        self.selectedTimeStart = selectedTimeStart
        self.timeStartSource = timeStartSource
        self.timeStartDeltaSeconds = timeStartDeltaSeconds
        self.end = end
        self.isSettled = isSettled
        self.normalizedKinds = normalizedKinds
        self.normalizesForIngest = normalizesForIngest
    }
}

public struct ProtectControllerValidationTimeStartSummary: Codable, Sendable, Equatable {
    public let rule: String
    public let fetched: ProtectControllerValidationCounts
    public let settled: ProtectControllerValidationCounts
    public let differingExamples: [ProtectControllerValidationEventSample]

    public init(
        rule: String,
        fetched: ProtectControllerValidationCounts,
        settled: ProtectControllerValidationCounts,
        differingExamples: [ProtectControllerValidationEventSample]
    ) {
        self.rule = rule
        self.fetched = fetched
        self.settled = settled
        self.differingExamples = differingExamples
    }
}

public struct ProtectControllerValidationSettledSummary: Codable, Sendable, Equatable {
    public let rule: String
    public let settledCount: Int
    public let unsettledCount: Int
    public let settledExamples: [ProtectControllerValidationEventSample]
    public let unsettledExamples: [ProtectControllerValidationEventSample]

    public init(
        rule: String,
        settledCount: Int,
        unsettledCount: Int,
        settledExamples: [ProtectControllerValidationEventSample],
        unsettledExamples: [ProtectControllerValidationEventSample]
    ) {
        self.rule = rule
        self.settledCount = settledCount
        self.unsettledCount = unsettledCount
        self.settledExamples = settledExamples
        self.unsettledExamples = unsettledExamples
    }
}

public struct ProtectControllerValidationDedupeCollision: Codable, Sendable, Equatable {
    public let sourceEventID: String
    public let kind: String
    public let occurrenceCount: Int
    public let eventTypes: [String]
    public let cameras: [String]

    public init(
        sourceEventID: String,
        kind: String,
        occurrenceCount: Int,
        eventTypes: [String],
        cameras: [String]
    ) {
        self.sourceEventID = sourceEventID
        self.kind = kind
        self.occurrenceCount = occurrenceCount
        self.eventTypes = eventTypes
        self.cameras = cameras
    }
}

public struct ProtectControllerValidationMultiKindExample: Codable, Sendable, Equatable {
    public let sourceEventID: String
    public let kinds: [String]
    public let type: String?
    public let camera: String?

    public init(sourceEventID: String, kinds: [String], type: String?, camera: String?) {
        self.sourceEventID = sourceEventID
        self.kinds = kinds
        self.type = type
        self.camera = camera
    }
}

public struct ProtectControllerValidationDedupeSummary: Codable, Sendable, Equatable {
    public let rule: String
    public let analysisScope: String
    public let normalizedSettledEventCount: Int
    public let ignoredSettledSourceEventCount: Int
    public let uniqueEventKindKeyCount: Int
    public let duplicateRowCount: Int
    public let eventIDCount: Int
    public let idFallbackCount: Int
    public let missingSourceEventIDCount: Int
    public let multiKindSettledSourceEventCount: Int
    public let duplicateKeys: [ProtectControllerValidationDedupeCollision]
    public let multiKindExamples: [ProtectControllerValidationMultiKindExample]

    public init(
        rule: String,
        analysisScope: String,
        normalizedSettledEventCount: Int,
        ignoredSettledSourceEventCount: Int,
        uniqueEventKindKeyCount: Int,
        duplicateRowCount: Int,
        eventIDCount: Int,
        idFallbackCount: Int,
        missingSourceEventIDCount: Int,
        multiKindSettledSourceEventCount: Int,
        duplicateKeys: [ProtectControllerValidationDedupeCollision],
        multiKindExamples: [ProtectControllerValidationMultiKindExample]
    ) {
        self.rule = rule
        self.analysisScope = analysisScope
        self.normalizedSettledEventCount = normalizedSettledEventCount
        self.ignoredSettledSourceEventCount = ignoredSettledSourceEventCount
        self.uniqueEventKindKeyCount = uniqueEventKindKeyCount
        self.duplicateRowCount = duplicateRowCount
        self.eventIDCount = eventIDCount
        self.idFallbackCount = idFallbackCount
        self.missingSourceEventIDCount = missingSourceEventIDCount
        self.multiKindSettledSourceEventCount = multiKindSettledSourceEventCount
        self.duplicateKeys = duplicateKeys
        self.multiKindExamples = multiKindExamples
    }
}

public struct ProtectControllerValidationSnapshotResult: Codable, Sendable, Equatable {
    public let directoryPath: String
    public let eventCount: Int
    public let cameraCount: Int

    public init(directoryPath: String, eventCount: Int, cameraCount: Int) {
        self.directoryPath = directoryPath
        self.eventCount = eventCount
        self.cameraCount = cameraCount
    }
}

public struct ProtectControllerValidationResponse: Codable, Sendable, Equatable {
    public let command: String
    public let window: QueryWindow
    public let fetchedSourceEventCount: Int
    public let cameraLookupCount: Int
    public let sampleLimit: Int
    public let recentEvents: [ProtectControllerValidationEventSample]
    public let timeStartRule: ProtectControllerValidationTimeStartSummary
    public let settledEventFiltering: ProtectControllerValidationSettledSummary
    public let dedupeKey: ProtectControllerValidationDedupeSummary
    public let snapshot: ProtectControllerValidationSnapshotResult?
    public let status: String

    public init(
        command: String,
        window: QueryWindow,
        fetchedSourceEventCount: Int,
        cameraLookupCount: Int,
        sampleLimit: Int,
        recentEvents: [ProtectControllerValidationEventSample],
        timeStartRule: ProtectControllerValidationTimeStartSummary,
        settledEventFiltering: ProtectControllerValidationSettledSummary,
        dedupeKey: ProtectControllerValidationDedupeSummary,
        snapshot: ProtectControllerValidationSnapshotResult?,
        status: String
    ) {
        self.command = command
        self.window = window
        self.fetchedSourceEventCount = fetchedSourceEventCount
        self.cameraLookupCount = cameraLookupCount
        self.sampleLimit = sampleLimit
        self.recentEvents = recentEvents
        self.timeStartRule = timeStartRule
        self.settledEventFiltering = settledEventFiltering
        self.dedupeKey = dedupeKey
        self.snapshot = snapshot
        self.status = status
    }
}

public enum ProtectControllerValidationReportBuilder {
    public static func make(
        events: [ProtectEventPayload],
        cameras: [ProtectCameraRecord],
        window: QueryWindow,
        sampleLimit: Int
    ) -> ProtectControllerValidationResponse {
        let cameraNamesByID: [String: String] = Dictionary(
            uniqueKeysWithValues: cameras.compactMap { camera in
                guard let resolvedName = camera.resolvedName else {
                    return nil
                }
                return (camera.id, resolvedName)
            }
        )

        let settledEvents = events.filter(\.isSettled)
        let recentSamples = events.prefix(sampleLimit).map { sample(for: $0, cameraNamesByID: cameraNamesByID) }
        let differingExamples = events
            .filter { event in
                guard let detectedAt = event.detectedAt, let start = event.start else {
                    return false
                }
                return detectedAt != start
            }
            .prefix(sampleLimit)
            .map { sample(for: $0, cameraNamesByID: cameraNamesByID) }

        let settledExamples = settledEvents.prefix(sampleLimit).map { sample(for: $0, cameraNamesByID: cameraNamesByID) }
        let unsettledExamples = events.filter { !$0.isSettled }.prefix(sampleLimit).map { sample(for: $0, cameraNamesByID: cameraNamesByID) }

        let timeStartRule = ProtectControllerValidationTimeStartSummary(
            rule: "timeStart = detectedAt ?? start",
            fetched: counts(for: events),
            settled: counts(for: settledEvents),
            differingExamples: differingExamples
        )

        let settledSummary = ProtectControllerValidationSettledSummary(
            rule: "settled = end != nil",
            settledCount: settledEvents.count,
            unsettledCount: events.count - settledEvents.count,
            settledExamples: settledExamples,
            unsettledExamples: unsettledExamples
        )

        let dedupeSummary = makeDedupeSummary(
            settledEvents: settledEvents,
            cameraNamesByID: cameraNamesByID,
            sampleLimit: sampleLimit
        )

        return ProtectControllerValidationResponse(
            command: ProtectCadenceCommand.validate.rawValue,
            window: window,
            fetchedSourceEventCount: events.count,
            cameraLookupCount: cameras.count,
            sampleLimit: sampleLimit,
            recentEvents: recentSamples,
            timeStartRule: timeStartRule,
            settledEventFiltering: settledSummary,
            dedupeKey: dedupeSummary,
            snapshot: nil,
            status: "ok"
        )
    }

    private static func counts(for events: [ProtectEventPayload]) -> ProtectControllerValidationCounts {
        var detectedAtChosenCount = 0
        var startFallbackCount = 0
        var missingTimeStartCount = 0
        var detectedAtDiffersFromStartCount = 0

        for event in events {
            if let detectedAt = event.detectedAt {
                detectedAtChosenCount += 1
                if let start = event.start, detectedAt != start {
                    detectedAtDiffersFromStartCount += 1
                }
            } else if event.start != nil {
                startFallbackCount += 1
            } else {
                missingTimeStartCount += 1
            }
        }

        return ProtectControllerValidationCounts(
            eventCount: events.count,
            detectedAtChosenCount: detectedAtChosenCount,
            startFallbackCount: startFallbackCount,
            missingTimeStartCount: missingTimeStartCount,
            detectedAtDiffersFromStartCount: detectedAtDiffersFromStartCount
        )
    }

    private static func makeDedupeSummary(
        settledEvents: [ProtectEventPayload],
        cameraNamesByID: [String: String],
        sampleLimit: Int
    ) -> ProtectControllerValidationDedupeSummary {
        struct Key: Hashable {
            let sourceEventID: String
            let kind: String
        }

        struct CollisionAccumulator {
            var occurrenceCount: Int = 0
            var eventTypes = Set<String>()
            var cameras = Set<String>()
        }

        var normalizedRowCount = 0
        var ignoredSettledSourceEventCount = 0
        var eventIDCount = 0
        var idFallbackCount = 0
        var missingSourceEventIDCount = 0
        var duplicateAccumulators: [Key: CollisionAccumulator] = [:]
        var multiKindExamples: [ProtectControllerValidationMultiKindExample] = []
        var multiKindSettledSourceEventCount = 0

        for event in settledEvents {
            if event.eventID != nil {
                eventIDCount += 1
            } else if event.id != nil {
                idFallbackCount += 1
            } else {
                missingSourceEventIDCount += 1
            }

            let sample = sample(for: event, cameraNamesByID: cameraNamesByID)

            guard let sourceEventID = sample.sourceEventID else {
                ignoredSettledSourceEventCount += 1
                continue
            }

            let normalizedKinds = sample.normalizedKinds
            if normalizedKinds.isEmpty || !sample.normalizesForIngest {
                ignoredSettledSourceEventCount += 1
                continue
            }

            if normalizedKinds.count > 1 {
                multiKindSettledSourceEventCount += 1
                if multiKindExamples.count < sampleLimit {
                    multiKindExamples.append(
                        ProtectControllerValidationMultiKindExample(
                            sourceEventID: sourceEventID,
                            kinds: normalizedKinds,
                            type: sample.type,
                            camera: sample.camera
                        )
                    )
                }
            }

            for kind in normalizedKinds {
                normalizedRowCount += 1
                let key = Key(sourceEventID: sourceEventID, kind: kind)
                var accumulator = duplicateAccumulators[key] ?? CollisionAccumulator()
                accumulator.occurrenceCount += 1
                if let type = sample.type {
                    accumulator.eventTypes.insert(type)
                }
                if let camera = sample.camera {
                    accumulator.cameras.insert(camera)
                }
                duplicateAccumulators[key] = accumulator
            }
        }

        let duplicateKeys = duplicateAccumulators
            .filter { $0.value.occurrenceCount > 1 }
            .sorted { lhs, rhs in
                if lhs.value.occurrenceCount == rhs.value.occurrenceCount {
                    if lhs.key.sourceEventID == rhs.key.sourceEventID {
                        return lhs.key.kind < rhs.key.kind
                    }
                    return lhs.key.sourceEventID < rhs.key.sourceEventID
                }
                return lhs.value.occurrenceCount > rhs.value.occurrenceCount
            }
            .prefix(sampleLimit)
            .map { key, accumulator in
                ProtectControllerValidationDedupeCollision(
                    sourceEventID: key.sourceEventID,
                    kind: key.kind,
                    occurrenceCount: accumulator.occurrenceCount,
                    eventTypes: accumulator.eventTypes.sorted(),
                    cameras: accumulator.cameras.sorted()
                )
            }

        let uniqueKeyCount = duplicateAccumulators.count

        return ProtectControllerValidationDedupeSummary(
            rule: "dedupe key = source event id + normalized kind",
            analysisScope: "normalized settled events only, matching current ingest",
            normalizedSettledEventCount: normalizedRowCount,
            ignoredSettledSourceEventCount: ignoredSettledSourceEventCount,
            uniqueEventKindKeyCount: uniqueKeyCount,
            duplicateRowCount: normalizedRowCount - uniqueKeyCount,
            eventIDCount: eventIDCount,
            idFallbackCount: idFallbackCount,
            missingSourceEventIDCount: missingSourceEventIDCount,
            multiKindSettledSourceEventCount: multiKindSettledSourceEventCount,
            duplicateKeys: duplicateKeys,
            multiKindExamples: multiKindExamples
        )
    }

    private static func sample(
        for event: ProtectEventPayload,
        cameraNamesByID: [String: String]
    ) -> ProtectControllerValidationEventSample {
        let sourceEventID = event.eventID ?? event.id
        let sourceEventIDField: String?
        if event.eventID != nil {
            sourceEventIDField = "eventId"
        } else if event.id != nil {
            sourceEventIDField = "id"
        } else {
            sourceEventIDField = nil
        }

        let cameraID = event.cameraLookupKey
        let camera = event.currentCameraName ?? cameraID.flatMap { cameraNamesByID[$0] }
        let selectedTimeStart = event.detectedAt ?? event.start
        let timeStartSource: String?
        if event.detectedAt != nil {
            timeStartSource = "detectedAt"
        } else if event.start != nil {
            timeStartSource = "start"
        } else {
            timeStartSource = nil
        }
        let timeStartDeltaSeconds = timeDeltaSeconds(start: event.start, detectedAt: event.detectedAt)
        let normalizedKinds = ProtectEventNormalizer.normalizedKinds(from: event)
        let normalizesForIngest: Bool
        do {
            normalizesForIngest = try !ProtectEventNormalizer.normalize(
                event,
                fallbackCameraNamesByID: cameraNamesByID
            ).isEmpty
        } catch {
            normalizesForIngest = false
        }

        return ProtectControllerValidationEventSample(
            sourceEventID: sourceEventID,
            sourceEventIDField: sourceEventIDField,
            camera: camera,
            cameraID: cameraID,
            type: event.type,
            start: event.start,
            detectedAt: event.detectedAt,
            selectedTimeStart: selectedTimeStart,
            timeStartSource: timeStartSource,
            timeStartDeltaSeconds: timeStartDeltaSeconds,
            end: event.end,
            isSettled: event.isSettled,
            normalizedKinds: normalizedKinds,
            normalizesForIngest: normalizesForIngest
        )
    }

    private static func timeDeltaSeconds(start: Date?, detectedAt: Date?) -> Double? {
        guard let start, let detectedAt else {
            return nil
        }
        return detectedAt.timeIntervalSince(start)
    }
}

public enum ProtectCadenceValidateRunner {
    public static func run(
        arguments: [String],
        now: Date = Date(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        clientFactory: @Sendable (ProtectControllerConfiguration) -> ProtectControllerClient = { configuration in
            ProtectControllerClient(configuration: configuration)
        }
    ) async throws -> ProtectControllerValidationResponse {
        let cli = try ValidateCLI(arguments: arguments)
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
        let window = cli.queryWindow(now: now)
        let client = clientFactory(configuration)
        let events = try await client.fetchRecentEvents(window: window)
        let cameras = try await client.fetchCameras()

        if let snapshotDirectoryPath = cli.snapshotDirectoryPath {
            try ProtectAPISnapshotWriter(directoryURL: URL(fileURLWithPath: snapshotDirectoryPath)).write(
                events: events,
                cameras: cameras
            )
        }

        let base = ProtectControllerValidationReportBuilder.make(
            events: events,
            cameras: cameras,
            window: window,
            sampleLimit: cli.sampleLimit
        )

        return ProtectControllerValidationResponse(
            command: base.command,
            window: base.window,
            fetchedSourceEventCount: base.fetchedSourceEventCount,
            cameraLookupCount: base.cameraLookupCount,
            sampleLimit: base.sampleLimit,
            recentEvents: base.recentEvents,
            timeStartRule: base.timeStartRule,
            settledEventFiltering: base.settledEventFiltering,
            dedupeKey: base.dedupeKey,
            snapshot: cli.snapshotDirectoryPath.map {
                ProtectControllerValidationSnapshotResult(
                    directoryPath: $0,
                    eventCount: events.count,
                    cameraCount: cameras.count
                )
            },
            status: base.status
        )
    }
}
