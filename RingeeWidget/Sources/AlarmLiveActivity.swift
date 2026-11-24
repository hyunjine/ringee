import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

/// AlarmKit 알람의 카운트다운 / 일시정지 상태를 잠금화면과 Dynamic Island 에 표시한다.
struct AlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<RingeeAlarmMetadata>.self) { context in
            HStack {
                Image(systemName: "alarm")
                Text(context.attributes.presentation.alert.title)
                    .font(.headline)
                Spacer()
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.presentation.alert.title)
                }
            } compactLeading: {
                Image(systemName: "alarm")
            } compactTrailing: {
                EmptyView()
            } minimal: {
                Image(systemName: "alarm")
            }
        }
    }
}
