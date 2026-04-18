import ArgumentParser
import Foundation

public struct ProtectCadenceCLIAuthCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "auth",
        abstract: "Manage saved Protect controller auth."
    )

    @Argument(help: "Auth action: status, login, or clear.")
    var action: String?

    @OptionGroup var configOptions: ProtectCadenceConfigPathOptions
    @OptionGroup var authOverrides: ProtectCadenceAuthOverrideOptions
    @OptionGroup var outputOptions: ProtectCadenceOutputOptions

    @Flag(name: .customLong("force"), help: "Skip confirmation for clear.")
    var force = false

    public init() {}

    public mutating func run() async throws {
        try ProtectCadenceCLIPrinter.print(
            .auth(try ProtectCadenceAuthRunner.run(cli: try AuthCLI(command: self))),
            options: outputOptions
        )
    }
}
