public enum ProtectCadenceCommand: String, Sendable {
    case ingest = "protect-cadence-ingest"
    case query = "protect-cadence-query"
}

public struct ProtectCadenceBanner: Sendable {
    public let command: ProtectCadenceCommand

    public init(command: ProtectCadenceCommand) {
        self.command = command
    }

    public var text: String {
        switch command {
        case .ingest:
            return "protect-cadence-ingest: ingest pipeline not implemented yet"
        case .query:
            return "protect-cadence-query: query pipeline not implemented yet"
        }
    }
}
