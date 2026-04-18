import ArgumentParser
import Foundation

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
    @OptionGroup var outputOptions: ProtectCadenceOutputOptions

    public init() {}

    public mutating func run() async throws {
        try ProtectCadenceCLIPrinter.print(
            .model(try ProtectCadenceModelRunner.run(cli: try ModelCLI(command: self))),
            options: outputOptions
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
    @OptionGroup var outputOptions: ProtectCadenceOutputOptions

    @Option(name: .customLong("limit"), help: "Maximum episodes to return. Default 50.")
    var limit = 50

    @Option(name: .customLong("order"), help: "Episode order: newest or oldest.")
    var order = "newest"

    public init() {}

    public mutating func run() async throws {
        try ProtectCadenceCLIPrinter.print(
            .model(try ProtectCadenceModelRunner.run(cli: try ModelCLI(command: self))),
            options: outputOptions
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
    @OptionGroup var outputOptions: ProtectCadenceOutputOptions

    @Option(
        name: .customLong("finding-type"),
        help: "Repeatable finding-type filter: unexpected_presence, unexpected_transition, or unusual_duration."
    )
    var findingTypes: [String] = []

    @Option(name: .customLong("limit"), help: "Maximum findings to return. Default 50.")
    var limit = 50

    public init() {}

    public mutating func run() async throws {
        try ProtectCadenceCLIPrinter.print(
            .model(try ProtectCadenceModelRunner.run(cli: try ModelCLI(command: self))),
            options: outputOptions
        )
    }
}
