import Foundation

enum ProtectCadenceCLIPrinter {
    static func print(
        _ output: ProtectCadenceCLIOutput,
        options: ProtectCadenceOutputOptions
    ) throws {
        Swift.print(try ProtectCadenceOutputRenderer.render(
            output: output,
            format: try options.resolvedFormat()
        ))
    }
}
