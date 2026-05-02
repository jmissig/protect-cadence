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
        case ["setup"]:
            return ProtectCadenceCLICommand.helpMessage(for: ProtectCadenceCLISetupCommand.self)
        case ["validate"]:
            return ProtectCadenceCLICommand.helpMessage(for: ProtectCadenceCLIValidateCommand.self)
        case ["query"]:
            return ProtectCadenceCLICommand.helpMessage(for: ProtectCadenceCLIQueryCommand.self)
        case ["model"]:
            return ProtectCadenceCLICommand.helpMessage(for: ProtectCadenceCLIModelCommand.self)
        case ["annotations"]:
            return ProtectCadenceCLICommand.helpMessage(for: ProtectCadenceCLIAnnotationsCommand.self)
        case ["annotations", "add"]:
            return ProtectCadenceCLICommand.helpMessage(for: ProtectCadenceCLIAnnotationsAddCommand.self)
        case ["annotations", "list"]:
            return ProtectCadenceCLICommand.helpMessage(for: ProtectCadenceCLIAnnotationsListCommand.self)
        case ["annotations", "kinds"]:
            return ProtectCadenceCLICommand.helpMessage(for: ProtectCadenceCLIAnnotationsKindsCommand.self)
        case ["annotations", "targets"]:
            return ProtectCadenceCLICommand.helpMessage(for: ProtectCadenceCLIAnnotationsTargetsCommand.self)
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
