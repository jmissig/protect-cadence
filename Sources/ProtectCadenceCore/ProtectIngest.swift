import Foundation

public enum ProtectIngestError: Error, CustomStringConvertible {
    case conflictingModes
    case invalidFixtureJSON

    public var description: String {
        switch self {
        case .conflictingModes:
            return "choose only one ingest source: --last-hours or --event-json"
        case .invalidFixtureJSON:
            return "--event-json must contain either one Protect event object or an array of Protect event objects"
        }
    }
}

public final class ProtectIngestService {
    private let database: ProtectCadenceDatabase
    private let client: ProtectControllerClient?

    public init(database: ProtectCadenceDatabase, client: ProtectControllerClient? = nil) {
        self.database = database
        self.client = client
    }

    public func readyResponse() -> IngestResponse {
        IngestResponse(
            command: ProtectCadenceCommand.ingest.rawValue,
            databasePath: database.path,
            fetchedEventCount: 0,
            normalizedRowCount: 0,
            insertedRowCount: 0,
            ignoredEventCount: 0,
            status: "ready"
        )
    }

    public func ingestFixtureEvents(
        from data: Data,
        cameraLookupData: Data? = nil,
        fallbackCameraName: String? = nil
    ) throws -> IngestResponse {
        let payloads = try decodeEventPayloads(from: data)
        let cameraNamesByID: [String: String]
        if let cameraLookupData {
            let cameras = try decodeCameraRecords(from: cameraLookupData)
            cameraNamesByID = Dictionary(
                uniqueKeysWithValues: cameras.compactMap { camera in
                    guard let resolvedName = camera.resolvedName else {
                        return nil
                    }
                    return (camera.id, resolvedName)
                }
            )
        } else {
            cameraNamesByID = [:]
        }

        let result = try normalizedRows(
            from: payloads,
            fallbackCameraName: fallbackCameraName,
            cameraNamesByID: cameraNamesByID
        )
        let insertedRowCount = try database.insertIgnoringDuplicates(result.rows)

        return IngestResponse(
            command: ProtectCadenceCommand.ingest.rawValue,
            databasePath: database.path,
            fetchedEventCount: payloads.count,
            normalizedRowCount: result.rows.count,
            insertedRowCount: insertedRowCount,
            ignoredEventCount: result.ignoredEventCount,
            status: "ok"
        )
    }

    public func ingestControllerEvents(
        window: QueryWindow,
        snapshotDirectory: URL? = nil
    ) async throws -> IngestResponse {
        guard let client else {
            return readyResponse()
        }

        let fetchedPayloads = try await client.fetchRecentEvents(window: window)
        let settledPayloads = fetchedPayloads.filter(\.isSettled)
        let ignoredUnsettledCount = fetchedPayloads.count - settledPayloads.count

        let needsCameraLookup = settledPayloads.contains { payload in
            payload.currentCameraName == nil && payload.cameraLookupKey != nil
        }

        let cameras = needsCameraLookup ? try await client.fetchCameras() : []
        let cameraNamesByID: [String: String] = Dictionary(
            uniqueKeysWithValues: cameras.compactMap { camera in
                guard let resolvedName = camera.resolvedName else {
                    return nil
                }
                return (camera.id, resolvedName)
            }
        )

        if let snapshotDirectory {
            try ProtectAPISnapshotWriter(directoryURL: snapshotDirectory).write(
                events: settledPayloads,
                cameras: cameras
            )
        }

        let result = try normalizedRows(from: settledPayloads, cameraNamesByID: cameraNamesByID)
        let insertedRowCount = try database.insertIgnoringDuplicates(result.rows)

        return IngestResponse(
            command: ProtectCadenceCommand.ingest.rawValue,
            databasePath: database.path,
            window: window,
            fetchedEventCount: fetchedPayloads.count,
            normalizedRowCount: result.rows.count,
            insertedRowCount: insertedRowCount,
            ignoredEventCount: ignoredUnsettledCount + result.ignoredEventCount,
            status: "ok"
        )
    }

    private func decodeEventPayloads(from data: Data) throws -> [ProtectEventPayload] {
        let decoder = JSONDecoder()

        if let payloads = try? decoder.decode([ProtectEventPayload].self, from: data) {
            return payloads
        }

        if let payload = try? decoder.decode(ProtectEventPayload.self, from: data) {
            return [payload]
        }

        throw ProtectIngestError.invalidFixtureJSON
    }

    private func decodeCameraRecords(from data: Data) throws -> [ProtectCameraRecord] {
        try JSONDecoder().decode([ProtectCameraRecord].self, from: data)
    }

    private func normalizedRows(
        from payloads: [ProtectEventPayload],
        fallbackCameraName: String? = nil,
        cameraNamesByID: [String: String]
    ) throws -> (rows: [EventRow], ignoredEventCount: Int) {
        var normalizedRows: [EventRow] = []
        var ignoredEventCount = 0

        for payload in payloads {
            do {
                let rows = try ProtectEventNormalizer.normalize(
                    payload,
                    fallbackCameraName: fallbackCameraName,
                    fallbackCameraNamesByID: cameraNamesByID
                )

                if rows.isEmpty {
                    ignoredEventCount += 1
                } else {
                    normalizedRows.append(contentsOf: rows)
                }
            } catch {
                ignoredEventCount += 1
            }
        }

        return (normalizedRows, ignoredEventCount)
    }
}
