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
        camera = try container.decodeIfPresent(ProtectEventCameraPayload.self, forKey: .camera)
        cameraID = try container.decodeIfPresent(String.self, forKey: .cameraID)
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
        fallbackCameraName: String? = nil
    ) throws -> [EventRow] {
        guard let eventID = payload.eventID ?? payload.id else {
            throw ProtectEventNormalizationError.missingEventID
        }

        guard let timeStart = payload.detectedAt ?? payload.start else {
            throw ProtectEventNormalizationError.missingTimeStart
        }

        guard let camera = fallbackCameraName ?? payload.camera?.displayName ?? payload.camera?.name else {
            throw ProtectEventNormalizationError.missingCameraName
        }

        let kinds = normalizedKinds(from: payload)
        guard !kinds.isEmpty else {
            return []
        }

        return kinds.map { kind in
            EventRow(
                timeStart: timeStart,
                timeEnd: payload.end,
                camera: camera,
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
        if let milliseconds = try decodeIfPresent(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: milliseconds / 1000)
        }

        if let stringValue = try decodeIfPresent(String.self, forKey: key) {
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
