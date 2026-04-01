import Foundation
import GRDB
import Testing
@testable import ProtectCadenceCore

private let realProtectCaptureVersion = "7.0.94"
private let realProtectEventsFixtureName = "events-response-protect-\(realProtectCaptureVersion).json"
private let realProtectCamerasFixtureName = "cameras-response-protect-\(realProtectCaptureVersion).json"
private let realProtectSchemaFixtureName = "schema-snapshot-protect-\(realProtectCaptureVersion).json"

struct ProtectCadenceCoreTests {
    @Test
    func normalizerExpandsSmartDetectTypesIntoMultipleRows() throws {
        let payload = ProtectEventPayload(
            id: "bootstrap-id",
            eventID: "event-1",
            type: "smartDetectZone",
            start: Date(timeIntervalSince1970: 100),
            end: Date(timeIntervalSince1970: 110),
            detectedAt: Date(timeIntervalSince1970: 105),
            smartDetectTypes: ["person", "vehicle", "person"],
            camera: ProtectEventCameraPayload(displayName: "Driveway")
        )

        let rows = try ProtectEventNormalizer.normalize(payload)

        #expect(rows.count == 2)
        #expect(rows.map(\.kind) == ["person", "vehicle"])
        #expect(rows.allSatisfy { $0.eventID == "event-1" })
        #expect(rows.allSatisfy { $0.timeStart == Date(timeIntervalSince1970: 105) })
        #expect(rows.allSatisfy { $0.timeEnd == Date(timeIntervalSince1970: 110) })
        #expect(rows.allSatisfy { $0.cameraID == nil })
        #expect(rows.allSatisfy { $0.camera == "Driveway" })
        #expect(rows.allSatisfy { $0.eventType == "smartDetectZone" })
    }

    @Test
    func normalizerMapsLegacyAliasesAndUsesFallbackCameraName() throws {
        let payload = ProtectEventPayload(
            id: "event-2",
            type: "smartDetectZone",
            start: Date(timeIntervalSince1970: 100),
            smartDetectTypes: ["car", "pet"],
            cameraID: "camera-2"
        )

        let rows = try ProtectEventNormalizer.normalize(payload, fallbackCameraName: "Backyard")

        #expect(rows.map(\.kind) == ["vehicle", "animal"])
        #expect(rows.allSatisfy { $0.eventID == "event-2" })
        #expect(rows.allSatisfy { $0.cameraID == "camera-2" })
        #expect(rows.allSatisfy { $0.camera == "Backyard" })
        #expect(rows.allSatisfy { $0.eventType == "smartDetectZone" })
    }

    @Test
    func normalizerIgnoresEventsWithoutKinds() throws {
        let payload = ProtectEventPayload(
            id: "event-3",
            type: "smartDetectZone",
            start: Date(timeIntervalSince1970: 100),
            camera: ProtectEventCameraPayload(displayName: "Garage")
        )

        let rows = try ProtectEventNormalizer.normalize(payload)

        #expect(rows.isEmpty)
    }

    @Test
    func payloadDecodesUnixMillisecondTimestamps() throws {
        let json = """
        {
          "id": "event-4",
          "eventId": "event-4",
          "type": "smartDetectZone",
          "start": 1710000000000,
          "end": 1710000005000,
          "detectedAt": 1710000001000,
          "smartDetectTypes": ["package"],
          "camera": {
            "displayName": "Porch"
          }
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(ProtectEventPayload.self, from: json)
        let rows = try ProtectEventNormalizer.normalize(payload)

        #expect(rows.count == 1)
        #expect(rows[0].kind == "package")
        #expect(rows[0].eventType == "smartDetectZone")
        #expect(rows[0].camera == "Porch")
        #expect(rows[0].timeStart == Date(timeIntervalSince1970: 1_710_000_001))
        #expect(rows[0].timeEnd == Date(timeIntervalSince1970: 1_710_000_005))
    }

    @Test
    func payloadDecodesCameraStringReferenceFromFixtureSnapshot() throws {
        let payloads: [ProtectEventPayload] = try decodeFixture("events-response.json")

        #expect(payloads[0].camera == nil)
        #expect(payloads[0].cameraReferenceID == "camera-001")
        #expect(payloads[0].cameraID == "camera-001")
    }

    @Test
    func realControllerSnapshotDecodesCurrentObservedEventShape() throws {
        let payloads: [ProtectEventPayload] = try decodeFixture(realProtectEventsFixtureName, fixtureSet: "ProtectAPIReal")

        #expect(!payloads.isEmpty)
        #expect(payloads[0].eventID == nil)
        #expect(payloads[0].id != nil)
        #expect(payloads[0].detectedAt == nil)
        #expect(payloads[0].cameraReferenceID == "camera-005")
    }

    @Test
    func validateCLIUsesDefaultsAndParsesOverrides() throws {
        let cli = try ValidateCLI(arguments: [
            "--last-hours", "12",
            "--sample-limit", "5",
            "--config", "/tmp/protect-config.json",
            "--controller-url", "https://protect.example",
            "--username", "local-user",
            "--password", "local-pass",
            "--allow-insecure-tls",
            "--write-api-snapshot-dir", "/tmp/sample",
        ])

        #expect(cli.lastHours == 12)
        #expect(cli.sampleLimit == 5)
        #expect(cli.configPath == "/tmp/protect-config.json")
        #expect(cli.controllerURL == "https://protect.example")
        #expect(cli.username == "local-user")
        #expect(cli.password == "local-pass")
        #expect(cli.allowInsecureTLS == true)
        #expect(cli.snapshotDirectoryPath == "/tmp/sample")
    }

    @Test
    func validationReportSummarizesRecentControllerAssumptions() {
        let window = QueryWindow(
            start: Date(timeIntervalSince1970: 2_000),
            end: Date(timeIntervalSince1970: 2_600)
        )
        let cameras = [
            ProtectCameraRecord(id: "camera-1", displayName: "Front", name: "Front"),
        ]
        let events = [
            ProtectEventPayload(
                id: "event-a",
                type: "smartDetectZone",
                start: Date(timeIntervalSince1970: 2_100),
                end: Date(timeIntervalSince1970: 2_120),
                detectedAt: Date(timeIntervalSince1970: 2_105),
                smartDetectTypes: ["person", "vehicle"],
                cameraReferenceID: "camera-1"
            ),
            ProtectEventPayload(
                eventID: "event-b",
                type: "package",
                start: Date(timeIntervalSince1970: 2_130),
                end: Date(timeIntervalSince1970: 2_131),
                cameraReferenceID: "camera-1"
            ),
            ProtectEventPayload(
                eventID: "dup-1",
                type: "smartDetectZone",
                start: Date(timeIntervalSince1970: 2_140),
                end: Date(timeIntervalSince1970: 2_150),
                detectedAt: Date(timeIntervalSince1970: 2_141),
                smartDetectTypes: ["person"],
                cameraReferenceID: "camera-1"
            ),
            ProtectEventPayload(
                eventID: "dup-1",
                type: "smartDetectLine",
                start: Date(timeIntervalSince1970: 2_142),
                end: Date(timeIntervalSince1970: 2_151),
                detectedAt: Date(timeIntervalSince1970: 2_143),
                smartDetectTypes: ["person"],
                cameraReferenceID: "camera-1"
            ),
            ProtectEventPayload(
                id: "event-open",
                type: "smartDetectZone",
                start: Date(timeIntervalSince1970: 2_160),
                detectedAt: Date(timeIntervalSince1970: 2_161),
                smartDetectTypes: ["person"],
                cameraReferenceID: "camera-1"
            ),
            ProtectEventPayload(
                type: "smartDetectZone",
                start: Date(timeIntervalSince1970: 2_170),
                end: Date(timeIntervalSince1970: 2_171),
                detectedAt: Date(timeIntervalSince1970: 2_170),
                smartDetectTypes: ["animal"],
                cameraReferenceID: "camera-1"
            ),
        ]

        let report = ProtectControllerValidationReportBuilder.make(
            events: events,
            cameras: cameras,
            window: window,
            sampleLimit: 3
        )

        #expect(report.command == "protect-cadence validate")
        #expect(report.fetchedSourceEventCount == 6)
        #expect(report.cameraLookupCount == 1)
        #expect(report.recentEvents.count == 3)
        #expect(report.timeStartRule.fetched.eventCount == 6)
        #expect(report.timeStartRule.fetched.detectedAtChosenCount == 5)
        #expect(report.timeStartRule.fetched.startFallbackCount == 1)
        #expect(report.timeStartRule.fetched.missingTimeStartCount == 0)
        #expect(report.timeStartRule.fetched.detectedAtDiffersFromStartCount == 4)
        #expect(report.timeStartRule.settled.eventCount == 5)
        #expect(report.settledEventFiltering.settledCount == 5)
        #expect(report.settledEventFiltering.unsettledCount == 1)
        #expect(report.dedupeKey.normalizedSettledEventCount == 5)
        #expect(report.dedupeKey.ignoredSettledSourceEventCount == 1)
        #expect(report.dedupeKey.eventIDCount == 3)
        #expect(report.dedupeKey.idFallbackCount == 1)
        #expect(report.dedupeKey.missingSourceEventIDCount == 1)
        #expect(report.dedupeKey.uniqueEventKindKeyCount == 4)
        #expect(report.dedupeKey.duplicateRowCount == 1)
        #expect(report.dedupeKey.multiKindSettledSourceEventCount == 1)
        #expect(report.dedupeKey.duplicateKeys.count == 1)
        #expect(report.dedupeKey.duplicateKeys[0].sourceEventID == "dup-1")
        #expect(report.dedupeKey.duplicateKeys[0].kind == "person")
        #expect(report.dedupeKey.duplicateKeys[0].occurrenceCount == 2)
        #expect(report.dedupeKey.multiKindExamples.count == 1)
        #expect(report.dedupeKey.multiKindExamples[0].sourceEventID == "event-a")
        #expect(report.snapshot == nil)
    }

    @Test
    func controllerConfigurationReadsOptInInsecureTLSFlag() throws {
        let configuration = try ProtectControllerConfiguration.fromEnvironment(
            [
                "PROTECT_CONTROLLER_URL": "https://unifi.local",
                "PROTECT_USERNAME": "user",
                "PROTECT_PASSWORD": "pass",
                "PROTECT_ALLOW_INSECURE_TLS": "1",
            ]
        )

        #expect(configuration.allowInsecureTLS == true)
    }

    @Test
    func defaultConfigPathUsesApplicationSupportDirectory() {
        let path = ProtectCadencePaths.defaultConfigPath(
            homeDirectoryURL: URL(fileURLWithPath: "/tmp/test-home", isDirectory: true)
        )

        #expect(path == "/tmp/test-home/Library/Application Support/protect-cadence/config.json")
    }

    @Test
    func databasePathResolverPrefersExplicitOverrideThenConfigThenDefault() throws {
        let configPath = temporaryDirectoryPath() + "/config.json"
        let configuredPath = temporaryDirectoryPath() + "/configured.sqlite"
        try ProtectCadenceConfigStore.save(
            ProtectCadenceConfig(databasePath: configuredPath),
            to: configPath
        )

        let fromConfig = try ProtectCadenceDatabasePathResolver.resolve(
            explicitOverride: nil,
            configPath: configPath
        )
        let fromOverride = try ProtectCadenceDatabasePathResolver.resolve(
            explicitOverride: "/tmp/override.sqlite",
            configPath: configPath
        )
        let fromDefault = try ProtectCadenceDatabasePathResolver.resolve(
            explicitOverride: nil,
            configPath: temporaryDirectoryPath() + "/missing-config.json"
        )

        #expect(fromConfig == configuredPath)
        #expect(fromOverride == "/tmp/override.sqlite")
        #expect(fromDefault == ProtectCadencePaths.makeDefault().databasePath)
    }

    @Test
    func configIgnoresLegacyNestedIngestDatabasePath() throws {
        let configPath = temporaryDirectoryPath() + "/config.json"
        try """
        {
          "auth": {
            "controllerURL": "https://protect.example",
            "username": "legacy-user",
            "password": "legacy-pass",
            "allowInsecureTLS": false
          },
          "ingest": {
            "databasePath": "/tmp/legacy.sqlite"
          }
        }
        """.data(using: .utf8)!.write(to: URL(fileURLWithPath: configPath))

        let config = try ProtectCadenceConfigStore.load(from: configPath)

        #expect(config?.auth?.controllerURL == "https://protect.example")
        #expect(config?.databasePath == nil)
    }

    @Test
    func authResolverUsesConfigPasswordWhenEnvIsAbsent() throws {
        let configPath = temporaryDirectoryPath() + "/config.json"
        try ProtectCadenceConfigStore.save(
            ProtectCadenceConfig(
                controllerURL: "https://config.example",
                username: "config-user",
                password: "config-pass",
                allowInsecureTLS: true
            ),
            to: configPath
        )

        let configuration = try ProtectAuthResolver.resolveControllerConfiguration(
            environment: [:],
            configPath: configPath
        )

        #expect(configuration.controllerURL.absoluteString == "https://config.example")
        #expect(configuration.username == "config-user")
        #expect(configuration.password == "config-pass")
        #expect(configuration.allowInsecureTLS == true)
    }

    @Test
    func authResolverAppliesExplicitThenEnvThenConfigPrecedence() throws {
        let configPath = temporaryDirectoryPath() + "/config.json"
        try ProtectCadenceConfigStore.save(
            ProtectCadenceConfig(
                controllerURL: "https://config.example",
                username: "config-user",
                password: "config-pass",
                allowInsecureTLS: false
            ),
            to: configPath
        )

        let configuration = try ProtectAuthResolver.resolveControllerConfiguration(
            overrides: ProtectAuthOverrides(
                controllerURL: "https://flag.example",
                username: "flag-user"
            ),
            environment: [
                "PROTECT_CONTROLLER_URL": "https://env.example",
                "PROTECT_USERNAME": "env-user",
                "PROTECT_PASSWORD": "env-pass",
                "PROTECT_ALLOW_INSECURE_TLS": "1",
            ],
            configPath: configPath
        )

        #expect(configuration.controllerURL.absoluteString == "https://flag.example")
        #expect(configuration.username == "flag-user")
        #expect(configuration.password == "env-pass")
        #expect(configuration.allowInsecureTLS == true)
    }

    @Test
    func authResolverRequiresConfigPasswordWhenEnvIsAbsent() throws {
        let configPath = temporaryDirectoryPath() + "/config.json"
        try ProtectCadenceConfigStore.save(
            ProtectCadenceConfig(
                controllerURL: "https://legacy.example",
                username: "legacy-user",
                allowInsecureTLS: false
            ),
            to: configPath
        )

        let status = try ProtectAuthResolver.currentStatus(
            environment: [:],
            configPath: configPath
        )

        #expect(status.storedPasswordExists == false)
        #expect(throws: ProtectAuthResolutionError.self) {
            _ = try ProtectAuthResolver.resolveControllerConfiguration(
                environment: [:],
                configPath: configPath
            )
        }
    }

    @Test
    func authLoginPromptsAndWritesConfig() throws {
        let configPath = temporaryDirectoryPath() + "/config.json"
        let prompter = TestPrompter(
            prompts: [
                "https://protect.example",
                "local-user",
            ],
            passwordPrompts: ["local-pass"],
            confirmations: [false]
        )

        let response = try ProtectCadenceAuthRunner.run(
            arguments: ["login", "--config", configPath],
            environment: [:],
            prompter: prompter
        )

        #expect(response.action == "login")
        #expect(response.status == "configured")
        #expect(response.configExists == true)
        #expect(response.storedPasswordExists == true)
        #expect(response.controllerURL == "https://protect.example")
        #expect(response.username == "local-user")

        let config = try ProtectCadenceConfigStore.load(from: configPath)
        #expect(config == ProtectCadenceConfig(
            controllerURL: "https://protect.example",
            username: "local-user",
            password: "local-pass",
            allowInsecureTLS: false
        ))
    }

    @Test
    func authLoginPersistsAuthOnlyConfigShapeWhenNoDatabasePathIsSet() throws {
        let configPath = temporaryDirectoryPath() + "/config.json"

        _ = try ProtectCadenceAuthRunner.run(
            arguments: [
                "login",
                "--config", configPath,
                "--controller-url", "https://protect.example",
                "--username", "nested-user",
                "--password", "nested-pass",
            ],
            environment: [:],
            prompter: TestPrompter(confirmations: [false])
        )

        let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
        let json = String(decoding: data, as: UTF8.self)

        #expect(json.contains("\"auth\""))
        #expect(json.contains("\"controllerURL\""))
        #expect(!json.contains("\"databasePath\""))
        #expect(!json.contains("\"ingest\""))
    }

    @Test
    func authStatusReportsConfigAndStoredPassword() throws {
        let configPath = temporaryDirectoryPath() + "/config.json"
        try ProtectCadenceConfigStore.save(
            ProtectCadenceConfig(
                controllerURL: "https://protect.example",
                username: "status-user",
                password: "stored-pass",
                allowInsecureTLS: true
            ),
            to: configPath
        )

        let output = try ProtectCadenceAuthRunner.run(
            arguments: ["status", "--config", configPath],
            environment: [:],
            prompter: TestPrompter()
        )

        #expect(output.action == "status")
        #expect(output.status == "ok")
        #expect(output.configExists == true)
        #expect(output.storedPasswordExists == true)
        #expect(output.allowInsecureTLS == true)
    }

    @Test
    func configStoreWritesRestrictedPermissions() throws {
        let configPath = temporaryDirectoryPath() + "/config.json"
        try ProtectCadenceConfigStore.save(
            ProtectCadenceConfig(
                controllerURL: "https://protect.example",
                username: "perm-user",
                password: "perm-pass"
            ),
            to: configPath
        )

        let attributes = try FileManager.default.attributesOfItem(atPath: configPath)
        let permissions = attributes[.posixPermissions] as? NSNumber

        #expect(permissions?.intValue == 0o600)
    }

    @Test
    func authClearDeletesConfig() throws {
        let configPath = temporaryDirectoryPath() + "/config.json"
        try ProtectCadenceConfigStore.save(
            ProtectCadenceConfig(
                controllerURL: "https://protect.example",
                username: "clear-user",
                password: "clear-pass"
            ),
            to: configPath
        )

        let output = try ProtectCadenceAuthRunner.run(
            arguments: ["clear", "--config", configPath, "--force"],
            environment: [:],
            prompter: TestPrompter()
        )

        #expect(output.action == "clear")
        #expect(output.status == "cleared")
        #expect(output.configExists == false)
        #expect(output.storedPasswordExists == false)
        #expect((try? ProtectCadenceConfigStore.load(from: configPath)) == nil)
    }

    @Test
    func recentEventsAreReturnedNewestFirst() throws {
        let database = try ProtectCadenceDatabase(path: temporaryDatabasePath())

        try database.insert(
            EventRow(
                timeStart: Date(timeIntervalSince1970: 100),
                camera: "Driveway",
                kind: "vehicle",
                eventID: "event-1"
            )
        )
        try database.insert(
            EventRow(
                timeStart: Date(timeIntervalSince1970: 200),
                camera: "Backyard",
                kind: "animal",
                eventID: "event-2"
            )
        )

        let recent = try database.fetchRecent(RecentEventsRequest(limit: 10))

        #expect(recent.map(\.eventID) == ["event-2", "event-1"])
    }

    @Test
    func recentRowsIncludeCameraIDAndEventType() throws {
        let database = try ProtectCadenceDatabase(path: temporaryDatabasePath())

        try database.insert(
            EventRow(
                timeStart: Date(timeIntervalSince1970: 100),
                timeEnd: Date(timeIntervalSince1970: 110),
                cameraID: "camera-123",
                camera: "Driveway",
                eventType: "smartDetectZone",
                kind: "person",
                eventID: "event-123"
            )
        )

        let recent = try database.fetchRecent(RecentEventsRequest(limit: 1))

        #expect(recent.count == 1)
        #expect(recent[0].cameraID == "camera-123")
        #expect(recent[0].camera == "Driveway")
        #expect(recent[0].eventType == "smartDetectZone")
    }

    @Test
    func migrationsUpgradeLegacyCurrentSchemaToIncludeCameraIDAndEventType() throws {
        let databasePath = temporaryDatabasePath()

        let dbQueue = try DatabaseQueue(path: databasePath)
        try dbQueue.write { db in
            try db.create(table: "events") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("time_start", .datetime).notNull()
                table.column("time_end", .datetime)
                table.column("camera", .text).notNull()
                table.column("kind", .text).notNull()
                table.column("event_id", .text).notNull()
            }

            try db.create(
                index: "events_on_event_id_kind",
                on: "events",
                columns: ["event_id", "kind"],
                unique: true
            )

            try db.execute(
                sql: """
                    INSERT INTO events (time_start, time_end, camera, kind, event_id)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [
                    Date(timeIntervalSince1970: 100),
                    Date(timeIntervalSince1970: 110),
                    "Driveway",
                    "person",
                    "event-legacy"
                ]
            )
        }

        let database = try ProtectCadenceDatabase(path: databasePath)
        let recent = try database.fetchRecent(RecentEventsRequest(limit: 1))

        #expect(recent.count == 1)
        #expect(recent[0].eventID == "event-legacy")
        #expect(recent[0].cameraID == nil)
        #expect(recent[0].eventType == nil)

        try dbQueue.read { db in
            let columns = Set(try db.columns(in: "events").map(\.name))
            #expect(columns.contains("camera_id"))
            #expect(columns.contains("event_type"))
        }
    }

    @Test
    func migrationsUpgradeOriginalLegacySchemaToFinalEventShape() throws {
        let databasePath = temporaryDatabasePath()

        let dbQueue = try DatabaseQueue(path: databasePath)
        try dbQueue.write { db in
            try db.create(table: "events") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("ts", .datetime).notNull()
                table.column("camera", .text).notNull()
                table.column("kind", .text).notNull()
                table.column("count", .integer).notNull().defaults(to: 1)
                table.column("sourceEventID", .text).notNull()
                table.column("rawJSON", .text)
            }

            try db.execute(
                sql: """
                    INSERT INTO events (ts, camera, kind, count, sourceEventID, rawJSON)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    Date(timeIntervalSince1970: 200),
                    "Porch",
                    "package",
                    1,
                    "event-original",
                    "{\"ignored\":true}"
                ]
            )
        }

        let database = try ProtectCadenceDatabase(path: databasePath)
        let recent = try database.fetchRecent(RecentEventsRequest(limit: 1))

        #expect(recent.count == 1)
        #expect(recent[0].eventID == "event-original")
        #expect(recent[0].camera == "Porch")
        #expect(recent[0].kind == "package")
        #expect(recent[0].cameraID == nil)
        #expect(recent[0].eventType == nil)

        try dbQueue.read { db in
            let columns = Set(try db.columns(in: "events").map(\.name))
            #expect(columns == ["id", "time_start", "time_end", "camera_id", "camera", "event_type", "kind", "event_id"])
        }
    }

    @Test
    func sameEventCanProduceMultipleKinds() throws {
        let database = try ProtectCadenceDatabase(path: temporaryDatabasePath())

        try database.insert(
            EventRow(
                timeStart: Date(timeIntervalSince1970: 100),
                timeEnd: Date(timeIntervalSince1970: 110),
                camera: "Driveway",
                kind: "person",
                eventID: "event-1"
            )
        )
        try database.insert(
            EventRow(
                timeStart: Date(timeIntervalSince1970: 100),
                timeEnd: Date(timeIntervalSince1970: 110),
                camera: "Driveway",
                kind: "vehicle",
                eventID: "event-1"
            )
        )

        let recent = try database.fetchRecent(RecentEventsRequest(limit: 10))

        #expect(recent.map(\.kind).sorted() == ["person", "vehicle"])
        #expect(Set(recent.map(\.eventID)) == ["event-1"])
    }

    @Test
    func eventsRequestFiltersByCameraKindTimeOfDayAndOrder() throws {
        let database = try ProtectCadenceDatabase(path: temporaryDatabasePath())
        let calendar = Calendar(identifier: .gregorian)

        func localDate(hour: Int, minute: Int, day: Int) -> Date {
            let components = DateComponents(
                timeZone: TimeZone(identifier: "America/Los_Angeles"),
                year: 2026,
                month: 3,
                day: day,
                hour: hour,
                minute: minute
            )
            return calendar.date(from: components)!
        }

        try insertRows(
            [
                EventRow(
                    timeStart: localDate(hour: 23, minute: 30, day: 24),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "match-older"
                ),
                EventRow(
                    timeStart: localDate(hour: 1, minute: 15, day: 25),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "match-newer"
                ),
                EventRow(
                    timeStart: localDate(hour: 12, minute: 0, day: 25),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "wrong-time"
                ),
                EventRow(
                    timeStart: localDate(hour: 23, minute: 45, day: 24),
                    camera: "Backyard",
                    kind: "person",
                    eventID: "wrong-camera"
                ),
                EventRow(
                    timeStart: localDate(hour: 0, minute: 30, day: 25),
                    camera: "Driveway",
                    kind: "vehicle",
                    eventID: "wrong-kind"
                ),
            ],
            into: database
        )

        let rows = try database.fetchEvents(
            EventsRequest(
                limit: 10,
                order: .oldest,
                filters: QueryFilters(
                    window: QueryWindow(
                        start: localDate(hour: 20, minute: 0, day: 24),
                        end: localDate(hour: 3, minute: 0, day: 25)
                    ),
                    cameras: ["Driveway"],
                    kinds: ["person"],
                    timeOfDay: QueryTimeOfDayRange(startHour: 22, startMinute: 0, endHour: 2, endMinute: 0)
                )
            )
        )

        #expect(rows.map(\.eventID) == ["match-older", "match-newer"])
    }

    @Test
    func eventsRequestCanFilterByWeekday() throws {
        let database = try ProtectCadenceDatabase(path: temporaryDatabasePath())

        try insertRows(
            [
                EventRow(
                    timeStart: localDate(day: 23, hour: 8, minute: 0),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "mon-event"
                ),
                EventRow(
                    timeStart: localDate(day: 24, hour: 8, minute: 0),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "tue-event"
                ),
                EventRow(
                    timeStart: localDate(day: 28, hour: 8, minute: 0),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "sat-event"
                ),
            ],
            into: database
        )

        let rows = try database.fetchEvents(
            EventsRequest(
                limit: 10,
                order: .oldest,
                filters: QueryFilters(
                    window: QueryWindow(
                        start: localDate(day: 23, hour: 0, minute: 0),
                        end: localDate(day: 29, hour: 0, minute: 0)
                    ),
                    weekdays: [.mon, .sat]
                )
            )
        )

        #expect(rows.map(\.eventID) == ["mon-event", "sat-event"])
    }

    @Test
    func eventsRequestCanFilterByExactLocalDateAndHourBuckets() throws {
        let database = try ProtectCadenceDatabase(path: temporaryDatabasePath())

        try insertRows(
            [
                EventRow(
                    timeStart: localDate(day: 25, hour: 6, minute: 5),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "match-a"
                ),
                EventRow(
                    timeStart: localDate(day: 25, hour: 6, minute: 45),
                    camera: "Driveway",
                    kind: "vehicle",
                    eventID: "match-b"
                ),
                EventRow(
                    timeStart: localDate(day: 25, hour: 7, minute: 5),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "wrong-hour"
                ),
                EventRow(
                    timeStart: localDate(day: 26, hour: 6, minute: 10),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "wrong-date"
                ),
            ],
            into: database
        )

        let rows = try database.fetchEvents(
            EventsRequest(
                limit: 10,
                order: .oldest,
                filters: QueryFilters(
                    window: QueryWindow(
                        start: localDate(day: 25, hour: 0, minute: 0),
                        end: localDate(day: 27, hour: 0, minute: 0)
                    ),
                    date: "2026-03-25",
                    hour: "06:00"
                )
            )
        )

        #expect(rows.map(\.eventID) == ["match-a", "match-b"])
    }

    @Test
    func summaryGroupsRowsByCameraAndKind() throws {
        let database = try ProtectCadenceDatabase(path: temporaryDatabasePath())

        try insertRows(
            [
                EventRow(
                    timeStart: Date(timeIntervalSince1970: 100),
                    camera: "Backyard",
                    kind: "animal",
                    eventID: "event-1"
                ),
                EventRow(
                    timeStart: Date(timeIntervalSince1970: 110),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "event-2"
                ),
                EventRow(
                    timeStart: Date(timeIntervalSince1970: 115),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "event-3"
                ),
                EventRow(
                    timeStart: Date(timeIntervalSince1970: 120),
                    camera: "Driveway",
                    kind: "vehicle",
                    eventID: "event-2"
                ),
            ],
            into: database
        )

        let summary = try database.fetchSummary(
            SummaryRequest(
                filters: QueryFilters(
                    window: QueryWindow(
                        start: Date(timeIntervalSince1970: 90),
                        end: Date(timeIntervalSince1970: 130)
                    )
                )
            )
        )

        #expect(summary.totalEventCount == 4)
        #expect(summary.totalSourceEventCount == 3)
        #expect(
            summary.groups == [
                summaryGroup(
                    group: ["camera": "Backyard", "kind": "animal"],
                    eventCount: 1,
                    sourceEventCount: 1,
                    filters: QueryFilters(
                        window: QueryWindow(
                            start: Date(timeIntervalSince1970: 90),
                            end: Date(timeIntervalSince1970: 130)
                        ),
                        cameras: ["Backyard"],
                        kinds: ["animal"]
                    )
                ),
                summaryGroup(
                    group: ["camera": "Driveway", "kind": "person"],
                    eventCount: 2,
                    sourceEventCount: 2,
                    filters: QueryFilters(
                        window: QueryWindow(
                            start: Date(timeIntervalSince1970: 90),
                            end: Date(timeIntervalSince1970: 130)
                        ),
                        cameras: ["Driveway"],
                        kinds: ["person"]
                    )
                ),
                summaryGroup(
                    group: ["camera": "Driveway", "kind": "vehicle"],
                    eventCount: 1,
                    sourceEventCount: 1,
                    filters: QueryFilters(
                        window: QueryWindow(
                            start: Date(timeIntervalSince1970: 90),
                            end: Date(timeIntervalSince1970: 130)
                        ),
                        cameras: ["Driveway"],
                        kinds: ["vehicle"]
                    )
                ),
            ]
        )
    }

    @Test
    func summaryWindowExcludesRowsOutsideRange() throws {
        let database = try ProtectCadenceDatabase(path: temporaryDatabasePath())

        try insertRows(
            [
                EventRow(
                    timeStart: Date(timeIntervalSince1970: 99),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "before-window"
                ),
                EventRow(
                    timeStart: Date(timeIntervalSince1970: 100),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "inside-window"
                ),
                EventRow(
                    timeStart: Date(timeIntervalSince1970: 200),
                    camera: "Driveway",
                    kind: "vehicle",
                    eventID: "at-end-boundary"
                ),
            ],
            into: database
        )

        let summary = try database.fetchSummary(
            SummaryRequest(
                filters: QueryFilters(
                    window: QueryWindow(
                        start: Date(timeIntervalSince1970: 100),
                        end: Date(timeIntervalSince1970: 200)
                    )
                )
            )
        )

        #expect(summary.totalEventCount == 1)
        #expect(summary.totalSourceEventCount == 1)
        #expect(summary.groups == [
            summaryGroup(
                group: ["camera": "Driveway", "kind": "person"],
                eventCount: 1,
                sourceEventCount: 1,
                filters: QueryFilters(
                    window: QueryWindow(
                        start: Date(timeIntervalSince1970: 100),
                        end: Date(timeIntervalSince1970: 200)
                    ),
                    cameras: ["Driveway"],
                    kinds: ["person"]
                )
            ),
        ])
    }

    @Test
    func summaryDistinctEventCountDoesNotDoubleCountKinds() throws {
        let database = try ProtectCadenceDatabase(path: temporaryDatabasePath())

        try insertRows(
            [
                EventRow(
                    timeStart: Date(timeIntervalSince1970: 100),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "event-1"
                ),
                EventRow(
                    timeStart: Date(timeIntervalSince1970: 100),
                    camera: "Driveway",
                    kind: "vehicle",
                    eventID: "event-1"
                ),
                EventRow(
                    timeStart: Date(timeIntervalSince1970: 101),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "event-2"
                ),
            ],
            into: database
        )

        let summary = try database.fetchSummary(
            SummaryRequest(
                filters: QueryFilters(
                    window: QueryWindow(
                        start: Date(timeIntervalSince1970: 90),
                        end: Date(timeIntervalSince1970: 110)
                    )
                )
            )
        )

        #expect(summary.totalEventCount == 3)
        #expect(summary.totalSourceEventCount == 2)
        #expect(summary.groups == [
            summaryGroup(
                group: ["camera": "Driveway", "kind": "person"],
                eventCount: 2,
                sourceEventCount: 2,
                filters: QueryFilters(
                    window: QueryWindow(
                        start: Date(timeIntervalSince1970: 90),
                        end: Date(timeIntervalSince1970: 110)
                    ),
                    cameras: ["Driveway"],
                    kinds: ["person"]
                )
            ),
            summaryGroup(
                group: ["camera": "Driveway", "kind": "vehicle"],
                eventCount: 1,
                sourceEventCount: 1,
                filters: QueryFilters(
                    window: QueryWindow(
                        start: Date(timeIntervalSince1970: 90),
                        end: Date(timeIntervalSince1970: 110)
                    ),
                    cameras: ["Driveway"],
                    kinds: ["vehicle"]
                )
            ),
        ])
    }

    @Test
    func summaryGroupedDistinctEventCountStaysStableForMultiKindEvents() throws {
        let database = try ProtectCadenceDatabase(path: temporaryDatabasePath())
        let calendar = Calendar(identifier: .gregorian)

        func localDate(day: Int, hour: Int, minute: Int) -> Date {
            let components = DateComponents(
                timeZone: TimeZone(identifier: "America/Los_Angeles"),
                year: 2026,
                month: 3,
                day: day,
                hour: hour,
                minute: minute
            )
            return calendar.date(from: components)!
        }

        try insertRows(
            [
                EventRow(
                    timeStart: localDate(day: 25, hour: 8, minute: 5),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "event-1"
                ),
                EventRow(
                    timeStart: localDate(day: 25, hour: 8, minute: 5),
                    camera: "Driveway",
                    kind: "vehicle",
                    eventID: "event-1"
                ),
                EventRow(
                    timeStart: localDate(day: 25, hour: 8, minute: 25),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "event-2"
                ),
                EventRow(
                    timeStart: localDate(day: 25, hour: 8, minute: 40),
                    camera: "Driveway",
                    kind: "vehicle",
                    eventID: "event-3"
                ),
            ],
            into: database
        )

        let summary = try database.fetchSummary(
            SummaryRequest(
                filters: QueryFilters(
                    window: QueryWindow(
                        start: localDate(day: 25, hour: 8, minute: 0),
                        end: localDate(day: 25, hour: 9, minute: 0)
                    )
                ),
                groupBy: [.date, .hour]
            )
        )

        #expect(summary.totalEventCount == 4)
        #expect(summary.totalSourceEventCount == 3)
        #expect(summary.groups == [
            summaryGroup(
                group: ["date": "2026-03-25", "hour": "08:00"],
                eventCount: 4,
                sourceEventCount: 3,
                filters: QueryFilters(
                    window: QueryWindow(
                        start: localDate(day: 25, hour: 8, minute: 0),
                        end: localDate(day: 25, hour: 9, minute: 0)
                    ),
                    date: "2026-03-25",
                    hour: "08:00"
                )
            ),
        ])
    }

    @Test
    func summaryReturnsZerosForEmptyWindow() throws {
        let database = try ProtectCadenceDatabase(path: temporaryDatabasePath())

        let summary = try database.fetchSummary(
            SummaryRequest(
                filters: QueryFilters(
                    window: QueryWindow(
                        start: Date(timeIntervalSince1970: 100),
                        end: Date(timeIntervalSince1970: 200)
                    )
                )
            )
        )

        #expect(summary.totalEventCount == 0)
        #expect(summary.totalSourceEventCount == 0)
        #expect(summary.groups.isEmpty)
    }

    @Test
    func summaryCanGroupByDateAndHour() throws {
        let database = try ProtectCadenceDatabase(path: temporaryDatabasePath())
        let calendar = Calendar(identifier: .gregorian)

        func localDate(day: Int, hour: Int, minute: Int) -> Date {
            let components = DateComponents(
                timeZone: TimeZone(identifier: "America/Los_Angeles"),
                year: 2026,
                month: 3,
                day: day,
                hour: hour,
                minute: minute
            )
            return calendar.date(from: components)!
        }

        try insertRows(
            [
                EventRow(timeStart: localDate(day: 24, hour: 23, minute: 10), camera: "Driveway", kind: "person", eventID: "event-1"),
                EventRow(timeStart: localDate(day: 24, hour: 23, minute: 40), camera: "Driveway", kind: "vehicle", eventID: "event-2"),
                EventRow(timeStart: localDate(day: 25, hour: 0, minute: 5), camera: "Driveway", kind: "person", eventID: "event-3"),
            ],
            into: database
        )

        let summary = try database.fetchSummary(
            SummaryRequest(
                filters: QueryFilters(
                    window: QueryWindow(
                        start: localDate(day: 24, hour: 22, minute: 0),
                        end: localDate(day: 25, hour: 1, minute: 0)
                    )
                ),
                groupBy: [.date, .hour]
            )
        )

        #expect(summary.groupBy == [.date, .hour])
        #expect(summary.groups == [
            summaryGroup(
                group: ["date": "2026-03-24", "hour": "23:00"],
                eventCount: 2,
                sourceEventCount: 2,
                filters: QueryFilters(
                    window: QueryWindow(
                        start: localDate(day: 24, hour: 22, minute: 0),
                        end: localDate(day: 25, hour: 1, minute: 0)
                    ),
                    date: "2026-03-24",
                    hour: "23:00"
                )
            ),
            summaryGroup(
                group: ["date": "2026-03-25", "hour": "00:00"],
                eventCount: 1,
                sourceEventCount: 1,
                filters: QueryFilters(
                    window: QueryWindow(
                        start: localDate(day: 24, hour: 22, minute: 0),
                        end: localDate(day: 25, hour: 1, minute: 0)
                    ),
                    date: "2026-03-25",
                    hour: "00:00"
                )
            ),
        ])
    }

    @Test
    func summaryCanFilterByWeekendAndGroupByWeekday() throws {
        let database = try ProtectCadenceDatabase(path: temporaryDatabasePath())

        try insertRows(
            [
                EventRow(
                    timeStart: localDate(day: 27, hour: 20, minute: 0),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "fri-event"
                ),
                EventRow(
                    timeStart: localDate(day: 28, hour: 20, minute: 0),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "sat-event"
                ),
                EventRow(
                    timeStart: localDate(day: 29, hour: 20, minute: 0),
                    camera: "Driveway",
                    kind: "vehicle",
                    eventID: "sun-event"
                ),
            ],
            into: database
        )

        let summary = try database.fetchSummary(
            SummaryRequest(
                filters: QueryFilters(
                    window: QueryWindow(
                        start: localDate(day: 27, hour: 0, minute: 0),
                        end: localDate(day: 30, hour: 0, minute: 0)
                    ),
                    weekdays: QueryWeekday.weekend
                ),
                groupBy: [.weekday]
            )
        )

        #expect(summary.totalEventCount == 2)
        #expect(summary.totalSourceEventCount == 2)
        #expect(summary.groupBy == [.weekday])
        #expect(summary.groups == [
            summaryGroup(
                group: ["weekday": "sat"],
                eventCount: 1,
                sourceEventCount: 1,
                filters: QueryFilters(
                    window: QueryWindow(
                        start: localDate(day: 27, hour: 0, minute: 0),
                        end: localDate(day: 30, hour: 0, minute: 0)
                    ),
                    weekdays: [.sat]
                )
            ),
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
        case .ingest, .auth, .validate:
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
        case .query, .auth, .validate:
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
        case .ingest, .query, .validate:
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
    func queryCompareHelpMentionsBoundaryModes() {
        let help = ProtectCadenceHelp.text(for: ["query", "compare", "--help"])

        #expect(help?.contains("--vs-window-before") == true)
        #expect(help?.contains("--vs-window-after") == true)
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
            #expect(error.description == "use exactly one compare mode: --vs-since/--vs-until, --vs-same-window-yesterday, --vs-same-window-last-week, --vs-window-before, --vs-window-after, or --vs-prior-window")
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
            #expect(error.description == "use exactly one compare mode: --vs-since/--vs-until, --vs-same-window-yesterday, --vs-same-window-last-week, --vs-window-before, --vs-window-after, or --vs-prior-window")
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
            #expect(error.description == "use exactly one compare mode: --vs-since/--vs-until, --vs-same-window-yesterday, --vs-same-window-last-week, --vs-window-before, --vs-window-after, or --vs-prior-window")
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
            #expect(error.description == "use exactly one compare mode: --vs-since/--vs-until, --vs-same-window-yesterday, --vs-same-window-last-week, --vs-window-before, --vs-window-after, or --vs-prior-window")
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
            #expect(error.description == "compare requires one compare mode: --vs-since/--vs-until, --vs-same-window-yesterday, --vs-same-window-last-week, --vs-window-before, --vs-window-after, or --vs-prior-window")
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
            #expect(error.description == "compare requires a primary window via --last-hours or --since/--until")
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

    @Test
    func controllerClientAuthenticatesBeforeFetchingEvents() async throws {
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
            ]
        )

        let client = ProtectControllerClient(
            configuration: ProtectControllerConfiguration(
                controllerURL: URL(string: "https://protect.example")!,
                username: "user",
                password: "pass"
            ),
            transport: transport
        )

        let events = try await client.fetchRecentEvents(
            window: QueryWindow(
                start: Date(timeIntervalSince1970: 1_710_000_000),
                end: Date(timeIntervalSince1970: 1_710_003_600)
            )
        )

        #expect(events.count == 5)

        let requests = await transport.recordedRequests()
        #expect(requests.count == 2)
        #expect(requests[0].url?.path == "/api/auth/login")
        #expect(requests[0].httpMethod == "POST")
        #expect(String(data: requests[0].httpBody ?? Data(), encoding: .utf8)?.contains("\"username\":\"user\"") == true)
        #expect(requests[1].url?.path == "/proxy/protect/api/events")
        #expect(requests[1].value(forHTTPHeaderField: "Cookie") == "TOKEN=test-session")
        #expect(requests[1].value(forHTTPHeaderField: "x-csrf-token") == "csrf-test-token")
    }

    @Test
    func controllerIngestUsesCameraLookupAndWritesSnapshotArtifacts() async throws {
        let database = try ProtectCadenceDatabase(path: temporaryDatabasePath())
        let snapshotDirectory = temporaryDirectoryPath()
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

        let client = ProtectControllerClient(
            configuration: ProtectControllerConfiguration(
                controllerURL: URL(string: "https://protect.example")!,
                username: "user",
                password: "pass"
            ),
            transport: transport
        )
        let service = ProtectIngestService(database: database, client: client)

        let response = try await service.ingestControllerEvents(
            window: QueryWindow(
                start: Date(timeIntervalSince1970: 1_710_000_000),
                end: Date(timeIntervalSince1970: 1_710_003_600)
            ),
            snapshotDirectory: URL(fileURLWithPath: snapshotDirectory, isDirectory: true)
        )

        #expect(response.fetchedSourceEventCount == 5)
        #expect(response.normalizedEventCount == 4)
        #expect(response.insertedEventCount == 4)
        #expect(response.ignoredSourceEventCount == 2)

        let recent = try database.fetchRecent(RecentEventsRequest(limit: 10))
        #expect(recent.map(\.kind).sorted() == ["animal", "package", "person", "vehicle"])
        #expect(Set(recent.map(\.camera)) == ["Entry 02", "North 01"])
        #expect(Set(recent.compactMap(\.cameraID)) == ["camera-001", "camera-002"])
        #expect(Set(recent.compactMap(\.eventType)) == ["package", "smartDetectZone"])

        #expect(FileManager.default.fileExists(atPath: URL(fileURLWithPath: snapshotDirectory).appendingPathComponent("events-response.json").path))
        #expect(FileManager.default.fileExists(atPath: URL(fileURLWithPath: snapshotDirectory).appendingPathComponent("cameras-response.json").path))
        #expect(FileManager.default.fileExists(atPath: URL(fileURLWithPath: snapshotDirectory).appendingPathComponent("schema-snapshot.json").path))
    }

    @Test
    func fixtureIngestAcceptsArraySnapshotsAndDeduplicatesReplays() throws {
        let database = try ProtectCadenceDatabase(path: temporaryDatabasePath())
        let service = ProtectIngestService(database: database)
        let eventData = try fixtureData("events-response.json")
        let cameraData = try fixtureData("cameras-response.json")

        let first = try service.ingestFixtureEvents(from: eventData, cameraLookupData: cameraData)
        let second = try service.ingestFixtureEvents(from: eventData, cameraLookupData: cameraData)

        #expect(first.fetchedSourceEventCount == 5)
        #expect(first.normalizedEventCount == 5)
        #expect(first.insertedEventCount == 5)
        #expect(first.ignoredSourceEventCount == 1)
        #expect(second.insertedEventCount == 0)

        let recent = try database.fetchRecent(RecentEventsRequest(limit: 10))
        #expect(Set(recent.compactMap(\.cameraID)) == ["camera-001", "camera-002"])
        #expect(Set(recent.compactMap(\.eventType)) == ["package", "smartDetectZone"])
    }

    @Test
    func schemaSnapshotMatchesCommittedFixtureInventory() throws {
        let eventsData = try fixtureData("events-response.json")
        let camerasData = try fixtureData("cameras-response.json")
        let expected: ProtectSchemaSnapshot = try decodeFixture("schema-snapshot.json")

        let actual = try ProtectSchemaSnapshot.make(
            files: [
                ("events-response.json", eventsData),
                ("cameras-response.json", camerasData),
            ]
        )

        #expect(actual == expected)
    }

    @Test
    func realControllerSchemaSnapshotMatchesCommittedFixtureInventory() throws {
        let eventsData = try fixtureData(realProtectEventsFixtureName, fixtureSet: "ProtectAPIReal")
        let camerasData = try fixtureData(realProtectCamerasFixtureName, fixtureSet: "ProtectAPIReal")
        let expected: ProtectSchemaSnapshot = try decodeFixture(realProtectSchemaFixtureName, fixtureSet: "ProtectAPIReal")

        let actual = try ProtectSchemaSnapshot.make(
            files: [
                ("events-response.json", eventsData),
                ("cameras-response.json", camerasData),
            ]
        )

        #expect(actual == expected)
    }

    @Test
    func snapshotWriterProducesCommittedFixturesFromUnsanitizedSamples() throws {
        let snapshotDirectory = temporaryDirectoryPath()
        let writer = ProtectAPISnapshotWriter(
            directoryURL: URL(fileURLWithPath: snapshotDirectory, isDirectory: true)
        )

        try writer.write(
            events: unsanitizedSampleEvents(),
            cameras: unsanitizedSampleCameras()
        )

        let expectedEvents = try fixtureData("events-response.json")
        let expectedCameras = try fixtureData("cameras-response.json")
        let expectedSchema = try fixtureData("schema-snapshot.json")

        let actualEvents = try Data(contentsOf: URL(fileURLWithPath: snapshotDirectory).appendingPathComponent("events-response.json"))
        let actualCameras = try Data(contentsOf: URL(fileURLWithPath: snapshotDirectory).appendingPathComponent("cameras-response.json"))
        let actualSchema = try Data(contentsOf: URL(fileURLWithPath: snapshotDirectory).appendingPathComponent("schema-snapshot.json"))

        if ProcessInfo.processInfo.environment["REGENERATE_PROTECT_FIXTURES"] == "1" {
            try actualEvents.write(to: fixturesDirectoryURL().appendingPathComponent("events-response.json"))
            try actualCameras.write(to: fixturesDirectoryURL().appendingPathComponent("cameras-response.json"))
            try actualSchema.write(to: fixturesDirectoryURL().appendingPathComponent("schema-snapshot.json"))
            return
        }

        #expect(actualEvents == expectedEvents)
        #expect(actualCameras == expectedCameras)
        #expect(actualSchema == expectedSchema)
    }

    private func insertRows(_ rows: [EventRow], into database: ProtectCadenceDatabase) throws {
        for row in rows {
            try database.insert(row)
        }
    }

    private func temporaryDatabasePath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
            .path
    }

    private func localDate(
        year: Int = 2026,
        month: Int = 3,
        day: Int,
        hour: Int,
        minute: Int,
        second: Int = 0,
        timeZoneID: String = "America/Los_Angeles"
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID)!
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        ))!
    }

    private func temporaryDirectoryPath() -> String {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.path
    }

    private func withDefaultTimeZone<T>(_ timeZoneID: String, operation: () throws -> T) throws -> T {
        let original = NSTimeZone.default
        NSTimeZone.default = try #require(TimeZone(identifier: timeZoneID))
        defer {
            NSTimeZone.default = original
        }
        return try operation()
    }

    private func fixtureData(_ name: String, fixtureSet: String = "ProtectAPI") throws -> Data {
        try Data(contentsOf: fixturesDirectoryURL(fixtureSet: fixtureSet).appendingPathComponent(name))
    }

    private func fixturePath(_ name: String, fixtureSet: String = "ProtectAPI") -> String {
        fixturesDirectoryURL(fixtureSet: fixtureSet).appendingPathComponent(name).path
    }

    private func decodeFixture<T: Decodable>(_ name: String, fixtureSet: String = "ProtectAPI") throws -> T {
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: fixtureData(name, fixtureSet: fixtureSet))
    }

    private func fixturesDirectoryURL(
        fixtureSet: String = "ProtectAPI",
        filePath: StaticString = #filePath
    ) -> URL {
        URL(fileURLWithPath: "\(filePath)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(fixtureSet)", isDirectory: true)
    }

    private func unsanitizedSampleCameras() -> [ProtectCameraRecord] {
        [
            ProtectCameraRecord(id: "raw-driveway-camera", displayName: "Driveway", name: "Driveway"),
            ProtectCameraRecord(id: "raw-porch-camera", displayName: "Porch", name: "Porch"),
        ]
    }

    private func unsanitizedSampleEvents() -> [ProtectEventPayload] {
        [
            ProtectEventPayload(
                id: "raw-event-alpha",
                eventID: "raw-event-alpha",
                type: "smartDetectZone",
                start: Date(timeIntervalSince1970: 1_710_000_000),
                end: Date(timeIntervalSince1970: 1_710_000_006),
                detectedAt: Date(timeIntervalSince1970: 1_710_000_002),
                smartDetectTypes: ["person", "vehicle"],
                cameraReferenceID: "raw-driveway-camera",
                cameraID: "raw-driveway-camera"
            ),
            ProtectEventPayload(
                id: "raw-event-beta",
                eventID: "raw-event-beta",
                type: "smartDetectZone",
                start: Date(timeIntervalSince1970: 1_710_000_100),
                end: Date(timeIntervalSince1970: 1_710_000_109),
                detectedAt: Date(timeIntervalSince1970: 1_710_000_104),
                smartDetectTypes: ["animal"],
                camera: ProtectEventCameraPayload(
                    id: "raw-porch-camera",
                    displayName: "Porch",
                    name: "Porch"
                )
            ),
            ProtectEventPayload(
                id: "raw-event-gamma",
                eventID: "raw-event-gamma",
                type: "package",
                start: Date(timeIntervalSince1970: 1_710_000_200),
                end: Date(timeIntervalSince1970: 1_710_000_203),
                cameraReferenceID: "raw-driveway-camera",
                cameraID: "raw-driveway-camera"
            ),
            ProtectEventPayload(
                id: "raw-event-delta",
                eventID: "raw-event-delta",
                type: "motion",
                start: Date(timeIntervalSince1970: 1_710_000_300),
                end: Date(timeIntervalSince1970: 1_710_000_305),
                cameraReferenceID: "raw-driveway-camera"
            ),
            ProtectEventPayload(
                id: "raw-event-epsilon",
                eventID: "raw-event-epsilon",
                type: "smartDetectZone",
                start: Date(timeIntervalSince1970: 1_710_000_400),
                detectedAt: Date(timeIntervalSince1970: 1_710_000_401),
                smartDetectTypes: ["person"],
                cameraReferenceID: "raw-porch-camera",
                cameraID: "raw-porch-camera"
            ),
        ]
    }

    private func drillDown(_ filters: QueryFilters) -> QueryDrillDownDescriptor {
        QueryDrillDownDescriptor(filters: filters)
    }

    private func summaryGroup(
        group: [String: String],
        eventCount: Int,
        sourceEventCount: Int,
        filters: QueryFilters
    ) -> SummaryGroup {
        SummaryGroup(
            group: group,
            eventCount: eventCount,
            sourceEventCount: sourceEventCount,
            drillDown: drillDown(filters)
        )
    }

    private func compareGroup(
        group: [String: String],
        window: CompareCounts,
        comparisonWindow: CompareCounts,
        eventCountDelta: Int,
        sourceEventCountDelta: Int,
        windowFilters: QueryFilters,
        comparisonFilters: QueryFilters
    ) -> CompareGroup {
        CompareGroup(
            group: group,
            window: window,
            comparisonWindow: comparisonWindow,
            eventCountDelta: eventCountDelta,
            sourceEventCountDelta: sourceEventCountDelta,
            windowDrillDown: drillDown(windowFilters),
            comparisonWindowDrillDown: drillDown(comparisonFilters)
        )
    }
}

private actor RecordingProtectHTTPTransport: ProtectHTTPTransport {
    struct StubbedResponse: Sendable {
        let statusCode: Int
        let headers: [String: String]
        let body: Data
    }

    private var responses: [StubbedResponse]
    private var requests: [URLRequest] = []

    init(responses: [StubbedResponse]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = responses.removeFirst()
        return (
            response.body,
            HTTPURLResponse(
                url: request.url!,
                statusCode: response.statusCode,
                httpVersion: nil,
                headerFields: response.headers
            )!
        )
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}

private final class TestPrompter: ProtectAuthPrompter, @unchecked Sendable {
    private var prompts: [String]
    private var passwordPrompts: [String]
    private var confirmations: [Bool]

    init(
        prompts: [String] = [],
        passwordPrompts: [String] = [],
        confirmations: [Bool] = []
    ) {
        self.prompts = prompts
        self.passwordPrompts = passwordPrompts
        self.confirmations = confirmations
    }

    func prompt(_ message: String, defaultValue: String?) throws -> String {
        guard !prompts.isEmpty else {
            throw ProtectAuthResolutionError.inputUnavailable(message)
        }
        return prompts.removeFirst()
    }

    func promptPassword(_ message: String) throws -> String {
        guard !passwordPrompts.isEmpty else {
            throw ProtectAuthResolutionError.inputUnavailable(message)
        }
        return passwordPrompts.removeFirst()
    }

    func confirm(_ message: String) throws -> Bool {
        guard !confirmations.isEmpty else {
            throw ProtectAuthResolutionError.inputUnavailable(message)
        }
        return confirmations.removeFirst()
    }
}

private final class RecordedStatusOutput: @unchecked Sendable {
    private(set) var lines: [String] = []

    func write(_ line: String) {
        lines.append(line)
    }
}
