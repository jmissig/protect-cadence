import Foundation

public struct ProtectAPISnapshotWriter {
    public let directoryURL: URL

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    public func write(events: [ProtectEventPayload], cameras: [ProtectCameraRecord]) throws {
        let sanitizedEvents = ProtectSnapshotSanitizer.sanitize(events: events, cameras: cameras)
        let sanitizedCameras = ProtectSnapshotSanitizer.sanitize(cameras: cameras)

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let eventsData = try JSONOutput.encodeData(sanitizedEvents)
        let camerasData = try JSONOutput.encodeData(sanitizedCameras)
        let schemaSnapshot = try ProtectSchemaSnapshot.make(
            files: [
                ("events-response.json", eventsData),
                ("cameras-response.json", camerasData),
            ]
        )
        let schemaData = try JSONOutput.encodeData(schemaSnapshot)

        try eventsData.write(to: directoryURL.appendingPathComponent("events-response.json"))
        try camerasData.write(to: directoryURL.appendingPathComponent("cameras-response.json"))
        try schemaData.write(to: directoryURL.appendingPathComponent("schema-snapshot.json"))
    }
}

public enum ProtectSnapshotSanitizer {
    private static let cameraLabelPrefixes = [
        "North",
        "Entry",
        "South",
        "Garden",
        "Garage",
        "Drive",
        "Yard",
        "Walk",
        "Patio",
        "Gate",
        "Deck",
        "Rear",
    ]

    public static func sanitize(events: [ProtectEventPayload], cameras: [ProtectCameraRecord]) -> [ProtectEventPayload] {
        let cameraIDMap = Dictionary(
            uniqueKeysWithValues: cameras.enumerated().map { index, camera in
                (camera.id, String(format: "camera-%03d", index + 1))
            }
        )
        let cameraNameMap = Dictionary(
            uniqueKeysWithValues: cameras.enumerated().map { index, camera in
                (camera.id, sanitizedCameraName(for: index + 1))
            }
        )
        let eventIDMap: [String: String] = Dictionary(
            uniqueKeysWithValues: events.enumerated().compactMap { index, event in
                guard let rawID = event.eventID ?? event.id else {
                    return nil
                }
                return (rawID, String(format: "event-%03d", index + 1))
            }
        )

        return events.map { event in
            let sanitizedCamera: ProtectEventCameraPayload?
            if let camera = event.camera {
                let rawCameraID = camera.id ?? event.cameraLookupKey ?? ""
                let sanitizedCameraID = rawCameraID.isEmpty ? nil : cameraIDMap[rawCameraID]
                let sanitizedCameraName = rawCameraID.isEmpty ? nil : cameraNameMap[rawCameraID]
                sanitizedCamera = ProtectEventCameraPayload(
                    id: sanitizedCameraID,
                    displayName: sanitizedCameraName ?? camera.displayName,
                    name: sanitizedCameraName ?? camera.name
                )
            } else {
                sanitizedCamera = nil
            }

            let sanitizedCameraReferenceID = event.cameraReferenceID.flatMap { cameraIDMap[$0] }
            let sanitizedCameraID = event.cameraID.flatMap { cameraIDMap[$0] }

            return ProtectEventPayload(
                id: event.id.flatMap { eventIDMap[$0] } ?? event.id,
                eventID: event.eventID.flatMap { eventIDMap[$0] } ?? event.eventID,
                type: event.type,
                start: event.start,
                end: event.end,
                detectedAt: event.detectedAt,
                smartDetectTypes: event.smartDetectTypes,
                camera: sanitizedCamera,
                cameraReferenceID: sanitizedCameraReferenceID,
                cameraID: sanitizedCameraID
            )
        }
    }

    public static func sanitize(cameras: [ProtectCameraRecord]) -> [ProtectCameraRecord] {
        cameras.enumerated().map { index, _ in
            let ordinal = index + 1
            let id = String(format: "camera-%03d", ordinal)
            let name = sanitizedCameraName(for: ordinal)
            return ProtectCameraRecord(id: id, displayName: name, name: name)
        }
    }

    private static func sanitizedCameraName(for ordinal: Int) -> String {
        let prefix = cameraLabelPrefixes[(ordinal - 1) % cameraLabelPrefixes.count]
        return "\(prefix) \(String(format: "%02d", ordinal))"
    }
}

public struct ProtectSchemaSnapshot: Codable, Sendable, Equatable {
    public let files: [ProtectSchemaSnapshotFile]

    public init(files: [ProtectSchemaSnapshotFile]) {
        self.files = files
    }

    public static func make(files: [(String, Data)]) throws -> ProtectSchemaSnapshot {
        let snapshotFiles = try files.map { fileName, data in
            let json = try JSONSerialization.jsonObject(with: data)
            return ProtectSchemaSnapshotFile.make(fileName: fileName, json: json)
        }
        return ProtectSchemaSnapshot(files: snapshotFiles)
    }
}

public struct ProtectSchemaSnapshotFile: Codable, Sendable, Equatable {
    public let fileName: String
    public let rootType: String
    public let paths: [ProtectSchemaSnapshotPath]

    static func make(fileName: String, json: Any) -> ProtectSchemaSnapshotFile {
        var entries: [String: ProtectSchemaSnapshotAccumulator] = [:]
        let sampleCount: Int

        if let array = json as? [Any] {
            sampleCount = max(1, array.count)
            for (sampleID, item) in array.enumerated() {
                collect(value: item, path: "[]", sampleID: sampleID, entries: &entries)
            }
            entries["$"] = ProtectSchemaSnapshotAccumulator(types: ["array"], sampleIDs: Set(array.indices))
        } else {
            sampleCount = 1
            collect(value: json, path: "$", sampleID: 0, entries: &entries)
        }

        let rootType = schemaTypeName(for: json)
        let paths = entries
            .map { path, accumulator in
                ProtectSchemaSnapshotPath(
                    path: path,
                    types: accumulator.types.sorted(),
                    presence: accumulator.sampleIDs.count == sampleCount ? "always" : "sometimes"
                )
            }
            .sorted { lhs, rhs in lhs.path < rhs.path }

        return ProtectSchemaSnapshotFile(fileName: fileName, rootType: rootType, paths: paths)
    }
}

public struct ProtectSchemaSnapshotPath: Codable, Sendable, Equatable {
    public let path: String
    public let types: [String]
    public let presence: String
}

private struct ProtectSchemaSnapshotAccumulator {
    var types: Set<String>
    var sampleIDs: Set<Int>
}

private func collect(
    value: Any,
    path: String,
    sampleID: Int,
    entries: inout [String: ProtectSchemaSnapshotAccumulator]
) {
    record(path: path, type: schemaTypeName(for: value), sampleID: sampleID, entries: &entries)

    switch value {
    case let dictionary as [String: Any]:
        for key in dictionary.keys.sorted() {
            guard let nestedValue = dictionary[key] else {
                continue
            }
            collect(value: nestedValue, path: "\(path).\(key)", sampleID: sampleID, entries: &entries)
        }
    case let array as [Any]:
        for item in array {
            collect(value: item, path: "\(path)[]", sampleID: sampleID, entries: &entries)
        }
    default:
        break
    }
}

private func record(
    path: String,
    type: String,
    sampleID: Int,
    entries: inout [String: ProtectSchemaSnapshotAccumulator]
) {
    var accumulator = entries[path] ?? ProtectSchemaSnapshotAccumulator(types: [], sampleIDs: [])
    accumulator.types.insert(type)
    accumulator.sampleIDs.insert(sampleID)
    entries[path] = accumulator
}

private func schemaTypeName(for value: Any) -> String {
    switch value {
    case is NSNull:
        return "null"
    case is [Any]:
        return "array"
    case is [String: Any]:
        return "object"
    case let number as NSNumber:
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return "bool"
        }
        return "number"
    case is String:
        return "string"
    default:
        return "unknown"
    }
}
