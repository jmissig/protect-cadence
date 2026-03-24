import Foundation
import ProtectCadenceCore

struct IngestStatus: Codable {
    let command: String
    let databasePath: String
    let status: String
    let detail: String
    let insertedRows: Int?
}

enum IngestCLIError: Error, CustomStringConvertible {
    case missingValue(String)

    var description: String {
        switch self {
        case let .missingValue(flag):
            return "missing value for \(flag)"
        }
    }
}

struct IngestCLI {
    let databasePath: String
    let eventJSONPath: String?
    let cameraName: String?

    init(arguments: [String]) throws {
        var remaining = arguments
        var databasePath = ProtectCadencePaths.makeDefault().databasePath
        var eventJSONPath: String?
        var cameraName: String?

        func popValue(for flag: String) throws -> String {
            guard let index = remaining.firstIndex(of: flag) else {
                throw IngestCLIError.missingValue(flag)
            }
            guard remaining.indices.contains(index + 1) else {
                throw IngestCLIError.missingValue(flag)
            }

            let value = remaining[index + 1]
            remaining.removeSubrange(index...(index + 1))
            return value
        }

        if remaining.contains("--db") {
            databasePath = try popValue(for: "--db")
        }

        if remaining.contains("--event-json") {
            eventJSONPath = try popValue(for: "--event-json")
        }

        if remaining.contains("--camera-name") {
            cameraName = try popValue(for: "--camera-name")
        }

        self.databasePath = databasePath
        self.eventJSONPath = eventJSONPath
        self.cameraName = cameraName
    }
}

do {
    let cli = try IngestCLI(arguments: Array(CommandLine.arguments.dropFirst()))
    let database = try ProtectCadenceDatabase(path: cli.databasePath)

    let status: IngestStatus

    if let eventJSONPath = cli.eventJSONPath {
        let data = try Data(contentsOf: URL(fileURLWithPath: eventJSONPath))
        let payload = try JSONDecoder().decode(ProtectEventPayload.self, from: data)
        let rows = try ProtectEventNormalizer.normalize(payload, fallbackCameraName: cli.cameraName)
        try database.insertIgnoringDuplicates(rows)

        status = IngestStatus(
            command: ProtectCadenceCommand.ingest.rawValue,
            databasePath: cli.databasePath,
            status: "ok",
            detail: "Normalized one Protect event payload into local event rows.",
            insertedRows: rows.count
        )
    } else {
        status = IngestStatus(
            command: ProtectCadenceCommand.ingest.rawValue,
            databasePath: cli.databasePath,
            status: "not_implemented",
            detail: "Database is initialized. Protect API ingestion is not implemented yet.",
            insertedRows: nil
        )
    }

    print(try JSONOutput.encode(status))
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
