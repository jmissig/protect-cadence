import Foundation
import GRDB

public struct Annotation: Codable, Sendable, Equatable {
    public let id: Int64
    public let account: String
    public let targetKind: String
    public let targetID: String
    public let body: String
    public let source: String
    public let createdAtISO8601: String
    public let updatedAtISO8601: String
}

public struct AnnotationTarget: Codable, Sendable, Equatable {
    public let kind: String?
    public let id: String?
}

public struct AnnotationTargetUsage: Codable, Sendable, Equatable {
    public let kind: String
    public let id: String
    public let annotationCount: Int
    public let lastUpdatedAtISO8601: String?
}

public struct ListAnnotationKindsResponse: Codable, Sendable, Equatable {
    public let command: String
    public let kinds: [String]
}

public struct ListAnnotationTargetsResponse: Codable, Sendable, Equatable {
    public let command: String
    public let account: String
    public let annotationsDatabasePath: String
    public let kind: String?
    public let totalMatchingTargets: Int
    public let returnedTargets: Int
    public let targets: [AnnotationTargetUsage]
}

public struct AddAnnotationResponse: Codable, Sendable, Equatable {
    public let command: String
    public let account: String
    public let annotationsDatabasePath: String
    public let annotation: Annotation
}

public struct ListAnnotationsResponse: Codable, Sendable, Equatable {
    public let command: String
    public let account: String
    public let annotationsDatabasePath: String
    public let target: AnnotationTarget
    public let totalMatchingAnnotations: Int
    public let returnedAnnotations: Int
    public let annotations: [Annotation]
}

public enum AnnotationCommandOutput: Encodable, Sendable {
    case kinds(ListAnnotationKindsResponse)
    case targets(ListAnnotationTargetsResponse)
    case add(AddAnnotationResponse)
    case list(ListAnnotationsResponse)

    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .kinds(response): try response.encode(to: encoder)
        case let .targets(response): try response.encode(to: encoder)
        case let .add(response): try response.encode(to: encoder)
        case let .list(response): try response.encode(to: encoder)
        }
    }
}

public struct AnnotationLookupTarget: Hashable, Sendable {
    public let kind: String
    public let id: String

    public init(kind: String, id: String) {
        self.kind = kind
        self.id = id
    }
}

public enum AnnotationError: Error, CustomStringConvertible {
    case missingSubcommand
    case unknownSubcommand(String)
    case invalidTargetKind(String)
    case missingTargetID
    case emptyField(String)
    case invalidPositiveInteger(flag: String, value: String)

    public var description: String {
        switch self {
        case .missingSubcommand:
            return "expected a subcommand such as 'add', 'list', 'kinds', or 'targets'"
        case let .unknownSubcommand(subcommand):
            return "unknown annotations subcommand '\(subcommand)'"
        case let .invalidTargetKind(kind):
            return "unsupported annotation target kind '\(kind)'; run `protect-cadence annotations kinds`"
        case .missingTargetID:
            return "--target-id requires --target-kind"
        case let .emptyField(field):
            return "\(field) must not be empty"
        case let .invalidPositiveInteger(flag, value):
            return "\(flag) must be greater than zero, got '\(value)'"
        }
    }
}

public enum AnnotationTargetKind: String, Codable, Sendable, CaseIterable {
    case camera
    case event
    case episode
    case finding
    case zone
    case context
    case window
}

public enum ProtectCadenceAnnotationsDatabasePathResolver {
    public static func resolve(
        explicitOverride: String?,
        evidenceDatabasePath: String?,
        configPath: String
    ) throws -> String {
        if let explicitOverride, !explicitOverride.isEmpty {
            return explicitOverride
        }

        if let evidenceDatabasePath, !evidenceDatabasePath.isEmpty {
            return siblingPath(for: evidenceDatabasePath)
        }

        let evidencePath = try ProtectCadenceDatabasePathResolver.resolve(
            explicitOverride: nil,
            configPath: configPath
        )
        return siblingPath(for: evidencePath)
    }

    private static func siblingPath(for evidenceDatabasePath: String) -> String {
        let url = URL(fileURLWithPath: evidenceDatabasePath)
        let directoryURL = url.deletingLastPathComponent()
        let fileExtension = url.pathExtension
        let baseName = url.deletingPathExtension().lastPathComponent
        let fileName = fileExtension.isEmpty
            ? "\(baseName)-annotations.sqlite"
            : "\(baseName)-annotations.\(fileExtension)"
        return directoryURL.appendingPathComponent(fileName).path
    }
}

public final class ProtectCadenceAnnotationsDatabase: @unchecked Sendable {
    private let dbQueue: DatabaseQueue
    public let path: String

    public init(path: String) throws {
        self.path = path
        dbQueue = try DatabaseQueue(path: path)
    }

    public static func listKinds() -> ListAnnotationKindsResponse {
        ListAnnotationKindsResponse(
            command: "annotations kinds",
            kinds: AnnotationTargetKind.allCases.map(\.rawValue).sorted()
        )
    }

    public func add(
        account: String,
        targetKind: String,
        targetID: String,
        body: String,
        source: String = "human",
        now: Date = Date()
    ) throws -> AddAnnotationResponse {
        let account = try Self.validateField(account, name: "--account")
        let targetKind = try Self.validateTargetKind(targetKind)
        let targetID = try Self.validateField(targetID, name: "--target-id")
        let body = try Self.validateField(body, name: "--body")
        let source = try Self.validateField(source, name: "--source")
        let timestamp = Self.timestamp(now)
        try migrate()

        return try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO annotations (
                        account, target_kind, target_id, body, source, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [account, targetKind, targetID, body, source, timestamp, timestamp]
            )
            let annotation = try Self.fetchAnnotation(db: db, id: db.lastInsertedRowID)
            return AddAnnotationResponse(
                command: "annotations add",
                account: account,
                annotationsDatabasePath: path,
                annotation: annotation
            )
        }
    }

    public func listTargets(account: String, kind: String? = nil, limit: Int = 50) throws -> ListAnnotationTargetsResponse {
        let account = try Self.validateField(account, name: "--account")
        let kind = try kind.map(Self.validateTargetKind)
        let limit = try Self.validateLimit(limit)

        return try readIfPresent(
            empty: ListAnnotationTargetsResponse(
                command: "annotations targets",
                account: account,
                annotationsDatabasePath: path,
                kind: kind,
                totalMatchingTargets: 0,
                returnedTargets: 0,
                targets: []
            )
        ) { db in
            let total = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM (
                        SELECT target_kind, target_id
                        FROM annotations
                        WHERE account = ?
                          AND (? IS NULL OR target_kind = ?)
                        GROUP BY target_kind, target_id
                    )
                    """,
                arguments: [account, kind, kind]
            ) ?? 0

            let targets = try Row.fetchAll(
                db,
                sql: """
                    SELECT target_kind, target_id, COUNT(*) AS annotation_count, MAX(updated_at) AS last_updated_at
                    FROM annotations
                    WHERE account = ?
                      AND (? IS NULL OR target_kind = ?)
                    GROUP BY target_kind, target_id
                    ORDER BY last_updated_at DESC, target_kind ASC, target_id ASC
                    LIMIT ?
                    """,
                arguments: [account, kind, kind, limit]
            ).map { row in
                AnnotationTargetUsage(
                    kind: row["target_kind"],
                    id: row["target_id"],
                    annotationCount: row["annotation_count"],
                    lastUpdatedAtISO8601: row["last_updated_at"]
                )
            }

            return ListAnnotationTargetsResponse(
                command: "annotations targets",
                account: account,
                annotationsDatabasePath: path,
                kind: kind,
                totalMatchingTargets: total,
                returnedTargets: targets.count,
                targets: targets
            )
        }
    }

    public func list(
        account: String,
        targetKind: String? = nil,
        targetID: String? = nil,
        limit: Int = 50
    ) throws -> ListAnnotationsResponse {
        let account = try Self.validateField(account, name: "--account")
        let targetKind = try targetKind.map(Self.validateTargetKind)
        if targetKind == nil, targetID != nil { throw AnnotationError.missingTargetID }
        let targetID = try targetID.map { try Self.validateField($0, name: "--target-id") }
        let limit = try Self.validateLimit(limit)
        let target = AnnotationTarget(kind: targetKind, id: targetID)

        return try readIfPresent(
            empty: ListAnnotationsResponse(
                command: "annotations list",
                account: account,
                annotationsDatabasePath: path,
                target: target,
                totalMatchingAnnotations: 0,
                returnedAnnotations: 0,
                annotations: []
            )
        ) { db in
            let total = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*)
                    FROM annotations
                    WHERE account = ?
                      AND (? IS NULL OR target_kind = ?)
                      AND (? IS NULL OR target_id = ?)
                    """,
                arguments: [account, targetKind, targetKind, targetID, targetID]
            ) ?? 0
            let annotations = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, account, target_kind, target_id, body, source, created_at, updated_at
                    FROM annotations
                    WHERE account = ?
                      AND (? IS NULL OR target_kind = ?)
                      AND (? IS NULL OR target_id = ?)
                    ORDER BY updated_at DESC, id DESC
                    LIMIT ?
                    """,
                arguments: [account, targetKind, targetKind, targetID, targetID, limit]
            ).map(Self.annotation(row:))

            return ListAnnotationsResponse(
                command: "annotations list",
                account: account,
                annotationsDatabasePath: path,
                target: target,
                totalMatchingAnnotations: total,
                returnedAnnotations: annotations.count,
                annotations: annotations
            )
        }
    }

    public func fetch(account: String, targets: Set<AnnotationLookupTarget>) throws -> [AnnotationLookupTarget: [Annotation]] {
        guard !targets.isEmpty else { return [:] }
        let account = try Self.validateField(account, name: "--account")
        guard FileManager.default.fileExists(atPath: path) else { return [:] }

        return try dbQueue.read { db in
            guard try db.tableExists("annotations") else { return [:] }
            var result: [AnnotationLookupTarget: [Annotation]] = [:]
            for target in targets.sorted(by: { ($0.kind, $0.id) < ($1.kind, $1.id) }) {
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT id, account, target_kind, target_id, body, source, created_at, updated_at
                        FROM annotations
                        WHERE account = ? AND target_kind = ? AND target_id = ?
                        ORDER BY updated_at DESC, id DESC
                        """,
                    arguments: [account, target.kind, target.id]
                )
                let annotations = rows.map(Self.annotation(row:))
                if !annotations.isEmpty { result[target] = annotations }
            }
            return result
        }
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_annotations") { db in
            try db.execute(sql: """
                CREATE TABLE annotations (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    account TEXT NOT NULL,
                    target_kind TEXT NOT NULL,
                    target_id TEXT NOT NULL,
                    body TEXT NOT NULL,
                    source TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                CREATE INDEX idx_annotations_account_target ON annotations(account, target_kind, target_id);
                CREATE INDEX idx_annotations_account_updated_at ON annotations(account, updated_at);
                """)
        }
        try migrator.migrate(dbQueue)
    }

    private func readIfPresent<T>(empty: T, _ block: (Database) throws -> T) throws -> T {
        guard FileManager.default.fileExists(atPath: path) else { return empty }
        return try dbQueue.read { db in
            guard try db.tableExists("annotations") else { return empty }
            return try block(db)
        }
    }

    private static func fetchAnnotation(db: Database, id: Int64) throws -> Annotation {
        let row = try Row.fetchOne(
            db,
            sql: """
                SELECT id, account, target_kind, target_id, body, source, created_at, updated_at
                FROM annotations
                WHERE id = ?
                """,
            arguments: [id]
        )!
        return annotation(row: row)
    }

    private static func annotation(row: Row) -> Annotation {
        Annotation(
            id: row["id"],
            account: row["account"],
            targetKind: row["target_kind"],
            targetID: row["target_id"],
            body: row["body"],
            source: row["source"],
            createdAtISO8601: row["created_at"],
            updatedAtISO8601: row["updated_at"]
        )
    }

    private static func validateTargetKind(_ value: String) throws -> String {
        guard let kind = AnnotationTargetKind(rawValue: value) else {
            throw AnnotationError.invalidTargetKind(value)
        }
        return kind.rawValue
    }

    private static func validateField(_ value: String, name: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AnnotationError.emptyField(name) }
        return trimmed
    }

    private static func validateLimit(_ value: Int) throws -> Int {
        guard value > 0 else {
            throw AnnotationError.invalidPositiveInteger(flag: "--limit", value: String(value))
        }
        return value
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

public enum AnnotationTargetFactory {
    public static func cameraTargets(camera: String, cameraID: String?) -> [AnnotationLookupTarget] {
        var targets: [AnnotationLookupTarget] = [AnnotationLookupTarget(kind: AnnotationTargetKind.camera.rawValue, id: "name:\(camera)")]
        if let cameraID, !cameraID.isEmpty {
            targets.insert(AnnotationLookupTarget(kind: AnnotationTargetKind.camera.rawValue, id: "id:\(cameraID)"), at: 0)
        }
        return targets
    }

    public static func eventTarget(eventID: String, kind: String) -> AnnotationLookupTarget {
        AnnotationLookupTarget(kind: AnnotationTargetKind.event.rawValue, id: "event_id:\(eventID)#kind:\(kind)")
    }

    public static func episodeTarget(runID: Int64, episodeID: Int64) -> AnnotationLookupTarget {
        AnnotationLookupTarget(kind: AnnotationTargetKind.episode.rawValue, id: "run:\(runID)/episode:\(episodeID)")
    }

    public static func findingTarget(runID: Int64, findingID: Int64) -> AnnotationLookupTarget {
        AnnotationLookupTarget(kind: AnnotationTargetKind.finding.rawValue, id: "run:\(runID)/finding:\(findingID)")
    }
}
