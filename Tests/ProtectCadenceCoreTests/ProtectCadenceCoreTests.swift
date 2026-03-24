import Foundation
import Testing
@testable import ProtectCadenceCore

struct ProtectCadenceCoreTests {
    @Test
    func normalizerExpandsSmartDetectTypesIntoMultipleRows() throws {
        let payload = ProtectEventPayload(
            id: "bootstrap-id",
            eventID: "event-1",
            type: "smartDetectZone",
            start: Date(timeIntervalSince1970: 100),
            end: Date(timeIntervalSince1970: 110),
            detectedAt: Date(timeIntervalSince1970: 105),
            smartDetectTypes: ["person", "vehicle", "person"],
            camera: ProtectEventCameraPayload(displayName: "Driveway")
        )

        let rows = try ProtectEventNormalizer.normalize(payload)

        #expect(rows.count == 2)
        #expect(rows.map(\.kind) == ["person", "vehicle"])
        #expect(rows.allSatisfy { $0.eventID == "event-1" })
        #expect(rows.allSatisfy { $0.timeStart == Date(timeIntervalSince1970: 105) })
        #expect(rows.allSatisfy { $0.timeEnd == Date(timeIntervalSince1970: 110) })
        #expect(rows.allSatisfy { $0.camera == "Driveway" })
    }

    @Test
    func normalizerMapsLegacyAliasesAndUsesFallbackCameraName() throws {
        let payload = ProtectEventPayload(
            id: "event-2",
            start: Date(timeIntervalSince1970: 100),
            smartDetectTypes: ["car", "pet"]
        )

        let rows = try ProtectEventNormalizer.normalize(payload, fallbackCameraName: "Backyard")

        #expect(rows.map(\.kind) == ["vehicle", "animal"])
        #expect(rows.allSatisfy { $0.eventID == "event-2" })
        #expect(rows.allSatisfy { $0.camera == "Backyard" })
    }

    @Test
    func normalizerIgnoresEventsWithoutKinds() throws {
        let payload = ProtectEventPayload(
            id: "event-3",
            type: "smartDetectZone",
            start: Date(timeIntervalSince1970: 100),
            camera: ProtectEventCameraPayload(displayName: "Garage")
        )

        let rows = try ProtectEventNormalizer.normalize(payload)

        #expect(rows.isEmpty)
    }

    @Test
    func payloadDecodesUnixMillisecondTimestamps() throws {
        let json = """
        {
          "id": "event-4",
          "eventId": "event-4",
          "type": "smartDetectZone",
          "start": 1710000000000,
          "end": 1710000005000,
          "detectedAt": 1710000001000,
          "smartDetectTypes": ["package"],
          "camera": {
            "displayName": "Porch"
          }
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(ProtectEventPayload.self, from: json)
        let rows = try ProtectEventNormalizer.normalize(payload)

        #expect(rows.count == 1)
        #expect(rows[0].kind == "package")
        #expect(rows[0].camera == "Porch")
        #expect(rows[0].timeStart == Date(timeIntervalSince1970: 1_710_000_001))
        #expect(rows[0].timeEnd == Date(timeIntervalSince1970: 1_710_000_005))
    }

    @Test
    func recentEventsAreReturnedNewestFirst() throws {
        let database = try ProtectCadenceDatabase(path: temporaryDatabasePath())

        try database.insert(
            EventRow(
                timeStart: Date(timeIntervalSince1970: 100),
                camera: "Driveway",
                kind: "vehicle",
                eventID: "event-1"
            )
        )
        try database.insert(
            EventRow(
                timeStart: Date(timeIntervalSince1970: 200),
                camera: "Backyard",
                kind: "animal",
                eventID: "event-2"
            )
        )

        let recent = try database.fetchRecent(RecentEventsRequest(limit: 10))

        #expect(recent.map(\.eventID) == ["event-2", "event-1"])
    }

    @Test
    func sameEventCanProduceMultipleKinds() throws {
        let database = try ProtectCadenceDatabase(path: temporaryDatabasePath())

        try database.insert(
            EventRow(
                timeStart: Date(timeIntervalSince1970: 100),
                timeEnd: Date(timeIntervalSince1970: 110),
                camera: "Driveway",
                kind: "person",
                eventID: "event-1"
            )
        )
        try database.insert(
            EventRow(
                timeStart: Date(timeIntervalSince1970: 100),
                timeEnd: Date(timeIntervalSince1970: 110),
                camera: "Driveway",
                kind: "vehicle",
                eventID: "event-1"
            )
        )

        let recent = try database.fetchRecent(RecentEventsRequest(limit: 10))

        #expect(recent.map(\.kind).sorted() == ["person", "vehicle"])
        #expect(Set(recent.map(\.eventID)) == ["event-1"])
    }

    @Test
    func summaryGroupsRowsByCameraAndKind() throws {
        let database = try ProtectCadenceDatabase(path: temporaryDatabasePath())

        try insertRows(
            [
                EventRow(
                    timeStart: Date(timeIntervalSince1970: 100),
                    camera: "Backyard",
                    kind: "animal",
                    eventID: "event-1"
                ),
                EventRow(
                    timeStart: Date(timeIntervalSince1970: 110),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "event-2"
                ),
                EventRow(
                    timeStart: Date(timeIntervalSince1970: 115),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "event-3"
                ),
                EventRow(
                    timeStart: Date(timeIntervalSince1970: 120),
                    camera: "Driveway",
                    kind: "vehicle",
                    eventID: "event-2"
                ),
            ],
            into: database
        )

        let summary = try database.fetchSummary(
            SummaryRequest(
                window: QueryWindow(
                    start: Date(timeIntervalSince1970: 90),
                    end: Date(timeIntervalSince1970: 130)
                )
            )
        )

        #expect(summary.totalRows == 4)
        #expect(summary.distinctEventCount == 3)
        #expect(
            summary.groups == [
                SummaryGroup(camera: "Backyard", kind: "animal", rowCount: 1),
                SummaryGroup(camera: "Driveway", kind: "person", rowCount: 2),
                SummaryGroup(camera: "Driveway", kind: "vehicle", rowCount: 1),
            ]
        )
    }

    @Test
    func summaryWindowExcludesRowsOutsideRange() throws {
        let database = try ProtectCadenceDatabase(path: temporaryDatabasePath())

        try insertRows(
            [
                EventRow(
                    timeStart: Date(timeIntervalSince1970: 99),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "before-window"
                ),
                EventRow(
                    timeStart: Date(timeIntervalSince1970: 100),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "inside-window"
                ),
                EventRow(
                    timeStart: Date(timeIntervalSince1970: 200),
                    camera: "Driveway",
                    kind: "vehicle",
                    eventID: "at-end-boundary"
                ),
            ],
            into: database
        )

        let summary = try database.fetchSummary(
            SummaryRequest(
                window: QueryWindow(
                    start: Date(timeIntervalSince1970: 100),
                    end: Date(timeIntervalSince1970: 200)
                )
            )
        )

        #expect(summary.totalRows == 1)
        #expect(summary.distinctEventCount == 1)
        #expect(summary.groups == [SummaryGroup(camera: "Driveway", kind: "person", rowCount: 1)])
    }

    @Test
    func summaryDistinctEventCountDoesNotDoubleCountKinds() throws {
        let database = try ProtectCadenceDatabase(path: temporaryDatabasePath())

        try insertRows(
            [
                EventRow(
                    timeStart: Date(timeIntervalSince1970: 100),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "event-1"
                ),
                EventRow(
                    timeStart: Date(timeIntervalSince1970: 100),
                    camera: "Driveway",
                    kind: "vehicle",
                    eventID: "event-1"
                ),
                EventRow(
                    timeStart: Date(timeIntervalSince1970: 101),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "event-2"
                ),
            ],
            into: database
        )

        let summary = try database.fetchSummary(
            SummaryRequest(
                window: QueryWindow(
                    start: Date(timeIntervalSince1970: 90),
                    end: Date(timeIntervalSince1970: 110)
                )
            )
        )

        #expect(summary.totalRows == 3)
        #expect(summary.distinctEventCount == 2)
    }

    @Test
    func summaryReturnsZerosForEmptyWindow() throws {
        let database = try ProtectCadenceDatabase(path: temporaryDatabasePath())

        let summary = try database.fetchSummary(
            SummaryRequest(
                window: QueryWindow(
                    start: Date(timeIntervalSince1970: 100),
                    end: Date(timeIntervalSince1970: 200)
                )
            )
        )

        #expect(summary.totalRows == 0)
        #expect(summary.distinctEventCount == 0)
        #expect(summary.groups.isEmpty)
    }

    @Test
    func queryRunnerSummaryProducesEncodableSummaryOutput() throws {
        let databasePath = temporaryDatabasePath()
        let database = try ProtectCadenceDatabase(path: databasePath)
        let now = Date(timeIntervalSince1970: 10_000)

        try insertRows(
            [
                EventRow(
                    timeStart: now.addingTimeInterval(-30 * 60),
                    camera: "Porch",
                    kind: "package",
                    eventID: "event-1"
                ),
            ],
            into: database
        )

        let output = try ProtectCadenceQueryRunner.run(
            arguments: ["summary", "--db", databasePath, "--last-hours", "2"],
            now: now
        )

        switch output {
        case let .summary(response):
            #expect(response.command == "protect-cadence-query")
            #expect(response.totalRows == 1)
            #expect(response.distinctEventCount == 1)
            #expect(response.groups == [SummaryGroup(camera: "Porch", kind: "package", rowCount: 1)])

            let json = try JSONOutput.encode(output)
            #expect(json.contains("\"command\""))
            #expect(json.contains("\"window\""))
            #expect(json.contains("\"distinctEventCount\""))
        case .recent:
            Issue.record("expected summary output")
        }
    }

    @Test
    func queryCLIRejectsInvalidLastHours() throws {
        do {
            _ = try QueryCLI(arguments: ["summary", "--last-hours", "0"])
            Issue.record("expected --last-hours validation error")
        } catch let error as QueryCLIError {
            #expect(error.description.contains("--last-hours"))
        }
    }

    @Test
    func queryRunnerRecentStillReturnsNewestFirst() throws {
        let databasePath = temporaryDatabasePath()
        let database = try ProtectCadenceDatabase(path: databasePath)

        try insertRows(
            [
                EventRow(
                    timeStart: Date(timeIntervalSince1970: 100),
                    camera: "Driveway",
                    kind: "vehicle",
                    eventID: "event-1"
                ),
                EventRow(
                    timeStart: Date(timeIntervalSince1970: 200),
                    camera: "Backyard",
                    kind: "animal",
                    eventID: "event-2"
                ),
            ],
            into: database
        )

        let output = try ProtectCadenceQueryRunner.run(
            arguments: ["recent", "--db", databasePath, "--limit", "1"]
        )

        switch output {
        case let .recent(response):
            #expect(response.events.map(\.eventID) == ["event-2"])
        case .summary:
            Issue.record("expected recent output")
        }
    }

    @Test
    func queryRunnerRecentCanFilterByLastHours() throws {
        let databasePath = temporaryDatabasePath()
        let database = try ProtectCadenceDatabase(path: databasePath)
        let now = Date(timeIntervalSince1970: 10_000)

        try insertRows(
            [
                EventRow(
                    timeStart: now.addingTimeInterval(-30 * 60),
                    camera: "Driveway",
                    kind: "vehicle",
                    eventID: "recent-event"
                ),
                EventRow(
                    timeStart: now.addingTimeInterval(-26 * 60 * 60),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "old-event"
                ),
            ],
            into: database
        )

        let output = try ProtectCadenceQueryRunner.run(
            arguments: ["recent", "--db", databasePath, "--last-hours", "24"],
            now: now
        )

        switch output {
        case let .recent(response):
            #expect(response.window == QueryWindow(start: now.addingTimeInterval(-24 * 60 * 60), end: now))
            #expect(response.events.map(\.eventID) == ["recent-event"])
        case .summary:
            Issue.record("expected recent output")
        }
    }

    private func insertRows(_ rows: [EventRow], into database: ProtectCadenceDatabase) throws {
        for row in rows {
            try database.insert(row)
        }
    }

    private func temporaryDatabasePath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
            .path
    }
}
