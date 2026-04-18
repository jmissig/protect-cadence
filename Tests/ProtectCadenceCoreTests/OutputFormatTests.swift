import Foundation
import Testing
@testable import ProtectCadenceCore

struct OutputFormatTests {
    @Test
    func queryEventsCommandParsesExplicitFormat() throws {
        let command = try ProtectCadenceCLIQueryEventsCommand.parse([
            "--format", "text",
            "--limit", "5",
        ])

        #expect(command.outputOptions.format == .text)
        #expect(try command.outputOptions.resolvedFormat() == .text)
    }

    @Test
    func validateCommandParsesJSONShortcut() throws {
        let command = try ProtectCadenceCLIValidateCommand.parse([
            "--json",
        ])

        #expect(command.outputOptions.json)
        #expect(try command.outputOptions.resolvedFormat() == .json)
    }

    @Test
    func outputOptionsRejectConflictingTextAndJSONFlags() throws {
        let command = try ProtectCadenceCLIAuthCommand.parse([
            "status",
            "--format", "text",
            "--json",
        ])

        #expect(throws: ProtectCadenceOutputOptionsError.self) {
            _ = try command.outputOptions.resolvedFormat()
        }
    }

    @Test
    func autoFormatUsesTTYToChooseHumanStyle() {
        #expect(ProtectCadenceOutputRenderer.effectiveFormat(requestedFormat: .auto, stdoutIsTTY: true) == .richText)
        #expect(ProtectCadenceOutputRenderer.effectiveFormat(requestedFormat: .auto, stdoutIsTTY: false) == .plainText)
        #expect(ProtectCadenceOutputRenderer.effectiveFormat(requestedFormat: .json, stdoutIsTTY: true) == .json)
    }

    @Test
    func queryEventsHumanOutputShowsCompactEvidenceRows() throws {
        let output = ProtectCadenceCLIOutput.query(.events(
            EventsResponse(
                command: ProtectCadenceCommand.query.rawValue,
                databasePath: "/tmp/protect-cadence.sqlite",
                filters: QueryFilters(
                    window: QueryWindow(
                        start: Date(timeIntervalSince1970: 100),
                        end: Date(timeIntervalSince1970: 200)
                    ),
                    cameras: ["Garage"],
                    kinds: ["vehicle"]
                ),
                events: [
                    EventRow(
                        timeStart: Date(timeIntervalSince1970: 110),
                        timeEnd: Date(timeIntervalSince1970: 140),
                        cameraID: "camera-1",
                        camera: "Garage",
                        eventType: "smartDetectLine",
                        kind: "vehicle",
                        eventID: "event-1"
                    ),
                ]
            )
        ))

        let text = try ProtectCadenceOutputRenderer.render(
            output: output,
            format: .text,
            stdoutIsTTY: false
        )

        #expect(text.contains("Events: 1"))
        #expect(text.contains("Garage"))
        #expect(text.contains("vehicle"))
        #expect(text.contains("smartDetectLine"))
        #expect(!text.contains("cameraID"))
    }

    @Test
    func querySummaryRichOutputUsesTableLayout() throws {
        let output = ProtectCadenceCLIOutput.query(.summary(
            SummaryResponse(
                command: ProtectCadenceCommand.query.rawValue,
                databasePath: "/tmp/protect-cadence.sqlite",
                filters: QueryFilters(
                    window: QueryWindow(
                        start: Date(timeIntervalSince1970: 1_000),
                        end: Date(timeIntervalSince1970: 2_000)
                    )
                ),
                totalEventCount: 4,
                totalSourceEventCount: 3,
                groupBy: [.camera, .kind],
                groups: [
                    SummaryGroup(
                        group: ["camera": "Driveway", "kind": "person"],
                        eventCount: 4,
                        sourceEventCount: 3,
                        drillDown: QueryDrillDownDescriptor(filters: QueryFilters(cameras: ["Driveway"], kinds: ["person"]))
                    ),
                ]
            )
        ))

        let text = try ProtectCadenceOutputRenderer.render(
            output: output,
            format: .text,
            stdoutIsTTY: true
        )

        #expect(text.contains("Summary"))
        #expect(text.contains("Total events: 4"))
        #expect(text.contains("Driveway"))
        #expect(text.contains("┌"))
        #expect(text.contains("Camera"))
    }

    @Test
    func queryCompareHumanOutputKeepsTotalsAndDeltasVisible() throws {
        let output = ProtectCadenceCLIOutput.query(.compare(
            CompareResponse(
                command: ProtectCadenceCommand.query.rawValue,
                databasePath: "/tmp/protect-cadence.sqlite",
                filters: QueryFilters(
                    window: QueryWindow(
                        start: Date(timeIntervalSince1970: 3_000),
                        end: Date(timeIntervalSince1970: 3_600)
                    ),
                    cameras: ["Porch"]
                ),
                comparisonWindow: QueryWindow(
                    start: Date(timeIntervalSince1970: 2_000),
                    end: Date(timeIntervalSince1970: 2_600)
                ),
                groupBy: [.camera, .kind],
                totals: CompareCounts(eventCount: 5, sourceEventCount: 4),
                comparisonTotals: CompareCounts(eventCount: 2, sourceEventCount: 2),
                totalEventCountDelta: 3,
                totalSourceEventCountDelta: 2,
                groups: [
                    CompareGroup(
                        group: ["camera": "Porch", "kind": "package"],
                        window: CompareCounts(eventCount: 5, sourceEventCount: 4),
                        comparisonWindow: CompareCounts(eventCount: 2, sourceEventCount: 2),
                        eventCountDelta: 3,
                        sourceEventCountDelta: 2,
                        windowDrillDown: QueryDrillDownDescriptor(filters: QueryFilters(cameras: ["Porch"], kinds: ["package"])),
                        comparisonWindowDrillDown: QueryDrillDownDescriptor(filters: QueryFilters(cameras: ["Porch"], kinds: ["package"]))
                    ),
                ]
            )
        ))

        let text = try ProtectCadenceOutputRenderer.render(
            output: output,
            format: .text,
            stdoutIsTTY: false
        )

        #expect(text.contains("Primary totals: 5 events / 4 source"))
        #expect(text.contains("Comparison totals: 2 events / 2 source"))
        #expect(text.contains("Delta: +3 events / +2 source"))
        #expect(text.contains("package"))
    }

    @Test
    func modelFindingsHumanOutputPrefersSummaryColumns() throws {
        let output = ProtectCadenceCLIOutput.model(.findings(
            ModelFindingsResponse(
                command: ProtectCadenceCommand.model.rawValue,
                action: ModelSubcommand.findings.rawValue,
                sourceDatabasePath: "/tmp/protect-cadence.sqlite",
                modelDatabasePath: "/tmp/protect-cadence-model.sqlite",
                build: ModelBuildMetadata(
                    runID: 1,
                    builtAt: Date(timeIntervalSince1970: 5_000),
                    sourceDatabasePath: "/tmp/protect-cadence.sqlite",
                    sourceEventCount: 10,
                    sourceWindow: nil,
                    parameters: ModelBuildParameters(
                        quietGapSeconds: 120,
                        modelVersion: "test",
                        unexpectedPresenceMinimumStateCount: 2,
                        unexpectedTransitionMinimumPairCount: 2,
                        unusualDurationMinimumBucketCount: 2,
                        unusualDurationRatioThreshold: 2.0,
                        unusualDurationMinimumDeltaSeconds: 30
                    )
                ),
                window: QueryWindow(
                    start: Date(timeIntervalSince1970: 4_000),
                    end: Date(timeIntervalSince1970: 5_000)
                ),
                cameras: ["Driveway"],
                kinds: ["person"],
                findingTypes: [.unexpectedPresence],
                limit: 50,
                findings: [
                    ModelFinding(
                        id: 1,
                        findingType: .unexpectedPresence,
                        camera: "Driveway",
                        primaryKind: "person",
                        stateKey: "Driveway:person",
                        episodeID: 10,
                        episodeStartTime: Date(timeIntervalSince1970: 4_500),
                        episodeEndTime: Date(timeIntervalSince1970: 4_560),
                        hourOfDay: 7,
                        dayClass: .weekday,
                        score: 1.5,
                        bucketEpisodeCount: 1,
                        stateEpisodeCount: 3,
                        observedDurationSeconds: nil,
                        expectedDurationSeconds: nil,
                        durationDirection: nil,
                        previousEpisodeID: nil,
                        previousPrimaryKind: nil,
                        previousStateKey: nil,
                        transitionBucketCount: nil,
                        transitionPairCount: nil,
                        observedGapSeconds: nil,
                        expectedGapSeconds: nil,
                        linkedEpisodeIDs: [10]
                    ),
                ]
            )
        ))

        let text = try ProtectCadenceOutputRenderer.render(
            output: output,
            format: .text,
            stdoutIsTTY: false
        )

        #expect(text.contains("Model findings: 1"))
        #expect(text.contains("unexpected_presence"))
        #expect(text.contains("Driveway"))
        #expect(text.contains("bucket 1, state 3"))
        #expect(!text.contains("linkedEpisodeIDs"))
    }

    @Test
    func validateHumanOutputSummarizesRulesAndExamples() throws {
        let output = ProtectCadenceCLIOutput.validate(
            ProtectControllerValidationResponse(
                command: ProtectCadenceCommand.validate.rawValue,
                window: QueryWindow(
                    start: Date(timeIntervalSince1970: 6_000),
                    end: Date(timeIntervalSince1970: 7_000)
                ),
                fetchedSourceEventCount: 6,
                cameraLookupCount: 2,
                sampleLimit: 3,
                recentEvents: [
                    ProtectControllerValidationEventSample(
                        sourceEventID: "event-1",
                        sourceEventIDField: "eventId",
                        camera: "Front",
                        cameraID: "camera-1",
                        type: "smartDetectZone",
                        start: Date(timeIntervalSince1970: 6_100),
                        detectedAt: Date(timeIntervalSince1970: 6_101),
                        selectedTimeStart: Date(timeIntervalSince1970: 6_101),
                        timeStartSource: "detectedAt",
                        timeStartDeltaSeconds: 1,
                        end: Date(timeIntervalSince1970: 6_130),
                        isSettled: true,
                        normalizedKinds: ["person"],
                        normalizesForIngest: true
                    ),
                ],
                timeStartRule: ProtectControllerValidationTimeStartSummary(
                    rule: "timeStart = detectedAt ?? start",
                    fetched: ProtectControllerValidationCounts(
                        eventCount: 6,
                        detectedAtChosenCount: 5,
                        startFallbackCount: 1,
                        missingTimeStartCount: 0,
                        detectedAtDiffersFromStartCount: 4
                    ),
                    settled: ProtectControllerValidationCounts(
                        eventCount: 5,
                        detectedAtChosenCount: 4,
                        startFallbackCount: 1,
                        missingTimeStartCount: 0,
                        detectedAtDiffersFromStartCount: 3
                    ),
                    differingExamples: []
                ),
                settledEventFiltering: ProtectControllerValidationSettledSummary(
                    rule: "settled = end != nil",
                    settledCount: 5,
                    unsettledCount: 1,
                    settledExamples: [],
                    unsettledExamples: []
                ),
                dedupeKey: ProtectControllerValidationDedupeSummary(
                    rule: "dedupe key = source event id + normalized kind",
                    analysisScope: "normalized settled events only",
                    normalizedSettledEventCount: 5,
                    ignoredSettledSourceEventCount: 0,
                    uniqueEventKindKeyCount: 5,
                    duplicateRowCount: 0,
                    eventIDCount: 4,
                    idFallbackCount: 1,
                    missingSourceEventIDCount: 0,
                    multiKindSettledSourceEventCount: 1,
                    duplicateKeys: [],
                    multiKindExamples: []
                ),
                snapshot: ProtectControllerValidationSnapshotResult(
                    directoryPath: "/tmp/protect-snapshot",
                    eventCount: 6,
                    cameraCount: 2
                ),
                status: "ok"
            )
        )

        let text = try ProtectCadenceOutputRenderer.render(
            output: output,
            format: .text,
            stdoutIsTTY: false
        )

        #expect(text.contains("Validate: ok"))
        #expect(text.contains("Time start rule: timeStart = detectedAt ?? start"))
        #expect(text.contains("Settled filter: settled = end != nil"))
        #expect(text.contains("Recent events"))
        #expect(text.contains("/tmp/protect-snapshot"))
    }

    @Test
    func explicitJSONRenderingStillUsesStructuredResponseShape() throws {
        let output = ProtectCadenceCLIOutput.query(.summary(
            SummaryResponse(
                command: ProtectCadenceCommand.query.rawValue,
                databasePath: "/tmp/protect-cadence.sqlite",
                filters: QueryFilters(),
                totalEventCount: 1,
                totalSourceEventCount: 1,
                groupBy: [.camera, .kind],
                groups: [
                    SummaryGroup(
                        group: ["camera": "Porch", "kind": "package"],
                        eventCount: 1,
                        sourceEventCount: 1,
                        drillDown: QueryDrillDownDescriptor(filters: QueryFilters(cameras: ["Porch"], kinds: ["package"]))
                    ),
                ]
            )
        ))

        let json = try ProtectCadenceOutputRenderer.render(
            output: output,
            format: .json,
            stdoutIsTTY: true
        )

        #expect(json.contains("\"drillDown\""))
        #expect(json.contains("\"totalSourceEventCount\""))
        #expect(json.contains("\"eventCount\""))
    }
}
