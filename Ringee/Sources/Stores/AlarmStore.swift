import AlarmKit
import Foundation
import Observation
import SwiftUI

/// AlarmKit 스케줄링과 앱 로컬 알람 목록을 함께 관리한다.
@Observable
final class AlarmStore {
    enum StoreError: LocalizedError {
        case notAuthorized

        var errorDescription: String? {
            switch self {
            case .notAuthorized: "알람 권한이 없습니다. 설정에서 알람 권한을 허용해 주세요."
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

    /// AlarmKit 의 알람 · 권한 변경을 구독하고, 빠진 알람을 다시 등록한다.
    func startObserving() {
        guard observationTasks.isEmpty else { return }
        observationTasks.append(Task { [weak self] in
            await self?.restoreMissingAlarms()
        })
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

    /// 새 알람을 등록한다. `item.id` 는 새로 만든 값이어야 한다.
    func add(_ item: AlarmItem) async throws {
        try await register(item)
    }

    /// 기존 알람을 `updated` 의 설정으로 바꾼다.
    /// 새 ID 로 먼저 등록한 뒤 기존 알람을 취소하므로, 등록에 실패하면 기존 알람이 그대로 남는다.
    func update(_ item: AlarmItem, with updated: AlarmItem) async throws {
        var replacement = updated
        if replacement.id == item.id {
            replacement = AlarmItem(
                hour: updated.hour,
                minute: updated.minute,
                weekdays: updated.weekdays,
                excludesHolidays: updated.excludesHolidays,
                snoozeEnabled: updated.snoozeEnabled,
                snoozeMinutes: updated.snoozeMinutes,
                label: updated.label,
                sound: updated.sound
            )
        }
        try await register(replacement)
        delete(item)
    }

    /// 사용자가 명시적으로 삭제할 때만 알람을 목록 · AlarmKit 에서 지운다.
    func delete(_ item: AlarmItem) {
        try? manager.cancel(id: item.id)
        savedItems[item.id] = nil
        refreshItems()
        persist()
    }

    // MARK: - Private

    /// 저장돼 있지만 AlarmKit 에 없는 알람(예: 예전 버전의 한 번만 울리는 알람이 울리고 사라진 경우)을 다시 등록한다.
    private func restoreMissingAlarms() async {
        guard manager.authorizationState == .authorized else { return }
        let liveIDs = Set(((try? manager.alarms) ?? []).map(\.id))
        for item in savedItems.values where !liveIDs.contains(item.id) {
            _ = try? await AlarmManager.shared.schedule(id: item.id, configuration: Self.configuration(for: item))
        }
    }

    /// AlarmKit 에 매주 반복 알람으로 등록하고 로컬 목록에 저장한다.
    private func register(_ item: AlarmItem) async throws {
        try await ensureAuthorized()

        var item = item
        if item.label.isEmpty { item.label = "알람" }

        savedItems[item.id] = item
        persist()
        do {
            _ = try await AlarmManager.shared.schedule(id: item.id, configuration: Self.configuration(for: item))
            refreshItems()
        } catch {
            savedItems[item.id] = nil
            persist()
            throw error
        }
    }

    /// 알람 하나에 해당하는 AlarmKit 설정.
    /// 반복 요일이 없으면 7일 모두 반복해, 울린 뒤에도 알람이 사라지지 않는다.
    /// TODO: 공휴일 제외(`excludesHolidays`)는 공휴일 데이터 출처가 정해지면 반영한다. (#4)
    private nonisolated static func configuration(for item: AlarmItem) -> AlarmManager.AlarmConfiguration<RingeeAlarmMetadata> {
        let schedule = Alarm.Schedule.relative(.init(
            time: .init(hour: item.hour, minute: item.minute),
            repeats: .weekly(AlarmWeekday.effectiveDays(for: item.weekdays).map(\.localeWeekday))
        ))
        let alert = makeAlert(title: item.label, snoozeEnabled: item.snoozeEnabled)
        let presentation = AlarmPresentation(
            alert: alert,
            countdown: item.snoozeEnabled ? AlarmPresentation.Countdown(title: "다시 알림") : nil
        )
        let attributes = AlarmAttributes<RingeeAlarmMetadata>(
            presentation: presentation,
            tintColor: .orange
        )
        return AlarmManager.AlarmConfiguration(
            countdownDuration: item.snoozeEnabled
                ? Alarm.CountdownDuration(preAlert: nil, postAlert: TimeInterval(item.snoozeMinutes * 60))
                : nil,
            schedule: schedule,
            attributes: attributes,
            sound: item.sound.alertSound
        )
    }

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

    /// 다시 알림이 켜져 있으면 "다시 알림" 버튼을 누를 때 `postAlert` 만큼 카운트다운 뒤 다시 울린다.
    private nonisolated static func makeAlert(title: String, snoozeEnabled: Bool) -> AlarmPresentation.Alert {
        let resource = LocalizedStringResource(stringLiteral: title)
        let snoozeButton = snoozeEnabled
            ? AlarmButton(text: "다시 알림", textColor: .white, systemImageName: "repeat")
            : nil
        let behavior: AlarmPresentation.Alert.SecondaryButtonBehavior? = snoozeEnabled ? .countdown : nil
        if #available(iOS 26.1, *) {
            return AlarmPresentation.Alert(
                title: resource,
                secondaryButton: snoozeButton,
                secondaryButtonBehavior: behavior
            )
        } else {
            return AlarmPresentation.Alert(
                title: resource,
                stopButton: AlarmButton(text: "끄기", textColor: .white, systemImageName: "stop.circle"),
                secondaryButton: snoozeButton,
                secondaryButtonBehavior: behavior
            )
        }
    }

    /// AlarmKit 알람 목록이 바뀌어도 저장된 알람은 지우지 않는다.
    /// 울린 알람도 사용자가 삭제하기 전까지 목록에 남는다.
    private func sync(with alarms: [Alarm]) {
        refreshItems()
    }

    private func refreshItems() {
        items = savedItems.values.sorted {
            ($0.minuteOfDay, $0.label) < ($1.minuteOfDay, $1.label)
        }
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
