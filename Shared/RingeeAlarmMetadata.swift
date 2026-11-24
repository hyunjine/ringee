import AlarmKit

/// 앱과 위젯 익스텐션이 함께 사용하는 알람 메타데이터.
/// AlarmKit 이 Live Activity 로 전달하므로 두 타깃에 모두 포함되어야 한다.
nonisolated struct RingeeAlarmMetadata: AlarmMetadata {}
