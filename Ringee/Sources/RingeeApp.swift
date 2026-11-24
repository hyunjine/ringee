import SwiftUI

@main
struct RingeeApp: App {
    @State private var store = AlarmStore()

    var body: some Scene {
        WindowGroup {
            AlarmListView()
                .environment(store)
                .task { store.startObserving() }
        }
    }
}
