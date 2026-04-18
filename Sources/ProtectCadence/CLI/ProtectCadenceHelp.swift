import Foundation

public enum ProtectCadenceHelp {
    public static func text(for arguments: [String]) -> String? {
        let normalizedArguments = normalize(arguments)

        switch normalizedArguments {
        case []:
            return ProtectCadenceCLICommand.helpMessage(for: ProtectCadenceCLICommand.self)
        case ["ingest"]:
            return ProtectCadenceCLICommand.helpMessage(for: ProtectCadenceCLIIngestCommand.self)
        case ["auth"]:
            return ProtectCadenceCLICommand.helpMessage(for: ProtectCadenceCLIAuthCommand.self)
        case ["validate"]:
            return ProtectCadenceCLICommand.helpMessage(for: ProtectCadenceCLIValidateCommand.self)
        case ["query"]:
            return ProtectCadenceCLICommand.helpMessage(for: ProtectCadenceCLIQueryCommand.self)
        case ["model"]:
            return ProtectCadenceCLICommand.helpMessage(for: ProtectCadenceCLIModelCommand.self)
        case ["model", "rebuild"]:
            return ProtectCadenceCLICommand.helpMessage(for: ProtectCadenceCLIModelRebuildCommand.self)
        case ["model", "episodes"]:
            return ProtectCadenceCLICommand.helpMessage(for: ProtectCadenceCLIModelEpisodesCommand.self)
        case ["model", "findings"]:
            return ProtectCadenceCLICommand.helpMessage(for: ProtectCadenceCLIModelFindingsCommand.self)
        case ["query", "events"]:
            return ProtectCadenceCLICommand.helpMessage(for: ProtectCadenceCLIQueryEventsCommand.self)
        case ["query", "summary"]:
            return ProtectCadenceCLICommand.helpMessage(for: ProtectCadenceCLIQuerySummaryCommand.self)
        case ["query", "compare"]:
            return ProtectCadenceCLICommand.helpMessage(for: ProtectCadenceCLIQueryCompareCommand.self)
        default:
            return nil
        }
    }

    private static func normalize(_ arguments: [String]) -> [String] {
        var normalized = arguments
        if normalized.first == "help" {
            normalized.removeFirst()
        }
        normalized.removeAll { $0 == "--help" || $0 == "-h" }
        return normalized
    }
}
