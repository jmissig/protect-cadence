import ArgumentParser
import Foundation

private enum ProtectCadenceCLIPrinter {
    static func printJSON<T: Encodable>(_ value: T) throws {
        print(try JSONOutput.encode(value))
    }
}

struct ProtectCadenceConfigPathOptions: ParsableArguments {
    @Option(
        name: .customLong("config"),
        help: "Override config file path."
    )
    var configPath = ProtectCadencePaths.defaultConfigPath()
}

struct ProtectCadenceDatabasePathOptions: ParsableArguments {
    @Option(
        name: .customLong("db"),
        help: "Override SQLite path for this run."
    )
    var databasePathOverride: String?
}

struct ProtectCadenceModelDatabasePathOptions: ParsableArguments {
    @Option(
        name: .customLong("model-db"),
        help: "Override where the cadence-pattern model is stored for this run."
    )
    var modelDatabasePathOverride: String?
}

struct ProtectCadenceAuthOverrideOptions: ParsableArguments {
    @Option(
        name: .customLong("controller-url"),
        help: "Override Protect controller URL."
    )
    var controllerURL: String?

    @Option(
        name: .customLong("username"),
        help: "Override Protect username."
    )
    var username: String?

    @Option(
        name: .customLong("password"),
        help: "Override Protect password."
    )
    var password: String?

    @Flag(
        name: .customLong("allow-insecure-tls"),
        help: "Disable TLS certificate verification."
    )
    var allowInsecureTLS = false
}

struct ProtectCadencePrimaryWindowOptions: ParsableArguments {
    @Option(
        name: .customLong("since"),
        help: "Inclusive lower bound. Accepts ISO 8601 with offset/Z or local YYYY-MM-DD[ T]HH:MM[:SS]."
    )
    var since: String?

    @Option(
        name: .customLong("until"),
        help: "Exclusive upper bound. Requires --since."
    )
    var until: String?

    @Option(
        name: .customLong("last-hours"),
        help: "Recent window ending now."
    )
    var lastHours: Int?
}

struct ProtectCadenceQueryFilterOptions: ParsableArguments {
    @Option(
        name: .customLong("camera"),
        help: "Repeatable display-name filter."
    )
    var cameras: [String] = []

    @Option(
        name: .customLong("kind"),
        help: "Repeatable kind filter."
    )
    var kinds: [String] = []

    @Option(
        name: .customLong("day-of-week"),
        help: "Repeatable local weekday filter."
    )
    var dayOfWeek: [String] = []

    @Flag(
        name: .customLong("weekday"),
        help: "Include Monday through Friday."
    )
    var weekday = false

    @Flag(
        name: .customLong("weekend"),
        help: "Include Saturday and Sunday."
    )
    var weekend = false

    @Option(
        name: .customLong("date"),
        help: "Exact local calendar-date bucket filter."
    )
    var date: String?

    @Option(
        name: .customLong("hour"),
        help: "Exact local hour bucket filter."
    )
    var hour: String?

    @Option(
        name: .customLong("time-of-day"),
        help: "Local time-of-day filter, including overnight ranges."
    )
    var timeOfDay: String?
}

struct ProtectCadenceCompareModeOptions: ParsableArguments {
    @Option(
        name: .customLong("vs-since"),
        help: "Explicit comparison window lower bound."
    )
    var since: String?

    @Option(
        name: .customLong("vs-until"),
        help: "Explicit comparison window upper bound."
    )
    var until: String?

    @Option(
        name: .customLong("vs-window-before"),
        help: "Use an equal-duration comparison window ending at this time."
    )
    var windowBefore: String?

    @Option(
        name: .customLong("vs-window-after"),
        help: "Use an equal-duration comparison window starting at this time."
    )
    var windowAfter: String?

    @Flag(
        name: .customLong("vs-same-window-yesterday"),
        help: "Shift the primary window back by one local day."
    )
    var sameWindowYesterday = false

    @Flag(
        name: .customLong("vs-same-window-last-week"),
        help: "Shift the primary window back by seven local days."
    )
    var sameWindowLastWeek = false

    @Flag(
        name: .customLong("vs-prior-window"),
        help: "Use the immediately preceding equal-duration window."
    )
    var priorWindow = false
}

struct ProtectCadenceModelFilterOptions: ParsableArguments {
    @Option(
        name: .customLong("camera"),
        help: "Repeatable episode camera filter."
    )
    var cameras: [String] = []

    @Option(
        name: .customLong("kind"),
        help: "Repeatable primary-kind filter."
    )
    var kinds: [String] = []

    @Option(
        name: .customLong("state-key"),
        help: "Repeatable state-key filter."
    )
    var stateKeys: [String] = []
}

public struct ProtectCadenceCLICommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "protect-cadence",
        abstract: "Turn UniFi Protect detections into a small local event store.",
        discussion: """
        Treat cameras as sensors, not as a dashboard surface.

        Examples:
          protect-cadence ingest --last-hours 6
          protect-cadence query events --last-hours 2 --camera Driveway
          protect-cadence query compare --last-hours 1 --vs-prior-window
          protect-cadence model rebuild
          protect-cadence model findings --finding-type unexpected_presence
          protect-cadence model findings --finding-type unexpected_transition
        """,
        subcommands: [
            ProtectCadenceCLIIngestCommand.self,
            ProtectCadenceCLIQueryCommand.self,
            ProtectCadenceCLIModelCommand.self,
            ProtectCadenceCLIAuthCommand.self,
            ProtectCadenceCLIValidateCommand.self,
        ]
    )

    public init() {}
}

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
        try ProtectCadenceCLIPrinter.printJSON(
            try await ProtectCadenceIngestRunner.run(cli: try IngestCLI(command: self))
        )
    }
}

public struct ProtectCadenceCLIAuthCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "auth",
        abstract: "Manage saved Protect controller auth."
    )

    @Argument(help: "Auth action: status, login, or clear.")
    var action: String?

    @OptionGroup var configOptions: ProtectCadenceConfigPathOptions
    @OptionGroup var authOverrides: ProtectCadenceAuthOverrideOptions

    @Flag(name: .customLong("force"), help: "Skip confirmation for clear.")
    var force = false

    public init() {}

    public mutating func run() async throws {
        try ProtectCadenceCLIPrinter.printJSON(
            try ProtectCadenceAuthRunner.run(cli: try AuthCLI(command: self))
        )
    }
}

public struct ProtectCadenceCLIValidateCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Fetch a recent controller sample and summarize ingest assumptions."
    )

    @OptionGroup var configOptions: ProtectCadenceConfigPathOptions
    @OptionGroup var authOverrides: ProtectCadenceAuthOverrideOptions

    @Option(name: .customLong("last-hours"), help: "Recent sample window ending now. Default 6.")
    var lastHours = 6

    @Option(name: .customLong("sample-limit"), help: "Example rows to include per section. Default 10.")
    var sampleLimit = 10

    @Option(
        name: .customLong("write-api-snapshot-dir"),
        help: "Save a sanitized snapshot of the fetched sample."
    )
    var snapshotDirectoryPath: String?

    public init() {}

    public mutating func run() async throws {
        try ProtectCadenceCLIPrinter.printJSON(
            try await ProtectCadenceValidateRunner.run(cli: try ValidateCLI(command: self))
        )
    }
}

public struct ProtectCadenceCLIQueryCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "query",
        abstract: "Read events or grouped summaries from SQLite.",
        subcommands: [
            ProtectCadenceCLIQueryEventsCommand.self,
            ProtectCadenceCLIQuerySummaryCommand.self,
            ProtectCadenceCLIQueryCompareCommand.self,
        ]
    )

    public init() {}
}

public struct ProtectCadenceCLIModelCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "model",
        abstract: "Build and inspect a model of event cadence patterns.",
        discussion: """
        Use this to summarize what tends to happen on each camera, then inspect modeled episodes or attention findings that may deserve a closer look.

        Examples:
          protect-cadence model rebuild
          protect-cadence model findings --last-hours 24
          protect-cadence model episodes --camera Driveway --since 2026-04-14T00:00:00Z
        """,
        subcommands: [
            ProtectCadenceCLIModelRebuildCommand.self,
            ProtectCadenceCLIModelEpisodesCommand.self,
            ProtectCadenceCLIModelFindingsCommand.self,
        ]
    )

    public init() {}
}

public struct ProtectCadenceCLIModelRebuildCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "rebuild",
        abstract: "Rebuild the event-cadence model from the evidence database."
    )

    @OptionGroup var databaseOptions: ProtectCadenceDatabasePathOptions
    @OptionGroup var modelDatabaseOptions: ProtectCadenceModelDatabasePathOptions
    @OptionGroup var configOptions: ProtectCadenceConfigPathOptions

    public init() {}

    public mutating func run() async throws {
        try ProtectCadenceCLIPrinter.printJSON(
            try ProtectCadenceModelRunner.run(cli: try ModelCLI(command: self))
        )
    }
}

public struct ProtectCadenceCLIModelEpisodesCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "episodes",
        abstract: "Inspect modeled detection episodes from the cadence patterns model."
    )

    @OptionGroup var databaseOptions: ProtectCadenceDatabasePathOptions
    @OptionGroup var modelDatabaseOptions: ProtectCadenceModelDatabasePathOptions
    @OptionGroup var configOptions: ProtectCadenceConfigPathOptions
    @OptionGroup var primaryWindow: ProtectCadencePrimaryWindowOptions
    @OptionGroup var filters: ProtectCadenceModelFilterOptions

    @Option(name: .customLong("limit"), help: "Maximum episodes to return. Default 50.")
    var limit = 50

    @Option(name: .customLong("order"), help: "Episode order: newest or oldest.")
    var order = "newest"

    public init() {}

    public mutating func run() async throws {
        try ProtectCadenceCLIPrinter.printJSON(
            try ProtectCadenceModelRunner.run(cli: try ModelCLI(command: self))
        )
    }
}

public struct ProtectCadenceCLIModelFindingsCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "findings",
        abstract: "Inspect attention findings from the cadence patterns model."
    )

    @OptionGroup var databaseOptions: ProtectCadenceDatabasePathOptions
    @OptionGroup var modelDatabaseOptions: ProtectCadenceModelDatabasePathOptions
    @OptionGroup var configOptions: ProtectCadenceConfigPathOptions
    @OptionGroup var primaryWindow: ProtectCadencePrimaryWindowOptions
    @OptionGroup var filters: ProtectCadenceModelFilterOptions

    @Option(
        name: .customLong("finding-type"),
        help: "Repeatable finding-type filter: unexpected_presence, unexpected_transition, or unusual_duration."
    )
    var findingTypes: [String] = []

    @Option(name: .customLong("limit"), help: "Maximum findings to return. Default 50.")
    var limit = 50

    public init() {}

    public mutating func run() async throws {
        try ProtectCadenceCLIPrinter.printJSON(
            try ProtectCadenceModelRunner.run(cli: try ModelCLI(command: self))
        )
    }
}

public struct ProtectCadenceCLIQueryEventsCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "events",
        abstract: "Read filtered normalized event rows."
    )

    @OptionGroup var databaseOptions: ProtectCadenceDatabasePathOptions
    @OptionGroup var configOptions: ProtectCadenceConfigPathOptions
    @OptionGroup var primaryWindow: ProtectCadencePrimaryWindowOptions
    @OptionGroup var filters: ProtectCadenceQueryFilterOptions

    @Option(name: .customLong("limit"), help: "Row limit. Default 50.")
    var limit = 50

    @Option(name: .customLong("order"), help: "Row order: newest or oldest.")
    var order = "newest"

    public init() {}

    public mutating func run() async throws {
        try ProtectCadenceCLIPrinter.printJSON(
            try ProtectCadenceQueryRunner.run(cli: try QueryCLI(command: self))
        )
    }
}

public struct ProtectCadenceCLIQuerySummaryCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "summary",
        abstract: "Read grouped event counts."
    )

    @OptionGroup var databaseOptions: ProtectCadenceDatabasePathOptions
    @OptionGroup var configOptions: ProtectCadenceConfigPathOptions
    @OptionGroup var primaryWindow: ProtectCadencePrimaryWindowOptions
    @OptionGroup var filters: ProtectCadenceQueryFilterOptions

    @Option(name: .customLong("group-by"), help: "Repeatable grouping: camera, kind, date, hour, or weekday.")
    var groupBy: [String] = []

    public init() {}

    public mutating func run() async throws {
        try ProtectCadenceCLIPrinter.printJSON(
            try ProtectCadenceQueryRunner.run(cli: try QueryCLI(command: self))
        )
    }
}

public struct ProtectCadenceCLIQueryCompareCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "compare",
        abstract: "Compare two time windows using shared filters."
    )

    @OptionGroup var databaseOptions: ProtectCadenceDatabasePathOptions
    @OptionGroup var configOptions: ProtectCadenceConfigPathOptions
    @OptionGroup var primaryWindow: ProtectCadencePrimaryWindowOptions
    @OptionGroup var filters: ProtectCadenceQueryFilterOptions
    @OptionGroup var compareMode: ProtectCadenceCompareModeOptions

    @Option(name: .customLong("group-by"), help: "Repeatable grouping: camera, kind, date, hour, or weekday.")
    var groupBy: [String] = []

    public init() {}

    public mutating func run() async throws {
        try ProtectCadenceCLIPrinter.printJSON(
            try ProtectCadenceQueryRunner.run(cli: try QueryCLI(command: self))
        )
    }
}
