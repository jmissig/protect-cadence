import Foundation
import GRDB
import Testing
@testable import ProtectCadence

@Suite("Query CLI Parsing")
struct QueryCLIParsingTests {
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

}
