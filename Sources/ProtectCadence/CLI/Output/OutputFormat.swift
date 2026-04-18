import ArgumentParser
import Darwin
import Foundation

public enum OutputFormat: String, CaseIterable, Codable, Sendable, ExpressibleByArgument {
    case auto
    case text
    case json
}

public enum ProtectCadenceRenderedFormat: Sendable, Equatable {
    case richText
    case plainText
    case json
}

public enum ProtectCadenceOutputOptionsError: Error, CustomStringConvertible {
    case conflictingJSONAndFormat(OutputFormat)

    public var description: String {
        switch self {
        case let .conflictingJSONAndFormat(format):
            return "--json conflicts with --format \(format.rawValue); use only one machine-readable override"
        }
    }
}

struct ProtectCadenceOutputOptions: ParsableArguments {
    @Option(
        name: .customLong("format"),
        help: "Output format: auto, text, or json."
    )
    var format: OutputFormat = .auto

    @Flag(
        name: .customLong("json"),
        help: "Shortcut for --format json."
    )
    var json = false

    func resolvedFormat() throws -> OutputFormat {
        if json {
            if format == .text {
                throw ProtectCadenceOutputOptionsError.conflictingJSONAndFormat(format)
            }
            return .json
        }

        return format
    }
}

public enum ProtectCadenceOutputRenderer {
    public static func render(
        output: ProtectCadenceCLIOutput,
        format: OutputFormat,
        stdoutIsTTY: Bool = isStandardOutputTTY()
    ) throws -> String {
        switch effectiveFormat(requestedFormat: format, stdoutIsTTY: stdoutIsTTY) {
        case .json:
            return try JSONOutput.encode(output)
        case .richText:
            return HumanReadableOutputRenderer(style: .richText).render(output)
        case .plainText:
            return HumanReadableOutputRenderer(style: .plainText).render(output)
        }
    }

    public static func effectiveFormat(
        requestedFormat: OutputFormat,
        stdoutIsTTY: Bool
    ) -> ProtectCadenceRenderedFormat {
        switch requestedFormat {
        case .json:
            return .json
        case .auto, .text:
            return stdoutIsTTY ? .richText : .plainText
        }
    }

    public static func isStandardOutputTTY() -> Bool {
        isatty(STDOUT_FILENO) == 1
    }
}

private enum HumanOutputStyle {
    case richText
    case plainText
}

private struct HumanReadableOutputRenderer {
    let style: HumanOutputStyle

    func render(_ output: ProtectCadenceCLIOutput) -> String {
        switch output {
        case let .ingest(response):
            return renderIngest(response)
        case let .query(response):
            return renderQuery(response)
        case let .model(response):
            return renderModel(response)
        case let .auth(response):
            return renderAuth(response)
        case let .validate(response):
            return renderValidate(response)
        }
    }

    private func renderIngest(_ response: IngestResponse) -> String {
        var lines = [
            "Ingest: \(response.status)",
            "Database: \(response.databasePath)",
        ]

        if let window = response.window {
            lines.append("Window: \(format(window: window))")
        }

        lines.append(contentsOf: [
            "Fetched source events: \(response.fetchedSourceEventCount)",
            "Normalized events: \(response.normalizedEventCount)",
            "Inserted events: \(response.insertedEventCount)",
            "Ignored source events: \(response.ignoredSourceEventCount)",
        ])

        return lines.joined(separator: "\n")
    }

    private func renderAuth(_ response: AuthCommandResponse) -> String {
        var lines = [
            "Auth \(response.action): \(response.status)",
            response.message,
            "Config path: \(response.configPath)",
            "Config exists: \(yesNo(response.configExists))",
            "Stored password: \(yesNo(response.storedPasswordExists))",
        ]

        if let controllerURL = response.controllerURL {
            lines.append("Controller URL: \(controllerURL)")
        }
        if let username = response.username {
            lines.append("Username: \(username)")
        }
        if let allowInsecureTLS = response.allowInsecureTLS {
            lines.append("Allow insecure TLS: \(yesNo(allowInsecureTLS))")
        }

        return lines.joined(separator: "\n")
    }

    private func renderValidate(_ response: ProtectControllerValidationResponse) -> String {
        var lines = [
            "Validate: \(response.status)",
            "Window: \(format(window: response.window))",
            "Fetched source events: \(response.fetchedSourceEventCount)",
            "Camera lookups: \(response.cameraLookupCount)",
            "Sample limit: \(response.sampleLimit)",
            "",
            "Time start rule: \(response.timeStartRule.rule)",
            "Fetched: \(describe(response.timeStartRule.fetched))",
            "Settled: \(describe(response.timeStartRule.settled))",
            "",
            "Settled filter: \(response.settledEventFiltering.rule)",
            "Settled: \(response.settledEventFiltering.settledCount)",
            "Unsettled: \(response.settledEventFiltering.unsettledCount)",
            "",
            "Dedupe key: \(response.dedupeKey.rule)",
            "Scope: \(response.dedupeKey.analysisScope)",
            "Normalized settled rows: \(response.dedupeKey.normalizedSettledEventCount)",
            "Ignored settled source events: \(response.dedupeKey.ignoredSettledSourceEventCount)",
            "Duplicate rows: \(response.dedupeKey.duplicateRowCount)",
            "Multi-kind settled source events: \(response.dedupeKey.multiKindSettledSourceEventCount)",
        ]

        if let snapshot = response.snapshot {
            lines.append("")
            lines.append("Snapshot: \(snapshot.directoryPath)")
            lines.append("Snapshot events: \(snapshot.eventCount)")
            lines.append("Snapshot cameras: \(snapshot.cameraCount)")
        }

        if !response.recentEvents.isEmpty {
            lines.append("")
            lines.append("Recent events")
            lines.append(renderTable(
                headers: ["Time", "Camera", "Type", "Kinds", "Settled"],
                rows: response.recentEvents.map { event in
                    [
                        event.selectedTimeStart.map(format(localDateTime:)) ?? "-",
                        event.camera ?? "-",
                        event.type ?? "-",
                        event.normalizedKinds.isEmpty ? "-" : event.normalizedKinds.joined(separator: ","),
                        yesNo(event.isSettled),
                    ]
                }
            ))
        }

        if !response.dedupeKey.duplicateKeys.isEmpty {
            lines.append("")
            lines.append("Duplicate keys")
            lines.append(renderTable(
                headers: ["Source event", "Kind", "Rows", "Types", "Cameras"],
                rows: response.dedupeKey.duplicateKeys.map { collision in
                    [
                        collision.sourceEventID,
                        collision.kind,
                        String(collision.occurrenceCount),
                        collision.eventTypes.joined(separator: ","),
                        collision.cameras.joined(separator: ","),
                    ]
                }
            ))
        }

        return lines.joined(separator: "\n")
    }

    private func renderQuery(_ response: QueryCommandOutput) -> String {
        switch response {
        case let .events(events):
            return renderEvents(events)
        case let .summary(summary):
            return renderSummary(summary)
        case let .compare(compare):
            return renderCompare(compare)
        }
    }

    private func renderEvents(_ response: EventsResponse) -> String {
        let showsDuration = response.events.contains { $0.timeEnd != nil }
        let showsEventType = response.events.contains { $0.eventType != nil }
        let showsEventID = Set(response.events.map(\.eventID)).count != response.events.count

        var headers = ["Time", "Camera", "Kind"]
        if showsDuration {
            headers.append("Duration")
        }
        if showsEventType {
            headers.append("Type")
        }
        if showsEventID {
            headers.append("Event")
        }

        let rows = response.events.map { event in
            var row = [
                format(localDateTime: event.timeStart),
                event.camera,
                event.kind,
            ]
            if showsDuration {
                row.append(formatDuration(start: event.timeStart, end: event.timeEnd))
            }
            if showsEventType {
                row.append(event.eventType ?? "-")
            }
            if showsEventID {
                row.append(event.eventID)
            }
            return row
        }

        var lines = [
            "Events: \(response.events.count)",
            "Count semantics: \(response.countSemantics.rawValue)",
            "Database: \(response.databasePath)",
        ]
        lines.append(contentsOf: renderFilterLines(response.filters))
        lines.append("")
        lines.append(renderTable(headers: headers, rows: rows))
        return lines.joined(separator: "\n")
    }

    private func renderSummary(_ response: SummaryResponse) -> String {
        var lines = [
            "Summary",
            "Count semantics: \(response.countSemantics.rawValue)",
            "Database: \(response.databasePath)",
            "Total events: \(response.totalEventCount)",
            "Total source events: \(response.totalSourceEventCount)",
            "Group by: \(response.groupBy.map(displayName(for:)).joined(separator: ", "))",
        ]
        lines.append(contentsOf: renderFilterLines(response.filters))
        lines.append("")

        let headers = response.groupBy.map(displayName(for:)) + ["Events", "Source"]
        let rows = response.groups.map { group in
            response.groupBy.map { dimension in
                group.group[dimension.rawValue] ?? "-"
            } + [
                String(group.eventCount),
                String(group.sourceEventCount),
            ]
        }

        lines.append(renderTable(headers: headers, rows: rows))
        return lines.joined(separator: "\n")
    }

    private func renderCompare(_ response: CompareResponse) -> String {
        let primaryWindow = response.filters.window.map(format(window:)) ?? "all stored rows"
        let comparisonWindow = format(window: response.comparisonWindow)

        var lines = [
            "Compare",
            "Count semantics: \(response.countSemantics.rawValue)",
            "Database: \(response.databasePath)",
            "Primary window: \(primaryWindow)",
            "Comparison window: \(comparisonWindow)",
            "Primary totals: \(response.totals.eventCount) events / \(response.totals.sourceEventCount) source",
            "Comparison totals: \(response.comparisonTotals.eventCount) events / \(response.comparisonTotals.sourceEventCount) source",
            "Delta: \(signed(response.totalEventCountDelta)) events / \(signed(response.totalSourceEventCountDelta)) source",
            "Group by: \(response.groupBy.map(displayName(for:)).joined(separator: ", "))",
        ]

        lines.append(contentsOf: renderFilterLines(response.filters, omitWindow: true))
        lines.append("")

        let headers = response.groupBy.map(displayName(for:)) + ["Events", "Compare", "Delta", "Source", "CmpSrc", "SrcDelta"]
        let rows = response.groups.map { group in
            response.groupBy.map { dimension in
                group.group[dimension.rawValue] ?? "-"
            } + [
                String(group.window.eventCount),
                String(group.comparisonWindow.eventCount),
                signed(group.eventCountDelta),
                String(group.window.sourceEventCount),
                String(group.comparisonWindow.sourceEventCount),
                signed(group.sourceEventCountDelta),
            ]
        }

        lines.append(renderTable(headers: headers, rows: rows))
        return lines.joined(separator: "\n")
    }

    private func renderModel(_ response: ModelCommandOutput) -> String {
        switch response {
        case let .rebuild(rebuild):
            return renderModelRebuild(rebuild)
        case let .episodes(episodes):
            return renderModelEpisodes(episodes)
        case let .findings(findings):
            return renderModelFindings(findings)
        }
    }

    private func renderModelRebuild(_ response: ModelRebuildResponse) -> String {
        var lines = [
            "Model rebuild: \(response.status)",
            "Source DB: \(response.sourceDatabasePath)",
            "Model DB: \(response.modelDatabasePath)",
            "Built at: \(format(localDateTime: response.build.builtAt))",
            "Source events: \(response.build.sourceEventCount)",
            "Episodes: \(response.episodeCount)",
            "State bucket stats: \(response.stateBucketStatCount)",
            "State transition stats: \(response.stateTransitionStatCount)",
            "Findings: \(response.findingCount)",
            "Rebuild duration: \(String(format: "%.2fs", response.rebuildDurationSeconds))",
        ]

        if let sourceWindow = response.build.sourceWindow {
            lines.insert("Source window: \(format(window: sourceWindow))", at: 4)
        }

        return lines.joined(separator: "\n")
    }

    private func renderModelEpisodes(_ response: ModelEpisodesResponse) -> String {
        var lines = [
            "Model episodes: \(response.episodes.count)",
            "Source DB: \(response.sourceDatabasePath)",
            "Model DB: \(response.modelDatabasePath)",
            "Built at: \(format(localDateTime: response.build.builtAt))",
            "Limit: \(response.limit)",
            "Order: \(response.order.rawValue)",
        ]
        lines.append(contentsOf: renderModelFilterLines(
            window: response.window,
            cameras: response.cameras,
            kinds: response.kinds,
            stateKeys: response.stateKeys
        ))
        lines.append("")

        lines.append(renderTable(
            headers: ["Start", "End", "Camera", "Kind", "Duration", "Events", "State", "Flags"],
            rows: response.episodes.map { episode in
                [
                    format(localDateTime: episode.startTime),
                    format(localDateTime: episode.endTime),
                    episode.camera,
                    episode.primaryKind,
                    secondsString(episode.durationSeconds),
                    "\(episode.eventCount)/\(episode.sourceEventCount)",
                    episode.stateKey,
                    episode.containsUnsettled ? "unsettled" : "-",
                ]
            }
        ))
        return lines.joined(separator: "\n")
    }

    private func renderModelFindings(_ response: ModelFindingsResponse) -> String {
        var lines = [
            "Model findings: \(response.findings.count)",
            "Source DB: \(response.sourceDatabasePath)",
            "Model DB: \(response.modelDatabasePath)",
            "Built at: \(format(localDateTime: response.build.builtAt))",
            "Limit: \(response.limit)",
        ]
        lines.append(contentsOf: renderModelFilterLines(
            window: response.window,
            cameras: response.cameras,
            kinds: response.kinds,
            stateKeys: []
        ))

        if !response.findingTypes.isEmpty {
            lines.append("Finding types: \(response.findingTypes.map(\.rawValue).joined(separator: ", "))")
        }

        lines.append("")
        lines.append(renderTable(
            headers: ["Start", "Camera", "Finding", "Kind", "Score", "Detail"],
            rows: response.findings.map { finding in
                [
                    format(localDateTime: finding.episodeStartTime),
                    finding.camera,
                    finding.findingType.rawValue,
                    finding.primaryKind,
                    String(format: "%.2f", finding.score),
                    findingDetail(finding),
                ]
            }
        ))
        return lines.joined(separator: "\n")
    }

    private func renderFilterLines(_ filters: QueryFilters, omitWindow: Bool = false) -> [String] {
        var lines: [String] = []

        if !omitWindow {
            if let window = filters.window {
                lines.append("Window: \(format(window: window))")
            } else {
                lines.append("Window: all stored rows")
            }
        }

        if !filters.cameras.isEmpty {
            lines.append("Cameras: \(filters.cameras.joined(separator: ", "))")
        }
        if !filters.kinds.isEmpty {
            lines.append("Kinds: \(filters.kinds.joined(separator: ", "))")
        }
        if !filters.weekdays.isEmpty {
            lines.append("Weekdays: \(filters.weekdays.map(\.rawValue).joined(separator: ", "))")
        }
        if let timeOfDay = filters.timeOfDay {
            lines.append("Time of day: \(timeOfDay.rawValue)")
        }
        if let date = filters.date {
            lines.append("Date: \(date)")
        }
        if let hour = filters.hour {
            lines.append("Hour: \(hour)")
        }

        return lines
    }

    private func renderModelFilterLines(
        window: QueryWindow?,
        cameras: [String],
        kinds: [String],
        stateKeys: [String]
    ) -> [String] {
        var lines: [String] = []

        if let window {
            lines.append("Window: \(format(window: window))")
        } else {
            lines.append("Window: all modeled rows")
        }
        if !cameras.isEmpty {
            lines.append("Cameras: \(cameras.joined(separator: ", "))")
        }
        if !kinds.isEmpty {
            lines.append("Kinds: \(kinds.joined(separator: ", "))")
        }
        if !stateKeys.isEmpty {
            lines.append("State keys: \(stateKeys.joined(separator: ", "))")
        }

        return lines
    }

    private func renderTable(headers: [String], rows: [[String]]) -> String {
        guard !rows.isEmpty else {
            return "(no rows)"
        }

        let normalizedHeaders = headers.map { clipped($0, to: 32) }
        let normalizedRows = rows.map { row in
            row.enumerated().map { index, value in
                clipped(value, to: normalizedHeaders[index].count > 24 ? normalizedHeaders[index].count : 32)
            }
        }

        let widths = normalizedHeaders.indices.map { index in
            max(
                normalizedHeaders[index].count,
                normalizedRows.map { $0[index].count }.max() ?? 0
            )
        }

        switch style {
        case .richText:
            return renderRichTable(headers: normalizedHeaders, rows: normalizedRows, widths: widths)
        case .plainText:
            return renderPlainTable(headers: normalizedHeaders, rows: normalizedRows, widths: widths)
        }
    }

    private func renderRichTable(headers: [String], rows: [[String]], widths: [Int]) -> String {
        let top = "┌" + widths.map { String(repeating: "─", count: $0 + 2) }.joined(separator: "┬") + "┐"
        let separator = "├" + widths.map { String(repeating: "─", count: $0 + 2) }.joined(separator: "┼") + "┤"
        let bottom = "└" + widths.map { String(repeating: "─", count: $0 + 2) }.joined(separator: "┴") + "┘"

        var lines = [top, rowLine(headers, widths: widths, left: "│", middle: "│", right: "│"), separator]
        for row in rows {
            lines.append(rowLine(row, widths: widths, left: "│", middle: "│", right: "│"))
        }
        lines.append(bottom)
        return lines.joined(separator: "\n")
    }

    private func renderPlainTable(headers: [String], rows: [[String]], widths: [Int]) -> String {
        let headerLine = rowLine(headers, widths: widths, left: "", middle: "", right: "")
        let separator = widths.map { String(repeating: "-", count: $0) }.joined(separator: "  ")
        let rowLines = rows.map { rowLine($0, widths: widths, left: "", middle: "", right: "") }
        return ([headerLine, separator] + rowLines).joined(separator: "\n")
    }

    private func rowLine(
        _ columns: [String],
        widths: [Int],
        left: String,
        middle: String,
        right: String
    ) -> String {
        let padded = zip(columns, widths).map { value, width in
            let clippedValue = clipped(value, to: width)
            return left.isEmpty ? pad(clippedValue, to: width) : " " + pad(clippedValue, to: width) + " "
        }

        if left.isEmpty {
            return padded.joined(separator: "  ")
        }

        return left + padded.joined(separator: middle) + right
    }

    private func format(window: QueryWindow) -> String {
        "\(format(localDateTime: window.start)) -> \(format(localDateTime: window.end))"
    }

    private func format(localDateTime date: Date) -> String {
        Self.localDateTimeFormatter.string(from: date)
    }

    private func formatDuration(start: Date, end: Date?) -> String {
        guard let end else {
            return "-"
        }
        return secondsString(max(0, Int(end.timeIntervalSince(start).rounded())))
    }

    private func secondsString(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m \(remainingSeconds)s"
        }
        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        }
        return "\(remainingSeconds)s"
    }

    private func describe(_ counts: ProtectControllerValidationCounts) -> String {
        [
            "events \(counts.eventCount)",
            "detectedAt \(counts.detectedAtChosenCount)",
            "start fallback \(counts.startFallbackCount)",
            "missing \(counts.missingTimeStartCount)",
            "detectedAt != start \(counts.detectedAtDiffersFromStartCount)",
        ].joined(separator: ", ")
    }

    private func findingDetail(_ finding: ModelFinding) -> String {
        switch finding.findingType {
        case .unexpectedPresence:
            return "bucket \(finding.bucketEpisodeCount), state \(finding.stateEpisodeCount)"
        case .unexpectedTransition:
            let previous = finding.previousPrimaryKind ?? "-"
            let pairCount = finding.transitionPairCount.map(String.init) ?? "-"
            return "\(previous) -> \(finding.primaryKind), pairs \(pairCount)"
        case .unusualDuration:
            let observed = finding.observedDurationSeconds.map(secondsString) ?? "-"
            let expected = finding.expectedDurationSeconds.map { secondsString(Int($0.rounded())) } ?? "-"
            let direction = finding.durationDirection ?? "-"
            return "\(direction), observed \(observed), expected \(expected)"
        }
    }

    private func displayName(for groupBy: SummaryGroupBy) -> String {
        switch groupBy {
        case .camera:
            return "Camera"
        case .kind:
            return "Kind"
        case .date:
            return "Date"
        case .hour:
            return "Hour"
        case .weekday:
            return "Weekday"
        }
    }

    private func clipped(_ value: String, to width: Int) -> String {
        guard value.count > width else {
            return value
        }

        guard width > 3 else {
            return String(value.prefix(width))
        }

        return String(value.prefix(width - 3)) + "..."
    }

    private func pad(_ value: String, to width: Int) -> String {
        if value.count >= width {
            return value
        }
        return value + String(repeating: " ", count: width - value.count)
    }

    private func yesNo(_ value: Bool) -> String {
        value ? "yes" : "no"
    }

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : String(value)
    }

    private static let localDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
