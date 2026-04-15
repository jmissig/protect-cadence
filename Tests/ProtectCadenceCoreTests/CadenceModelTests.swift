import Foundation
import GRDB
import Testing
@testable import ProtectCadenceCore

struct CadenceModelTests {
    @Test
    func modelRebuildMaterializesDeterministicSingleCameraEpisodes() throws {
        try withDefaultTimeZone("America/Los_Angeles") {
            let sourceDatabasePath = temporarySQLitePath()
            let modelDatabasePath = temporarySQLitePath()
            let sourceDatabase = try ProtectCadenceDatabase(path: sourceDatabasePath)

            try insertRows(
                [
                    EventRow(
                        timeStart: localDate(day: 14, hour: 8, minute: 0),
                        timeEnd: localDate(day: 14, hour: 8, minute: 1),
                        cameraID: "driveway-1",
                        camera: "Driveway",
                        kind: "person",
                        eventID: "driveway-a"
                    ),
                    EventRow(
                        timeStart: localDate(day: 14, hour: 8, minute: 3),
                        timeEnd: localDate(day: 14, hour: 8, minute: 4),
                        cameraID: "driveway-1",
                        camera: "Driveway",
                        kind: "vehicle",
                        eventID: "driveway-b"
                    ),
                    EventRow(
                        timeStart: localDate(day: 14, hour: 8, minute: 4),
                        timeEnd: localDate(day: 14, hour: 8, minute: 5),
                        cameraID: "backyard-1",
                        camera: "Backyard",
                        kind: "animal",
                        eventID: "backyard-a"
                    ),
                    EventRow(
                        timeStart: localDate(day: 14, hour: 8, minute: 12),
                        timeEnd: localDate(day: 14, hour: 8, minute: 13),
                        cameraID: "driveway-1",
                        camera: "Driveway",
                        kind: "person",
                        eventID: "driveway-c"
                    ),
                    EventRow(
                        timeStart: localDate(day: 14, hour: 8, minute: 14),
                        timeEnd: localDate(day: 14, hour: 8, minute: 16),
                        cameraID: "driveway-1",
                        camera: "Driveway",
                        kind: "person",
                        eventID: "driveway-d"
                    ),
                ],
                into: sourceDatabase
            )

            let rebuild = try ProtectCadenceModelRunner.run(
                arguments: ["rebuild", "--db", sourceDatabasePath, "--model-db", modelDatabasePath],
                now: localDate(day: 14, hour: 9, minute: 0)
            )

            switch rebuild {
            case let .rebuild(response):
                #expect(response.command == "protect-cadence model")
                #expect(response.action == "rebuild")
                #expect(response.sourceDatabasePath == sourceDatabasePath)
                #expect(response.modelDatabasePath == modelDatabasePath)
                #expect(response.episodeCount == 3)
                #expect(response.stateBucketStatCount == 2)
                #expect(response.stateTransitionStatCount == 1)
                #expect(response.rebuildDurationSeconds >= 0)
            case .episodes, .findings:
                Issue.record("expected rebuild output")
            }

            let episodesOutput = try ProtectCadenceModelRunner.run(
                arguments: ["episodes", "--model-db", modelDatabasePath, "--order", "oldest", "--limit", "10"],
                now: localDate(day: 14, hour: 9, minute: 0)
            )

            switch episodesOutput {
            case let .episodes(response):
                #expect(response.episodes.count == 3)

                let first = response.episodes[0]
                #expect(first.camera == "Driveway")
                #expect(first.cameraID == "driveway-1")
                #expect(first.primaryKind == "person")
                #expect(first.stateKey == "Driveway:person")
                #expect(first.startTime == localDate(day: 14, hour: 8, minute: 0))
                #expect(first.endTime == localDate(day: 14, hour: 8, minute: 4))
                #expect(first.durationSeconds == 4 * 60)
                #expect(first.eventCount == 2)
                #expect(first.sourceEventCount == 2)
                #expect(first.dayClass == .weekday)
                #expect(first.kinds == [
                    ModelEpisodeKind(kind: "person", occurrenceCount: 1, isPrimary: true),
                    ModelEpisodeKind(kind: "vehicle", occurrenceCount: 1, isPrimary: false),
                ])
                #expect(first.sourceEventIDs == ["driveway-a", "driveway-b"])

                let second = response.episodes[1]
                #expect(second.camera == "Backyard")
                #expect(second.primaryKind == "animal")
                #expect(second.stateKey == "Backyard:animal")
                #expect(second.eventCount == 1)

                let third = response.episodes[2]
                #expect(third.camera == "Driveway")
                #expect(third.primaryKind == "person")
                #expect(third.eventCount == 2)
                #expect(third.sourceEventIDs == ["driveway-c", "driveway-d"])
            case .rebuild, .findings:
                Issue.record("expected episodes output")
            }
        }
    }

    @Test
    func modelRebuildWritesInspectableModelTables() throws {
        try withDefaultTimeZone("America/Los_Angeles") {
            let sourceDatabasePath = temporarySQLitePath()
            let modelDatabasePath = temporarySQLitePath()
            let sourceDatabase = try ProtectCadenceDatabase(path: sourceDatabasePath)

            try insertRows(
                [
                    EventRow(
                        timeStart: localDate(day: 13, hour: 8, minute: 0),
                        timeEnd: localDate(day: 13, hour: 8, minute: 2),
                        camera: "Driveway",
                        kind: "person",
                        eventID: "weekday-1"
                    ),
                    EventRow(
                        timeStart: localDate(day: 14, hour: 8, minute: 5),
                        timeEnd: localDate(day: 14, hour: 8, minute: 7),
                        camera: "Driveway",
                        kind: "person",
                        eventID: "weekday-2"
                    ),
                    EventRow(
                        timeStart: localDate(day: 15, hour: 14, minute: 0),
                        timeEnd: localDate(day: 15, hour: 14, minute: 1),
                        camera: "Driveway",
                        kind: "person",
                        eventID: "weekday-3"
                    ),
                ],
                into: sourceDatabase
            )

            _ = try ProtectCadenceModelRunner.run(
                arguments: ["rebuild", "--db", sourceDatabasePath, "--model-db", modelDatabasePath],
                now: localDate(day: 15, hour: 18, minute: 0)
            )

            let dbQueue = try DatabaseQueue(path: modelDatabasePath)
            try dbQueue.read { db in
                let runCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM model_runs")
                let episodeCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM episodes")
                let kindCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM episode_kinds")
                let transitionStatCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM state_transition_stats")
                let findingCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM attention_findings")

                #expect(runCount == 1)
                #expect(episodeCount == 3)
                #expect(kindCount == 3)
                #expect(transitionStatCount == 2)
                #expect(findingCount == 1)

                let bucketRow = try #require(
                    try Row.fetchOne(
                        db,
                        sql: """
                            SELECT episode_count, state_episode_count, average_duration_seconds
                            FROM state_bucket_stats
                            WHERE camera = 'Driveway'
                              AND primary_kind = 'person'
                              AND hour_of_day = 8
                              AND day_class = 'weekday'
                            """
                    )
                )

                #expect((bucketRow["episode_count"] as Int) == 2)
                #expect((bucketRow["state_episode_count"] as Int) == 3)
                #expect((bucketRow["average_duration_seconds"] as Double) == 120.0)

                let transitionRow = try #require(
                    try Row.fetchOne(
                        db,
                        sql: """
                            SELECT transition_count, pair_transition_count
                            FROM state_transition_stats
                            WHERE camera = 'Driveway'
                              AND from_state_key = 'Driveway:person'
                              AND to_state_key = 'Driveway:person'
                              AND hour_of_day = 8
                              AND day_class = 'weekday'
                            """
                    )
                )

                #expect((transitionRow["transition_count"] as Int) == 1)
                #expect((transitionRow["pair_transition_count"] as Int) == 2)
            }
        }
    }

    @Test
    func findingsSurfaceIncludesUnexpectedPresence() throws {
        try withDefaultTimeZone("America/Los_Angeles") {
            let sourceDatabasePath = temporarySQLitePath()
            let modelDatabasePath = temporarySQLitePath()
            let sourceDatabase = try ProtectCadenceDatabase(path: sourceDatabasePath)

            try insertRows(
                [
                    EventRow(
                        timeStart: localDate(day: 7, hour: 8, minute: 0),
                        timeEnd: localDate(day: 7, hour: 8, minute: 2),
                        camera: "Driveway",
                        kind: "person",
                        eventID: "episode-1"
                    ),
                    EventRow(
                        timeStart: localDate(day: 8, hour: 8, minute: 0),
                        timeEnd: localDate(day: 8, hour: 8, minute: 2),
                        camera: "Driveway",
                        kind: "person",
                        eventID: "episode-2"
                    ),
                    EventRow(
                        timeStart: localDate(day: 9, hour: 14, minute: 0),
                        timeEnd: localDate(day: 9, hour: 14, minute: 1),
                        camera: "Driveway",
                        kind: "person",
                        eventID: "episode-3"
                    ),
                ],
                into: sourceDatabase
            )

            _ = try ProtectCadenceModelRunner.run(
                arguments: ["rebuild", "--db", sourceDatabasePath, "--model-db", modelDatabasePath],
                now: localDate(day: 9, hour: 18, minute: 0)
            )

            let findingsOutput = try ProtectCadenceModelRunner.run(
                arguments: [
                    "findings",
                    "--model-db", modelDatabasePath,
                    "--finding-type", "unexpected_presence",
                    "--limit", "10",
                ],
                now: localDate(day: 9, hour: 18, minute: 0)
            )

            switch findingsOutput {
            case let .findings(response):
                #expect(response.findings.count == 1)
                let finding = response.findings[0]
                #expect(finding.findingType == .unexpectedPresence)
                #expect(finding.camera == "Driveway")
                #expect(finding.primaryKind == "person")
                #expect(finding.hourOfDay == 14)
                #expect(finding.dayClass == .weekday)
                #expect(finding.bucketEpisodeCount == 1)
                #expect(finding.stateEpisodeCount == 3)
            case .rebuild, .episodes:
                Issue.record("expected findings output")
            }
        }
    }

    @Test
    func findingsSurfaceIncludesUnusualDuration() throws {
        try withDefaultTimeZone("America/Los_Angeles") {
            let sourceDatabasePath = temporarySQLitePath()
            let modelDatabasePath = temporarySQLitePath()
            let sourceDatabase = try ProtectCadenceDatabase(path: sourceDatabasePath)

            try insertRows(
                [
                    EventRow(
                        timeStart: localDate(day: 1, hour: 8, minute: 0),
                        timeEnd: localDate(day: 1, hour: 8, minute: 1),
                        camera: "Driveway",
                        kind: "person",
                        eventID: "episode-1"
                    ),
                    EventRow(
                        timeStart: localDate(day: 2, hour: 8, minute: 0),
                        timeEnd: localDate(day: 2, hour: 8, minute: 2),
                        camera: "Driveway",
                        kind: "person",
                        eventID: "episode-2"
                    ),
                    EventRow(
                        timeStart: localDate(day: 3, hour: 8, minute: 0),
                        timeEnd: localDate(day: 3, hour: 8, minute: 15),
                        camera: "Driveway",
                        kind: "person",
                        eventID: "episode-3"
                    ),
                ],
                into: sourceDatabase
            )

            _ = try ProtectCadenceModelRunner.run(
                arguments: ["rebuild", "--db", sourceDatabasePath, "--model-db", modelDatabasePath],
                now: localDate(day: 3, hour: 18, minute: 0)
            )

            let findingsOutput = try ProtectCadenceModelRunner.run(
                arguments: [
                    "findings",
                    "--model-db", modelDatabasePath,
                    "--finding-type", "unusual_duration",
                    "--limit", "10",
                ],
                now: localDate(day: 3, hour: 18, minute: 0)
            )

            switch findingsOutput {
            case let .findings(response):
                #expect(response.findings.count == 1)
                let finding = response.findings[0]
                #expect(finding.findingType == .unusualDuration)
                #expect(finding.camera == "Driveway")
                #expect(finding.primaryKind == "person")
                #expect(finding.hourOfDay == 8)
                #expect(finding.bucketEpisodeCount == 3)
                #expect(finding.stateEpisodeCount == 3)
                #expect(finding.durationDirection == "longer")
                #expect(finding.observedDurationSeconds == 15 * 60)
                #expect((finding.expectedDurationSeconds ?? 0) > 300)
            case .rebuild, .episodes:
                Issue.record("expected findings output")
            }
        }
    }

    @Test
    func findingsSurfaceIncludesUnexpectedTransition() throws {
        try withDefaultTimeZone("America/Los_Angeles") {
            let sourceDatabasePath = temporarySQLitePath()
            let modelDatabasePath = temporarySQLitePath()
            let sourceDatabase = try ProtectCadenceDatabase(path: sourceDatabasePath)

            try insertRows(
                [
                    EventRow(
                        timeStart: localDate(day: 6, hour: 8, minute: 0),
                        timeEnd: localDate(day: 6, hour: 8, minute: 1),
                        camera: "Driveway",
                        kind: "person",
                        eventID: "day-1-person"
                    ),
                    EventRow(
                        timeStart: localDate(day: 6, hour: 8, minute: 10),
                        timeEnd: localDate(day: 6, hour: 8, minute: 11),
                        camera: "Driveway",
                        kind: "vehicle",
                        eventID: "day-1-vehicle"
                    ),
                    EventRow(
                        timeStart: localDate(day: 7, hour: 8, minute: 0),
                        timeEnd: localDate(day: 7, hour: 8, minute: 1),
                        camera: "Driveway",
                        kind: "person",
                        eventID: "day-2-person"
                    ),
                    EventRow(
                        timeStart: localDate(day: 7, hour: 8, minute: 10),
                        timeEnd: localDate(day: 7, hour: 8, minute: 11),
                        camera: "Driveway",
                        kind: "vehicle",
                        eventID: "day-2-vehicle"
                    ),
                    EventRow(
                        timeStart: localDate(day: 8, hour: 14, minute: 0),
                        timeEnd: localDate(day: 8, hour: 14, minute: 1),
                        camera: "Driveway",
                        kind: "person",
                        eventID: "day-3-person"
                    ),
                    EventRow(
                        timeStart: localDate(day: 8, hour: 14, minute: 10),
                        timeEnd: localDate(day: 8, hour: 14, minute: 11),
                        camera: "Driveway",
                        kind: "vehicle",
                        eventID: "day-3-vehicle"
                    ),
                ],
                into: sourceDatabase
            )

            _ = try ProtectCadenceModelRunner.run(
                arguments: ["rebuild", "--db", sourceDatabasePath, "--model-db", modelDatabasePath],
                now: localDate(day: 8, hour: 18, minute: 0)
            )

            let findingsOutput = try ProtectCadenceModelRunner.run(
                arguments: [
                    "findings",
                    "--model-db", modelDatabasePath,
                    "--finding-type", "unexpected_transition",
                    "--limit", "10",
                ],
                now: localDate(day: 8, hour: 18, minute: 0)
            )

            switch findingsOutput {
            case let .findings(response):
                #expect(response.findings.count == 1)
                let finding = response.findings[0]
                #expect(finding.findingType == .unexpectedTransition)
                #expect(finding.camera == "Driveway")
                #expect(finding.primaryKind == "vehicle")
                #expect(finding.previousPrimaryKind == "person")
                #expect(finding.stateKey == "Driveway:vehicle")
                #expect(finding.previousStateKey == "Driveway:person")
                #expect(finding.hourOfDay == 14)
                #expect(finding.dayClass == .weekday)
                #expect(finding.transitionBucketCount == 1)
                #expect(finding.transitionPairCount == 3)
                #expect(finding.observedGapSeconds == 9 * 60)
                #expect((finding.expectedGapSeconds ?? 0) == Double(9 * 60))
                #expect(finding.previousEpisodeID != nil)
                #expect(finding.linkedEpisodeIDs.count == 2)
            case .rebuild, .episodes:
                Issue.record("expected findings output")
            }
        }
    }

    private func insertRows(_ rows: [EventRow], into database: ProtectCadenceDatabase) throws {
        for row in rows {
            try database.insert(row)
        }
    }

    private func temporarySQLitePath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
            .path
    }

    private func localDate(
        year: Int = 2026,
        month: Int = 4,
        day: Int,
        hour: Int,
        minute: Int,
        second: Int = 0,
        timeZoneID: String = "America/Los_Angeles"
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID)!
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        ))!
    }

    private func withDefaultTimeZone<T>(_ timeZoneID: String, operation: () throws -> T) throws -> T {
        let original = NSTimeZone.default
        NSTimeZone.default = try #require(TimeZone(identifier: timeZoneID))
        defer {
            NSTimeZone.default = original
        }
        return try operation()
    }
}
