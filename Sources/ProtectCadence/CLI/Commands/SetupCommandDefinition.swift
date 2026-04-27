import ArgumentParser
import Foundation

public struct ProtectCadenceCLISetupCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Alias for `auth login` to configure saved Protect controller auth."
    )

    @OptionGroup var configOptions: ProtectCadenceConfigPathOptions
    @OptionGroup var authOverrides: ProtectCadenceAuthOverrideOptions
    @OptionGroup var outputOptions: ProtectCadenceOutputOptions

    public init() {}

    public mutating func run() async throws {
        let cli = AuthCLI(
            action: .login,
            overrides: ProtectAuthOverrides(
                controllerURL: authOverrides.controllerURL,
                username: authOverrides.username,
                password: authOverrides.password,
                allowInsecureTLS: authOverrides.allowInsecureTLS ? true : nil
            ),
            configPath: configOptions.configPath,
            force: false
        )
        try ProtectCadenceCLIPrinter.print(
            .auth(try ProtectCadenceAuthRunner.run(cli: cli)),
            options: outputOptions
        )
    }
}
