import ArgumentParser
import Foundation

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

public struct ProtectCadenceCLIQueryEventsCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "events",
        abstract: "Read filtered normalized event rows."
    )

    @OptionGroup var databaseOptions: ProtectCadenceDatabasePathOptions
    @OptionGroup var configOptions: ProtectCadenceConfigPathOptions
    @OptionGroup var primaryWindow: ProtectCadencePrimaryWindowOptions
    @OptionGroup var filters: ProtectCadenceQueryFilterOptions
    @OptionGroup var annotationsOptions: ProtectCadenceAnnotationsOptions
    @OptionGroup var outputOptions: ProtectCadenceOutputOptions

    @Option(name: .customLong("limit"), help: "Row limit. Default 50.")
    var limit = 50

    @Option(name: .customLong("order"), help: "Row order: newest or oldest.")
    var order = "newest"

    public init() {}

    public mutating func run() async throws {
        try ProtectCadenceCLIPrinter.print(
            .query(try ProtectCadenceQueryRunner.run(cli: try QueryCLI(command: self))),
            options: outputOptions
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
    @OptionGroup var annotationsOptions: ProtectCadenceAnnotationsOptions
    @OptionGroup var outputOptions: ProtectCadenceOutputOptions

    @Option(name: .customLong("group-by"), help: "Repeatable grouping: camera, kind, date, hour, or weekday.")
    var groupBy: [String] = []

    public init() {}

    public mutating func run() async throws {
        try ProtectCadenceCLIPrinter.print(
            .query(try ProtectCadenceQueryRunner.run(cli: try QueryCLI(command: self))),
            options: outputOptions
        )
    }
}

public struct ProtectCadenceCLIQueryCompareCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "compare",
        abstract: "Compare a primary time window with one or more peer windows using shared filters."
    )

    @OptionGroup var databaseOptions: ProtectCadenceDatabasePathOptions
    @OptionGroup var configOptions: ProtectCadenceConfigPathOptions
    @OptionGroup var primaryWindow: ProtectCadencePrimaryWindowOptions
    @OptionGroup var filters: ProtectCadenceQueryFilterOptions
    @OptionGroup var compareMode: ProtectCadenceCompareModeOptions
    @OptionGroup var annotationsOptions: ProtectCadenceAnnotationsOptions
    @OptionGroup var outputOptions: ProtectCadenceOutputOptions

    @Option(name: .customLong("group-by"), help: "Repeatable grouping: camera, kind, date, hour, or weekday.")
    var groupBy: [String] = []

    public init() {}

    public mutating func run() async throws {
        try ProtectCadenceCLIPrinter.print(
            .query(try ProtectCadenceQueryRunner.run(cli: try QueryCLI(command: self))),
            options: outputOptions
        )
    }
}
