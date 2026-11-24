import SwiftUI

/// 알람 사운드를 고르는 화면. 항목을 누르면 선택과 함께 미리듣기를 재생한다.
struct SoundPickerView: View {
    @Binding var selection: AlarmSound
    @State private var player = SoundPreviewPlayer()

    var body: some View {
        List {
            Section("알람 사운드") {
                ForEach(AlarmSound.allCases) { sound in
                    Button {
                        selection = sound
                        player.play(sound)
                    } label: {
                        HStack {
                            Text(sound.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if player.playingSound == sound {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundStyle(.secondary)
                                    .symbolEffect(.variableColor.iterative)
                            }
                            if selection == sound {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                                    .fontWeight(.semibold)
                            }
                        }
                        .contentShape(.rect)
                    }
                }
            }
        }
        .navigationTitle("사운드")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { player.stop() }
    }
}

#Preview {
    NavigationStack {
        SoundPickerView(selection: .constant(.bell))
    }
}
