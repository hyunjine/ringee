import AlarmKit
import SwiftUI

/// 등록된 알람 목록. 오른쪽 위 + 로 새 알람을 추가하고, 행을 누르면 편집한다.
struct AlarmListView: View {
    @Environment(AlarmStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var isPresentingEditor = false
    @State private var editingItem: AlarmItem?

    var body: some View {
        NavigationStack {
            Group {
                if store.authorizationState == .denied {
                    deniedView
                } else if store.items.isEmpty {
                    emptyView
                } else {
                    list
                }
            }
            .navigationTitle("알람")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("알람 추가", systemImage: "plus") {
                        isPresentingEditor = true
                    }
                }
            }
            .sheet(isPresented: $isPresentingEditor) {
                AlarmEditView()
            }
            .sheet(item: $editingItem) { item in
                AlarmEditView(editing: item)
            }
        }
    }

    private var list: some View {
        List {
            ForEach(store.items) { item in
                Button {
                    editingItem = item
                } label: {
                    AlarmRow(item: item)
                }
                .tint(.primary)
            }
            .onDelete { offsets in
                offsets.map { store.items[$0] }.forEach(store.delete)
            }
        }
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("알람 없음", systemImage: "alarm")
        } description: {
            Text("+ 버튼을 눌러 새 알람을 추가하세요.")
        } actions: {
            Button("알람 추가") { isPresentingEditor = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
        }
    }

    private var deniedView: some View {
        ContentUnavailableView {
            Label("알람 권한 꺼짐", systemImage: "alarm.waves.left.and.right")
        } description: {
            Text("설정에서 Ringee 의 알람 권한을 허용해야 알람이 울립니다.")
        } actions: {
            Button("설정 열기") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
    }
}

private struct AlarmRow: View {
    let item: AlarmItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.date, format: .dateTime.hour().minute())
                .font(.system(size: 48, weight: .light))
                .monospacedDigit()
            Text("\(item.label), \(item.date.formatted(.dateTime.month().day().weekday()))")
                .font(.subheadline)
            Label(item.sound.title, systemImage: "music.note")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    AlarmListView()
        .environment(AlarmStore())
}
