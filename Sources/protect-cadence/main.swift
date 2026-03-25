import Foundation
import ProtectCadenceCore

@main
enum ProtectCadenceCommandMain {
    static func main() async {
        do {
            let output = try await ProtectCadenceCLIRunner.run(arguments: Array(CommandLine.arguments.dropFirst()))
            print(try JSONOutput.encode(output))
        } catch {
            fputs("error: \(error)\n", stderr)
            exit(1)
        }
    }
}
