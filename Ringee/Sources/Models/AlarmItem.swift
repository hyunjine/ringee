import Foundation

/// 앱이 기억하는 알람 정보. AlarmKit 의 `Alarm` 에는 레이블 · 사운드가 없어 따로 저장한다.
nonisolated struct AlarmItem: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var date: Date
    var label: String
    var sound: AlarmSound
}
