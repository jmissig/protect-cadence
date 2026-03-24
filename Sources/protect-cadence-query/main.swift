import Foundation
import ProtectCadenceCore

do {
    let output = try ProtectCadenceQueryRunner.run(arguments: Array(CommandLine.arguments.dropFirst()))
    print(try JSONOutput.encode(output))
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
