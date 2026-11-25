import AlarmKit
import SwiftUI

/// 등록된 알람 목록. 오른쪽 위 + 로 새 알람을 추가하고, 행을 누르면 편집한다.
struct AlarmListView: View {
    @Environment(AlarmStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var isPresentingEditor = false
    @State private var editingItem: AlarmItem?
    @State private var errorMessage: String?

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
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
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
            .alert(
                "알람을 켜지 못했습니다",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var list: some View {
        List {
            ForEach(store.items) { item in
                AlarmRow(item: item, isEnabled: enabledBinding(for: item)) {
                    editingItem = item
                }
            }
            .onDelete { offsets in
                offsets.map { store.items[$0] }.forEach(store.delete)
            }
        }
    }

    /// 토글을 바꾸면 AlarmKit 등록 · 취소를 함께 처리한다.
    private func enabledBinding(for item: AlarmItem) -> Binding<Bool> {
        Binding(
            get: { item.isEnabled },
            set: { enabled in
                Task {
                    do {
                        try await store.setEnabled(item, enabled)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        )
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

/// 알람 한 줄. 텍스트 영역을 누르면 편집하고, 오른쪽 토글로 켜고 끈다. 꺼진 알람은 텍스트를 흐리게 보여 준다.
private struct AlarmRow: View {
    let item: AlarmItem
    @Binding var isEnabled: Bool
    let onTap: () -> Void

    var body: some View {
        HStack {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.timeOfDay, format: .dateTime.hour().minute())
                        .font(.system(size: 48, weight: .light))
                        .monospacedDigit()
                    Text("\(item.label), \(item.repeatSummary)")
                        .font(.subheadline)
                    Label(item.sound.title, systemImage: "music.note")
                        .font(.footnote)
                        .foregroundStyle(isEnabled ? .secondary : .tertiary)
                }
                .foregroundStyle(isEnabled ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Toggle("알람 켜기", isOn: $isEnabled)
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    AlarmListView()
        .environment(AlarmStore())
}
