import Foundation
import GRDB
import Testing
@testable import ProtectCadence

@Suite("Annotations")
struct ProtectCadenceAnnotationTests {
    @Test
    func annotationsCommandWritesSidecarAndListsTargets() async throws {
        let evidencePath = temporaryDatabasePath()
        let annotationsPath = temporaryDatabasePath()
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let added = try await ProtectCadenceCLIRunner.run(
            arguments: [
                "annotations", "add",
                "--db", evidencePath,
                "--annotations-db", annotationsPath,
                "--account", "julian",
                "--target-kind", "camera",
                "--target-id", "name:Driveway",
                "--body", "Construction week made this camera noisy.",
                "--source", "human",
            ],
            now: now
        )

        switch added {
        case let .annotations(.add(response)):
            #expect(response.annotationsDatabasePath == annotationsPath)
            #expect(response.annotation.account == "julian")
            #expect(response.annotation.targetKind == "camera")
            #expect(response.annotation.targetID == "name:Driveway")
            #expect(response.annotation.body == "Construction week made this camera noisy.")
            #expect(response.annotation.createdAtISO8601 == "2023-11-14T22:13:20Z")
        case .ingest, .query, .model, .annotations, .auth, .validate:
            Issue.record("expected annotations add output")
        }

        let targets = try await ProtectCadenceCLIRunner.run(
            arguments: [
                "annotations", "targets",
                "--db", evidencePath,
                "--annotations-db", annotationsPath,
                "--account", "julian",
                "--kind", "camera",
            ]
        )

        switch targets {
        case let .annotations(.targets(response)):
            #expect(response.totalMatchingTargets == 1)
            #expect(response.targets.first?.kind == "camera")
            #expect(response.targets.first?.id == "name:Driveway")
            #expect(response.targets.first?.annotationCount == 1)
        case .ingest, .query, .model, .annotations, .auth, .validate:
            Issue.record("expected annotations targets output")
        }
    }

    @Test
    func queryEventsIncludesSidecarAnnotationsUnlessOptedOut() async throws {
        let evidencePath = temporaryDatabasePath()
        let annotationsPath = temporaryDatabasePath()
        let database = try ProtectCadenceDatabase(path: evidencePath)
        let now = Date(timeIntervalSince1970: 20_000)

        try insertRows(
            [
                EventRow(
                    timeStart: now.addingTimeInterval(-60),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "protect-event-1"
                ),
            ],
            into: database
        )

        _ = try await ProtectCadenceCLIRunner.run(
            arguments: [
                "annotations", "add",
                "--db", evidencePath,
                "--annotations-db", annotationsPath,
                "--target-kind", "event",
                "--target-id", "event_id:protect-event-1#kind:person",
                "--body", "Known delivery.",
            ],
            now: now
        )

        let annotated = try await ProtectCadenceCLIRunner.run(
            arguments: [
                "query", "events",
                "--db", evidencePath,
                "--annotations-db", annotationsPath,
                "--last-hours", "1",
            ],
            now: now
        )

        switch annotated {
        case let .query(.events(response)):
            #expect(response.events.count == 1)
            #expect(response.events[0].annotations?.first?.body == "Known delivery.")
        case .ingest, .query, .model, .annotations, .auth, .validate:
            Issue.record("expected query events output")
        }

        let optedOut = try await ProtectCadenceCLIRunner.run(
            arguments: [
                "query", "events",
                "--db", evidencePath,
                "--annotations-db", annotationsPath,
                "--last-hours", "1",
                "--no-annotations",
            ],
            now: now
        )

        switch optedOut {
        case let .query(.events(response)):
            #expect(response.events.count == 1)
            #expect(response.events[0].annotations == nil)
        case .ingest, .query, .model, .annotations, .auth, .validate:
            Issue.record("expected query events output")
        }
    }


    @Test
    func annotationsListKindsValidationAndAccountIsolation() throws {
        let evidencePath = temporaryDatabasePath()
        let annotationsPath = temporaryDatabasePath()
        let now = Date(timeIntervalSince1970: 1_700_000_100)

        let kinds = ProtectCadenceAnnotationsRunner.listKinds()
        switch kinds {
        case let .kinds(response):
            #expect(response.kinds == ["camera", "context", "episode", "event", "finding", "window", "zone"])
        case .targets, .add, .list:
            Issue.record("expected annotation kinds output")
        }

        let database = try ProtectCadenceAnnotationsDatabase(path: annotationsPath)
        _ = try database.add(
            account: "julian",
            targetKind: "camera",
            targetID: "name:Driveway",
            body: "Julian camera note.",
            now: now
        )
        _ = try database.add(
            account: "alice",
            targetKind: "camera",
            targetID: "name:Driveway",
            body: "Alice camera note.",
            now: now.addingTimeInterval(60)
        )

        let listed = try ProtectCadenceAnnotationsRunner.run(arguments: [
            "list",
            "--db", evidencePath,
            "--annotations-db", annotationsPath,
            "--account", "julian",
            "--target-kind", "camera",
            "--target-id", "name:Driveway",
        ])

        switch listed {
        case let .list(response):
            #expect(response.totalMatchingAnnotations == 1)
            #expect(response.returnedAnnotations == 1)
            #expect(response.annotations.map(\.body) == ["Julian camera note."])
        case .kinds, .targets, .add:
            Issue.record("expected annotation list output")
        }

        #expect(throws: AnnotationError.self) {
            _ = try database.add(
                account: "julian",
                targetKind: "invalid",
                targetID: "name:Driveway",
                body: "Should fail."
            )
        }
    }

    @Test
    func annotationsDefaultToSiblingSidecarAndKeepEvidenceDatabaseClean() async throws {
        let evidencePath = temporaryDatabasePath()
        _ = try ProtectCadenceDatabase(path: evidencePath)
        let expectedAnnotationsPath = try ProtectCadenceAnnotationsDatabasePathResolver.resolve(
            explicitOverride: nil,
            evidenceDatabasePath: evidencePath,
            configPath: ProtectCadencePaths.defaultConfigPath()
        )

        let output = try await ProtectCadenceCLIRunner.run(arguments: [
            "annotations", "add",
            "--db", evidencePath,
            "--target-kind", "context",
            "--target-id", "construction-week",
            "--body", "Temporary noisy period.",
        ])

        switch output {
        case let .annotations(.add(response)):
            #expect(response.annotationsDatabasePath == expectedAnnotationsPath)
            #expect(FileManager.default.fileExists(atPath: expectedAnnotationsPath))
        case .ingest, .query, .model, .annotations, .auth, .validate:
            Issue.record("expected annotations add output")
        }

        let evidenceQueue = try DatabaseQueue(path: evidencePath)
        let evidenceHasAnnotationsTable = try await evidenceQueue.read { db in
            try db.tableExists("annotations")
        }
        #expect(!evidenceHasAnnotationsTable)
    }


    @Test
    func queryWithoutExistingAnnotationsSidecarDoesNotCreateOne() throws {
        let evidencePath = temporaryDatabasePath()
        let database = try ProtectCadenceDatabase(path: evidencePath)
        try database.insert(
            EventRow(
                timeStart: Date(timeIntervalSince1970: 100),
                camera: "Driveway",
                kind: "person",
                eventID: "event-1"
            )
        )
        let annotationsPath = try ProtectCadenceAnnotationsDatabasePathResolver.resolve(
            explicitOverride: nil,
            evidenceDatabasePath: evidencePath,
            configPath: ProtectCadencePaths.defaultConfigPath()
        )
        #expect(!FileManager.default.fileExists(atPath: annotationsPath))

        let output = try ProtectCadenceQueryRunner.run(arguments: [
            "events",
            "--db", evidencePath,
            "--limit", "1",
        ])

        switch output {
        case let .events(response):
            #expect(response.events.count == 1)
            #expect(response.events[0].annotations == nil)
        case .summary, .compare:
            Issue.record("expected query events output")
        }
        #expect(!FileManager.default.fileExists(atPath: annotationsPath))
    }

    @Test
    func querySummaryAndCompareIncludeCameraAnnotations() throws {
        let evidencePath = temporaryDatabasePath()
        let annotationsPath = temporaryDatabasePath()
        let database = try ProtectCadenceDatabase(path: evidencePath)
        try insertRows(
            [
                EventRow(
                    timeStart: localDate(day: 27, hour: 8, minute: 5),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "primary-event"
                ),
                EventRow(
                    timeStart: localDate(day: 26, hour: 8, minute: 5),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "comparison-event"
                ),
            ],
            into: database
        )
        _ = try ProtectCadenceAnnotationsDatabase(path: annotationsPath).add(
            account: "default",
            targetKind: "camera",
            targetID: "name:Driveway",
            body: "Construction noise caveat."
        )

        let summary = try ProtectCadenceQueryRunner.run(arguments: [
            "summary",
            "--db", evidencePath,
            "--annotations-db", annotationsPath,
            "--since", "2026-03-27 08:00",
            "--until", "2026-03-27 09:00",
            "--group-by", "camera",
        ])
        switch summary {
        case let .summary(response):
            #expect(response.groups.count == 1)
            #expect(response.groups[0].annotations?.map(\.body) == ["Construction noise caveat."])
        case .events, .compare:
            Issue.record("expected query summary output")
        }

        let compare = try ProtectCadenceQueryRunner.run(arguments: [
            "compare",
            "--db", evidencePath,
            "--annotations-db", annotationsPath,
            "--since", "2026-03-27 08:00",
            "--until", "2026-03-27 09:00",
            "--vs-since", "2026-03-26 08:00",
            "--vs-until", "2026-03-26 09:00",
            "--group-by", "camera",
        ])
        switch compare {
        case let .compare(response):
            #expect(response.groups.count == 1)
            #expect(response.groups[0].annotations?.map(\.body) == ["Construction noise caveat."])
        case .events, .summary:
            Issue.record("expected query compare output")
        }
    }

    @Test
    func modelEpisodesAndFindingsIncludeCameraAnnotations() throws {
        try withDefaultTimeZone("America/Los_Angeles") {
            let evidencePath = temporaryDatabasePath()
            let modelPath = temporaryDatabasePath()
            let annotationsPath = temporaryDatabasePath()
            let database = try ProtectCadenceDatabase(path: evidencePath)
            try insertRows(
                [
                    EventRow(
                        timeStart: localDate(month: 4, day: 7, hour: 8, minute: 0),
                        timeEnd: localDate(month: 4, day: 7, hour: 8, minute: 2),
                        camera: "Driveway",
                        kind: "person",
                        eventID: "episode-1"
                    ),
                    EventRow(
                        timeStart: localDate(month: 4, day: 8, hour: 8, minute: 0),
                        timeEnd: localDate(month: 4, day: 8, hour: 8, minute: 2),
                        camera: "Driveway",
                        kind: "person",
                        eventID: "episode-2"
                    ),
                    EventRow(
                        timeStart: localDate(month: 4, day: 9, hour: 14, minute: 0),
                        timeEnd: localDate(month: 4, day: 9, hour: 14, minute: 1),
                        camera: "Driveway",
                        kind: "person",
                        eventID: "episode-3"
                    ),
                ],
                into: database
            )
            _ = try ProtectCadenceAnnotationsDatabase(path: annotationsPath).add(
                account: "default",
                targetKind: "camera",
                targetID: "name:Driveway",
                body: "Driveway model caveat."
            )

            _ = try ProtectCadenceModelRunner.run(
                arguments: ["rebuild", "--db", evidencePath, "--model-db", modelPath],
                now: localDate(month: 4, day: 9, hour: 18, minute: 0)
            )

            let episodes = try ProtectCadenceModelRunner.run(arguments: [
                "episodes",
                "--model-db", modelPath,
                "--annotations-db", annotationsPath,
                "--limit", "1",
            ])
            switch episodes {
            case let .episodes(response):
                #expect(response.episodes.count == 1)
                #expect(response.episodes[0].annotations?.map(\.body) == ["Driveway model caveat."])
            case .rebuild, .findings:
                Issue.record("expected model episodes output")
            }

            let findings = try ProtectCadenceModelRunner.run(arguments: [
                "findings",
                "--model-db", modelPath,
                "--annotations-db", annotationsPath,
                "--finding-type", "unexpected_presence",
                "--limit", "1",
            ])
            switch findings {
            case let .findings(response):
                #expect(response.findings.count == 1)
                #expect(response.findings[0].annotations?.map(\.body) == ["Driveway model caveat."])
            case .rebuild, .episodes:
                Issue.record("expected model findings output")
            }

            let optedOutEpisodes = try ProtectCadenceModelRunner.run(arguments: [
                "episodes",
                "--model-db", modelPath,
                "--annotations-db", annotationsPath,
                "--no-annotations",
                "--limit", "1",
            ])
            switch optedOutEpisodes {
            case let .episodes(response):
                #expect(response.episodes.count == 1)
                #expect(response.episodes[0].annotations == nil)
            case .rebuild, .findings:
                Issue.record("expected model episodes output")
            }
        }
    }

}
