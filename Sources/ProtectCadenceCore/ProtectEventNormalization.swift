import Foundation

public struct ProtectEventPayload: Codable, Sendable {
    public let id: String?
    public let eventID: String?
    public let type: String?
    public let start: Date?
    public let end: Date?
    public let detectedAt: Date?
    public let smartDetectTypes: [String]
    public let camera: ProtectEventCameraPayload?
    public let cameraReferenceID: String?
    public let cameraID: String?

    public init(
        id: String? = nil,
        eventID: String? = nil,
        type: String? = nil,
        start: Date? = nil,
        end: Date? = nil,
        detectedAt: Date? = nil,
        smartDetectTypes: [String] = [],
        camera: ProtectEventCameraPayload? = nil,
        cameraReferenceID: String? = nil,
        cameraID: String? = nil
    ) {
        self.id = id
        self.eventID = eventID
        self.type = type
        self.start = start
        self.end = end
        self.detectedAt = detectedAt
        self.smartDetectTypes = smartDetectTypes
        self.camera = camera
        self.cameraReferenceID = cameraReferenceID
        self.cameraID = cameraID
    }

    enum CodingKeys: String, CodingKey {
        case id
        case eventID = "eventId"
        case type
        case start
        case end
        case detectedAt
        case smartDetectTypes
        case camera
        case cameraID = "cameraId"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(String.self, forKey: .id)
        eventID = try container.decodeIfPresent(String.self, forKey: .eventID)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        start = try container.decodeFlexibleDateIfPresent(forKey: .start)
        end = try container.decodeFlexibleDateIfPresent(forKey: .end)
        detectedAt = try container.decodeFlexibleDateIfPresent(forKey: .detectedAt)
        smartDetectTypes = try container.decodeIfPresent([String].self, forKey: .smartDetectTypes) ?? []
        if let cameraPayload = try? container.decodeIfPresent(ProtectEventCameraPayload.self, forKey: .camera) {
            camera = cameraPayload
            cameraReferenceID = nil
        } else if let cameraIDReference = try container.decodeIfPresent(String.self, forKey: .camera) {
            camera = nil
            cameraReferenceID = cameraIDReference
        } else {
            camera = nil
            cameraReferenceID = nil
        }
        cameraID = try container.decodeIfPresent(String.self, forKey: .cameraID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(eventID, forKey: .eventID)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(start, forKey: .start)
        try container.encodeIfPresent(end, forKey: .end)
        try container.encodeIfPresent(detectedAt, forKey: .detectedAt)
        try container.encode(smartDetectTypes, forKey: .smartDetectTypes)
        if let camera {
            try container.encode(camera, forKey: .camera)
        } else if let cameraReferenceID {
            try container.encode(cameraReferenceID, forKey: .camera)
        }
        try container.encodeIfPresent(cameraID, forKey: .cameraID)
    }

    public var currentCameraName: String? {
        camera?.displayName ?? camera?.name
    }

    public var cameraLookupKey: String? {
        cameraID ?? cameraReferenceID ?? camera?.id
    }

    public var isSettled: Bool {
        end != nil
    }
}

public struct ProtectEventCameraPayload: Codable, Sendable {
    public let id: String?
    public let displayName: String?
    public let name: String?

    public init(id: String? = nil, displayName: String? = nil, name: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.name = name
    }
}

public enum ProtectEventNormalizationError: Error, CustomStringConvertible {
    case missingEventID
    case missingTimeStart
    case missingCameraName

    public var description: String {
        switch self {
        case .missingEventID:
            return "Protect event payload is missing both eventId and id"
        case .missingTimeStart:
            return "Protect event payload is missing both detectedAt and start"
        case .missingCameraName:
            return "Protect event payload is missing camera name context"
        }
    }
}

public enum ProtectEventNormalizer {
    public static func normalize(
        _ payload: ProtectEventPayload,
        fallbackCameraName: String? = nil,
        fallbackCameraNamesByID: [String: String] = [:]
    ) throws -> [EventRow] {
        guard let eventID = payload.eventID ?? payload.id else {
            throw ProtectEventNormalizationError.missingEventID
        }

        guard let timeStart = payload.detectedAt ?? payload.start else {
            throw ProtectEventNormalizationError.missingTimeStart
        }

        guard let camera = fallbackCameraName
            ?? payload.currentCameraName
            ?? payload.cameraLookupKey.flatMap({ fallbackCameraNamesByID[$0] }) else {
            throw ProtectEventNormalizationError.missingCameraName
        }

        let cameraID = payload.cameraLookupKey

        let kinds = normalizedKinds(from: payload)
        guard !kinds.isEmpty else {
            return []
        }

        return kinds.map { kind in
            EventRow(
                timeStart: timeStart,
                timeEnd: payload.end,
                cameraID: cameraID,
                camera: camera,
                eventType: payload.type,
                kind: kind,
                eventID: eventID
            )
        }
    }

    static func normalizedKinds(from payload: ProtectEventPayload) -> [String] {
        let rawKinds: [String]

        if !payload.smartDetectTypes.isEmpty {
            rawKinds = payload.smartDetectTypes
        } else if let type = payload.type, isDirectKind(type) {
            rawKinds = [type]
        } else {
            rawKinds = []
        }

        var seen = Set<String>()
        var kinds: [String] = []

        for rawKind in rawKinds {
            let normalized = normalizeKind(rawKind)
            guard !normalized.isEmpty else {
                continue
            }
            guard seen.insert(normalized).inserted else {
                continue
            }
            kinds.append(normalized)
        }

        return kinds
    }

    private static func normalizeKind(_ rawKind: String) -> String {
        let trimmed = rawKind.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        switch trimmed {
        case "car":
            return "vehicle"
        case "pet":
            return "animal"
        default:
            return trimmed
        }
    }

    private static func isDirectKind(_ type: String) -> Bool {
        switch type {
        case "person", "animal", "vehicle", "package", "licensePlate", "face", "car", "pet":
            return true
        default:
            return type.hasPrefix("alrm")
        }
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleDateIfPresent(forKey key: Key) throws -> Date? {
        if let milliseconds = try? decodeIfPresent(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: milliseconds / 1000)
        }

        if let stringValue = try? decodeIfPresent(String.self, forKey: key) {
            if let milliseconds = Double(stringValue) {
                return Date(timeIntervalSince1970: milliseconds / 1000)
            }

            if let date = parseISO8601Date(stringValue) {
                return date
            }
        }

        return nil
    }

    private func parseISO8601Date(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let plainFormatter = ISO8601DateFormatter()
        plainFormatter.formatOptions = [.withInternetDateTime]
        return plainFormatter.date(from: value)
    }
}
