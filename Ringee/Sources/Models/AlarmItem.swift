import Foundation

/// 앱이 기억하는 알람 정보. AlarmKit 의 `Alarm` 에는 레이블 · 사운드 등이 없어 따로 저장한다.
/// 사용자가 삭제하기 전까지는 울린 뒤에도 목록에 남는다.
nonisolated struct AlarmItem: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var hour: Int
    var minute: Int
    /// 반복 요일. 비어 있으면 매일 반복한다.
    var weekdays: Set<AlarmWeekday>
    /// 공휴일에는 울리지 않음. 반복 요일이 있을 때만 의미가 있다.
    var excludesHolidays: Bool
    var snoozeEnabled: Bool
    /// 다시 알림까지 기다리는 시간 (분)
    var snoozeMinutes: Int
    var label: String
    var sound: AlarmSound

    static let defaultSnoozeMinutes = 9

    init(
        id: UUID = UUID(),
        hour: Int,
        minute: Int,
        weekdays: Set<AlarmWeekday> = [],
        excludesHolidays: Bool = false,
        snoozeEnabled: Bool = true,
        snoozeMinutes: Int = AlarmItem.defaultSnoozeMinutes,
        label: String,
        sound: AlarmSound
    ) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.weekdays = weekdays
        self.excludesHolidays = excludesHolidays
        self.snoozeEnabled = snoozeEnabled
        self.snoozeMinutes = snoozeMinutes
        self.label = label
        self.sound = sound
    }

    /// 반복 요일 요약 ("매일", "주중", "월 수 금" 등)
    var repeatSummary: String { AlarmWeekday.summary(for: weekdays) }

    /// 정렬 · 비교용 하루 중 분 단위 시각
    var minuteOfDay: Int { hour * 60 + minute }

    /// 오늘 날짜에 이 알람 시각을 붙인 값. 화면에 시각을 표시할 때 쓴다.
    var timeOfDay: Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, hour, minute, weekdays, excludesHolidays, snoozeEnabled, snoozeMinutes, label, sound
    }

    /// 1.0.0 MVP 가 저장한 날짜 기반 알람의 키
    private enum LegacyKeys: String, CodingKey {
        case date
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        sound = try container.decodeIfPresent(AlarmSound.self, forKey: .sound) ?? .systemDefault
        weekdays = try container.decodeIfPresent(Set<AlarmWeekday>.self, forKey: .weekdays) ?? []
        excludesHolidays = try container.decodeIfPresent(Bool.self, forKey: .excludesHolidays) ?? false
        snoozeEnabled = try container.decodeIfPresent(Bool.self, forKey: .snoozeEnabled) ?? true
        snoozeMinutes = try container.decodeIfPresent(Int.self, forKey: .snoozeMinutes) ?? Self.defaultSnoozeMinutes

        if let hour = try container.decodeIfPresent(Int.self, forKey: .hour),
           let minute = try container.decodeIfPresent(Int.self, forKey: .minute) {
            self.hour = hour
            self.minute = minute
        } else {
            // 예전 데이터: 고정 날짜의 시각만 가져와 매일 반복 알람으로 옮긴다.
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            let date = try legacy.decode(Date.self, forKey: .date)
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            hour = components.hour ?? 0
            minute = components.minute ?? 0
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(hour, forKey: .hour)
        try container.encode(minute, forKey: .minute)
        try container.encode(weekdays, forKey: .weekdays)
        try container.encode(excludesHolidays, forKey: .excludesHolidays)
        try container.encode(snoozeEnabled, forKey: .snoozeEnabled)
        try container.encode(snoozeMinutes, forKey: .snoozeMinutes)
        try container.encode(label, forKey: .label)
        try container.encode(sound, forKey: .sound)
    }
}
