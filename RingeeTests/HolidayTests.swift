import Foundation
import Testing
@testable import Ringee

struct HolidayResponseParserTests {
    @Test func parsesArrayOfItemsKeepingOnlyHolidays() throws {
        let json = """
        {"response":{"header":{"resultCode":"00","resultMsg":"NORMAL SERVICE."},"body":{"items":{"item":[
          {"dateKind":"01","dateName":"삼일절","isHoliday":"Y","locdate":20260301,"seq":1},
          {"dateKind":"01","dateName":"대체공휴일(삼일절)","isHoliday":"Y","locdate":20260302,"seq":1},
          {"dateKind":"01","dateName":"어떤 날","isHoliday":"N","locdate":20260303,"seq":1}
        ]},"numOfRows":100,"pageNo":1,"totalCount":3}}}
        """
        let holidays = try HolidayResponseParser.parse(Data(json.utf8))
        #expect(holidays == [
            Holiday(day: 20260301, name: "삼일절"),
            Holiday(day: 20260302, name: "대체공휴일(삼일절)"),
        ])
    }

    @Test func parsesSingleObjectItem() throws {
        let json = """
        {"response":{"header":{"resultCode":"00","resultMsg":"NORMAL SERVICE."},"body":{"items":{"item":
          {"dateKind":"01","dateName":"광복절","isHoliday":"Y","locdate":20260815,"seq":1}
        },"numOfRows":100,"pageNo":1,"totalCount":1}}}
        """
        let holidays = try HolidayResponseParser.parse(Data(json.utf8))
        #expect(holidays == [Holiday(day: 20260815, name: "광복절")])
    }

    @Test func parsesEmptyStringItemsAsNoHolidays() throws {
        let json = """
        {"response":{"header":{"resultCode":"00","resultMsg":"NORMAL SERVICE."},"body":{"items":"","numOfRows":10,"pageNo":1,"totalCount":0}}}
        """
        #expect(try HolidayResponseParser.parse(Data(json.utf8)).isEmpty)
    }

    @Test func throwsOnServiceError() {
        let json = """
        {"response":{"header":{"resultCode":"30","resultMsg":"SERVICE KEY IS NOT REGISTERED ERROR."}}}
        """
        #expect(throws: HolidayResponseParser.ParseError.self) {
            try HolidayResponseParser.parse(Data(json.utf8))
        }
    }

    @Test func requestURLEncodesDecodedKeyOnce() {
        // 발급 키는 URL 인코딩 상태로 들어온다. 한 번 디코드 → 한 번 인코딩해 %252F 같은 이중 인코딩이 없어야 한다.
        let url = HolidayService.requestURL(apiKey: "ab%2Fc%2Bd%3D%3D", year: 2026)
        let query = url.query(percentEncoded: true) ?? ""
        #expect(query.contains("serviceKey=ab%2Fc%2Bd%3D%3D"))
        #expect(!query.contains("%25"))
        #expect(query.contains("solYear=2026"))
        #expect(query.contains("_type=json"))
    }
}

struct HolidayCacheTests {
    @Test func needsRefreshWhenMissingOrStale() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var cache = HolidayCache()
        #expect(cache.needsRefresh(year: 2026, now: now))
        cache.years[2026] = .init(holidays: [], fetchedAt: now)
        #expect(!cache.needsRefresh(year: 2026, now: now.addingTimeInterval(60)))
        #expect(cache.needsRefresh(year: 2026, now: now.addingTimeInterval(HolidayCache.refreshInterval + 1)))
    }

    @Test func roundTrips() throws {
        var cache = HolidayCache()
        cache.years[2026] = .init(holidays: [Holiday(day: 20261225, name: "기독탄신일")], fetchedAt: Date(timeIntervalSince1970: 0))
        let decoded = try JSONDecoder().decode(HolidayCache.self, from: JSONEncoder().encode(cache))
        #expect(decoded == cache)
    }
}

struct AlarmOccurrencePlannerTests {
    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test func plansSelectedWeekdaysSkippingHolidays() {
        let seoul = calendar("Asia/Seoul")
        // 2026-02-13 (금) 09:00 기준, 주중 07:30, 설 연휴 2/16(월)~2/18(수) 제외
        let now = date(2026, 2, 13, 9, 0, calendar: seoul)
        let dates = AlarmOccurrencePlanner.occurrences(
            weekdays: AlarmWeekday.weekdays,
            hour: 7, minute: 30,
            holidays: [20260216, 20260217, 20260218],
            from: now, days: 14, calendar: seoul
        )
        let keys = dates.map { AlarmOccurrencePlanner.dayKey($0, calendar: seoul) }
        #expect(keys == [20260219, 20260220, 20260223, 20260224, 20260225, 20260226, 20260227])
        #expect(dates.allSatisfy { seoul.component(.hour, from: $0) == 7 && seoul.component(.minute, from: $0) == 30 })
    }

    @Test func includesTodayOnlyWhenTimeIsStillAhead() {
        let seoul = calendar("Asia/Seoul")
        let monday = date(2026, 11, 30, 6, 0, calendar: seoul) // 월요일 06:00
        let ahead = AlarmOccurrencePlanner.occurrences(
            weekdays: [.monday], hour: 7, minute: 0, holidays: [], from: monday, days: 14, calendar: seoul
        )
        #expect(ahead.first.map { AlarmOccurrencePlanner.dayKey($0, calendar: seoul) } == 20261130)

        let passed = AlarmOccurrencePlanner.occurrences(
            weekdays: [.monday], hour: 5, minute: 0, holidays: [], from: monday, days: 14, calendar: seoul
        )
        #expect(passed.map { AlarmOccurrencePlanner.dayKey($0, calendar: seoul) } == [20261207, 20261214])
    }

    @Test func staysWithinWindow() {
        let seoul = calendar("Asia/Seoul")
        let now = date(2026, 11, 26, 12, 0, calendar: seoul)
        let dates = AlarmOccurrencePlanner.occurrences(
            weekdays: AlarmWeekday.everyDay, hour: 8, minute: 0, holidays: [], from: now, days: 14, calendar: seoul
        )
        #expect(dates.count == 14)
        #expect(dates.allSatisfy { $0 > now && $0 <= now.addingTimeInterval(14 * 24 * 60 * 60) })
    }

    @Test func keepsWallClockTimeAcrossDST() {
        let newYork = calendar("America/New_York")
        // 2026-03-08 미국 서머타임 시작. 전후 모두 07:00 벽시계 시각이어야 한다.
        let now = date(2026, 3, 6, 12, 0, calendar: newYork)
        let dates = AlarmOccurrencePlanner.occurrences(
            weekdays: AlarmWeekday.everyDay, hour: 7, minute: 0, holidays: [], from: now, days: 5, calendar: newYork
        )
        #expect(dates.count == 5)
        #expect(dates.allSatisfy { newYork.component(.hour, from: $0) == 7 })
    }

    @Test func yearsSpanNewYear() {
        let seoul = calendar("Asia/Seoul")
        let now = date(2026, 12, 25, 9, 0, calendar: seoul)
        #expect(AlarmOccurrencePlanner.years(from: now, days: 14, calendar: seoul) == [2026, 2027])
    }
}

struct HolidayAlarmTests {
    @Test func missingDataDecodesAsEmpty() {
        #expect(HolidayAlarm.decodeList(from: nil).isEmpty)
        #expect(HolidayAlarm.decodeList(from: Data("garbage".utf8)).isEmpty)
    }

    @Test func roundTrips() {
        let list = [HolidayAlarm(itemID: UUID(), alarmID: UUID(), fireDate: Date(timeIntervalSince1970: 1_800_000_000))]
        #expect(HolidayAlarm.decodeList(from: HolidayAlarm.encodeList(list)) == list)
    }

    @Test func legacyItemWithoutHolidayFlagDecodesAsOff() throws {
        let json = """
        {"id":"\(UUID().uuidString)","hour":7,"minute":0,"label":"기상","sound":"bell"}
        """
        let item = try JSONDecoder().decode(AlarmItem.self, from: Data(json.utf8))
        #expect(item.excludesHolidays == false)
        #expect(item.weekdays == AlarmWeekday.everyDay)
    }
}
