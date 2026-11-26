import BackgroundTasks
import SwiftUI

@main
struct RingeeApp: App {
    /// 공휴일 제외 알람의 등록 창을 하루에 한 번 앞으로 미는 백그라운드 새로고침 작업.
    /// Info.plist 의 `BGTaskSchedulerPermittedIdentifiers` 와 같아야 한다.
    static let holidayRefreshTaskID = "com.hyunjine.ringee.holiday-replan"

    @State private var store = AlarmStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AlarmListView()
                .environment(store)
                .task { store.startObserving() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await store.replanHolidayAlarms() }
            case .background:
                Self.scheduleHolidayRefresh()
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(Self.holidayRefreshTaskID)) {
            await store.replanHolidayAlarms()
            await Self.scheduleHolidayRefresh()
        }
    }

    /// 다음 백그라운드 새로고침을 하루 뒤로 요청한다. 실제 실행 시점은 시스템이 정한다 (보장되지 않음).
    private static func scheduleHolidayRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: holidayRefreshTaskID)
        request.earliestBeginDate = Date.now.addingTimeInterval(24 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
