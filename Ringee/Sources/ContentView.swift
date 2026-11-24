import AlarmKit
import SwiftUI

struct ContentView: View {
    @State private var authorizationState = AlarmManager.shared.authorizationState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "alarm")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Ringee")
                .font(.largeTitle.bold())
            Text("알람 권한: \(authorizationState.description)")
                .foregroundStyle(.secondary)

            if authorizationState == .notDetermined {
                Button("알람 권한 요청") {
                    Task { await requestAuthorization() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private func requestAuthorization() async {
        do {
            authorizationState = try await AlarmManager.shared.requestAuthorization()
        } catch {
            print("AlarmKit 권한 요청 실패: \(error)")
        }
    }
}

extension AlarmManager.AuthorizationState {
    var description: String {
        switch self {
        case .notDetermined: "미결정"
        case .authorized: "허용됨"
        case .denied: "거부됨"
        @unknown default: "알 수 없음"
        }
    }
}

#Preview {
    ContentView()
}
