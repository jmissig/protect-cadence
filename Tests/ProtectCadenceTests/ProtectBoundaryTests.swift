import Foundation
import GRDB
import Testing
@testable import ProtectCadence

@Suite("Protect Boundary")
struct ProtectBoundaryTests {
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
    func modelDatabasePathResolverPrefersExplicitThenWritableSiblingThenManagedFallback() throws {
        let configPath = temporaryDirectoryPath() + "/config.json"
        let writableDirectory = temporaryDirectoryPath()
        let writableSourcePath = writableDirectory + "/protect-cadence.sqlite"
        try ProtectCadenceConfigStore.save(
            ProtectCadenceConfig(databasePath: writableSourcePath),
            to: configPath
        )

        let explicit = try ProtectCadenceModelDatabasePathResolver.resolve(
            explicitModelOverride: "/tmp/explicit-model.sqlite",
            sourceDatabaseOverride: nil,
            configPath: configPath,
            homeDirectoryURL: URL(fileURLWithPath: "/tmp/test-home", isDirectory: true)
        )
        let writableSibling = try ProtectCadenceModelDatabasePathResolver.resolve(
            explicitModelOverride: nil,
            sourceDatabaseOverride: nil,
            configPath: configPath,
            homeDirectoryURL: URL(fileURLWithPath: "/tmp/test-home", isDirectory: true)
        )
        let managedFallback = try ProtectCadenceModelDatabasePathResolver.resolve(
            explicitModelOverride: nil,
            sourceDatabaseOverride: "/definitely-missing-parent/protect-cadence.sqlite",
            configPath: configPath,
            homeDirectoryURL: URL(fileURLWithPath: "/tmp/test-home", isDirectory: true)
        )

        #expect(explicit == "/tmp/explicit-model.sqlite")
        #expect(writableSibling == writableDirectory + "/protect-cadence-model.sqlite")
        #expect(managedFallback == "/tmp/test-home/Library/Application Support/protect-cadence/protect-cadence-model.sqlite")
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

}
