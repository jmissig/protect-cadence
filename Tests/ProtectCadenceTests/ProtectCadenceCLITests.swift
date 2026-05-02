import Foundation
import GRDB
import Testing
@testable import ProtectCadence

@Suite("CLI Surface")
struct ProtectCadenceCLITests {
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

}
