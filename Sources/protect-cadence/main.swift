import Foundation
import ProtectCadenceCore

@main
enum ProtectCadenceCommandMain {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())

        if let help = ProtectCadenceHelp.text(for: arguments) {
            print(help)
            return
        }

        do {
            let output = try await ProtectCadenceCLIRunner.run(arguments: arguments)
            print(try JSONOutput.encode(output))
        } catch {
            fputs("error: \(error)\n", stderr)
            exit(1)
        }
    }
}
