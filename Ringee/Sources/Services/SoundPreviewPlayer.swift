import AVFoundation
import AudioToolbox
import Observation

/// 사운드 선택 화면에서 미리듣기를 재생한다.
@Observable
final class SoundPreviewPlayer {
    private(set) var playingSound: AlarmSound?
    @ObservationIgnored private var player: AVAudioPlayer?

    func play(_ sound: AlarmSound) {
        stop()
        guard let url = sound.fileURL else {
            // 기본 사운드는 번들 파일이 없으므로 시스템 알림음으로 대신 들려준다.
            AudioServicesPlayAlertSound(SystemSoundID(1005))
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.play()
            self.player = player
            playingSound = sound
        } catch {
            print("미리듣기 재생 실패: \(error)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingSound = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
