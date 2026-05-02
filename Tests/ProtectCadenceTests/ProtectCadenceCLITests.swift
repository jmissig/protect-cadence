import Foundation
import GRDB
import Testing
@testable import ProtectCadence

@Suite("CLI Surface")
struct ProtectCadenceCLITests {
    @Test
    func annotationsCommandWritesSidecarAndListsTargets() async throws {
        let evidencePath = temporaryDatabasePath()
        let annotationsPath = temporaryDatabasePath()
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let added = try await ProtectCadenceCLIRunner.run(
            arguments: [
                "annotations", "add",
                "--db", evidencePath,
                "--annotations-db", annotationsPath,
                "--account", "julian",
                "--target-kind", "camera",
                "--target-id", "name:Driveway",
                "--body", "Construction week made this camera noisy.",
                "--source", "human",
            ],
            now: now
        )

        switch added {
        case let .annotations(.add(response)):
            #expect(response.annotationsDatabasePath == annotationsPath)
            #expect(response.annotation.account == "julian")
            #expect(response.annotation.targetKind == "camera")
            #expect(response.annotation.targetID == "name:Driveway")
            #expect(response.annotation.body == "Construction week made this camera noisy.")
            #expect(response.annotation.createdAtISO8601 == "2023-11-14T22:13:20Z")
        case .ingest, .query, .model, .annotations, .auth, .validate:
            Issue.record("expected annotations add output")
        }

        let targets = try await ProtectCadenceCLIRunner.run(
            arguments: [
                "annotations", "targets",
                "--db", evidencePath,
                "--annotations-db", annotationsPath,
                "--account", "julian",
                "--kind", "camera",
            ]
        )

        switch targets {
        case let .annotations(.targets(response)):
            #expect(response.totalMatchingTargets == 1)
            #expect(response.targets.first?.kind == "camera")
            #expect(response.targets.first?.id == "name:Driveway")
            #expect(response.targets.first?.annotationCount == 1)
        case .ingest, .query, .model, .annotations, .auth, .validate:
            Issue.record("expected annotations targets output")
        }
    }

    @Test
    func queryEventsIncludesSidecarAnnotationsUnlessOptedOut() async throws {
        let evidencePath = temporaryDatabasePath()
        let annotationsPath = temporaryDatabasePath()
        let database = try ProtectCadenceDatabase(path: evidencePath)
        let now = Date(timeIntervalSince1970: 20_000)

        try insertRows(
            [
                EventRow(
                    timeStart: now.addingTimeInterval(-60),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "protect-event-1"
                ),
            ],
            into: database
        )

        _ = try await ProtectCadenceCLIRunner.run(
            arguments: [
                "annotations", "add",
                "--db", evidencePath,
                "--annotations-db", annotationsPath,
                "--target-kind", "event",
                "--target-id", "event_id:protect-event-1#kind:person",
                "--body", "Known delivery.",
            ],
            now: now
        )

        let annotated = try await ProtectCadenceCLIRunner.run(
            arguments: [
                "query", "events",
                "--db", evidencePath,
                "--annotations-db", annotationsPath,
                "--last-hours", "1",
            ],
            now: now
        )

        switch annotated {
        case let .query(.events(response)):
            #expect(response.events.count == 1)
            #expect(response.events[0].annotations?.first?.body == "Known delivery.")
        case .ingest, .query, .model, .annotations, .auth, .validate:
            Issue.record("expected query events output")
        }

        let optedOut = try await ProtectCadenceCLIRunner.run(
            arguments: [
                "query", "events",
                "--db", evidencePath,
                "--annotations-db", annotationsPath,
                "--last-hours", "1",
                "--no-annotations",
            ],
            now: now
        )

        switch optedOut {
        case let .query(.events(response)):
            #expect(response.events.count == 1)
            #expect(response.events[0].annotations == nil)
        case .ingest, .query, .model, .annotations, .auth, .validate:
            Issue.record("expected query events output")
        }
    }

    @Test
    func queryRunnerSummaryProducesEncodableSummaryOutput() throws {
        let databasePath = temporaryDatabasePath()
        let database = try ProtectCadenceDatabase(path: databasePath)
        let now = Date(timeIntervalSince1970: 10_000)

        try insertRows(
            [
                EventRow(
                    timeStart: now.addingTimeInterval(-30 * 60),
                    camera: "Porch",
                    kind: "package",
                    eventID: "event-1"
                ),
            ],
            into: database
        )

        let output = try ProtectCadenceQueryRunner.run(
            arguments: ["summary", "--db", databasePath, "--last-hours", "2"],
            now: now
        )

        switch output {
        case let .summary(response):
            #expect(response.command == "protect-cadence query")
            #expect(response.totalEventCount == 1)
            #expect(response.totalSourceEventCount == 1)
            #expect(response.countSemantics == .events)
            #expect(response.groups == [
                summaryGroup(
                    group: ["camera": "Porch", "kind": "package"],
                    eventCount: 1,
                    sourceEventCount: 1,
                    filters: QueryFilters(
                        window: QueryWindow(start: now.addingTimeInterval(-2 * 60 * 60), end: now),
                        cameras: ["Porch"],
                        kinds: ["package"]
                    )
                ),
            ])
            #expect(response.filters.window == QueryWindow(start: now.addingTimeInterval(-2 * 60 * 60), end: now))

            let json = try JSONOutput.encode(output)
            #expect(json.contains("\"command\""))
            #expect(json.contains("\"filters\""))
            #expect(json.contains("\"drillDown\""))
            #expect(json.contains("\"totalSourceEventCount\""))
            #expect(json.contains("\"eventCount\""))
            #expect(json.contains("\"sourceEventCount\""))
        case .events, .compare:
            Issue.record("expected summary output")
        }
    }

    @Test
    func unifiedRunnerRoutesQuerySummaryThroughSingleCommandSurface() async throws {
        let databasePath = temporaryDatabasePath()
        let database = try ProtectCadenceDatabase(path: databasePath)
        let now = Date(timeIntervalSince1970: 10_000)

        try insertRows(
            [
                EventRow(
                    timeStart: now.addingTimeInterval(-15 * 60),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "event-1"
                ),
            ],
            into: database
        )

        let output = try await ProtectCadenceCLIRunner.run(
            arguments: ["query", "summary", "--db", databasePath, "--last-hours", "1"],
            now: now
        )

        switch output {
        case let .query(queryOutput):
            switch queryOutput {
            case let .summary(response):
                #expect(response.command == "protect-cadence query")
                #expect(response.totalEventCount == 1)
                #expect(response.totalSourceEventCount == 1)
            case .events, .compare:
                Issue.record("expected summary output")
            }
        case .ingest, .model, .annotations, .auth, .validate:
            Issue.record("expected query output")
        }
    }

    @Test
    func unifiedRunnerRoutesFixtureIngestThroughSingleCommandSurface() async throws {
        let databasePath = temporaryDatabasePath()
        let output = try await ProtectCadenceCLIRunner.run(
            arguments: [
                "ingest",
                "--db", databasePath,
                "--event-json", fixturePath("events-response.json"),
                "--camera-json", fixturePath("cameras-response.json"),
            ]
        )

        switch output {
        case let .ingest(response):
            #expect(response.command == "protect-cadence ingest")
            #expect(response.fetchedSourceEventCount == 5)
            #expect(response.normalizedEventCount == 5)
            #expect(response.insertedEventCount == 5)
        case .query, .model, .annotations, .auth, .validate:
            Issue.record("expected ingest output")
        }
    }

    @Test
    func authRunnerStatusProducesSingleCommandResponseShape() async throws {
        let configPath = temporaryDirectoryPath() + "/config.json"
        try ProtectCadenceConfigStore.save(
            ProtectCadenceConfig(
                controllerURL: "https://protect.example",
                username: "cli-user",
                password: "cli-pass"
            ),
            to: configPath
        )

        let output = try ProtectCadenceCLIOutput.auth(
            ProtectCadenceAuthRunner.run(
                arguments: ["status", "--config", configPath],
                environment: [:],
                prompter: TestPrompter()
            )
        )

        switch output {
        case let .auth(response):
            #expect(response.command == "protect-cadence auth")
            #expect(response.action == "status")
            #expect(response.status == "ok")
        case .ingest, .query, .model, .annotations, .validate:
            Issue.record("expected auth output")
        }
    }

    @Test
    func setupAliasRoutesToAuthLogin() async throws {
        let configPath = temporaryDirectoryPath() + "/config.json"
        let output = try await ProtectCadenceCLIRunner.run(
            arguments: [
                "setup",
                "--config", configPath,
                "--controller-url", "https://protect.example",
                "--username", "setup-user",
                "--password", "setup-pass",
            ],
            environment: ["PROTECT_ALLOW_INSECURE_TLS": "false"]
        )

        switch output {
        case let .auth(response):
            #expect(response.command == "protect-cadence auth")
            #expect(response.action == "login")
            #expect(response.status == "configured")
            #expect(response.controllerURL == "https://protect.example")
            #expect(response.username == "setup-user")
            #expect(response.storedPasswordExists)
        case .ingest, .query, .model, .annotations, .validate:
            Issue.record("expected auth output")
        }
    }

    @Test
    func ingestRunnerUsesResolvedConfigPassword() async throws {
        let configPath = temporaryDirectoryPath() + "/config.json"
        let databasePath = temporaryDatabasePath()
        try ProtectCadenceConfigStore.save(
            ProtectCadenceConfig(
                controllerURL: "https://protect.example",
                username: "ingest-user",
                password: "ingest-pass"
            ),
            to: configPath
        )

        let transport = RecordingProtectHTTPTransport(
            responses: [
                .init(
                    statusCode: 200,
                    headers: [
                        "Set-Cookie": "TOKEN=test-session; Path=/; HttpOnly",
                        "x-csrf-token": "csrf-test-token",
                    ],
                    body: Data("{}".utf8)
                ),
                .init(
                    statusCode: 200,
                    headers: [:],
                    body: try fixtureData("events-response.json")
                ),
                .init(
                    statusCode: 200,
                    headers: [:],
                    body: try fixtureData("cameras-response.json")
                ),
            ]
        )

        let response = try await ProtectCadenceIngestRunner.run(
            arguments: ["--db", databasePath, "--config", configPath, "--last-hours", "1"],
            now: Date(timeIntervalSince1970: 1_710_003_600),
            environment: [:],
            clientFactory: { configuration in
                #expect(configuration.username == "ingest-user")
                #expect(configuration.password == "ingest-pass")
                return ProtectControllerClient(configuration: configuration, transport: transport)
            }
        )

        #expect(response.command == "protect-cadence ingest")
        #expect(response.fetchedSourceEventCount == 5)
    }

    @Test
    func bareIngestOnboardingSavesConfigAndSkipsSeedCleanly() async throws {
        let configPath = temporaryDirectoryPath() + "/config.json"
        let managedDatabasePath = temporaryDirectoryPath() + "/managed.sqlite"
        let prompter = TestPrompter(
            prompts: [
                "https://protect.example",
                "onboard-user",
                managedDatabasePath,
            ],
            passwordPrompts: ["onboard-pass"],
            confirmations: [false, false]
        )
        let output = RecordedStatusOutput()

        let response = try await ProtectCadenceIngestRunner.run(
            arguments: ["--config", configPath],
            environment: [:],
            prompter: prompter,
            fileManager: .default,
            statusOutput: output.write
        )

        #expect(response.status == "ready")
        #expect(response.databasePath == managedDatabasePath)

        let config = try ProtectCadenceConfigStore.load(from: configPath)
        #expect(config == ProtectCadenceConfig(
            auth: ProtectCadenceAuthConfig(
                controllerURL: "https://protect.example",
                username: "onboard-user",
                password: "onboard-pass",
                allowInsecureTLS: false
            ),
            databasePath: managedDatabasePath
        ))
        #expect(output.lines.contains("First-run setup for protect-cadence."))
        #expect(output.lines.contains("Saved config. Next time, run something like: `protect-cadence ingest --last-hours 6`"))
    }

    @Test
    func bareIngestOnboardingSeedsDatabaseInteractively() async throws {
        let configPath = temporaryDirectoryPath() + "/config.json"
        let managedDatabasePath = temporaryDirectoryPath() + "/managed.sqlite"
        let prompter = TestPrompter(
            prompts: [
                "https://protect.example",
                "seed-user",
                managedDatabasePath,
                "24",
            ],
            passwordPrompts: ["seed-pass"],
            confirmations: [true, true]
        )
        let output = RecordedStatusOutput()
        let transport = RecordingProtectHTTPTransport(
            responses: [
                .init(
                    statusCode: 200,
                    headers: [
                        "Set-Cookie": "TOKEN=test-session; Path=/; HttpOnly",
                        "x-csrf-token": "csrf-test-token",
                    ],
                    body: Data("{}".utf8)
                ),
                .init(
                    statusCode: 200,
                    headers: [:],
                    body: try fixtureData("events-response.json")
                ),
                .init(
                    statusCode: 200,
                    headers: [:],
                    body: try fixtureData("cameras-response.json")
                ),
            ]
        )

        let response = try await ProtectCadenceIngestRunner.run(
            arguments: ["--config", configPath],
            now: Date(timeIntervalSince1970: 1_710_003_600),
            environment: [:],
            prompter: prompter,
            fileManager: .default,
            statusOutput: output.write,
            clientFactory: { configuration in
                ProtectControllerClient(configuration: configuration, transport: transport)
            }
        )

        #expect(response.status == "ok")
        #expect(response.databasePath == managedDatabasePath)
        #expect(response.fetchedSourceEventCount == 5)
        #expect(output.lines.contains("Authenticating with Protect..."))
        #expect(output.lines.contains("Fetching recent Protect events..."))
        #expect(output.lines.contains("Writing events to SQLite..."))
        #expect(output.lines.contains("Next time, run something like: `protect-cadence ingest --last-hours 6`"))
    }

    @Test
    func helpTextIncludesInteractiveIngestGuidance() {
        let help = ProtectCadenceHelp.text(for: ["ingest", "--help"])

        #expect(help?.contains("Interactive first-run setup") == true)
    }

    @Test
    func parserTreatsSetupAsExecutableAliasCommand() throws {
        let parsed = try ProtectCadenceCLICommand.parseAsRoot(["setup"])

        #expect(parsed is ProtectCadenceCLISetupCommand)
    }

    @Test
    func helpTextIncludesSetupAliasGuidance() {
        let help = ProtectCadenceHelp.text(for: ["setup", "--help"])

        #expect(help?.contains("Alias for `auth login`") == true)
    }

    @Test
    func parserTreatsBareValidateAsExecutableCommand() throws {
        let parsed = try ProtectCadenceCLICommand.parseAsRoot(["validate"])

        #expect(parsed is ProtectCadenceCLIValidateCommand)
    }

    @Test
    func bareIngestRequiresExplicitModeAfterSetup() async throws {
        let configPath = temporaryDirectoryPath() + "/config.json"
        try ProtectCadenceConfigStore.save(
            ProtectCadenceConfig(
                auth: ProtectCadenceAuthConfig(
                    controllerURL: "https://protect.example",
                    username: "ready-user",
                    password: "ready-pass",
                    allowInsecureTLS: false
                ),
                databasePath: temporaryDatabasePath()
            ),
            to: configPath
        )

        do {
            _ = try await ProtectCadenceIngestRunner.run(
                arguments: ["--config", configPath],
                environment: [:],
                prompter: TestPrompter(),
                fileManager: .default,
                statusOutput: { _ in }
            )
            Issue.record("expected missing mode error")
        } catch let error as IngestCLIError {
            #expect(error.description == "no ingest mode selected; try --last-hours <n> or --event-json <file>")
        }
    }

    @Test
    func bareQueryReturnsQueryHelpText() {
        let help = ProtectCadenceHelp.text(for: ["query"])

        #expect(help?.contains("protect-cadence query") == true)
        #expect(help?.contains("events") == true)
        #expect(help?.contains("summary") == true)
        #expect(help?.contains("compare") == true)
    }


    @Test
    func queryCompareHelpMentionsPriorWindowMode() {
        let help = ProtectCadenceHelp.text(for: ["query", "compare", "--help"])

        #expect(help?.contains("--vs-prior-window") == true)
    }

    @Test
    func queryCompareHelpMentionsSameWindowLastWeekMode() {
        let help = ProtectCadenceHelp.text(for: ["query", "compare", "--help"])

        #expect(help?.contains("--vs-same-window-last-week") == true)
    }

    @Test
    func queryCompareHelpMentionsSameWeekdayPriorWeeksMode() {
        let help = ProtectCadenceHelp.text(for: ["query", "compare", "--help"])

        #expect(help?.contains("--vs-same-weekday-prior-weeks") == true)
    }

    @Test
    func queryCompareHelpMentionsBoundaryModes() {
        let help = ProtectCadenceHelp.text(for: ["query", "compare", "--help"])

        #expect(help?.contains("--vs-window-before") == true)
        #expect(help?.contains("--vs-window-after") == true)
    }

    @Test
    func queryEventsHelpExplainsHourDoesNotResolveWindow() {
        let help = ProtectCadenceHelp.text(for: ["query", "events", "--help"])

        #expect(help?.contains("--hour") == true)
        #expect(help?.contains("Does not resolve a") == true)
        #expect(help?.contains("window on its own.") == true)
    }

    @Test
    func queryCLIRejectsInvalidLastHours() throws {
        do {
            _ = try QueryCLI(arguments: ["summary", "--last-hours", "0"])
            Issue.record("expected --last-hours validation error")
        } catch let error as QueryCLIError {
            #expect(error.description.contains("--last-hours"))
        }
    }

    @Test
    func queryCLIParsesConfigPathAndDatabaseOverride() throws {
        let cli = try QueryCLI(arguments: [
            "events",
            "--config", "/tmp/custom-config.json",
            "--db", "/tmp/custom.sqlite",
            "--limit", "5",
        ])

        #expect(cli.configPath == "/tmp/custom-config.json")
        #expect(cli.databasePathOverride == "/tmp/custom.sqlite")
        #expect(cli.limit == 5)
    }

    @Test
    func queryCLIParsesSharedFiltersForEventsAndSummary() throws {
        let since = "2026-03-25T01:00:00Z"
        let until = "2026-03-25T05:00:00Z"
        let eventsCLI = try QueryCLI(arguments: [
            "events",
            "--since", since,
            "--until", until,
            "--camera", "Driveway",
            "--camera", "Backyard",
            "--kind", "person",
            "--kind", "vehicle",
            "--day-of-week", "mon",
            "--weekend",
            "--time-of-day", "22:15-06:45",
            "--date", "2026-03-29",
            "--hour", "06:00",
            "--order", "oldest",
            "--limit", "25",
        ])
        let summaryCLI = try QueryCLI(arguments: [
            "summary",
            "--since", since,
            "--until", until,
            "--camera", "Driveway",
            "--kind", "person",
            "--weekday",
            "--day-of-week", "sun",
            "--time-of-day", "22:15-06:45",
            "--date", "2026-03-30",
            "--hour", "05:00",
            "--group-by", "date",
            "--group-by", "kind",
        ])

        #expect(eventsCLI.filters.window == nil)
        #expect(eventsCLI.windowBounds == QueryWindowBounds(
            since: QueryDateParser.parse(since)!,
            until: QueryDateParser.parse(until)!
        ))
        #expect(eventsCLI.filters.cameras == ["Driveway", "Backyard"])
        #expect(eventsCLI.filters.kinds == ["person", "vehicle"])
        #expect(eventsCLI.filters.weekdays == [.mon, .sun, .sat])
        #expect(eventsCLI.filters.timeOfDay == QueryTimeOfDayRange(startHour: 22, startMinute: 15, endHour: 6, endMinute: 45))
        #expect(eventsCLI.filters.date == "2026-03-29")
        #expect(eventsCLI.filters.hour == "06:00")
        #expect(eventsCLI.order == .oldest)
        #expect(eventsCLI.limit == 25)

        #expect(summaryCLI.filters.cameras == ["Driveway"])
        #expect(summaryCLI.filters.kinds == ["person"])
        #expect(Set(summaryCLI.filters.weekdays) == Set([.mon, .tue, .wed, .thu, .fri, .sun]))
        #expect(summaryCLI.filters.timeOfDay == QueryTimeOfDayRange(startHour: 22, startMinute: 15, endHour: 6, endMinute: 45))
        #expect(summaryCLI.filters.date == "2026-03-30")
        #expect(summaryCLI.filters.hour == "05:00")
        #expect(summaryCLI.windowBounds == QueryWindowBounds(
            since: QueryDateParser.parse(since)!,
            until: QueryDateParser.parse(until)!
        ))
        #expect(summaryCLI.groupBy == [.date, .kind])
    }

    @Test
    func queryCLIParsesCompareModes() throws {
        let explicitCLI = try QueryCLI(arguments: [
            "compare",
            "--since", "2026-03-25T01:00:00Z",
            "--until", "2026-03-25T02:00:00Z",
            "--vs-since", "2026-03-24T01:00:00Z",
            "--vs-until", "2026-03-24T02:00:00Z",
            "--camera", "Driveway",
            "--kind", "person",
            "--group-by", "hour",
        ])
        let yesterdayCLI = try QueryCLI(arguments: [
            "compare",
            "--last-hours", "1",
            "--vs-same-window-yesterday",
        ])
        let lastWeekCLI = try QueryCLI(arguments: [
            "compare",
            "--last-hours", "1",
            "--vs-same-window-last-week",
        ])
        let beforeCLI = try QueryCLI(arguments: [
            "compare",
            "--last-hours", "1",
            "--vs-window-before", "2026-03-24T02:00:00Z",
        ])
        let afterCLI = try QueryCLI(arguments: [
            "compare",
            "--last-hours", "1",
            "--vs-window-after", "2026-03-26T04:00:00Z",
        ])
        let priorCLI = try QueryCLI(arguments: [
            "compare",
            "--last-hours", "1",
            "--vs-prior-window",
        ])
        let sameWeekdayPriorWeeksCLI = try QueryCLI(arguments: [
            "compare",
            "--last-hours", "1",
            "--vs-same-weekday-prior-weeks", "4",
        ])

        #expect(explicitCLI.windowBounds == QueryWindowBounds(
            since: QueryDateParser.parse("2026-03-25T01:00:00Z")!,
            until: QueryDateParser.parse("2026-03-25T02:00:00Z")!
        ))
        #expect(explicitCLI.compareMode == .explicitWindow(QueryWindowBounds(
            since: QueryDateParser.parse("2026-03-24T01:00:00Z")!,
            until: QueryDateParser.parse("2026-03-24T02:00:00Z")!
        )))
        #expect(explicitCLI.filters.cameras == ["Driveway"])
        #expect(explicitCLI.filters.kinds == ["person"])
        #expect(explicitCLI.groupBy == [.hour])

        #expect(yesterdayCLI.compareMode == .sameWindowYesterday)
        #expect(lastWeekCLI.compareMode == .sameWindowLastWeek)
        #expect(beforeCLI.compareMode == .windowBefore(QueryDateParser.parse("2026-03-24T02:00:00Z")!))
        #expect(afterCLI.compareMode == .windowAfter(QueryDateParser.parse("2026-03-26T04:00:00Z")!))
        #expect(priorCLI.compareMode == .priorWindow)
        #expect(sameWeekdayPriorWeeksCLI.compareMode == .sameWeekdayPriorWeeks(4))
    }

    @Test
    func queryCLIRejectsConflictingCompareModes() throws {
        do {
            _ = try QueryCLI(arguments: [
                "compare",
                "--last-hours", "1",
                "--vs-same-window-yesterday",
                "--vs-same-window-last-week",
            ])
            Issue.record("expected conflicting compare mode error")
        } catch let error as QueryCLIError {
            #expect(error.description == "use exactly one compare mode: --vs-since/--vs-until, --vs-same-window-yesterday, --vs-same-window-last-week, --vs-same-weekday-prior-weeks, --vs-window-before, --vs-window-after, or --vs-prior-window")
        }

        do {
            _ = try QueryCLI(arguments: [
                "compare",
                "--last-hours", "1",
                "--vs-same-window-last-week",
                "--vs-window-before", "2026-03-20 09:00",
            ])
            Issue.record("expected conflicting compare mode error")
        } catch let error as QueryCLIError {
            #expect(error.description == "use exactly one compare mode: --vs-since/--vs-until, --vs-same-window-yesterday, --vs-same-window-last-week, --vs-same-weekday-prior-weeks, --vs-window-before, --vs-window-after, or --vs-prior-window")
        }

        do {
            _ = try QueryCLI(arguments: [
                "compare",
                "--last-hours", "1",
                "--vs-window-after", "2026-03-20 09:00",
                "--vs-prior-window",
            ])
            Issue.record("expected conflicting compare mode error")
        } catch let error as QueryCLIError {
            #expect(error.description == "use exactly one compare mode: --vs-since/--vs-until, --vs-same-window-yesterday, --vs-same-window-last-week, --vs-same-weekday-prior-weeks, --vs-window-before, --vs-window-after, or --vs-prior-window")
        }

        do {
            _ = try QueryCLI(arguments: [
                "compare",
                "--last-hours", "1",
                "--vs-since", "2026-03-24T01:00:00Z",
                "--vs-until", "2026-03-24T02:00:00Z",
                "--vs-prior-window",
            ])
            Issue.record("expected explicit/helper compare mode conflict")
        } catch let error as QueryCLIError {
            #expect(error.description == "use exactly one compare mode: --vs-since/--vs-until, --vs-same-window-yesterday, --vs-same-window-last-week, --vs-same-weekday-prior-weeks, --vs-window-before, --vs-window-after, or --vs-prior-window")
        }

        do {
            _ = try QueryCLI(arguments: [
                "compare",
                "--last-hours", "1",
                "--vs-same-window-last-week",
                "--vs-same-weekday-prior-weeks", "4",
            ])
            Issue.record("expected same-weekday compare mode conflict")
        } catch let error as QueryCLIError {
            #expect(error.description == "use exactly one compare mode: --vs-since/--vs-until, --vs-same-window-yesterday, --vs-same-window-last-week, --vs-same-weekday-prior-weeks, --vs-window-before, --vs-window-after, or --vs-prior-window")
        }
    }

    @Test
    func queryCLIRejectsInvalidSameWeekdayPriorWeekCount() throws {
        do {
            _ = try QueryCLI(arguments: [
                "compare",
                "--last-hours", "1",
                "--vs-same-weekday-prior-weeks", "0",
            ])
            Issue.record("expected invalid same-weekday prior week count error")
        } catch let error as QueryCLIError {
            #expect(error.description == "--vs-same-weekday-prior-weeks must be greater than zero, got '0'")
        }
    }

    @Test
    func queryCLIRejectsIncompleteExplicitCompareWindow() throws {
        do {
            _ = try QueryCLI(arguments: [
                "compare",
                "--last-hours", "1",
                "--vs-since", "2026-03-24T01:00:00Z",
            ])
            Issue.record("expected incomplete compare window error")
        } catch let error as QueryCLIError {
            #expect(error.description == "--vs-since requires --vs-until, and --vs-until requires --vs-since")
        }
    }

    @Test
    func queryCLIRejectsMissingBoundaryCompareValue() throws {
        do {
            _ = try QueryCLI(arguments: [
                "compare",
                "--last-hours", "1",
                "--vs-window-before",
            ])
            Issue.record("expected missing boundary compare value error")
        } catch {
            #expect(ProtectCadenceCLIQueryCompareCommand.message(for: error).contains("--vs-window-before"))
        }

        do {
            _ = try QueryCLI(arguments: [
                "compare",
                "--last-hours", "1",
                "--vs-window-after",
            ])
            Issue.record("expected missing boundary compare value error")
        } catch {
            #expect(ProtectCadenceCLIQueryCompareCommand.message(for: error).contains("--vs-window-after"))
        }
    }

    @Test
    func queryCLIRejectsCompareWithoutMode() throws {
        do {
            let cli = try QueryCLI(arguments: [
                "compare",
                "--last-hours", "1",
            ])
            _ = try cli.compareRequest(now: Date(timeIntervalSince1970: 0))
            Issue.record("expected missing compare mode error")
        } catch let error as QueryCLIError {
            #expect(error.description == "compare requires one compare mode: --vs-since/--vs-until, --vs-same-window-yesterday, --vs-same-window-last-week, --vs-same-weekday-prior-weeks, --vs-window-before, --vs-window-after, or --vs-prior-window")
        }
    }

    @Test
    func queryCLIRejectsCompareWithoutPrimaryWindow() throws {
        do {
            let cli = try QueryCLI(arguments: [
                "compare",
                "--vs-same-window-yesterday",
            ])
            _ = try cli.compareRequest(now: Date(timeIntervalSince1970: 0))
            Issue.record("expected missing primary window error")
        } catch let error as QueryCLIError {
            #expect(error.description == "compare requires a primary window via --last-hours or --since [--until]")
        }
    }

    @Test
    func queryCLIResolvesCompareHelperUsingPrimaryWindowShiftedBackOneDay() throws {
        try withDefaultTimeZone("America/Los_Angeles") {
            let cli = try QueryCLI(arguments: [
                "compare",
                "--since", "2026-03-27 08:00",
                "--until", "2026-03-27 09:30",
                "--vs-same-window-yesterday",
            ])

            let request = try cli.compareRequest(now: Date(timeIntervalSince1970: 0))

            #expect(request.compareMode == .sameWindowYesterday)
            #expect(request.filters.window == QueryWindow(
                start: localDate(day: 27, hour: 8, minute: 0),
                end: localDate(day: 27, hour: 9, minute: 30)
            ))
            #expect(request.comparisonWindow == QueryWindow(
                start: localDate(day: 26, hour: 8, minute: 0),
                end: localDate(day: 26, hour: 9, minute: 30)
            ))
        }
    }

    @Test
    func queryCLIResolvesPriorWindowCompareHelperUsingEqualPrimaryDuration() throws {
        try withDefaultTimeZone("America/Los_Angeles") {
            let cli = try QueryCLI(arguments: [
                "compare",
                "--since", "2026-03-27 08:00",
                "--until", "2026-03-27 09:30",
                "--vs-prior-window",
            ])

            let request = try cli.compareRequest(now: Date(timeIntervalSince1970: 0))

            #expect(request.compareMode == .priorWindow)
            #expect(request.filters.window == QueryWindow(
                start: localDate(day: 27, hour: 8, minute: 0),
                end: localDate(day: 27, hour: 9, minute: 30)
            ))
            #expect(request.comparisonWindow == QueryWindow(
                start: localDate(day: 27, hour: 6, minute: 30),
                end: localDate(day: 27, hour: 8, minute: 0)
            ))
        }
    }

    @Test
    func queryCLIResolvesSameWindowLastWeekUsingPrimaryWindowShiftedBackSevenDays() throws {
        try withDefaultTimeZone("America/Los_Angeles") {
            let cli = try QueryCLI(arguments: [
                "compare",
                "--since", "2026-03-27 08:00",
                "--until", "2026-03-27 09:30",
                "--vs-same-window-last-week",
            ])

            let request = try cli.compareRequest(now: Date(timeIntervalSince1970: 0))

            #expect(request.compareMode == .sameWindowLastWeek)
            #expect(request.filters.window == QueryWindow(
                start: localDate(day: 27, hour: 8, minute: 0),
                end: localDate(day: 27, hour: 9, minute: 30)
            ))
            #expect(request.comparisonWindow == QueryWindow(
                start: localDate(day: 20, hour: 8, minute: 0),
                end: localDate(day: 20, hour: 9, minute: 30)
            ))
        }
    }

    @Test
    func queryCLIResolvesSameWeekdayPriorWeeksUsingMatchingLocalSpans() throws {
        try withDefaultTimeZone("America/Los_Angeles") {
            let cli = try QueryCLI(arguments: [
                "compare",
                "--since", "2026-04-27 08:00",
                "--until", "2026-04-27 10:00",
                "--vs-same-weekday-prior-weeks", "4",
            ])

            let request = try cli.compareRequest(now: Date(timeIntervalSince1970: 0))

            #expect(request.compareMode == .sameWeekdayPriorWeeks(4))
            #expect(request.filters.window == QueryWindow(
                start: localDate(month: 4, day: 27, hour: 8, minute: 0),
                end: localDate(month: 4, day: 27, hour: 10, minute: 0)
            ))
            #expect(request.comparisonWindows == [
                QueryWindow(
                    start: localDate(month: 4, day: 20, hour: 8, minute: 0),
                    end: localDate(month: 4, day: 20, hour: 10, minute: 0)
                ),
                QueryWindow(
                    start: localDate(month: 4, day: 13, hour: 8, minute: 0),
                    end: localDate(month: 4, day: 13, hour: 10, minute: 0)
                ),
                QueryWindow(
                    start: localDate(month: 4, day: 6, hour: 8, minute: 0),
                    end: localDate(month: 4, day: 6, hour: 10, minute: 0)
                ),
                QueryWindow(
                    start: localDate(day: 30, hour: 8, minute: 0),
                    end: localDate(day: 30, hour: 10, minute: 0)
                ),
            ])
        }
    }

    @Test
    func queryCLIResolvesWindowBeforeBoundaryUsingPrimaryDuration() throws {
        try withDefaultTimeZone("America/Los_Angeles") {
            let cli = try QueryCLI(arguments: [
                "compare",
                "--since", "2026-03-27 08:00",
                "--until", "2026-03-27 09:00",
                "--vs-window-before", "2026-03-20 09:00",
            ])

            let request = try cli.compareRequest(now: Date(timeIntervalSince1970: 0))

            #expect(request.compareMode == .windowBefore(localDate(day: 20, hour: 9, minute: 0)))
            #expect(request.comparisonWindow == QueryWindow(
                start: localDate(day: 20, hour: 8, minute: 0),
                end: localDate(day: 20, hour: 9, minute: 0)
            ))
        }
    }

    @Test
    func queryCLIResolvesWindowAfterBoundaryUsingPrimaryDuration() throws {
        try withDefaultTimeZone("America/Los_Angeles") {
            let cli = try QueryCLI(arguments: [
                "compare",
                "--since", "2026-03-20 08:00",
                "--until", "2026-03-20 09:00",
                "--vs-window-after", "2026-03-27 08:00",
            ])

            let request = try cli.compareRequest(now: Date(timeIntervalSince1970: 0))

            #expect(request.compareMode == .windowAfter(localDate(day: 27, hour: 8, minute: 0)))
            #expect(request.comparisonWindow == QueryWindow(
                start: localDate(day: 27, hour: 8, minute: 0),
                end: localDate(day: 27, hour: 9, minute: 0)
            ))
        }
    }

    @Test
    func queryDateParserAcceptsLocalDateAndTimeForms() throws {
        let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))

        #expect(QueryDateParser.parse("2026-03-27", timeZone: timeZone) == localDate(day: 27, hour: 0, minute: 0))
        #expect(QueryDateParser.parse("2026-03-27 14:05", timeZone: timeZone) == localDate(day: 27, hour: 14, minute: 5))
        #expect(QueryDateParser.parse("2026-03-27T14:05", timeZone: timeZone) == localDate(day: 27, hour: 14, minute: 5))
        #expect(QueryDateParser.parse("2026-03-27 14:05:09", timeZone: timeZone) == localDate(day: 27, hour: 14, minute: 5, second: 9))
    }

    @Test
    func queryDateParserRejectsInvalidLocalForms() throws {
        let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))

        #expect(QueryDateParser.parse("2026-03-27 7:05", timeZone: timeZone) == nil)
        #expect(QueryDateParser.parse("2026-02-30", timeZone: timeZone) == nil)
    }

    @Test
    func queryCLIResolvesLocalDateOnlyBoundsAtHostLocalMidnight() throws {
        try withDefaultTimeZone("America/Los_Angeles") {
            let cli = try QueryCLI(arguments: [
                "events",
                "--since", "2026-03-27",
                "--until", "2026-03-28",
            ])

            let request = try cli.eventsRequest(now: Date(timeIntervalSince1970: 0))

            #expect(request.filters.window == QueryWindow(
                start: localDate(day: 27, hour: 0, minute: 0),
                end: localDate(day: 28, hour: 0, minute: 0)
            ))
        }
    }

    @Test
    func queryCLIResolvesDateFilterWithoutExplicitWindowToFullLocalDay() throws {
        try withDefaultTimeZone("America/Los_Angeles") {
            let now = localDate(day: 28, hour: 12, minute: 0)
            let expectedWindow = QueryWindow(
                start: localDate(day: 27, hour: 0, minute: 0),
                end: localDate(day: 28, hour: 0, minute: 0)
            )

            let eventsRequest = try QueryCLI(arguments: [
                "events",
                "--date", "2026-03-27",
            ]).eventsRequest(now: now)

            let summaryRequest = try QueryCLI(arguments: [
                "summary",
                "--date", "2026-03-27",
            ]).summaryRequest(now: now)

            #expect(eventsRequest.filters.window == expectedWindow)
            #expect(summaryRequest.filters.window == expectedWindow)
        }
    }

    @Test
    func queryCLILeavesHourWithoutExplicitWindowAsPureFilterForEvents() throws {
        let now = QueryDateParser.parse("2026-03-28T12:00:00Z")!
        let request = try QueryCLI(arguments: [
            "events",
            "--hour", "08:00",
        ]).eventsRequest(now: now)

        #expect(request.filters.window == nil)
        #expect(request.filters.hour == "08:00")
    }

    @Test
    func queryCLIUsesSummaryDefaultWindowWhenHourHasNoExplicitWindow() throws {
        let now = QueryDateParser.parse("2026-03-28T12:00:00Z")!
        let request = try QueryCLI(arguments: [
            "summary",
            "--hour", "08:00",
        ]).summaryRequest(now: now)

        #expect(request.filters.window == QueryWindow(
            start: now.addingTimeInterval(-24 * 60 * 60),
            end: now
        ))
        #expect(request.filters.hour == "08:00")
    }

    @Test
    func queryCLIResolvesDateAndHourWithoutExplicitWindowToFullLocalDay() throws {
        try withDefaultTimeZone("America/Los_Angeles") {
            let now = localDate(day: 28, hour: 12, minute: 0)
            let expectedWindow = QueryWindow(
                start: localDate(day: 27, hour: 0, minute: 0),
                end: localDate(day: 28, hour: 0, minute: 0)
            )

            let eventsRequest = try QueryCLI(arguments: [
                "events",
                "--date", "2026-03-27",
                "--hour", "08:00",
            ]).eventsRequest(now: now)

            let summaryRequest = try QueryCLI(arguments: [
                "summary",
                "--date", "2026-03-27",
                "--hour", "08:00",
            ]).summaryRequest(now: now)

            #expect(eventsRequest.filters.window == expectedWindow)
            #expect(eventsRequest.filters.date == "2026-03-27")
            #expect(eventsRequest.filters.hour == "08:00")
            #expect(summaryRequest.filters.window == expectedWindow)
            #expect(summaryRequest.filters.date == "2026-03-27")
            #expect(summaryRequest.filters.hour == "08:00")
        }
    }

    @Test
    func queryCLIRejectsInvalidDayOfWeek() throws {
        do {
            _ = try QueryCLI(arguments: [
                "events",
                "--day-of-week", "monday",
            ])
            Issue.record("expected invalid weekday error")
        } catch let error as QueryCLIError {
            #expect(error.description == "invalid value 'monday' for --day-of-week, expected sun, mon, tue, wed, thu, fri, or sat")
        }
    }

    @Test
    func queryCLIRejectsInvalidDateBucket() throws {
        do {
            _ = try QueryCLI(arguments: [
                "events",
                "--date", "2026-02-30",
            ])
            Issue.record("expected invalid date bucket error")
        } catch let error as QueryCLIError {
            #expect(error.description == "invalid value '2026-02-30' for --date, expected local YYYY-MM-DD")
        }
    }

    @Test
    func queryCLIRejectsInvalidHourBucket() throws {
        do {
            _ = try QueryCLI(arguments: [
                "events",
                "--hour", "07:30",
            ])
            Issue.record("expected invalid hour bucket error")
        } catch let error as QueryCLIError {
            #expect(error.description == "invalid value '07:30' for --hour, expected HH:00")
        }
    }

    @Test
    func queryCLIRejectsConflictingWindowFlags() throws {
        do {
            _ = try QueryCLI(arguments: ["events", "--last-hours", "2", "--since", "2026-03-25T01:00:00Z", "--until", "2026-03-25T02:00:00Z"])
            Issue.record("expected conflicting window flags error")
        } catch let error as QueryCLIError {
            #expect(error.description.contains("either --last-hours or --since/--until"))
        }
    }

    @Test
    func queryRequestResolutionUsesNowForMissingUpperSide() throws {
        let now = QueryDateParser.parse("2026-03-25T05:00:00Z")!
        let eventsCLI = try QueryCLI(arguments: [
            "events",
            "--since", "2026-03-25T01:00:00Z",
        ])

        let eventsRequest = try eventsCLI.eventsRequest(now: now)

        #expect(eventsRequest.filters.window == QueryWindow(
            start: QueryDateParser.parse("2026-03-25T01:00:00Z")!,
            end: now
        ))
    }

    @Test
    func queryRequestResolutionRejectsInvalidResolvedWindow() throws {
        let now = QueryDateParser.parse("2026-03-25T05:00:00Z")!
        let cli = try QueryCLI(arguments: [
            "events",
            "--since", "2026-03-25T06:00:00Z",
        ])

        do {
            _ = try cli.eventsRequest(now: now)
            Issue.record("expected invalid resolved window error")
        } catch let error as QueryCLIError {
            #expect(error.description == "resolved time window must have start earlier than end, got 2026-03-25T06:00:00Z to 2026-03-25T05:00:00Z")
        }
    }

    @Test
    func queryCLIRejectsInvalidExplicitSinceUntilRange() throws {
        do {
            _ = try QueryCLI(arguments: [
                "summary",
                "--since", "2026-03-25T05:00:00Z",
                "--until", "2026-03-25T05:00:00Z",
            ])
            Issue.record("expected invalid explicit window error")
        } catch let error as QueryCLIError {
            #expect(error.description == "resolved time window must have start earlier than end, got 2026-03-25T05:00:00Z to 2026-03-25T05:00:00Z")
        }
    }

    @Test
    func queryRunnerUsesConfiguredDatabasePath() throws {
        let configPath = temporaryDirectoryPath() + "/config.json"
        let databasePath = temporaryDatabasePath()
        let database = try ProtectCadenceDatabase(path: databasePath)

        try insertRows(
            [
                EventRow(
                    timeStart: Date(timeIntervalSince1970: 200),
                    camera: "Backyard",
                    kind: "animal",
                    eventID: "event-2"
                ),
            ],
            into: database
        )

        try ProtectCadenceConfigStore.save(
            ProtectCadenceConfig(databasePath: databasePath),
            to: configPath
        )

        let output = try ProtectCadenceQueryRunner.run(
            arguments: ["events", "--config", configPath, "--limit", "1"]
        )

        switch output {
        case let .events(response):
            #expect(response.databasePath == databasePath)
            #expect(response.events.map(\.eventID) == ["event-2"])
            #expect(response.countSemantics == .events)
        case .summary, .compare:
            Issue.record("expected events output")
        }
    }

    @Test
    func queryRunnerRecentStillReturnsNewestFirst() throws {
        let databasePath = temporaryDatabasePath()
        let database = try ProtectCadenceDatabase(path: databasePath)

        try insertRows(
            [
                EventRow(
                    timeStart: Date(timeIntervalSince1970: 100),
                    camera: "Driveway",
                    kind: "vehicle",
                    eventID: "event-1"
                ),
                EventRow(
                    timeStart: Date(timeIntervalSince1970: 200),
                    camera: "Backyard",
                    kind: "animal",
                    eventID: "event-2"
                ),
            ],
            into: database
        )

        let output = try ProtectCadenceQueryRunner.run(
            arguments: ["events", "--db", databasePath, "--limit", "1"]
        )

        switch output {
        case let .events(response):
            #expect(response.events.map(\.eventID) == ["event-2"])
        case .summary, .compare:
            Issue.record("expected events output")
        }
    }

    @Test
    func queryRunnerRecentCanFilterByLastHours() throws {
        let databasePath = temporaryDatabasePath()
        let database = try ProtectCadenceDatabase(path: databasePath)
        let now = Date(timeIntervalSince1970: 10_000)

        try insertRows(
            [
                EventRow(
                    timeStart: now.addingTimeInterval(-30 * 60),
                    camera: "Driveway",
                    kind: "vehicle",
                    eventID: "recent-event"
                ),
                EventRow(
                    timeStart: now.addingTimeInterval(-26 * 60 * 60),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "old-event"
                ),
            ],
            into: database
        )

        let output = try ProtectCadenceQueryRunner.run(
            arguments: ["events", "--db", databasePath, "--last-hours", "24"],
            now: now
        )

        switch output {
        case let .events(response):
            #expect(response.filters.window == QueryWindow(start: now.addingTimeInterval(-24 * 60 * 60), end: now))
            #expect(response.events.map(\.eventID) == ["recent-event"])
        case .summary, .compare:
            Issue.record("expected events output")
        }
    }

    @Test
    func queryRunnerEventsCanFilterBySinceOnly() throws {
        let databasePath = temporaryDatabasePath()
        let database = try ProtectCadenceDatabase(path: databasePath)
        let now = Date(timeIntervalSince1970: 10_000)

        try insertRows(
            [
                EventRow(
                    timeStart: now.addingTimeInterval(-2 * 60 * 60),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "older-event"
                ),
                EventRow(
                    timeStart: now.addingTimeInterval(-30 * 60),
                    camera: "Driveway",
                    kind: "vehicle",
                    eventID: "recent-event"
                ),
            ],
            into: database
        )

        let output = try ProtectCadenceQueryRunner.run(
            arguments: [
                "events",
                "--db", databasePath,
                "--since", QueryDateParser.encode(now.addingTimeInterval(-60 * 60)),
            ],
            now: now
        )

        switch output {
        case let .events(response):
            #expect(response.filters.window == QueryWindow(start: now.addingTimeInterval(-60 * 60), end: now))
            #expect(response.events.map(\.eventID) == ["recent-event"])
        case .summary, .compare:
            Issue.record("expected events output")
        }
    }

    @Test
    func queryRunnerSummaryUsesFullLocalDayForDateWithoutExplicitWindow() throws {
        let databasePath = temporaryDatabasePath()
        let database = try ProtectCadenceDatabase(path: databasePath)

        try insertRows(
            [
                EventRow(
                    timeStart: localDate(day: 25, hour: 1, minute: 15),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "day-start"
                ),
                EventRow(
                    timeStart: localDate(day: 25, hour: 23, minute: 10),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "day-end"
                ),
                EventRow(
                    timeStart: localDate(day: 26, hour: 1, minute: 0),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "next-day"
                ),
            ],
            into: database
        )

        let output = try withDefaultTimeZone("America/Los_Angeles") {
            try ProtectCadenceQueryRunner.run(
                arguments: [
                    "summary",
                    "--db", databasePath,
                    "--date", "2026-03-25",
                ],
                now: localDate(day: 26, hour: 12, minute: 0)
            )
        }

        switch output {
        case let .summary(response):
            #expect(response.filters.window == QueryWindow(
                start: localDate(day: 25, hour: 0, minute: 0),
                end: localDate(day: 26, hour: 0, minute: 0)
            ))
            #expect(response.totalEventCount == 2)
            #expect(response.totalSourceEventCount == 2)
            #expect(response.groups == [
                summaryGroup(
                    group: ["camera": "Driveway", "kind": "person"],
                    eventCount: 2,
                    sourceEventCount: 2,
                    filters: QueryFilters(
                        window: QueryWindow(
                            start: localDate(day: 25, hour: 0, minute: 0),
                            end: localDate(day: 26, hour: 0, minute: 0)
                        ),
                        cameras: ["Driveway"],
                        kinds: ["person"],
                        date: "2026-03-25"
                    )
                ),
            ])
        case .events, .compare:
            Issue.record("expected summary output")
        }
    }

    @Test
    func queryRunnerAppliesWeekdayFiltersToEventsAndSummary() throws {
        let databasePath = temporaryDatabasePath()
        let database = try ProtectCadenceDatabase(path: databasePath)

        try insertRows(
            [
                EventRow(
                    timeStart: localDate(day: 27, hour: 21, minute: 0),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "fri-event"
                ),
                EventRow(
                    timeStart: localDate(day: 28, hour: 21, minute: 0),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "sat-event"
                ),
                EventRow(
                    timeStart: localDate(day: 29, hour: 21, minute: 0),
                    camera: "Driveway",
                    kind: "vehicle",
                    eventID: "sun-event"
                ),
            ],
            into: database
        )

        let eventsOutput = try ProtectCadenceQueryRunner.run(
            arguments: [
                "events",
                "--db", databasePath,
                "--since", "2026-03-27T00:00:00-07:00",
                "--until", "2026-03-30T00:00:00-07:00",
                "--weekend",
                "--order", "oldest",
            ]
        )
        let summaryOutput = try ProtectCadenceQueryRunner.run(
            arguments: [
                "summary",
                "--db", databasePath,
                "--since", "2026-03-27T00:00:00-07:00",
                "--until", "2026-03-30T00:00:00-07:00",
                "--day-of-week", "sun",
                "--group-by", "weekday",
            ]
        )

        switch eventsOutput {
        case let .events(response):
            #expect(response.filters.weekdays == [.sun, .sat])
            #expect(response.events.map(\.eventID) == ["sat-event", "sun-event"])
        case .summary, .compare:
            Issue.record("expected events output")
        }

        switch summaryOutput {
        case let .summary(response):
            #expect(response.filters.weekdays == [.sun])
            #expect(response.totalEventCount == 1)
            #expect(response.groups == [
                summaryGroup(
                    group: ["weekday": "sun"],
                    eventCount: 1,
                    sourceEventCount: 1,
                    filters: QueryFilters(
                        window: QueryWindow(
                            start: localDate(day: 27, hour: 0, minute: 0),
                            end: localDate(day: 30, hour: 0, minute: 0)
                        ),
                        weekdays: [.sun]
                    )
                ),
            ])
        case .events, .compare:
            Issue.record("expected summary output")
        }
    }

    @Test
    func queryRunnerSummarySupportsDistributionGroupsInOneWindow() throws {
        let databasePath = temporaryDatabasePath()
        let database = try ProtectCadenceDatabase(path: databasePath)

        try insertRows(
            [
                EventRow(
                    timeStart: localDate(day: 25, hour: 8, minute: 5),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "driveway-person"
                ),
                EventRow(
                    timeStart: localDate(day: 25, hour: 8, minute: 15),
                    camera: "Backyard",
                    kind: "animal",
                    eventID: "backyard-animal"
                ),
                EventRow(
                    timeStart: localDate(day: 25, hour: 9, minute: 10),
                    camera: "Porch",
                    kind: "package",
                    eventID: "porch-package"
                ),
            ],
            into: database
        )

        let output = try withDefaultTimeZone("America/Los_Angeles") {
            try ProtectCadenceQueryRunner.run(
                arguments: [
                    "summary",
                    "--db", databasePath,
                    "--since", "2026-03-25 08:00",
                    "--until", "2026-03-25 10:00",
                    "--group-by", "weekday",
                    "--group-by", "hour",
                    "--group-by", "camera",
                ]
            )
        }

        switch output {
        case let .summary(response):
            let window = QueryWindow(
                start: localDate(day: 25, hour: 8, minute: 0),
                end: localDate(day: 25, hour: 10, minute: 0)
            )

            #expect(response.filters.window == window)
            #expect(response.groupBy == [.weekday, .hour, .camera])
            #expect(response.totalEventCount == 3)
            #expect(response.totalSourceEventCount == 3)
            #expect(response.groups == [
                summaryGroup(
                    group: ["weekday": "wed", "hour": "08:00", "camera": "Backyard"],
                    eventCount: 1,
                    sourceEventCount: 1,
                    filters: QueryFilters(
                        window: window,
                        cameras: ["Backyard"],
                        weekdays: [.wed],
                        hour: "08:00"
                    )
                ),
                summaryGroup(
                    group: ["weekday": "wed", "hour": "08:00", "camera": "Driveway"],
                    eventCount: 1,
                    sourceEventCount: 1,
                    filters: QueryFilters(
                        window: window,
                        cameras: ["Driveway"],
                        weekdays: [.wed],
                        hour: "08:00"
                    )
                ),
                summaryGroup(
                    group: ["weekday": "wed", "hour": "09:00", "camera": "Porch"],
                    eventCount: 1,
                    sourceEventCount: 1,
                    filters: QueryFilters(
                        window: window,
                        cameras: ["Porch"],
                        weekdays: [.wed],
                        hour: "09:00"
                    )
                ),
            ])

            let json = try JSONOutput.encode(output)
            #expect(json.contains("\"groupBy\""))
            #expect(json.contains("\"weekday\""))
            #expect(json.contains("\"hour\""))
            #expect(json.contains("\"camera\""))
            #expect(json.contains("\"drillDown\""))
        case .events, .compare:
            Issue.record("expected summary output")
        }
    }

    @Test
    func queryRunnerCompareProducesWindowToWindowCountsAndDeltas() throws {
        let databasePath = temporaryDatabasePath()
        let database = try ProtectCadenceDatabase(path: databasePath)

        try insertRows(
            [
                EventRow(
                    timeStart: localDate(day: 27, hour: 8, minute: 5),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "window-driveway-person-1"
                ),
                EventRow(
                    timeStart: localDate(day: 27, hour: 8, minute: 15),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "window-driveway-person-2"
                ),
                EventRow(
                    timeStart: localDate(day: 27, hour: 8, minute: 20),
                    camera: "Porch",
                    kind: "package",
                    eventID: "window-porch-package"
                ),
                EventRow(
                    timeStart: localDate(day: 26, hour: 8, minute: 10),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "comparison-driveway-person"
                ),
                EventRow(
                    timeStart: localDate(day: 26, hour: 8, minute: 25),
                    camera: "Driveway",
                    kind: "vehicle",
                    eventID: "comparison-driveway-vehicle"
                ),
            ],
            into: database
        )

        let output = try ProtectCadenceQueryRunner.run(
            arguments: [
                "compare",
                "--db", databasePath,
                "--since", "2026-03-27 08:00",
                "--until", "2026-03-27 09:00",
                "--vs-since", "2026-03-26 08:00",
                "--vs-until", "2026-03-26 09:00",
            ]
        )

        switch output {
        case let .compare(response):
            #expect(response.filters.window == QueryWindow(
                start: localDate(day: 27, hour: 8, minute: 0),
                end: localDate(day: 27, hour: 9, minute: 0)
            ))
            #expect(response.comparisonWindow == QueryWindow(
                start: localDate(day: 26, hour: 8, minute: 0),
                end: localDate(day: 26, hour: 9, minute: 0)
            ))
            #expect(response.groupBy == [.camera, .kind])
            #expect(response.totals == CompareCounts(eventCount: 3, sourceEventCount: 3))
            #expect(response.comparisonTotals == CompareCounts(eventCount: 2, sourceEventCount: 2))
            #expect(response.totalEventCountDelta == 1)
            #expect(response.totalSourceEventCountDelta == 1)
            #expect(response.groups == [
                compareGroup(
                    group: ["camera": "Driveway", "kind": "person"],
                    window: CompareCounts(eventCount: 2, sourceEventCount: 2),
                    comparisonWindow: CompareCounts(eventCount: 1, sourceEventCount: 1),
                    eventCountDelta: 1,
                    sourceEventCountDelta: 1,
                    windowFilters: QueryFilters(
                        window: QueryWindow(
                            start: localDate(day: 27, hour: 8, minute: 0),
                            end: localDate(day: 27, hour: 9, minute: 0)
                        ),
                        cameras: ["Driveway"],
                        kinds: ["person"]
                    ),
                    comparisonFilters: QueryFilters(
                        window: QueryWindow(
                            start: localDate(day: 26, hour: 8, minute: 0),
                            end: localDate(day: 26, hour: 9, minute: 0)
                        ),
                        cameras: ["Driveway"],
                        kinds: ["person"]
                    )
                ),
                compareGroup(
                    group: ["camera": "Driveway", "kind": "vehicle"],
                    window: CompareCounts(eventCount: 0, sourceEventCount: 0),
                    comparisonWindow: CompareCounts(eventCount: 1, sourceEventCount: 1),
                    eventCountDelta: -1,
                    sourceEventCountDelta: -1,
                    windowFilters: QueryFilters(
                        window: QueryWindow(
                            start: localDate(day: 27, hour: 8, minute: 0),
                            end: localDate(day: 27, hour: 9, minute: 0)
                        ),
                        cameras: ["Driveway"],
                        kinds: ["vehicle"]
                    ),
                    comparisonFilters: QueryFilters(
                        window: QueryWindow(
                            start: localDate(day: 26, hour: 8, minute: 0),
                            end: localDate(day: 26, hour: 9, minute: 0)
                        ),
                        cameras: ["Driveway"],
                        kinds: ["vehicle"]
                    )
                ),
                compareGroup(
                    group: ["camera": "Porch", "kind": "package"],
                    window: CompareCounts(eventCount: 1, sourceEventCount: 1),
                    comparisonWindow: CompareCounts(eventCount: 0, sourceEventCount: 0),
                    eventCountDelta: 1,
                    sourceEventCountDelta: 1,
                    windowFilters: QueryFilters(
                        window: QueryWindow(
                            start: localDate(day: 27, hour: 8, minute: 0),
                            end: localDate(day: 27, hour: 9, minute: 0)
                        ),
                        cameras: ["Porch"],
                        kinds: ["package"]
                    ),
                    comparisonFilters: QueryFilters(
                        window: QueryWindow(
                            start: localDate(day: 26, hour: 8, minute: 0),
                            end: localDate(day: 26, hour: 9, minute: 0)
                        ),
                        cameras: ["Porch"],
                        kinds: ["package"]
                    )
                ),
            ])

            let json = try JSONOutput.encode(output)
            #expect(json.contains("\"comparisonWindow\""))
            #expect(json.contains("\"eventCountDelta\""))
            #expect(json.contains("\"comparisonTotals\""))
            #expect(json.contains("\"windowDrillDown\""))
            #expect(json.contains("\"comparisonWindowDrillDown\""))
        case .events, .summary:
            Issue.record("expected compare output")
        }
    }



    @Test
    func queryRunnerComparePreservesZeroBucketsAcrossWindows() throws {
        let databasePath = temporaryDatabasePath()
        let database = try ProtectCadenceDatabase(path: databasePath)

        try insertRows(
            [
                EventRow(
                    timeStart: localDate(day: 27, hour: 8, minute: 5),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "window-driveway-person"
                ),
                EventRow(
                    timeStart: localDate(day: 26, hour: 8, minute: 25),
                    camera: "Backyard",
                    kind: "animal",
                    eventID: "comparison-backyard-animal"
                ),
            ],
            into: database
        )

        let output = try ProtectCadenceQueryRunner.run(
            arguments: [
                "compare",
                "--db", databasePath,
                "--since", "2026-03-27 08:00",
                "--until", "2026-03-27 09:00",
                "--vs-since", "2026-03-26 08:00",
                "--vs-until", "2026-03-26 09:00",
            ]
        )

        switch output {
        case let .compare(response):
            #expect(response.groups == [
                compareGroup(
                    group: ["camera": "Backyard", "kind": "animal"],
                    window: CompareCounts(eventCount: 0, sourceEventCount: 0),
                    comparisonWindow: CompareCounts(eventCount: 1, sourceEventCount: 1),
                    eventCountDelta: -1,
                    sourceEventCountDelta: -1,
                    windowFilters: QueryFilters(
                        window: QueryWindow(
                            start: localDate(day: 27, hour: 8, minute: 0),
                            end: localDate(day: 27, hour: 9, minute: 0)
                        ),
                        cameras: ["Backyard"],
                        kinds: ["animal"]
                    ),
                    comparisonFilters: QueryFilters(
                        window: QueryWindow(
                            start: localDate(day: 26, hour: 8, minute: 0),
                            end: localDate(day: 26, hour: 9, minute: 0)
                        ),
                        cameras: ["Backyard"],
                        kinds: ["animal"]
                    )
                ),
                compareGroup(
                    group: ["camera": "Driveway", "kind": "person"],
                    window: CompareCounts(eventCount: 1, sourceEventCount: 1),
                    comparisonWindow: CompareCounts(eventCount: 0, sourceEventCount: 0),
                    eventCountDelta: 1,
                    sourceEventCountDelta: 1,
                    windowFilters: QueryFilters(
                        window: QueryWindow(
                            start: localDate(day: 27, hour: 8, minute: 0),
                            end: localDate(day: 27, hour: 9, minute: 0)
                        ),
                        cameras: ["Driveway"],
                        kinds: ["person"]
                    ),
                    comparisonFilters: QueryFilters(
                        window: QueryWindow(
                            start: localDate(day: 26, hour: 8, minute: 0),
                            end: localDate(day: 26, hour: 9, minute: 0)
                        ),
                        cameras: ["Driveway"],
                        kinds: ["person"]
                    )
                ),
            ])
        case .events, .summary:
            Issue.record("expected compare output")
        }
    }

    @Test
    func queryRunnerCompareSupportsPriorWindowHelperEndToEnd() throws {
        let databasePath = temporaryDatabasePath()
        let database = try ProtectCadenceDatabase(path: databasePath)

        try insertRows(
            [
                EventRow(
                    timeStart: localDate(day: 27, hour: 8, minute: 10),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "window-driveway-person"
                ),
                EventRow(
                    timeStart: localDate(day: 27, hour: 7, minute: 10),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "prior-driveway-person"
                ),
                EventRow(
                    timeStart: localDate(day: 27, hour: 7, minute: 40),
                    camera: "Porch",
                    kind: "package",
                    eventID: "prior-porch-package"
                ),
            ],
            into: database
        )

        let output = try ProtectCadenceQueryRunner.run(
            arguments: [
                "compare",
                "--db", databasePath,
                "--since", "2026-03-27 08:00",
                "--until", "2026-03-27 09:00",
                "--vs-prior-window",
            ]
        )

        switch output {
        case let .compare(response):
            #expect(response.filters.window == QueryWindow(
                start: localDate(day: 27, hour: 8, minute: 0),
                end: localDate(day: 27, hour: 9, minute: 0)
            ))
            #expect(response.comparisonWindow == QueryWindow(
                start: localDate(day: 27, hour: 7, minute: 0),
                end: localDate(day: 27, hour: 8, minute: 0)
            ))
            #expect(response.totals == CompareCounts(eventCount: 1, sourceEventCount: 1))
            #expect(response.comparisonTotals == CompareCounts(eventCount: 2, sourceEventCount: 2))
            #expect(response.totalEventCountDelta == -1)
            #expect(response.groups == [
                compareGroup(
                    group: ["camera": "Driveway", "kind": "person"],
                    window: CompareCounts(eventCount: 1, sourceEventCount: 1),
                    comparisonWindow: CompareCounts(eventCount: 1, sourceEventCount: 1),
                    eventCountDelta: 0,
                    sourceEventCountDelta: 0,
                    windowFilters: QueryFilters(
                        window: QueryWindow(
                            start: localDate(day: 27, hour: 8, minute: 0),
                            end: localDate(day: 27, hour: 9, minute: 0)
                        ),
                        cameras: ["Driveway"],
                        kinds: ["person"]
                    ),
                    comparisonFilters: QueryFilters(
                        window: QueryWindow(
                            start: localDate(day: 27, hour: 7, minute: 0),
                            end: localDate(day: 27, hour: 8, minute: 0)
                        ),
                        cameras: ["Driveway"],
                        kinds: ["person"]
                    )
                ),
                compareGroup(
                    group: ["camera": "Porch", "kind": "package"],
                    window: CompareCounts(eventCount: 0, sourceEventCount: 0),
                    comparisonWindow: CompareCounts(eventCount: 1, sourceEventCount: 1),
                    eventCountDelta: -1,
                    sourceEventCountDelta: -1,
                    windowFilters: QueryFilters(
                        window: QueryWindow(
                            start: localDate(day: 27, hour: 8, minute: 0),
                            end: localDate(day: 27, hour: 9, minute: 0)
                        ),
                        cameras: ["Porch"],
                        kinds: ["package"]
                    ),
                    comparisonFilters: QueryFilters(
                        window: QueryWindow(
                            start: localDate(day: 27, hour: 7, minute: 0),
                            end: localDate(day: 27, hour: 8, minute: 0)
                        ),
                        cameras: ["Porch"],
                        kinds: ["package"]
                    )
                ),
            ])
        case .events, .summary:
            Issue.record("expected compare output")
        }
    }

    @Test
    func queryRunnerCompareSupportsSameWindowLastWeekHelperEndToEnd() throws {
        let databasePath = temporaryDatabasePath()
        let database = try ProtectCadenceDatabase(path: databasePath)

        try insertRows(
            [
                EventRow(
                    timeStart: localDate(day: 27, hour: 8, minute: 10),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "window-driveway-person"
                ),
                EventRow(
                    timeStart: localDate(day: 20, hour: 8, minute: 10),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "last-week-driveway-person"
                ),
                EventRow(
                    timeStart: localDate(day: 20, hour: 8, minute: 40),
                    camera: "Porch",
                    kind: "package",
                    eventID: "last-week-porch-package"
                ),
            ],
            into: database
        )

        let output = try ProtectCadenceQueryRunner.run(
            arguments: [
                "compare",
                "--db", databasePath,
                "--since", "2026-03-27 08:00",
                "--until", "2026-03-27 09:00",
                "--vs-same-window-last-week",
            ]
        )

        switch output {
        case let .compare(response):
            #expect(response.filters.window == QueryWindow(
                start: localDate(day: 27, hour: 8, minute: 0),
                end: localDate(day: 27, hour: 9, minute: 0)
            ))
            #expect(response.comparisonWindow == QueryWindow(
                start: localDate(day: 20, hour: 8, minute: 0),
                end: localDate(day: 20, hour: 9, minute: 0)
            ))
            #expect(response.totals == CompareCounts(eventCount: 1, sourceEventCount: 1))
            #expect(response.comparisonTotals == CompareCounts(eventCount: 2, sourceEventCount: 2))
            #expect(response.totalEventCountDelta == -1)
            #expect(response.groups == [
                compareGroup(
                    group: ["camera": "Driveway", "kind": "person"],
                    window: CompareCounts(eventCount: 1, sourceEventCount: 1),
                    comparisonWindow: CompareCounts(eventCount: 1, sourceEventCount: 1),
                    eventCountDelta: 0,
                    sourceEventCountDelta: 0,
                    windowFilters: QueryFilters(
                        window: QueryWindow(
                            start: localDate(day: 27, hour: 8, minute: 0),
                            end: localDate(day: 27, hour: 9, minute: 0)
                        ),
                        cameras: ["Driveway"],
                        kinds: ["person"]
                    ),
                    comparisonFilters: QueryFilters(
                        window: QueryWindow(
                            start: localDate(day: 20, hour: 8, minute: 0),
                            end: localDate(day: 20, hour: 9, minute: 0)
                        ),
                        cameras: ["Driveway"],
                        kinds: ["person"]
                    )
                ),
                compareGroup(
                    group: ["camera": "Porch", "kind": "package"],
                    window: CompareCounts(eventCount: 0, sourceEventCount: 0),
                    comparisonWindow: CompareCounts(eventCount: 1, sourceEventCount: 1),
                    eventCountDelta: -1,
                    sourceEventCountDelta: -1,
                    windowFilters: QueryFilters(
                        window: QueryWindow(
                            start: localDate(day: 27, hour: 8, minute: 0),
                            end: localDate(day: 27, hour: 9, minute: 0)
                        ),
                        cameras: ["Porch"],
                        kinds: ["package"]
                    ),
                    comparisonFilters: QueryFilters(
                        window: QueryWindow(
                            start: localDate(day: 20, hour: 8, minute: 0),
                            end: localDate(day: 20, hour: 9, minute: 0)
                        ),
                        cameras: ["Porch"],
                        kinds: ["package"]
                    )
                ),
            ])
        case .events, .summary:
            Issue.record("expected compare output")
        }
    }

    @Test
    func queryRunnerCompareSupportsSameWeekdayPriorWeeksSeparately() throws {
        try withDefaultTimeZone("America/Los_Angeles") {
            let databasePath = temporaryDatabasePath()
            let database = try ProtectCadenceDatabase(path: databasePath)

            try insertRows(
                [
                    EventRow(
                        timeStart: localDate(month: 4, day: 27, hour: 8, minute: 10),
                        camera: "Driveway",
                        kind: "person",
                        eventID: "window-driveway-person"
                    ),
                    EventRow(
                        timeStart: localDate(month: 4, day: 27, hour: 8, minute: 25),
                        camera: "Backyard",
                        kind: "animal",
                        eventID: "window-backyard-animal"
                    ),
                    EventRow(
                        timeStart: localDate(month: 4, day: 20, hour: 8, minute: 10),
                        camera: "Driveway",
                        kind: "person",
                        eventID: "week-1-driveway-person"
                    ),
                    EventRow(
                        timeStart: localDate(month: 4, day: 20, hour: 8, minute: 40),
                        camera: "Porch",
                        kind: "package",
                        eventID: "week-1-porch-package"
                    ),
                    EventRow(
                        timeStart: localDate(month: 4, day: 13, hour: 8, minute: 20),
                        camera: "Backyard",
                        kind: "animal",
                        eventID: "week-2-backyard-animal"
                    ),
                    EventRow(
                        timeStart: localDate(day: 30, hour: 9, minute: 15),
                        camera: "Driveway",
                        kind: "vehicle",
                        eventID: "week-4-driveway-vehicle"
                    ),
                ],
                into: database
            )

            let output = try ProtectCadenceQueryRunner.run(
                arguments: [
                    "compare",
                    "--db", databasePath,
                    "--since", "2026-04-27 08:00",
                    "--until", "2026-04-27 10:00",
                    "--vs-same-weekday-prior-weeks", "4",
                    "--group-by", "camera",
                    "--group-by", "kind",
                ]
            )

            switch output {
            case let .compare(response):
                let peers = try #require(response.comparisonPeers)
                #expect(peers.count == 4)
                #expect(response.comparisonWindow == QueryWindow(
                    start: localDate(month: 4, day: 20, hour: 8, minute: 0),
                    end: localDate(month: 4, day: 20, hour: 10, minute: 0)
                ))
                #expect(response.comparisonTotals == CompareCounts(eventCount: 2, sourceEventCount: 2))
                #expect(response.groups == peers[0].groups)
                #expect(peers.map(\.comparisonWindow) == [
                    QueryWindow(
                        start: localDate(month: 4, day: 20, hour: 8, minute: 0),
                        end: localDate(month: 4, day: 20, hour: 10, minute: 0)
                    ),
                    QueryWindow(
                        start: localDate(month: 4, day: 13, hour: 8, minute: 0),
                        end: localDate(month: 4, day: 13, hour: 10, minute: 0)
                    ),
                    QueryWindow(
                        start: localDate(month: 4, day: 6, hour: 8, minute: 0),
                        end: localDate(month: 4, day: 6, hour: 10, minute: 0)
                    ),
                    QueryWindow(
                        start: localDate(day: 30, hour: 8, minute: 0),
                        end: localDate(day: 30, hour: 10, minute: 0)
                    ),
                ])
                #expect(peers[0].groups == [
                    compareGroup(
                        group: ["camera": "Backyard", "kind": "animal"],
                        window: CompareCounts(eventCount: 1, sourceEventCount: 1),
                        comparisonWindow: CompareCounts(eventCount: 0, sourceEventCount: 0),
                        eventCountDelta: 1,
                        sourceEventCountDelta: 1,
                        windowFilters: QueryFilters(
                            window: QueryWindow(
                                start: localDate(month: 4, day: 27, hour: 8, minute: 0),
                                end: localDate(month: 4, day: 27, hour: 10, minute: 0)
                            ),
                            cameras: ["Backyard"],
                            kinds: ["animal"]
                        ),
                        comparisonFilters: QueryFilters(
                            window: QueryWindow(
                                start: localDate(month: 4, day: 20, hour: 8, minute: 0),
                                end: localDate(month: 4, day: 20, hour: 10, minute: 0)
                            ),
                            cameras: ["Backyard"],
                            kinds: ["animal"]
                        )
                    ),
                    compareGroup(
                        group: ["camera": "Driveway", "kind": "person"],
                        window: CompareCounts(eventCount: 1, sourceEventCount: 1),
                        comparisonWindow: CompareCounts(eventCount: 1, sourceEventCount: 1),
                        eventCountDelta: 0,
                        sourceEventCountDelta: 0,
                        windowFilters: QueryFilters(
                            window: QueryWindow(
                                start: localDate(month: 4, day: 27, hour: 8, minute: 0),
                                end: localDate(month: 4, day: 27, hour: 10, minute: 0)
                            ),
                            cameras: ["Driveway"],
                            kinds: ["person"]
                        ),
                        comparisonFilters: QueryFilters(
                            window: QueryWindow(
                                start: localDate(month: 4, day: 20, hour: 8, minute: 0),
                                end: localDate(month: 4, day: 20, hour: 10, minute: 0)
                            ),
                            cameras: ["Driveway"],
                            kinds: ["person"]
                        )
                    ),
                    compareGroup(
                        group: ["camera": "Porch", "kind": "package"],
                        window: CompareCounts(eventCount: 0, sourceEventCount: 0),
                        comparisonWindow: CompareCounts(eventCount: 1, sourceEventCount: 1),
                        eventCountDelta: -1,
                        sourceEventCountDelta: -1,
                        windowFilters: QueryFilters(
                            window: QueryWindow(
                                start: localDate(month: 4, day: 27, hour: 8, minute: 0),
                                end: localDate(month: 4, day: 27, hour: 10, minute: 0)
                            ),
                            cameras: ["Porch"],
                            kinds: ["package"]
                        ),
                        comparisonFilters: QueryFilters(
                            window: QueryWindow(
                                start: localDate(month: 4, day: 20, hour: 8, minute: 0),
                                end: localDate(month: 4, day: 20, hour: 10, minute: 0)
                            ),
                            cameras: ["Porch"],
                            kinds: ["package"]
                        )
                    ),
                ])
                #expect(peers[2].comparisonTotals == CompareCounts(eventCount: 0, sourceEventCount: 0))
                #expect(peers[2].groups.map(\.comparisonWindow) == [
                    CompareCounts(eventCount: 0, sourceEventCount: 0),
                    CompareCounts(eventCount: 0, sourceEventCount: 0),
                ])

                let json = try JSONOutput.encode(output)
                #expect(json.contains("\"comparisonPeers\""))
                #expect(json.contains("\"index\" : 4"))

                let text = try ProtectCadenceOutputRenderer.render(
                    output: .query(output),
                    format: .text,
                    stdoutIsTTY: false
                )
                #expect(text.contains("Comparison windows: 4"))
                #expect(text.contains("Comparison 4"))
                #expect(text.contains("vehicle"))
            case .events, .summary:
                Issue.record("expected compare output")
            }
        }
    }

    @Test
    func queryRunnerCompareSupportsWindowBeforeHelperEndToEnd() throws {
        let databasePath = temporaryDatabasePath()
        let database = try ProtectCadenceDatabase(path: databasePath)

        try insertRows(
            [
                EventRow(
                    timeStart: localDate(day: 27, hour: 8, minute: 10),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "window-driveway-person"
                ),
                EventRow(
                    timeStart: localDate(day: 20, hour: 8, minute: 10),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "before-driveway-person"
                ),
                EventRow(
                    timeStart: localDate(day: 20, hour: 8, minute: 40),
                    camera: "Porch",
                    kind: "package",
                    eventID: "before-porch-package"
                ),
            ],
            into: database
        )

        let output = try ProtectCadenceQueryRunner.run(
            arguments: [
                "compare",
                "--db", databasePath,
                "--since", "2026-03-27 08:00",
                "--until", "2026-03-27 09:00",
                "--vs-window-before", "2026-03-20 09:00",
            ]
        )

        switch output {
        case let .compare(response):
            #expect(response.comparisonWindow == QueryWindow(
                start: localDate(day: 20, hour: 8, minute: 0),
                end: localDate(day: 20, hour: 9, minute: 0)
            ))
            #expect(response.totals == CompareCounts(eventCount: 1, sourceEventCount: 1))
            #expect(response.comparisonTotals == CompareCounts(eventCount: 2, sourceEventCount: 2))
            #expect(response.groups == [
                compareGroup(
                    group: ["camera": "Driveway", "kind": "person"],
                    window: CompareCounts(eventCount: 1, sourceEventCount: 1),
                    comparisonWindow: CompareCounts(eventCount: 1, sourceEventCount: 1),
                    eventCountDelta: 0,
                    sourceEventCountDelta: 0,
                    windowFilters: QueryFilters(
                        window: QueryWindow(
                            start: localDate(day: 27, hour: 8, minute: 0),
                            end: localDate(day: 27, hour: 9, minute: 0)
                        ),
                        cameras: ["Driveway"],
                        kinds: ["person"]
                    ),
                    comparisonFilters: QueryFilters(
                        window: QueryWindow(
                            start: localDate(day: 20, hour: 8, minute: 0),
                            end: localDate(day: 20, hour: 9, minute: 0)
                        ),
                        cameras: ["Driveway"],
                        kinds: ["person"]
                    )
                ),
                compareGroup(
                    group: ["camera": "Porch", "kind": "package"],
                    window: CompareCounts(eventCount: 0, sourceEventCount: 0),
                    comparisonWindow: CompareCounts(eventCount: 1, sourceEventCount: 1),
                    eventCountDelta: -1,
                    sourceEventCountDelta: -1,
                    windowFilters: QueryFilters(
                        window: QueryWindow(
                            start: localDate(day: 27, hour: 8, minute: 0),
                            end: localDate(day: 27, hour: 9, minute: 0)
                        ),
                        cameras: ["Porch"],
                        kinds: ["package"]
                    ),
                    comparisonFilters: QueryFilters(
                        window: QueryWindow(
                            start: localDate(day: 20, hour: 8, minute: 0),
                            end: localDate(day: 20, hour: 9, minute: 0)
                        ),
                        cameras: ["Porch"],
                        kinds: ["package"]
                    )
                ),
            ])
        case .events, .summary:
            Issue.record("expected compare output")
        }
    }

    @Test
    func queryRunnerCompareSupportsWindowAfterHelperEndToEnd() throws {
        let databasePath = temporaryDatabasePath()
        let database = try ProtectCadenceDatabase(path: databasePath)

        try insertRows(
            [
                EventRow(
                    timeStart: localDate(day: 20, hour: 8, minute: 10),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "window-driveway-person"
                ),
                EventRow(
                    timeStart: localDate(day: 27, hour: 8, minute: 10),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "after-driveway-person"
                ),
                EventRow(
                    timeStart: localDate(day: 27, hour: 8, minute: 40),
                    camera: "Porch",
                    kind: "package",
                    eventID: "after-porch-package"
                ),
            ],
            into: database
        )

        let output = try ProtectCadenceQueryRunner.run(
            arguments: [
                "compare",
                "--db", databasePath,
                "--since", "2026-03-20 08:00",
                "--until", "2026-03-20 09:00",
                "--vs-window-after", "2026-03-27 08:00",
            ]
        )

        switch output {
        case let .compare(response):
            #expect(response.comparisonWindow == QueryWindow(
                start: localDate(day: 27, hour: 8, minute: 0),
                end: localDate(day: 27, hour: 9, minute: 0)
            ))
            #expect(response.totals == CompareCounts(eventCount: 1, sourceEventCount: 1))
            #expect(response.comparisonTotals == CompareCounts(eventCount: 2, sourceEventCount: 2))
            #expect(response.groups == [
                compareGroup(
                    group: ["camera": "Driveway", "kind": "person"],
                    window: CompareCounts(eventCount: 1, sourceEventCount: 1),
                    comparisonWindow: CompareCounts(eventCount: 1, sourceEventCount: 1),
                    eventCountDelta: 0,
                    sourceEventCountDelta: 0,
                    windowFilters: QueryFilters(
                        window: QueryWindow(
                            start: localDate(day: 20, hour: 8, minute: 0),
                            end: localDate(day: 20, hour: 9, minute: 0)
                        ),
                        cameras: ["Driveway"],
                        kinds: ["person"]
                    ),
                    comparisonFilters: QueryFilters(
                        window: QueryWindow(
                            start: localDate(day: 27, hour: 8, minute: 0),
                            end: localDate(day: 27, hour: 9, minute: 0)
                        ),
                        cameras: ["Driveway"],
                        kinds: ["person"]
                    )
                ),
                compareGroup(
                    group: ["camera": "Porch", "kind": "package"],
                    window: CompareCounts(eventCount: 0, sourceEventCount: 0),
                    comparisonWindow: CompareCounts(eventCount: 1, sourceEventCount: 1),
                    eventCountDelta: -1,
                    sourceEventCountDelta: -1,
                    windowFilters: QueryFilters(
                        window: QueryWindow(
                            start: localDate(day: 20, hour: 8, minute: 0),
                            end: localDate(day: 20, hour: 9, minute: 0)
                        ),
                        cameras: ["Porch"],
                        kinds: ["package"]
                    ),
                    comparisonFilters: QueryFilters(
                        window: QueryWindow(
                            start: localDate(day: 27, hour: 8, minute: 0),
                            end: localDate(day: 27, hour: 9, minute: 0)
                        ),
                        cameras: ["Porch"],
                        kinds: ["package"]
                    )
                ),
            ])
        case .events, .summary:
            Issue.record("expected compare output")
        }
    }
    @Test
    func queryCLIRejectsUntilWithoutSince() throws {
        do {
            _ = try QueryCLI(arguments: [
                "summary",
                "--until", "2026-03-25T03:00:00Z",
            ])
            Issue.record("expected --until requires --since error")
        } catch let error as QueryCLIError {
            #expect(error.description == "--until requires --since")
        }
    }

    @Test
    func queryCLIRejectsInvalidTimeBoundWithFormatGuidance() throws {
        do {
            _ = try QueryCLI(arguments: [
                "events",
                "--since", "yesterday afternoon",
            ])
            Issue.record("expected invalid time bound error")
        } catch let error as QueryCLIError {
            #expect(error.description == "invalid time value 'yesterday afternoon' for --since, expected ISO 8601 with Z or explicit offset, or local YYYY-MM-DD[ T]HH:MM[:SS]")
        }
    }

    @Test
    func queryRunnerRecentJSONIncludesCameraIDAndEventType() throws {
        let databasePath = temporaryDatabasePath()
        let database = try ProtectCadenceDatabase(path: databasePath)

        try database.insert(
            EventRow(
                timeStart: Date(timeIntervalSince1970: 100),
                cameraID: "camera-json",
                camera: "Garage",
                eventType: "smartDetectLine",
                kind: "vehicle",
                eventID: "event-json"
            )
        )

        let output = try ProtectCadenceQueryRunner.run(
            arguments: ["events", "--db", databasePath, "--limit", "1"]
        )
        let json = try JSONOutput.encode(output)

        #expect(json.contains("\"cameraID\""))
        #expect(json.contains("\"camera-json\""))
        #expect(json.contains("\"countSemantics\""))
        #expect(json.contains("\"eventType\""))
        #expect(json.contains("\"smartDetectLine\""))
    }

}
