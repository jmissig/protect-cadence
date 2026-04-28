import Foundation
import GRDB
import Testing
@testable import ProtectCadence

@Suite("Evidence Store")
struct ProtectCadenceStoreTests {
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
    func summaryCanGroupDistributionByWeekdayHourAndCameraWithinOneWindow() throws {
        let database = try ProtectCadenceDatabase(path: temporaryDatabasePath())

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
                    timeStart: localDate(day: 25, hour: 8, minute: 45),
                    camera: "Driveway",
                    kind: "vehicle",
                    eventID: "driveway-vehicle"
                ),
                EventRow(
                    timeStart: localDate(day: 25, hour: 9, minute: 10),
                    camera: "Porch",
                    kind: "package",
                    eventID: "porch-package"
                ),
                EventRow(
                    timeStart: localDate(day: 25, hour: 10, minute: 0),
                    camera: "Driveway",
                    kind: "person",
                    eventID: "outside-window"
                ),
            ],
            into: database
        )

        let window = QueryWindow(
            start: localDate(day: 25, hour: 8, minute: 0),
            end: localDate(day: 25, hour: 10, minute: 0)
        )

        let summary = try withDefaultTimeZone("America/Los_Angeles") {
            try database.fetchSummary(
                SummaryRequest(
                    filters: QueryFilters(window: window),
                    groupBy: [.weekday, .hour, .camera]
                )
            )
        }

        #expect(summary.totalEventCount == 4)
        #expect(summary.totalSourceEventCount == 4)
        #expect(summary.groupBy == [.weekday, .hour, .camera])
        #expect(summary.groups == [
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
                eventCount: 2,
                sourceEventCount: 2,
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

}
