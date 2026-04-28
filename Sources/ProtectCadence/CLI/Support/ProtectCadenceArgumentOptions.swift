import ArgumentParser
import Foundation

struct ProtectCadenceConfigPathOptions: ParsableArguments {
    @Option(
        name: .customLong("config"),
        help: "Override config file path."
    )
    var configPath = ProtectCadencePaths.defaultConfigPath()
}

struct ProtectCadenceDatabasePathOptions: ParsableArguments {
    @Option(
        name: .customLong("db"),
        help: "Override SQLite path for this run."
    )
    var databasePathOverride: String?
}

struct ProtectCadenceModelDatabasePathOptions: ParsableArguments {
    @Option(
        name: .customLong("model-db"),
        help: "Override where the cadence-pattern model is stored for this run."
    )
    var modelDatabasePathOverride: String?
}

struct ProtectCadenceAuthOverrideOptions: ParsableArguments {
    @Option(
        name: .customLong("controller-url"),
        help: "Override Protect controller URL."
    )
    var controllerURL: String?

    @Option(
        name: .customLong("username"),
        help: "Override Protect username."
    )
    var username: String?

    @Option(
        name: .customLong("password"),
        help: "Override Protect password."
    )
    var password: String?

    @Flag(
        name: .customLong("allow-insecure-tls"),
        help: "Disable TLS certificate verification."
    )
    var allowInsecureTLS = false
}

struct ProtectCadencePrimaryWindowOptions: ParsableArguments {
    @Option(
        name: .customLong("since"),
        help: "Inclusive lower bound. Accepts ISO 8601 with offset/Z or local YYYY-MM-DD[ T]HH:MM[:SS]."
    )
    var since: String?

    @Option(
        name: .customLong("until"),
        help: "Exclusive upper bound. Requires --since."
    )
    var until: String?

    @Option(
        name: .customLong("last-hours"),
        help: "Recent window ending now."
    )
    var lastHours: Int?
}

struct ProtectCadenceQueryFilterOptions: ParsableArguments {
    @Option(
        name: .customLong("camera"),
        help: "Repeatable display-name filter."
    )
    var cameras: [String] = []

    @Option(
        name: .customLong("kind"),
        help: "Repeatable kind filter."
    )
    var kinds: [String] = []

    @Option(
        name: .customLong("day-of-week"),
        help: "Repeatable local weekday filter."
    )
    var dayOfWeek: [String] = []

    @Flag(
        name: .customLong("weekday"),
        help: "Include Monday through Friday."
    )
    var weekday = false

    @Flag(
        name: .customLong("weekend"),
        help: "Include Saturday and Sunday."
    )
    var weekend = false

    @Option(
        name: .customLong("date"),
        help: "Exact local calendar-date bucket filter. Without an explicit window, resolves that full local day."
    )
    var date: String?

    @Option(
        name: .customLong("hour"),
        help: "Exact local hour bucket filter. Does not resolve a window on its own."
    )
    var hour: String?

    @Option(
        name: .customLong("time-of-day"),
        help: "Local time-of-day filter, including overnight ranges."
    )
    var timeOfDay: String?
}

struct ProtectCadenceCompareModeOptions: ParsableArguments {
    @Option(
        name: .customLong("vs-since"),
        help: "Explicit comparison window lower bound."
    )
    var since: String?

    @Option(
        name: .customLong("vs-until"),
        help: "Explicit comparison window upper bound."
    )
    var until: String?

    @Option(
        name: .customLong("vs-window-before"),
        help: "Use an equal-duration comparison window ending at this time."
    )
    var windowBefore: String?

    @Option(
        name: .customLong("vs-window-after"),
        help: "Use an equal-duration comparison window starting at this time."
    )
    var windowAfter: String?

    @Flag(
        name: .customLong("vs-same-window-yesterday"),
        help: "Shift the primary window back by one local day."
    )
    var sameWindowYesterday = false

    @Flag(
        name: .customLong("vs-same-window-last-week"),
        help: "Shift the primary window back by seven local days."
    )
    var sameWindowLastWeek = false

    @Option(
        name: .customLong("vs-same-weekday-prior-weeks"),
        help: "Compare against this many prior matching local weekday windows."
    )
    var sameWeekdayPriorWeeks: Int?

    @Flag(
        name: .customLong("vs-prior-window"),
        help: "Use the immediately preceding equal-duration window."
    )
    var priorWindow = false
}

struct ProtectCadenceModelFilterOptions: ParsableArguments {
    @Option(
        name: .customLong("camera"),
        help: "Repeatable episode camera filter."
    )
    var cameras: [String] = []

    @Option(
        name: .customLong("kind"),
        help: "Repeatable primary-kind filter."
    )
    var kinds: [String] = []

    @Option(
        name: .customLong("state-key"),
        help: "Repeatable state-key filter."
    )
    var stateKeys: [String] = []
}
