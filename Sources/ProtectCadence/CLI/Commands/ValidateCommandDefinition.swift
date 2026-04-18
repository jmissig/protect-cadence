import ArgumentParser
import Foundation

public struct ProtectCadenceCLIValidateCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Fetch a recent controller sample and summarize ingest assumptions."
    )

    @OptionGroup var configOptions: ProtectCadenceConfigPathOptions
    @OptionGroup var authOverrides: ProtectCadenceAuthOverrideOptions
    @OptionGroup var outputOptions: ProtectCadenceOutputOptions

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
        try ProtectCadenceCLIPrinter.print(
            .validate(try await ProtectCadenceValidateRunner.run(cli: try ValidateCLI(command: self))),
            options: outputOptions
        )
    }
}
