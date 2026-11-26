import ProjectDescription

// MARK: - Constants

let appName = "Ringee"
let bundleIdPrefix = "com.hyunjine.ringee"
let deploymentTargets: DeploymentTargets = .iOS("26.0")

// MARK: - Settings

// 버전 (MARKETING_VERSION · CURRENT_PROJECT_VERSION) 은 Configs/Version.xcconfig 에만 둔다.
// base 에 같은 키를 넣으면 xcconfig 보다 우선하니 넣지 않는다.
// Configs/App.xcconfig 가 Version.xcconfig 와 (있으면) 로컬 전용 Secrets.xcconfig 를 함께 불러온다.
let appXcconfig: Path = "Configs/App.xcconfig"

let baseSettings: SettingsDictionary = [
    "SWIFT_VERSION": "6.0",
    "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
    "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
    "SWIFT_STRICT_CONCURRENCY": "complete",
    "DEVELOPMENT_TEAM": "YCCX589JXZ",
    "CODE_SIGN_STYLE": "Automatic",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "TARGETED_DEVICE_FAMILY": "1",
]

let versionInfoPlist: [String: Plist.Value] = [
    "CFBundleShortVersionString": "$(MARKETING_VERSION)",
    "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
]

// MARK: - Targets

let app = Target.target(
    name: appName,
    destinations: [.iPhone],
    product: .app,
    bundleId: bundleIdPrefix,
    deploymentTargets: deploymentTargets,
    infoPlist: .extendingDefault(with: versionInfoPlist.merging([
        "CFBundleDisplayName": "Ringee",
        "UILaunchScreen": [:],
        "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
        // AlarmKit 권한 요청 시 시스템 팝업에 노출되는 문구
        "NSAlarmKitUsageDescription": "설정한 시간에 알람을 울리기 위해 알람 권한이 필요합니다.",
        // AlarmKit 의 카운트다운 / 스누즈 UI 는 Live Activity 로 표시된다
        "NSSupportsLiveActivities": true,
        // 공휴일 API(data.go.kr 특일정보) 키. Configs/Secrets.xcconfig 에 없으면 빈 값 → 공휴일 제외 기능 꺼짐
        "HolidayAPIKey": "$(HOLIDAY_API_KEY)",
        // 공휴일 제외 알람의 등록 창을 앞으로 미는 백그라운드 새로고침
        "UIBackgroundModes": ["fetch"],
        "BGTaskSchedulerPermittedIdentifiers": ["com.hyunjine.ringee.holiday-replan"],
    ]) { $1 }),
    sources: ["Ringee/Sources/**", "Shared/**"],
    resources: ["Ringee/Resources/**"],
    dependencies: [
        .target(name: "\(appName)Widget"),
    ]
)

let widget = Target.target(
    name: "\(appName)Widget",
    destinations: [.iPhone],
    product: .appExtension,
    bundleId: "\(bundleIdPrefix).widget",
    deploymentTargets: deploymentTargets,
    infoPlist: .extendingDefault(with: versionInfoPlist.merging([
        "CFBundleDisplayName": "Ringee Widget",
        "NSExtension": [
            "NSExtensionPointIdentifier": "com.apple.widgetkit-extension",
        ],
    ]) { $1 }),
    sources: ["RingeeWidget/Sources/**", "Shared/**"]
)

let tests = Target.target(
    name: "\(appName)Tests",
    destinations: [.iPhone],
    product: .unitTests,
    bundleId: "\(bundleIdPrefix).tests",
    deploymentTargets: deploymentTargets,
    infoPlist: .default,
    sources: ["RingeeTests/**"],
    dependencies: [
        .target(name: appName),
    ]
)

// MARK: - Project

let project = Project(
    name: appName,
    options: .options(
        defaultKnownRegions: ["ko", "en"],
        developmentRegion: "ko"
    ),
    settings: .settings(
        base: baseSettings,
        configurations: [
            .debug(name: .debug, xcconfig: appXcconfig),
            .release(name: .release, xcconfig: appXcconfig),
        ]
    ),
    targets: [app, widget, tests]
)
