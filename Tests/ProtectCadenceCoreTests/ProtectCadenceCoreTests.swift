import Foundation
import Testing
@testable import ProtectCadenceCore

private let realProtectCaptureVersion = "7.0.94"
private let realProtectEventsFixtureName = "events-response-protect-\(realProtectCaptureVersion).json"
private let realProtectCamerasFixtureName = "cameras-response-protect-\(realProtectCaptureVersion).json"
private let realProtectSchemaFixtureName = "schema-snapshot-protect-\(realProtectCaptureVersion).json"

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
    func payloadDecodesCameraStringReferenceFromFixtureSnapshot() throws {
        let payloads: [ProtectEventPayload] = try decodeFixture("events-response.json")

        #expect(payloads[0].camera == nil)
        #expect(payloads[0].cameraReferenceID == "camera-001")
        #expect(payloads[0].cameraID == "camera-001")
    }

    @Test
    func realControllerSnapshotDecodesCurrentObservedEventShape() throws {
        let payloads: [ProtectEventPayload] = try decodeFixture(realProtectEventsFixtureName, fixtureSet: "ProtectAPIReal")

        #expect(!payloads.isEmpty)
        #expect(payloads[0].eventID == nil)
        #expect(payloads[0].id != nil)
        #expect(payloads[0].detectedAt == nil)
        #expect(payloads[0].cameraReferenceID == "camera-005")
    }

    @Test
    func controllerConfigurationReadsOptInInsecureTLSFlag() throws {
        let configuration = try ProtectControllerConfiguration.fromEnvironment(
            [
                "PROTECT_CONTROLLER_URL": "https://unifi.local",
                "PROTECT_USERNAME": "user",
                "PROTECT_PASSWORD": "pass",
                "PROTECT_ALLOW_INSECURE_TLS": "1",
            ]
        )

        #expect(configuration.allowInsecureTLS == true)
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

    @Test
    func controllerClientAuthenticatesBeforeFetchingEvents() async throws {
        let transport = RecordingProtectHTTPTransport(
            responses: [
                .init(
                    statusCode: 200,
                    headers: [
                        "Set-Cookie": "TOKEN=test-session; Path=/; HttpOnly",
                        "x-csrf-token": "csrf-test-token",
                    ],
                    body: Data("{}".utf8)
                ),
                .init(
                    statusCode: 200,
                    headers: [:],
                    body: try fixtureData("events-response.json")
                ),
            ]
        )

        let client = ProtectControllerClient(
            configuration: ProtectControllerConfiguration(
                controllerURL: URL(string: "https://protect.example")!,
                username: "user",
                password: "pass"
            ),
            transport: transport
        )

        let events = try await client.fetchRecentEvents(
            window: QueryWindow(
                start: Date(timeIntervalSince1970: 1_710_000_000),
                end: Date(timeIntervalSince1970: 1_710_003_600)
            )
        )

        #expect(events.count == 5)

        let requests = await transport.recordedRequests()
        #expect(requests.count == 2)
        #expect(requests[0].url?.path == "/api/auth/login")
        #expect(requests[0].httpMethod == "POST")
        #expect(String(data: requests[0].httpBody ?? Data(), encoding: .utf8)?.contains("\"username\":\"user\"") == true)
        #expect(requests[1].url?.path == "/proxy/protect/api/events")
        #expect(requests[1].value(forHTTPHeaderField: "Cookie") == "TOKEN=test-session")
        #expect(requests[1].value(forHTTPHeaderField: "x-csrf-token") == "csrf-test-token")
    }

    @Test
    func controllerIngestUsesCameraLookupAndWritesSnapshotArtifacts() async throws {
        let database = try ProtectCadenceDatabase(path: temporaryDatabasePath())
        let snapshotDirectory = temporaryDirectoryPath()
        let transport = RecordingProtectHTTPTransport(
            responses: [
                .init(
                    statusCode: 200,
                    headers: [
                        "Set-Cookie": "TOKEN=test-session; Path=/; HttpOnly",
                        "x-csrf-token": "csrf-test-token",
                    ],
                    body: Data("{}".utf8)
                ),
                .init(
                    statusCode: 200,
                    headers: [:],
                    body: try fixtureData("events-response.json")
                ),
                .init(
                    statusCode: 200,
                    headers: [:],
                    body: try fixtureData("cameras-response.json")
                ),
            ]
        )

        let client = ProtectControllerClient(
            configuration: ProtectControllerConfiguration(
                controllerURL: URL(string: "https://protect.example")!,
                username: "user",
                password: "pass"
            ),
            transport: transport
        )
        let service = ProtectIngestService(database: database, client: client)

        let response = try await service.ingestControllerEvents(
            window: QueryWindow(
                start: Date(timeIntervalSince1970: 1_710_000_000),
                end: Date(timeIntervalSince1970: 1_710_003_600)
            ),
            snapshotDirectory: URL(fileURLWithPath: snapshotDirectory, isDirectory: true)
        )

        #expect(response.fetchedEventCount == 5)
        #expect(response.normalizedRowCount == 4)
        #expect(response.insertedRowCount == 4)
        #expect(response.ignoredEventCount == 2)

        let recent = try database.fetchRecent(RecentEventsRequest(limit: 10))
        #expect(recent.map(\.kind).sorted() == ["animal", "package", "person", "vehicle"])
        #expect(Set(recent.map(\.camera)) == ["Entry 02", "North 01"])

        #expect(FileManager.default.fileExists(atPath: URL(fileURLWithPath: snapshotDirectory).appendingPathComponent("events-response.json").path))
        #expect(FileManager.default.fileExists(atPath: URL(fileURLWithPath: snapshotDirectory).appendingPathComponent("cameras-response.json").path))
        #expect(FileManager.default.fileExists(atPath: URL(fileURLWithPath: snapshotDirectory).appendingPathComponent("schema-snapshot.json").path))
    }

    @Test
    func fixtureIngestAcceptsArraySnapshotsAndDeduplicatesReplays() throws {
        let database = try ProtectCadenceDatabase(path: temporaryDatabasePath())
        let service = ProtectIngestService(database: database)
        let eventData = try fixtureData("events-response.json")
        let cameraData = try fixtureData("cameras-response.json")

        let first = try service.ingestFixtureEvents(from: eventData, cameraLookupData: cameraData)
        let second = try service.ingestFixtureEvents(from: eventData, cameraLookupData: cameraData)

        #expect(first.fetchedEventCount == 5)
        #expect(first.normalizedRowCount == 5)
        #expect(first.insertedRowCount == 5)
        #expect(first.ignoredEventCount == 1)
        #expect(second.insertedRowCount == 0)
    }

    @Test
    func schemaSnapshotMatchesCommittedFixtureInventory() throws {
        let eventsData = try fixtureData("events-response.json")
        let camerasData = try fixtureData("cameras-response.json")
        let expected: ProtectSchemaSnapshot = try decodeFixture("schema-snapshot.json")

        let actual = try ProtectSchemaSnapshot.make(
            files: [
                ("events-response.json", eventsData),
                ("cameras-response.json", camerasData),
            ]
        )

        #expect(actual == expected)
    }

    @Test
    func realControllerSchemaSnapshotMatchesCommittedFixtureInventory() throws {
        let eventsData = try fixtureData(realProtectEventsFixtureName, fixtureSet: "ProtectAPIReal")
        let camerasData = try fixtureData(realProtectCamerasFixtureName, fixtureSet: "ProtectAPIReal")
        let expected: ProtectSchemaSnapshot = try decodeFixture(realProtectSchemaFixtureName, fixtureSet: "ProtectAPIReal")

        let actual = try ProtectSchemaSnapshot.make(
            files: [
                ("events-response.json", eventsData),
                ("cameras-response.json", camerasData),
            ]
        )

        #expect(actual == expected)
    }

    @Test
    func snapshotWriterProducesCommittedFixturesFromUnsanitizedSamples() throws {
        let snapshotDirectory = temporaryDirectoryPath()
        let writer = ProtectAPISnapshotWriter(
            directoryURL: URL(fileURLWithPath: snapshotDirectory, isDirectory: true)
        )

        try writer.write(
            events: unsanitizedSampleEvents(),
            cameras: unsanitizedSampleCameras()
        )

        let expectedEvents = try fixtureData("events-response.json")
        let expectedCameras = try fixtureData("cameras-response.json")
        let expectedSchema = try fixtureData("schema-snapshot.json")

        let actualEvents = try Data(contentsOf: URL(fileURLWithPath: snapshotDirectory).appendingPathComponent("events-response.json"))
        let actualCameras = try Data(contentsOf: URL(fileURLWithPath: snapshotDirectory).appendingPathComponent("cameras-response.json"))
        let actualSchema = try Data(contentsOf: URL(fileURLWithPath: snapshotDirectory).appendingPathComponent("schema-snapshot.json"))

        if ProcessInfo.processInfo.environment["REGENERATE_PROTECT_FIXTURES"] == "1" {
            try actualEvents.write(to: fixturesDirectoryURL().appendingPathComponent("events-response.json"))
            try actualCameras.write(to: fixturesDirectoryURL().appendingPathComponent("cameras-response.json"))
            try actualSchema.write(to: fixturesDirectoryURL().appendingPathComponent("schema-snapshot.json"))
            return
        }

        #expect(actualEvents == expectedEvents)
        #expect(actualCameras == expectedCameras)
        #expect(actualSchema == expectedSchema)
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

    private func temporaryDirectoryPath() -> String {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.path
    }

    private func fixtureData(_ name: String, fixtureSet: String = "ProtectAPI") throws -> Data {
        try Data(contentsOf: fixturesDirectoryURL(fixtureSet: fixtureSet).appendingPathComponent(name))
    }

    private func decodeFixture<T: Decodable>(_ name: String, fixtureSet: String = "ProtectAPI") throws -> T {
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: fixtureData(name, fixtureSet: fixtureSet))
    }

    private func fixturesDirectoryURL(
        fixtureSet: String = "ProtectAPI",
        filePath: StaticString = #filePath
    ) -> URL {
        URL(fileURLWithPath: "\(filePath)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(fixtureSet)", isDirectory: true)
    }

    private func unsanitizedSampleCameras() -> [ProtectCameraRecord] {
        [
            ProtectCameraRecord(id: "raw-driveway-camera", displayName: "Driveway", name: "Driveway"),
            ProtectCameraRecord(id: "raw-porch-camera", displayName: "Porch", name: "Porch"),
        ]
    }

    private func unsanitizedSampleEvents() -> [ProtectEventPayload] {
        [
            ProtectEventPayload(
                id: "raw-event-alpha",
                eventID: "raw-event-alpha",
                type: "smartDetectZone",
                start: Date(timeIntervalSince1970: 1_710_000_000),
                end: Date(timeIntervalSince1970: 1_710_000_006),
                detectedAt: Date(timeIntervalSince1970: 1_710_000_002),
                smartDetectTypes: ["person", "vehicle"],
                cameraReferenceID: "raw-driveway-camera",
                cameraID: "raw-driveway-camera"
            ),
            ProtectEventPayload(
                id: "raw-event-beta",
                eventID: "raw-event-beta",
                type: "smartDetectZone",
                start: Date(timeIntervalSince1970: 1_710_000_100),
                end: Date(timeIntervalSince1970: 1_710_000_109),
                detectedAt: Date(timeIntervalSince1970: 1_710_000_104),
                smartDetectTypes: ["animal"],
                camera: ProtectEventCameraPayload(
                    id: "raw-porch-camera",
                    displayName: "Porch",
                    name: "Porch"
                )
            ),
            ProtectEventPayload(
                id: "raw-event-gamma",
                eventID: "raw-event-gamma",
                type: "package",
                start: Date(timeIntervalSince1970: 1_710_000_200),
                end: Date(timeIntervalSince1970: 1_710_000_203),
                cameraReferenceID: "raw-driveway-camera",
                cameraID: "raw-driveway-camera"
            ),
            ProtectEventPayload(
                id: "raw-event-delta",
                eventID: "raw-event-delta",
                type: "motion",
                start: Date(timeIntervalSince1970: 1_710_000_300),
                end: Date(timeIntervalSince1970: 1_710_000_305),
                cameraReferenceID: "raw-driveway-camera"
            ),
            ProtectEventPayload(
                id: "raw-event-epsilon",
                eventID: "raw-event-epsilon",
                type: "smartDetectZone",
                start: Date(timeIntervalSince1970: 1_710_000_400),
                detectedAt: Date(timeIntervalSince1970: 1_710_000_401),
                smartDetectTypes: ["person"],
                cameraReferenceID: "raw-porch-camera",
                cameraID: "raw-porch-camera"
            ),
        ]
    }
}

private actor RecordingProtectHTTPTransport: ProtectHTTPTransport {
    struct StubbedResponse: Sendable {
        let statusCode: Int
        let headers: [String: String]
        let body: Data
    }

    private var responses: [StubbedResponse]
    private var requests: [URLRequest] = []

    init(responses: [StubbedResponse]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = responses.removeFirst()
        return (
            response.body,
            HTTPURLResponse(
                url: request.url!,
                statusCode: response.statusCode,
                httpVersion: nil,
                headerFields: response.headers
            )!
        )
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}
