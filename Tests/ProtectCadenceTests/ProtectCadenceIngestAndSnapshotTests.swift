import Foundation
import GRDB
import Testing
@testable import ProtectCadence

@Suite("Ingest and Snapshots")
struct ProtectCadenceIngestAndSnapshotTests {
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

        #expect(response.fetchedSourceEventCount == 5)
        #expect(response.normalizedEventCount == 4)
        #expect(response.insertedEventCount == 4)
        #expect(response.ignoredSourceEventCount == 2)

        let recent = try database.fetchRecent(RecentEventsRequest(limit: 10))
        #expect(recent.map(\.kind).sorted() == ["animal", "package", "person", "vehicle"])
        #expect(Set(recent.map(\.camera)) == ["Entry 02", "North 01"])
        #expect(Set(recent.compactMap(\.cameraID)) == ["camera-001", "camera-002"])
        #expect(Set(recent.compactMap(\.eventType)) == ["package", "smartDetectZone"])

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

        #expect(first.fetchedSourceEventCount == 5)
        #expect(first.normalizedEventCount == 5)
        #expect(first.insertedEventCount == 5)
        #expect(first.ignoredSourceEventCount == 1)
        #expect(second.insertedEventCount == 0)

        let recent = try database.fetchRecent(RecentEventsRequest(limit: 10))
        #expect(Set(recent.compactMap(\.cameraID)) == ["camera-001", "camera-002"])
        #expect(Set(recent.compactMap(\.eventType)) == ["package", "smartDetectZone"])
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
}
