import Foundation

public enum ProtectCadenceHelp {
    public static func text(for arguments: [String]) -> String? {
        switch arguments {
        case []:
            return topLevel
        case ["--help"], ["help"]:
            return topLevel
        case ["ingest", "--help"], ["help", "ingest"]:
            return ingest
        case ["auth", "--help"], ["help", "auth"]:
            return auth
        case ["query"], ["query", "--help"], ["help", "query"]:
            return query
        case ["query", "events", "--help"], ["help", "query", "events"]:
            return queryEvents
        case ["query", "summary", "--help"], ["help", "query", "summary"]:
            return querySummary
        default:
            return nil
        }
    }

    private static let topLevel = """
    Usage: protect-cadence <subcommand> [options]

    Subcommands:
      ingest   Initialize or ingest Protect events
      query    Read rows or grouped summaries from SQLite
      auth     Manage saved Protect controller auth

    Try:
      protect-cadence ingest --help
      protect-cadence auth --help
      protect-cadence query --help
    """

    private static let ingest = """
    Usage: protect-cadence ingest [options]

    Modes:
      no arguments               Interactive first-run setup when auth or DB path is missing
                                After setup, bare ingest requires an explicit mode
      --last-hours <n>           Fetch a bounded recent window from Protect
      --event-json <file>        Replay one event object or an array of events from disk

    Options:
      --db <path>                Override SQLite path for this run
      --config <path>            Override config file path
      --camera-json <file>       Companion camera snapshot for replay
      --camera-name <name>       Fallback camera name for replay
      --controller-url <url>     Live ingest override
      --username <value>         Live ingest override
      --password <value>         Live ingest override
      --allow-insecure-tls       Disable TLS certificate verification
      --write-api-snapshot-dir <dir>
                                Save sanitized API snapshots during live ingest
    """

    private static let auth = """
    Usage: protect-cadence auth [status|login|clear] [options]

    Commands:
      status                     Show current saved auth state
      login                      Save controller URL, username, password, and TLS setting
      clear                      Remove the config file

    Options:
      --config <path>            Override config file path
      --controller-url <url>     Login override
      --username <value>         Login override
      --password <value>         Login override
      --allow-insecure-tls       Save insecure TLS as true without prompting
      --force                    Skip confirmation for clear
    """

    private static let query = """
    Usage: protect-cadence query <events|summary> [options]

    Try:
      protect-cadence query events --help
      protect-cadence query summary --help
    """

    private static let queryEvents = """
    Usage: protect-cadence query events [options]

    Options:
      --db <path>                SQLite path override
      --config <path>            Override config file path
      --since <iso8601>          Inclusive lower bound, missing upper side resolves to now
      --until <iso8601>          Exclusive upper bound, requires --since
      --last-hours <n>           Recent window ending now
      --camera <name>            Repeatable display-name filter
      --kind <kind>              Repeatable kind filter
      --time-of-day <HH:MM-HH:MM>
                                Local time-of-day filter, supports overnight ranges
      --limit <n>                Row limit, default 50
      --order <newest|oldest>    Row order, default newest
    """

    private static let querySummary = """
    Usage: protect-cadence query summary [options]

    Options:
      --db <path>                SQLite path override
      --config <path>            Override config file path
      --since <iso8601>          Inclusive lower bound, missing upper side resolves to now
      --until <iso8601>          Exclusive upper bound, requires --since
      --last-hours <n>           Summary window ending now, default 24
      --camera <name>            Repeatable display-name filter
      --kind <kind>              Repeatable kind filter
      --time-of-day <HH:MM-HH:MM>
                                Local time-of-day filter, supports overnight ranges
      --group-by <camera|kind|date|hour|weekday>
                                Repeatable grouping, default camera + kind
    """
}
