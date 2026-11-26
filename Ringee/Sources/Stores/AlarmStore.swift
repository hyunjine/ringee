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
    private let holidays: HolidayService
    private let storageKey = "ringee.alarmItems"
    private let holidayAlarmsKey = "ringee.holidayAlarms"

    /// 저장된 알람 (AlarmKit 에 아직 남아 있는지와 상관없이)
    private var savedItems: [UUID: AlarmItem] = [:]
    /// 공휴일 제외 알람을 한 번만 울리는 AlarmKit 알람들로 등록해 둔 발생 (알람 하나 → 여러 AlarmKit ID)
    @ObservationIgnored private var holidayAlarms: [HolidayAlarm] = []
    @ObservationIgnored private var isReplanning = false
    @ObservationIgnored private var needsReplan = false
    @ObservationIgnored private var observationTasks: [Task<Void, Never>] = []

    init(defaults: UserDefaults = .standard, holidays: HolidayService = .shared) {
        self.defaults = defaults
        self.holidays = holidays
        self.authorizationState = manager.authorizationState
        loadSavedItems()
        holidayAlarms = HolidayAlarm.decodeList(from: defaults.data(forKey: holidayAlarmsKey))
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
    /// 꺼진 알람은 AlarmKit 에 등록하지 않고 같은 ID 로 값만 바꿔 저장한다 (꺼진 상태 유지).
    func update(_ item: AlarmItem, with updated: AlarmItem) async throws {
        guard item.isEnabled else {
            var disabled = AlarmItem(
                id: item.id,
                hour: updated.hour,
                minute: updated.minute,
                weekdays: updated.weekdays,
                excludesHolidays: updated.excludesHolidays,
                snoozeEnabled: updated.snoozeEnabled,
                snoozeMinutes: updated.snoozeMinutes,
                label: updated.label,
                sound: updated.sound,
                isEnabled: false
            )
            if disabled.label.isEmpty { disabled.label = "알람" }
            savedItems[item.id] = disabled
            refreshItems()
            persist()
            return
        }
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

    /// 알람을 켜거나 끈다. 끄면 AlarmKit 알람만 취소하고 목록에는 남기며, 켜면 같은 ID 로 다시 등록한다.
    func setEnabled(_ item: AlarmItem, _ enabled: Bool) async throws {
        guard var stored = savedItems[item.id], stored.isEnabled != enabled else { return }
        stored.isEnabled = enabled
        if enabled {
            try await register(stored)
        } else {
            cancelAllAlarms(for: stored.id)
            savedItems[stored.id] = stored
            refreshItems()
            persist()
        }
    }

    /// 사용자가 명시적으로 삭제할 때만 알람을 목록 · AlarmKit 에서 지운다.
    func delete(_ item: AlarmItem) {
        cancelAllAlarms(for: item.id)
        savedItems[item.id] = nil
        refreshItems()
        persist()
    }

    // MARK: - Private

    /// 저장돼 있지만 AlarmKit 에 없는 알람(예: 예전 버전의 한 번만 울리는 알람이 울리고 사라진 경우)을 다시 등록한다.
    /// 사용자가 꺼 둔 알람은 등록하지 않는다.
    private func restoreMissingAlarms() async {
        guard manager.authorizationState == .authorized else { return }
        let liveIDs = Set(((try? manager.alarms) ?? []).map(\.id))
        for item in savedItems.values where item.isEnabled && !item.excludesHolidays && !liveIDs.contains(item.id) {
            _ = try? await AlarmManager.shared.schedule(
                id: item.id,
                configuration: Self.configuration(for: item, schedule: Self.weeklySchedule(for: item))
            )
        }
        await replanHolidayAlarms()
    }

    // MARK: - Holiday exclusion

    /// 공휴일 제외 알람의 등록 창(`AlarmOccurrencePlanner.windowDays` 일)을 지금 기준으로 다시 채운다.
    /// 앱이 켜질 때 · 포그라운드로 올 때 · 백그라운드 새로고침 · 공휴일 제외 알람이 울리고 사라졌을 때 부른다.
    ///
    /// 이미 시각이 지난 발생(울리는 중이거나 다시 알림 대기 중일 수 있음)은 건드리지 않고,
    /// 앞으로의 발생만 계획과 맞춘다.
    ///
    /// 한계: 앱을 열지 않고 백그라운드 새로고침도 창 길이 넘게 돌지 않으면, 창이 끝난 뒤부터는 울리지 않는다.
    func replanHolidayAlarms() async {
        guard manager.authorizationState == .authorized else { return }
        if isReplanning {
            needsReplan = true
            return
        }
        isReplanning = true
        defer { isReplanning = false }
        repeat {
            needsReplan = false
            let now = Date.now
            let liveIDs = Set(((try? manager.alarms) ?? []).map(\.id))
            // AlarmKit 에서 사라진 발생을 목록에서 뺀다. 이미 울리고 끝난 발생이거나,
            // 앞으로 울릴 예정인데 사라진 발생(아래에서 다시 등록된다)이다.
            holidayAlarms.removeAll { !liveIDs.contains($0.alarmID) }

            // 삭제 · 꺼짐 · 공휴일 제외 해제된 알람의 앞으로의 발생은 취소한다.
            let orphaned = holidayAlarms.filter { entry in
                guard entry.fireDate > now else { return false }
                guard let item = savedItems[entry.itemID] else { return true }
                return !(item.isEnabled && item.excludesHolidays)
            }
            for entry in orphaned {
                try? manager.cancel(id: entry.alarmID)
            }
            let orphanedIDs = Set(orphaned.map(\.alarmID))
            holidayAlarms.removeAll { orphanedIDs.contains($0.alarmID) }

            for item in savedItems.values where item.isEnabled && item.excludesHolidays {
                if let plan = await holidayPlan(for: item, now: now) {
                    // 공휴일 데이터를 못 받았을 때 대신 등록해 둔 매주 반복 알람이 있으면 정리한다.
                    if liveIDs.contains(item.id) { try? manager.cancel(id: item.id) }
                    try? await syncHolidayAlarms(for: item, dates: plan, now: now)
                } else if !liveIDs.contains(item.id) {
                    // 공휴일 데이터를 쓸 수 없으면 공휴일 제외를 끈 것처럼 매주 반복으로 울린다.
                    _ = try? await AlarmManager.shared.schedule(
                        id: item.id,
                        configuration: Self.configuration(for: item, schedule: Self.weeklySchedule(for: item))
                    )
                }
            }
            persistHolidayAlarms()
        } while needsReplan
    }

    /// 공휴일을 뺀 앞으로의 발생 시각. 공휴일 데이터를 쓸 수 없으면 `nil`.
    private func holidayPlan(for item: AlarmItem, now: Date) async -> [Date]? {
        let currentYear = Calendar.current.component(.year, from: now)
        let years = Set(AlarmOccurrencePlanner.years(from: now)).union([currentYear, currentYear + 1]).sorted()
        guard let holidayDays = await holidays.holidayDays(for: years, now: now) else { return nil }
        return AlarmOccurrencePlanner.occurrences(
            weekdays: item.weekdays,
            hour: item.hour,
            minute: item.minute,
            holidays: holidayDays,
            from: now
        )
    }

    /// 한 알람의 앞으로의 발생을 `dates` 와 맞춘다. 없는 날짜는 한 번만 울리는 알람으로 등록하고, 빠진 날짜는 취소한다.
    private func syncHolidayAlarms(for item: AlarmItem, dates: [Date], now: Date) async throws {
        let wanted = Set(dates)
        let upcoming = holidayAlarms.filter { $0.itemID == item.id && $0.fireDate > now }
        let stale = upcoming.filter { !wanted.contains($0.fireDate) }
        for entry in stale {
            try? manager.cancel(id: entry.alarmID)
        }
        let staleIDs = Set(stale.map(\.alarmID))
        holidayAlarms.removeAll { staleIDs.contains($0.alarmID) }

        let scheduled = Set(upcoming.map(\.fireDate))
        for date in dates where !scheduled.contains(date) {
            let alarmID = UUID()
            _ = try await AlarmManager.shared.schedule(
                id: alarmID,
                configuration: Self.configuration(for: item, schedule: .fixed(date))
            )
            holidayAlarms.append(HolidayAlarm(itemID: item.id, alarmID: alarmID, fireDate: date))
            persistHolidayAlarms()
        }
    }

    /// 알람 하나에 딸린 AlarmKit 알람(매주 반복 1개 + 공휴일 제외 발생들)을 모두 취소한다.
    private func cancelAllAlarms(for itemID: UUID) {
        try? manager.cancel(id: itemID)
        for entry in holidayAlarms where entry.itemID == itemID {
            try? manager.cancel(id: entry.alarmID)
        }
        holidayAlarms.removeAll { $0.itemID == itemID }
        persistHolidayAlarms()
    }

    private func persistHolidayAlarms() {
        defaults.set(HolidayAlarm.encodeList(holidayAlarms), forKey: holidayAlarmsKey)
    }

    /// AlarmKit 에 등록하고 로컬 목록에 저장한다.
    /// - 공휴일 제외가 꺼져 있으면 매주 반복 알람 하나(AlarmKit ID = 알람 ID)로 등록한다.
    /// - 공휴일 제외가 켜져 있으면 앞으로 `AlarmOccurrencePlanner.windowDays` 일의 발생을 한 번만 울리는 알람들로 등록한다.
    ///   공휴일 데이터를 쓸 수 없으면(API 키 없음 · 받아 온 적 없음) 매주 반복으로 대신 등록한다.
    /// 등록에 실패하면 저장소를 등록 전 상태로 되돌린다 (꺼 둔 알람을 켜다 실패하면 꺼진 상태로 남는다).
    private func register(_ item: AlarmItem) async throws {
        try await ensureAuthorized()

        var item = item
        if item.label.isEmpty { item.label = "알람" }

        let previous = savedItems[item.id]
        savedItems[item.id] = item
        persist()
        do {
            let now = Date.now
            if item.excludesHolidays, let plan = await holidayPlan(for: item, now: now) {
                try? manager.cancel(id: item.id)
                try await syncHolidayAlarms(for: item, dates: plan, now: now)
            } else {
                _ = try await AlarmManager.shared.schedule(
                    id: item.id,
                    configuration: Self.configuration(for: item, schedule: Self.weeklySchedule(for: item))
                )
            }
            refreshItems()
        } catch {
            if previous == nil { cancelAllAlarms(for: item.id) }
            savedItems[item.id] = previous
            persist()
            throw error
        }
    }

    /// 매주 반복 일정. 반복 요일이 없으면 7일 모두 반복해, 울린 뒤에도 알람이 사라지지 않는다.
    private nonisolated static func weeklySchedule(for item: AlarmItem) -> Alarm.Schedule {
        .relative(.init(
            time: .init(hour: item.hour, minute: item.minute),
            repeats: .weekly(AlarmWeekday.effectiveDays(for: item.weekdays).map(\.localeWeekday))
        ))
    }

    /// 알람 하나에 해당하는 AlarmKit 설정.
    private nonisolated static func configuration(
        for item: AlarmItem,
        schedule: Alarm.Schedule
    ) -> AlarmManager.AlarmConfiguration<RingeeAlarmMetadata> {
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
    /// 공휴일 제외 알람의 발생이 울리고 사라지면 창을 다시 채운다.
    private func sync(with alarms: [Alarm]) {
        refreshItems()
        let liveIDs = Set(alarms.map(\.id))
        if holidayAlarms.contains(where: { !liveIDs.contains($0.alarmID) }) {
            Task { await replanHolidayAlarms() }
        }
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
