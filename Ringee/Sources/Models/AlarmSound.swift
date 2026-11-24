import ActivityKit
import Foundation

/// 알람이 울릴 때 재생되는 사운드.
/// `fileName` 이 nil 이면 시스템 기본 알람 사운드를 사용한다.
nonisolated enum AlarmSound: String, CaseIterable, Codable, Identifiable, Sendable {
    case systemDefault
    case bell
    case beep
    case chime
    case morning

    var id: String { rawValue }

    var title: String {
        switch self {
        case .systemDefault: "기본"
        case .bell: "클래식 벨"
        case .beep: "디지털 비프"
        case .chime: "부드러운 차임"
        case .morning: "아침 멜로디"
        }
    }

    /// 앱 번들에 포함된 사운드 파일 이름 (확장자 포함)
    var fileName: String? {
        switch self {
        case .systemDefault: nil
        case .bell: "ringee_bell.caf"
        case .beep: "ringee_beep.caf"
        case .chime: "ringee_chime.caf"
        case .morning: "ringee_morning.caf"
        }
    }

    var fileURL: URL? {
        guard let fileName else { return nil }
        return Bundle.main.url(forResource: fileName, withExtension: nil)
    }

    var alertSound: AlertConfiguration.AlertSound {
        guard let fileName else { return .default }
        return .named(fileName)
    }
}
