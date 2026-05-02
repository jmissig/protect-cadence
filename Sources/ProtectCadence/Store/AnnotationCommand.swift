import Foundation

public enum AnnotationSubcommand: String, Sendable {
    case add
    case list
    case kinds
    case targets
}

public struct AnnotationCLI: Sendable {
    public let subcommand: AnnotationSubcommand
    public let evidenceDatabasePathOverride: String?
    public let annotationsDatabasePathOverride: String?
    public let configPath: String
    public let account: String
    public let targetKind: String?
    public let targetID: String?
    public let body: String?
    public let source: String
    public let limit: Int

    public init(arguments: [String]) throws {
        guard let rawSubcommand = arguments.first else { throw AnnotationError.missingSubcommand }
        guard let subcommand = AnnotationSubcommand(rawValue: rawSubcommand) else {
            throw AnnotationError.unknownSubcommand(rawSubcommand)
        }

        var evidenceDatabasePathOverride: String?
        var annotationsDatabasePathOverride: String?
        var configPath = ProtectCadencePaths.defaultConfigPath()
        var account = "default"
        var targetKind: String?
        var targetID: String?
        var body: String?
        var source = "human"
        var limit = 50

        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            func nextValue() throws -> String {
                let valueIndex = index + 1
                guard valueIndex < arguments.count else {
                    throw ProtectCadenceCLIError.unexpectedArgument(argument)
                }
                index += 2
                return arguments[valueIndex]
            }

            switch argument {
            case "--db": evidenceDatabasePathOverride = try nextValue()
            case "--annotations-db": annotationsDatabasePathOverride = try nextValue()
            case "--config": configPath = try nextValue()
            case "--account": account = try nextValue()
            case "--target-kind", "--kind": targetKind = try nextValue()
            case "--target-id": targetID = try nextValue()
            case "--body": body = try nextValue()
            case "--source": source = try nextValue()
            case "--limit":
                let rawLimit = try nextValue()
                guard let parsed = Int(rawLimit), parsed > 0 else {
                    throw AnnotationError.invalidPositiveInteger(flag: "--limit", value: rawLimit)
                }
                limit = parsed
            default:
                throw ProtectCadenceCLIError.unexpectedArgument(argument)
            }
        }

        self.subcommand = subcommand
        self.evidenceDatabasePathOverride = evidenceDatabasePathOverride
        self.annotationsDatabasePathOverride = annotationsDatabasePathOverride
        self.configPath = configPath
        self.account = account
        self.targetKind = targetKind
        self.targetID = targetID
        self.body = body
        self.source = source
        self.limit = limit
    }

    init(command: ProtectCadenceCLIAnnotationsAddCommand) throws {
        subcommand = .add
        evidenceDatabasePathOverride = command.databaseOptions.databasePathOverride
        annotationsDatabasePathOverride = command.annotationsOptions.annotationsDatabasePathOverride
        configPath = command.configOptions.configPath
        account = command.annotationsOptions.account
        targetKind = command.targetKind
        targetID = command.targetID
        body = command.body
        source = command.source
        limit = 50
    }

    init(command: ProtectCadenceCLIAnnotationsListCommand) throws {
        subcommand = .list
        evidenceDatabasePathOverride = command.databaseOptions.databasePathOverride
        annotationsDatabasePathOverride = command.annotationsOptions.annotationsDatabasePathOverride
        configPath = command.configOptions.configPath
        account = command.annotationsOptions.account
        targetKind = command.targetKind
        targetID = command.targetID
        body = nil
        source = "human"
        limit = command.limit
    }

    init(command: ProtectCadenceCLIAnnotationsTargetsCommand) throws {
        subcommand = .targets
        evidenceDatabasePathOverride = command.databaseOptions.databasePathOverride
        annotationsDatabasePathOverride = command.annotationsOptions.annotationsDatabasePathOverride
        configPath = command.configOptions.configPath
        account = command.annotationsOptions.account
        targetKind = command.kind
        targetID = nil
        body = nil
        source = "human"
        limit = command.limit
    }
}

public enum ProtectCadenceAnnotationsRunner {
    public static func run(arguments: [String], now: Date = Date()) throws -> AnnotationCommandOutput {
        try run(cli: AnnotationCLI(arguments: arguments), now: now)
    }

    public static func listKinds() -> AnnotationCommandOutput {
        .kinds(ProtectCadenceAnnotationsDatabase.listKinds())
    }

    public static func run(cli: AnnotationCLI, now: Date = Date()) throws -> AnnotationCommandOutput {
        if cli.subcommand == .kinds { return listKinds() }

        let evidencePath = try ProtectCadenceDatabasePathResolver.resolve(
            explicitOverride: cli.evidenceDatabasePathOverride,
            configPath: cli.configPath
        )
        let annotationsPath = try ProtectCadenceAnnotationsDatabasePathResolver.resolve(
            explicitOverride: cli.annotationsDatabasePathOverride,
            evidenceDatabasePath: evidencePath,
            configPath: cli.configPath
        )
        let database = try ProtectCadenceAnnotationsDatabase(path: annotationsPath)

        switch cli.subcommand {
        case .kinds:
            return listKinds()
        case .targets:
            return .targets(try database.listTargets(account: cli.account, kind: cli.targetKind, limit: cli.limit))
        case .list:
            return .list(try database.list(account: cli.account, targetKind: cli.targetKind, targetID: cli.targetID, limit: cli.limit))
        case .add:
            guard let targetKind = cli.targetKind else { throw AnnotationError.emptyField("--target-kind") }
            guard let targetID = cli.targetID else { throw AnnotationError.emptyField("--target-id") }
            guard let body = cli.body else { throw AnnotationError.emptyField("--body") }
            return .add(try database.add(
                account: cli.account,
                targetKind: targetKind,
                targetID: targetID,
                body: body,
                source: cli.source,
                now: now
            ))
        }
    }
}
