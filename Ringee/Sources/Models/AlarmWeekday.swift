import Foundation

/// 알람이 반복되는 요일. 일요일부터 토요일 순서로 정렬된다.
nonisolated enum AlarmWeekday: Int, CaseIterable, Codable, Comparable, Identifiable, Sendable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    var id: Int { rawValue }

    /// 요일 칩 · 요약에 쓰는 한 글자 이름
    var shortName: String {
        switch self {
        case .sunday: "일"
        case .monday: "월"
        case .tuesday: "화"
        case .wednesday: "수"
        case .thursday: "목"
        case .friday: "금"
        case .saturday: "토"
        }
    }

    /// AlarmKit 반복 일정에 넘기는 요일 값
    var localeWeekday: Locale.Weekday {
        switch self {
        case .sunday: .sunday
        case .monday: .monday
        case .tuesday: .tuesday
        case .wednesday: .wednesday
        case .thursday: .thursday
        case .friday: .friday
        case .saturday: .saturday
        }
    }

    static let weekdays: Set<AlarmWeekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    static let weekend: Set<AlarmWeekday> = [.saturday, .sunday]

    static func < (lhs: AlarmWeekday, rhs: AlarmWeekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// 반복 요일 요약. 선택이 없거나 7일 모두면 "매일", 월~금이면 "주중", 토 · 일이면 "주말", 그 외에는 "월 수 금" 처럼 나열한다.
    static func summary(for days: Set<AlarmWeekday>) -> String {
        if days.isEmpty || days.count == allCases.count { return "매일" }
        if days == weekdays { return "주중" }
        if days == weekend { return "주말" }
        return days.sorted().map(\.shortName).joined(separator: " ")
    }

    /// 실제로 울릴 요일. 선택이 없으면 매일 울린다.
    static func effectiveDays(for days: Set<AlarmWeekday>) -> [AlarmWeekday] {
        days.isEmpty ? allCases : days.sorted()
    }
}
