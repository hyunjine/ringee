import Foundation

/// 공휴일 제외 알람이 앞으로 울릴 시각을 계산한다.
///
/// AlarmKit 의 매주 반복 일정은 특정 날짜만 건너뛸 수 없어서, 공휴일 제외 알람은
/// 앞으로 `windowDays` 일 동안의 각 발생을 한 번만 울리는 알람으로 따로 등록한다.
/// 앱이 열리거나 백그라운드 새로고침이 돌 때마다 창을 앞으로 밀어 다시 채운다.
///
/// 한계: 앱을 열지 않고 백그라운드 새로고침도 `windowDays` 일 넘게 돌지 않으면,
/// 창이 끝난 뒤부터는 공휴일 제외 알람이 울리지 않는다.
nonisolated enum AlarmOccurrencePlanner {
    /// 미리 등록해 두는 기간 (일)
    static let windowDays = 14

    /// `now` 이후 `days` 일 안에서 반복 요일 · 시각에 해당하고 공휴일이 아닌 발생 시각.
    /// 시각은 `calendar` 의 시간대 기준 벽시계 시각이며, 일광 절약 시간 전환일에도 해당 날짜의 그 시각을 쓴다.
    static func occurrences(
        weekdays: Set<AlarmWeekday>,
        hour: Int,
        minute: Int,
        holidays: Set<Int>,
        from now: Date,
        days: Int = windowDays,
        calendar: Calendar = .current
    ) -> [Date] {
        let activeDays = Set(AlarmWeekday.effectiveDays(for: weekdays).map(\.rawValue))
        let startOfToday = calendar.startOfDay(for: now)
        var result: [Date] = []
        // 오늘이 이미 지난 경우를 생각해 days 일을 꽉 채우도록 하루 더 본다.
        for offset in 0...days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            guard activeDays.contains(weekday) else { continue }
            guard !holidays.contains(dayKey(day, calendar: calendar)) else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = hour
            components.minute = minute
            components.second = 0
            // 존재하지 않는 시각(봄철 전환)은 다음 유효 시각으로 밀린다.
            guard let fireDate = calendar.date(from: components), fireDate > now else { continue }
            guard fireDate <= now.addingTimeInterval(TimeInterval(days) * 24 * 60 * 60) else { continue }
            result.append(fireDate)
        }
        return result
    }

    /// 날짜의 yyyyMMdd 정수 (공휴일 API 의 `locdate` 와 같은 형식)
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    /// 창 안의 날짜가 걸쳐 있는 연도 (공휴일 데이터를 받아야 하는 연도)
    static func years(from now: Date, days: Int = windowDays, calendar: Calendar = .current) -> [Int] {
        let start = calendar.component(.year, from: now)
        let endDate = calendar.date(byAdding: .day, value: days + 1, to: now) ?? now
        let end = calendar.component(.year, from: endDate)
        return Array(start...max(start, end))
    }
}
