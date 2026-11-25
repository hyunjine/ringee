import SwiftUI

/// 알람의 시간 · 반복 요일 · 레이블 · 사운드 · 다시 알림을 정하고 저장한다.
/// `editing` 이 있으면 그 알람을 편집하고, 없으면 새 알람을 추가한다.
/// 날짜는 고르지 않는다. 반복 요일이 없으면 매일 울린다.
struct AlarmEditView: View {
    @Environment(AlarmStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let editing: AlarmItem?

    @State private var time: Date
    @State private var weekdays: Set<AlarmWeekday>
    @State private var excludesHolidays: Bool
    @State private var label: String
    @State private var sound: AlarmSound
    @State private var snoozeEnabled: Bool
    @State private var snoozeMinutes: Int
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(editing: AlarmItem? = nil) {
        self.editing = editing
        _time = State(initialValue: editing?.timeOfDay ?? .now)
        _weekdays = State(initialValue: editing?.weekdays ?? [])
        _excludesHolidays = State(initialValue: editing?.excludesHolidays ?? false)
        _label = State(initialValue: editing?.label ?? "")
        _sound = State(initialValue: editing?.sound ?? .systemDefault)
        _snoozeEnabled = State(initialValue: editing?.snoozeEnabled ?? true)
        _snoozeMinutes = State(initialValue: editing?.snoozeMinutes ?? AlarmItem.defaultSnoozeMinutes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("시간", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)

                Section {
                    LabeledContent("반복", value: AlarmWeekday.summary(for: weekdays))
                    WeekdayChips(selection: $weekdays)
                    if !weekdays.isEmpty {
                        Toggle("공휴일 제외", isOn: $excludesHolidays)
                    }
                }

                Section {
                    LabeledContent("레이블") {
                        TextField("알람", text: $label)
                            .multilineTextAlignment(.trailing)
                    }
                    NavigationLink {
                        SoundPickerView(selection: $sound)
                    } label: {
                        LabeledContent("사운드", value: sound.title)
                    }
                    Toggle("다시 알림", isOn: $snoozeEnabled)
                    Picker("다시 알림 연기 시간", selection: $snoozeMinutes) {
                        ForEach(1...30, id: \.self) { minutes in
                            Text("\(minutes)분").tag(minutes)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(!snoozeEnabled)
                }

                if let editing {
                    Section {
                        Button("알람 삭제", role: .destructive) {
                            store.delete(editing)
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                        .disabled(isSaving)
                    }
                }
            }
            .navigationTitle(editing == nil ? "알람 추가" : "알람 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
            .alert(
                "알람을 저장하지 못했습니다",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private var draft: AlarmItem {
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        return AlarmItem(
            hour: components.hour ?? 0,
            minute: components.minute ?? 0,
            weekdays: weekdays,
            excludesHolidays: !weekdays.isEmpty && excludesHolidays,
            snoozeEnabled: snoozeEnabled,
            snoozeMinutes: snoozeMinutes,
            label: label.trimmingCharacters(in: .whitespacesAndNewlines),
            sound: sound
        )
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            if let editing {
                try await store.update(editing, with: draft)
            } else {
                try await store.add(draft)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 일 ~ 토 원형 요일 칩. 여러 요일을 선택할 수 있다.
private struct WeekdayChips: View {
    @Binding var selection: Set<AlarmWeekday>

    var body: some View {
        HStack {
            ForEach(AlarmWeekday.allCases) { day in
                let isSelected = selection.contains(day)
                Button {
                    if isSelected {
                        selection.remove(day)
                    } else {
                        selection.insert(day)
                    }
                } label: {
                    Text(day.shortName)
                        .font(.headline)
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(isSelected ? Color.accentColor : Color(.tertiarySystemFill)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(day.shortName)요일")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                if day != .saturday { Spacer(minLength: 0) }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    AlarmEditView()
        .environment(AlarmStore())
}
