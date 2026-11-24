import AlarmKit
import Foundation
import Observation
import SwiftUI

/// AlarmKit 스케줄링과 앱 로컬 알람 목록을 함께 관리한다.
@Observable
final class AlarmStore {
    enum StoreError: LocalizedError {
        case notAuthorized
        case pastDate

        var errorDescription: String? {
            switch self {
            case .notAuthorized: "알람 권한이 없습니다. 설정에서 알람 권한을 허용해 주세요."
            case .pastDate: "이미 지난 시간에는 알람을 설정할 수 없습니다."
            }
        }
    }

    private(set) var items: [AlarmItem] = []
    private(set) var authorizationState: AlarmManager.AuthorizationState

    private let manager = AlarmManager.shared
    private let defaults: UserDefaults
    private let storageKey = "ringee.alarmItems"

    /// 저장된 알람 (AlarmKit 에 아직 남아 있는지와 상관없이)
    private var savedItems: [UUID: AlarmItem] = [:]
    @ObservationIgnored private var observationTasks: [Task<Void, Never>] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.authorizationState = manager.authorizationState
        loadSavedItems()
        sync(with: (try? manager.alarms) ?? [])
    }

    /// AlarmKit 의 알람 · 권한 변경을 구독한다.
    func startObserving() {
        guard observationTasks.isEmpty else { return }
        observationTasks.append(Task { [weak self] in
            guard let updates = self?.manager.alarmUpdates else { return }
            for await alarms in updates {
                self?.sync(with: alarms)
            }
        })
        observationTasks.append(Task { [weak self] in
            guard let updates = self?.manager.authorizationUpdates else { return }
            for await state in updates {
                self?.authorizationState = state
            }
        })
    }

    // MARK: - Actions

    func schedule(date: Date, label: String, sound: AlarmSound) async throws {
        let fireDate = date.droppingSeconds
        guard fireDate > .now else { throw StoreError.pastDate }
        try await ensureAuthorized()

        let title = label.isEmpty ? "알람" : label
        let alert = makeAlert(title: title)
        let attributes = AlarmAttributes<RingeeAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            tintColor: .orange
        )
        let id = UUID()
        let configuration = AlarmManager.AlarmConfiguration<RingeeAlarmMetadata>.alarm(
            schedule: .fixed(fireDate),
            attributes: attributes,
            sound: sound.alertSound
        )

        let item = AlarmItem(id: id, date: fireDate, label: title, sound: sound)
        savedItems[id] = item
        persist()
        do {
            _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
            upsertVisible(item)
        } catch {
            savedItems[id] = nil
            persist()
            throw error
        }
    }

    func delete(_ item: AlarmItem) {
        try? manager.cancel(id: item.id)
        savedItems[item.id] = nil
        items.removeAll { $0.id == item.id }
        persist()
    }

    // MARK: - Private

    private func ensureAuthorized() async throws {
        switch manager.authorizationState {
        case .authorized:
            authorizationState = .authorized
        case .notDetermined:
            let state = try await AlarmManager.shared.requestAuthorization()
            authorizationState = state
            guard state == .authorized else { throw StoreError.notAuthorized }
        case .denied:
            authorizationState = .denied
            throw StoreError.notAuthorized
        @unknown default:
            throw StoreError.notAuthorized
        }
    }

    private func makeAlert(title: String) -> AlarmPresentation.Alert {
        let resource = LocalizedStringResource(stringLiteral: title)
        if #available(iOS 26.1, *) {
            return AlarmPresentation.Alert(title: resource)
        } else {
            return AlarmPresentation.Alert(
                title: resource,
                stopButton: AlarmButton(text: "끄기", textColor: .white, systemImageName: "stop.circle")
            )
        }
    }

    /// AlarmKit 에 남아 있는 알람만 목록에 보여 주고, 사라진 (울리고 꺼진 · 취소된) 알람은 저장소에서도 지운다.
    private func sync(with alarms: [Alarm]) {
        let liveIDs = Set(alarms.map(\.id))
        let removed = savedItems.keys.filter { !liveIDs.contains($0) }
        removed.forEach { savedItems[$0] = nil }
        if !removed.isEmpty { persist() }

        items = alarms
            .compactMap { savedItems[$0.id] }
            .sorted { $0.date < $1.date }
    }

    private func upsertVisible(_ item: AlarmItem) {
        items.removeAll { $0.id == item.id }
        items.append(item)
        items.sort { $0.date < $1.date }
    }

    private func loadSavedItems() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([AlarmItem].self, from: data)
        else { return }
        savedItems = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
    }

    private func persist() {
        let data = try? JSONEncoder().encode(Array(savedItems.values))
        defaults.set(data, forKey: storageKey)
    }
}

extension Date {
    /// 초 · 나노초를 버린 분 단위 시각
    nonisolated var droppingSeconds: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: self)
        return calendar.date(from: components) ?? self
    }
}
