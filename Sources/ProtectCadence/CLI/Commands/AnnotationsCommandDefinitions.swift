import ArgumentParser
import Foundation

public struct ProtectCadenceCLIAnnotationsCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "annotations",
        abstract: "Attach and list sidecar annotations.",
        subcommands: [
            ProtectCadenceCLIAnnotationsAddCommand.self,
            ProtectCadenceCLIAnnotationsListCommand.self,
            ProtectCadenceCLIAnnotationsKindsCommand.self,
            ProtectCadenceCLIAnnotationsTargetsCommand.self,
        ]
    )

    public init() {}
}

public struct ProtectCadenceCLIAnnotationsAddCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Attach an annotation to a target."
    )

    @OptionGroup var databaseOptions: ProtectCadenceDatabasePathOptions
    @OptionGroup var annotationsOptions: ProtectCadenceAnnotationsOptions
    @OptionGroup var configOptions: ProtectCadenceConfigPathOptions
    @OptionGroup var outputOptions: ProtectCadenceOutputOptions

    @Option(name: .customLong("target-kind"), help: "Target kind such as camera, event, episode, finding, zone, context, or window.")
    var targetKind: String

    @Option(name: .customLong("target-id"), help: "Target identifier following protect-cadence annotation conventions.")
    var targetID: String

    @Option(name: .customLong("body"), help: "Plain-English annotation body.")
    var body: String

    @Option(name: .customLong("source"), help: "Annotation source. Default human.")
    var source = "human"

    public init() {}

    public mutating func run() async throws {
        try ProtectCadenceCLIPrinter.print(
            .annotations(try ProtectCadenceAnnotationsRunner.run(cli: try AnnotationCLI(command: self))),
            options: outputOptions
        )
    }
}

public struct ProtectCadenceCLIAnnotationsListCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List annotations."
    )

    @OptionGroup var databaseOptions: ProtectCadenceDatabasePathOptions
    @OptionGroup var annotationsOptions: ProtectCadenceAnnotationsOptions
    @OptionGroup var configOptions: ProtectCadenceConfigPathOptions
    @OptionGroup var outputOptions: ProtectCadenceOutputOptions

    @Option(name: .customLong("target-kind"), help: "Optional target-kind filter.")
    var targetKind: String?

    @Option(name: .customLong("target-id"), help: "Optional target-id filter. Requires --target-kind.")
    var targetID: String?

    @Option(name: .customLong("limit"), help: "Maximum annotations to return. Default 50.")
    var limit = 50

    public init() {}

    public mutating func run() async throws {
        try ProtectCadenceCLIPrinter.print(
            .annotations(try ProtectCadenceAnnotationsRunner.run(cli: try AnnotationCLI(command: self))),
            options: outputOptions
        )
    }
}

public struct ProtectCadenceCLIAnnotationsKindsCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "kinds",
        abstract: "List supported annotation target kinds."
    )

    @OptionGroup var outputOptions: ProtectCadenceOutputOptions

    public init() {}

    public mutating func run() async throws {
        try ProtectCadenceCLIPrinter.print(
            .annotations(ProtectCadenceAnnotationsRunner.listKinds()),
            options: outputOptions
        )
    }
}

public struct ProtectCadenceCLIAnnotationsTargetsCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "targets",
        abstract: "List annotation target IDs currently used in the sidecar DB."
    )

    @OptionGroup var databaseOptions: ProtectCadenceDatabasePathOptions
    @OptionGroup var annotationsOptions: ProtectCadenceAnnotationsOptions
    @OptionGroup var configOptions: ProtectCadenceConfigPathOptions
    @OptionGroup var outputOptions: ProtectCadenceOutputOptions

    @Option(name: .customLong("kind"), help: "Optional target-kind filter.")
    var kind: String?

    @Option(name: .customLong("limit"), help: "Maximum targets to return. Default 50.")
    var limit = 50

    public init() {}

    public mutating func run() async throws {
        try ProtectCadenceCLIPrinter.print(
            .annotations(try ProtectCadenceAnnotationsRunner.run(cli: try AnnotationCLI(command: self))),
            options: outputOptions
        )
    }
}
