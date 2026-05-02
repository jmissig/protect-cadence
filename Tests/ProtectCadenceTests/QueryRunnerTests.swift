import Foundation
import GRDB
import Testing
@testable import ProtectCadence

@Suite("Query Runner")
struct QueryRunnerTests {
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
