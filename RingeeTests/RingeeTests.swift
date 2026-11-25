import Foundation
import Testing
@testable import Ringee

struct RingeeTests {
    @Test func metadataIsCodable() throws {
        let data = try JSONEncoder().encode(RingeeAlarmMetadata())
        _ = try JSONDecoder().decode(RingeeAlarmMetadata.self, from: data)
    }
}

struct AlarmWeekdayTests {
    @Test func summaryForNoSelectionIsDaily() {
        #expect(AlarmWeekday.summary(for: []) == "매일")
    }

    @Test func summaryForAllDaysIsDaily() {
        #expect(AlarmWeekday.summary(for: Set(AlarmWeekday.allCases)) == "매일")
    }

    @Test func summaryForWeekdaysAndWeekend() {
        #expect(AlarmWeekday.summary(for: AlarmWeekday.weekdays) == "주중")
        #expect(AlarmWeekday.summary(for: AlarmWeekday.weekend) == "주말")
    }

    @Test func summaryListsDaysInOrder() {
        #expect(AlarmWeekday.summary(for: [.friday, .monday, .wednesday]) == "월 수 금")
        #expect(AlarmWeekday.summary(for: [.saturday, .sunday, .monday]) == "일 월 토")
    }

    @Test func noSelectionRepeatsEveryDay() {
        #expect(AlarmWeekday.effectiveDays(for: []) == AlarmWeekday.allCases)
        #expect(AlarmWeekday.effectiveDays(for: [.friday, .monday]) == [.monday, .friday])
    }

    @Test func mapsToLocaleWeekdays() {
        #expect(AlarmWeekday.allCases.map(\.localeWeekday)
            == [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday])
    }
}

struct AlarmItemCodingTests {
    @Test func roundTrips() throws {
        let item = AlarmItem(
            hour: 7, minute: 30, weekdays: AlarmWeekday.weekdays, excludesHolidays: true,
            snoozeEnabled: false, snoozeMinutes: 5, label: "기상", sound: .bell
        )
        let decoded = try JSONDecoder().decode(AlarmItem.self, from: JSONEncoder().encode(item))
        #expect(decoded == item)
    }

    /// 1.0.0 MVP 가 저장한 날짜 기반 알람은 그 시각의 매일 반복 알람으로 옮겨진다.
    @Test func migratesLegacyDateItem() throws {
        let id = UUID()
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 25
        components.hour = 6
        components.minute = 45
        let date = try #require(Calendar.current.date(from: components))
        let legacy: [String: Any] = [
            "id": id.uuidString,
            "date": date.timeIntervalSinceReferenceDate,
            "label": "기상",
            "sound": "chime",
        ]
        let data = try JSONSerialization.data(withJSONObject: legacy)
        let item = try JSONDecoder().decode(AlarmItem.self, from: data)

        #expect(item.id == id)
        #expect(item.hour == 6)
        #expect(item.minute == 45)
        #expect(item.weekdays.isEmpty)
        #expect(item.repeatSummary == "매일")
        #expect(item.snoozeEnabled)
        #expect(item.snoozeMinutes == AlarmItem.defaultSnoozeMinutes)
        #expect(item.sound == .chime)
    }
}
