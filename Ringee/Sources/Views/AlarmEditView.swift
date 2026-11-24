import SwiftUI

/// 새 알람의 날짜 · 시간 · 레이블 · 사운드를 정하고 저장한다.
struct AlarmEditView: View {
    @Environment(AlarmStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date.now.addingTimeInterval(60).droppingSeconds
    @State private var label = ""
    @State private var sound: AlarmSound = .systemDefault
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var isPast: Bool { date.droppingSeconds <= .now }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("시간", selection: $date, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                }

                Section {
                    DatePicker(
                        "날짜",
                        selection: $date,
                        in: Calendar.current.startOfDay(for: .now)...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                } footer: {
                    if isPast {
                        Text("이미 지난 시간입니다. 미래의 날짜와 시간을 선택해 주세요.")
                            .foregroundStyle(.red)
                    } else {
                        Text(date.formatted(.dateTime.year().month().day().weekday().hour().minute()) + "에 알람이 울립니다.")
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
                }
            }
            .navigationTitle("알람 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        Task { await save() }
                    }
                    .disabled(isPast || isSaving)
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

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.schedule(date: date, label: label, sound: sound)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    AlarmEditView()
        .environment(AlarmStore())
}
