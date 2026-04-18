import Foundation
import GRDB
import Testing
@testable import ProtectCadence

let realProtectCaptureVersion = "7.0.94"
let realProtectEventsFixtureName = "events-response-protect-\(realProtectCaptureVersion).json"
let realProtectCamerasFixtureName = "cameras-response-protect-\(realProtectCaptureVersion).json"
let realProtectSchemaFixtureName = "schema-snapshot-protect-\(realProtectCaptureVersion).json"

func insertRows(_ rows: [EventRow], into database: ProtectCadenceDatabase) throws {
    for row in rows {
        try database.insert(row)
    }
}

func temporaryDatabasePath() -> String {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("sqlite")
        .path
}

func temporarySQLitePath() -> String {
    temporaryDatabasePath()
}

func localDate(
    year: Int = 2026,
    month: Int = 3,
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

func temporaryDirectoryPath() -> String {
    let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL.path
}

func withDefaultTimeZone<T>(_ timeZoneID: String, operation: () throws -> T) throws -> T {
    let original = NSTimeZone.default
    NSTimeZone.default = try #require(TimeZone(identifier: timeZoneID))
    defer {
        NSTimeZone.default = original
    }
    return try operation()
}

func fixtureData(_ name: String, fixtureSet: String = "ProtectAPI") throws -> Data {
    try Data(contentsOf: fixturesDirectoryURL(fixtureSet: fixtureSet).appendingPathComponent(name))
}

func fixturePath(_ name: String, fixtureSet: String = "ProtectAPI") -> String {
    fixturesDirectoryURL(fixtureSet: fixtureSet).appendingPathComponent(name).path
}

func decodeFixture<T: Decodable>(_ name: String, fixtureSet: String = "ProtectAPI") throws -> T {
    let decoder = JSONDecoder()
    return try decoder.decode(T.self, from: fixtureData(name, fixtureSet: fixtureSet))
}

func fixturesDirectoryURL(
    fixtureSet: String = "ProtectAPI",
    filePath: StaticString = #filePath
) -> URL {
    URL(fileURLWithPath: "\(filePath)")
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/\(fixtureSet)", isDirectory: true)
}

func unsanitizedSampleCameras() -> [ProtectCameraRecord] {
    [
        ProtectCameraRecord(id: "raw-driveway-camera", displayName: "Driveway", name: "Driveway"),
        ProtectCameraRecord(id: "raw-porch-camera", displayName: "Porch", name: "Porch"),
    ]
}

func unsanitizedSampleEvents() -> [ProtectEventPayload] {
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

func drillDown(_ filters: QueryFilters) -> QueryDrillDownDescriptor {
    QueryDrillDownDescriptor(filters: filters)
}

func summaryGroup(
    group: [String: String],
    eventCount: Int,
    sourceEventCount: Int,
    filters: QueryFilters
) -> SummaryGroup {
    SummaryGroup(
        group: group,
        eventCount: eventCount,
        sourceEventCount: sourceEventCount,
        drillDown: drillDown(filters)
    )
}

func compareGroup(
    group: [String: String],
    window: CompareCounts,
    comparisonWindow: CompareCounts,
    eventCountDelta: Int,
    sourceEventCountDelta: Int,
    windowFilters: QueryFilters,
    comparisonFilters: QueryFilters
) -> CompareGroup {
    CompareGroup(
        group: group,
        window: window,
        comparisonWindow: comparisonWindow,
        eventCountDelta: eventCountDelta,
        sourceEventCountDelta: sourceEventCountDelta,
        windowDrillDown: drillDown(windowFilters),
        comparisonWindowDrillDown: drillDown(comparisonFilters)
    )
}

actor RecordingProtectHTTPTransport: ProtectHTTPTransport {
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

final class TestPrompter: ProtectAuthPrompter, @unchecked Sendable {
    private var prompts: [String]
    private var passwordPrompts: [String]
    private var confirmations: [Bool]

    init(
        prompts: [String] = [],
        passwordPrompts: [String] = [],
        confirmations: [Bool] = []
    ) {
        self.prompts = prompts
        self.passwordPrompts = passwordPrompts
        self.confirmations = confirmations
    }

    func prompt(_ message: String, defaultValue: String?) throws -> String {
        guard !prompts.isEmpty else {
            throw ProtectAuthResolutionError.inputUnavailable(message)
        }
        return prompts.removeFirst()
    }

    func promptPassword(_ message: String) throws -> String {
        guard !passwordPrompts.isEmpty else {
            throw ProtectAuthResolutionError.inputUnavailable(message)
        }
        return passwordPrompts.removeFirst()
    }

    func confirm(_ message: String) throws -> Bool {
        guard !confirmations.isEmpty else {
            throw ProtectAuthResolutionError.inputUnavailable(message)
        }
        return confirmations.removeFirst()
    }
}

final class RecordedStatusOutput: @unchecked Sendable {
    private(set) var lines: [String] = []

    func write(_ line: String) {
        lines.append(line)
    }
}
