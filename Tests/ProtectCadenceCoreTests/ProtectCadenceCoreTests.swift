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

    private func temporaryDatabasePath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
            .path
    }
}
