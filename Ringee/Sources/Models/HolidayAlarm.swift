import Foundation

/// 공휴일 제외 알람의 발생 하나를 AlarmKit 에 한 번만 울리는 알람으로 등록한 기록.
/// 알람(`itemID`) 하나에 여러 개가 생기며, 삭제 · 끄기 · 편집 때 함께 취소한다.
nonisolated struct HolidayAlarm: Codable, Hashable, Sendable {
    let itemID: UUID
    let alarmID: UUID
    let fireDate: Date

    /// 저장된 목록을 읽는다. 저장된 적이 없거나(이전 버전) 읽을 수 없으면 빈 목록.
    static func decodeList(from data: Data?) -> [HolidayAlarm] {
        guard let data, let list = try? JSONDecoder().decode([HolidayAlarm].self, from: data) else { return [] }
        return list
    }

    static func encodeList(_ list: [HolidayAlarm]) -> Data? {
        try? JSONEncoder().encode(list)
    }
}
