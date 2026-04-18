import ArgumentParser
import Foundation

public struct ProtectCadenceCLIIngestCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "ingest",
        abstract: "Initialize or ingest Protect events.",
        discussion: """
        Modes:
          no arguments               Interactive first-run setup when auth or DB path is missing
                                    After setup, bare ingest requires an explicit mode
          --last-hours <n>           Fetch a bounded recent window from Protect
          --event-json <file>        Replay one event object or an array of events from disk
        """
    )

    @OptionGroup var databaseOptions: ProtectCadenceDatabasePathOptions
    @OptionGroup var configOptions: ProtectCadenceConfigPathOptions
    @OptionGroup var authOverrides: ProtectCadenceAuthOverrideOptions
    @OptionGroup var outputOptions: ProtectCadenceOutputOptions

    @Option(name: .customLong("event-json"), help: "Replay one event object or an array of events from disk.")
    var eventJSONPath: String?

    @Option(name: .customLong("camera-json"), help: "Companion camera snapshot for replay.")
    var cameraJSONPath: String?

    @Option(name: .customLong("camera-name"), help: "Fallback camera name for replay.")
    var cameraName: String?

    @Option(name: .customLong("last-hours"), help: "Fetch a bounded recent window from Protect.")
    var lastHours: Int?

    @Option(
        name: .customLong("write-api-snapshot-dir"),
        help: "Save sanitized API snapshots during live ingest."
    )
    var snapshotDirectoryPath: String?

    public init() {}

    public mutating func run() async throws {
        try ProtectCadenceCLIPrinter.print(
            .ingest(try await ProtectCadenceIngestRunner.run(cli: try IngestCLI(command: self))),
            options: outputOptions
        )
    }
}
