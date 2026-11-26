import Foundation
import OSLog

/// 공휴일 하루. `day` 는 yyyyMMdd 정수 (예: 20260301).
nonisolated struct Holiday: Codable, Hashable, Sendable {
    let day: Int
    let name: String
}

/// data.go.kr 특일정보(SpcdeInfoService) `getRestDeInfo` 응답 파서.
///
/// 항목은 `response.body.items.item` 에 오는데, 한국 공공 API 관례상 모양이 세 가지다.
/// - 항목이 여러 개: `item` 이 배열
/// - 항목이 하나: `item` 이 객체
/// - 항목이 없음: `items` 가 빈 문자열 `""`
nonisolated enum HolidayResponseParser {
    enum ParseError: Error, Equatable {
        case service(code: String, message: String)
    }

    /// `isHoliday == "Y"` 인 항목만 돌려준다.
    static func parse(_ data: Data) throws -> [Holiday] {
        let root = try JSONDecoder().decode(Root.self, from: data)
        if let header = root.response.header, header.resultCode != "00" {
            throw ParseError.service(code: header.resultCode, message: header.resultMsg ?? "")
        }
        return (root.response.body?.items.entries ?? [])
            .filter { $0.isHoliday == "Y" }
            .map { Holiday(day: $0.locdate, name: $0.dateName) }
    }

    private struct Root: Decodable {
        let response: Response
    }

    private struct Response: Decodable {
        let header: Header?
        let body: Body?
    }

    private struct Header: Decodable {
        let resultCode: String
        let resultMsg: String?
    }

    private struct Body: Decodable {
        let items: Items
    }

    private struct Items: Decodable {
        let entries: [Entry]

        private enum CodingKeys: String, CodingKey { case item }

        init(from decoder: any Decoder) throws {
            // 항목이 없으면 `items` 자리에 빈 문자열이 온다.
            if let single = try? decoder.singleValueContainer(), (try? single.decode(String.self)) != nil {
                entries = []
                return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let list = try? container.decode([Entry].self, forKey: .item) {
                entries = list
            } else if let one = try container.decodeIfPresent(Entry.self, forKey: .item) {
                entries = [one]
            } else {
                entries = []
            }
        }
    }

    private struct Entry: Decodable {
        let locdate: Int
        let dateName: String
        let isHoliday: String

        private enum CodingKeys: String, CodingKey { case locdate, dateName, isHoliday }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // locdate 는 보통 정수지만 문자열로 오는 경우도 받아 준다.
            if let value = try? container.decode(Int.self, forKey: .locdate) {
                locdate = value
            } else {
                locdate = Int(try container.decode(String.self, forKey: .locdate)) ?? 0
            }
            dateName = try container.decodeIfPresent(String.self, forKey: .dateName) ?? ""
            isHoliday = try container.decodeIfPresent(String.self, forKey: .isHoliday) ?? "N"
        }
    }
}

/// 연도별 공휴일 캐시. 한 번 받아 오면 오프라인에서도 쓸 수 있도록 UserDefaults 에 저장한다.
nonisolated struct HolidayCache: Codable, Sendable, Equatable {
    struct Entry: Codable, Sendable, Equatable {
        var holidays: [Holiday]
        var fetchedAt: Date
    }

    var years: [Int: Entry] = [:]

    /// 캐시가 이만큼 오래되면 다시 받아 온다 (대체 · 임시 공휴일이 뒤늦게 지정되는 경우 대비).
    static let refreshInterval: TimeInterval = 7 * 24 * 60 * 60

    func needsRefresh(year: Int, now: Date) -> Bool {
        guard let entry = years[year] else { return true }
        return now.timeIntervalSince(entry.fetchedAt) > Self.refreshInterval
    }
}

/// 공휴일 데이터를 받아 오고 캐시한다. 출처는 data.go.kr 특일정보 API (linker 앱과 같은 방식).
///
/// API 키는 `Configs/Secrets.xcconfig` 의 `HOLIDAY_API_KEY` → Info.plist `HolidayAPIKey` 로 들어온다.
/// 키가 없으면 공휴일 제외 기능은 꺼진 것처럼 동작한다.
@MainActor
final class HolidayService {
    static let shared = HolidayService()

    private nonisolated static let endpoint = URL(string: "https://apis.data.go.kr/B090041/openapi/service/SpcdeInfoService/getRestDeInfo")!
    private static let logger = Logger(subsystem: "com.hyunjine.ringee", category: "Holiday")

    private let defaults: UserDefaults
    private let session: URLSession
    private let apiKey: String?
    private let cacheKey = "ringee.holidayCache"
    private var cache: HolidayCache
    private var didLogMissingKey = false

    init(
        defaults: UserDefaults = .standard,
        session: URLSession = .shared,
        apiKey: String? = HolidayService.bundledAPIKey()
    ) {
        self.defaults = defaults
        self.session = session
        self.apiKey = apiKey
        if let data = defaults.data(forKey: cacheKey),
           let decoded = try? JSONDecoder().decode(HolidayCache.self, from: data) {
            cache = decoded
        } else {
            cache = HolidayCache()
        }
    }

    /// 공휴일 제외를 쓸 수 있는지 (API 키가 있는지)
    var isAvailable: Bool {
        if apiKey != nil { return true }
        if !didLogMissingKey {
            didLogMissingKey = true
            Self.logger.notice("HOLIDAY_API_KEY 가 없어 공휴일 제외 기능을 끈 상태로 동작합니다.")
        }
        return false
    }

    /// 주어진 연도들의 공휴일(yyyyMMdd). 캐시가 없거나 오래됐으면 받아 오고, 실패하면 캐시를 그대로 쓴다.
    /// 어느 연도든 데이터가 전혀 없으면 `nil` 을 돌려준다 (공휴일을 모르는 채로 알람을 빼먹지 않도록).
    func holidayDays(for years: [Int], now: Date = .now) async -> Set<Int>? {
        guard isAvailable else { return nil }
        for year in years where cache.needsRefresh(year: year, now: now) {
            await refresh(year: year, now: now)
        }
        var result = Set<Int>()
        for year in years {
            guard let entry = cache.years[year] else { return nil }
            result.formUnion(entry.holidays.map(\.day))
        }
        return result
    }

    private func refresh(year: Int, now: Date) async {
        guard let apiKey else { return }
        do {
            let (data, response) = try await session.data(from: Self.requestURL(apiKey: apiKey, year: year))
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                Self.logger.error("공휴일 \(year) 요청 실패: HTTP \(http.statusCode)")
                return
            }
            let holidays = try HolidayResponseParser.parse(data)
            cache.years[year] = .init(holidays: holidays, fetchedAt: now)
            persist()
            Self.logger.info("공휴일 \(year): \(holidays.count)일")
        } catch {
            Self.logger.error("공휴일 \(year) 요청 실패: \(error.localizedDescription)")
        }
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(cache), forKey: cacheKey)
    }

    /// 요청 URL. 키는 보통 URL 인코딩된 상태(%2F, %3D …)로 발급되므로 한 번 디코드한 뒤 직접 인코딩한다.
    /// `URLComponents.queryItems` 는 `+` 를 인코딩하지 않아 서버가 공백으로 읽기 때문에 쓰지 않는다.
    nonisolated static func requestURL(apiKey: String, year: Int) -> URL {
        let rawKey = apiKey.removingPercentEncoding ?? apiKey
        let query = [
            ("serviceKey", rawKey),
            ("solYear", String(year)),
            ("numOfRows", "100"),
            ("pageNo", "1"),
            ("_type", "json"),
        ]
        .map { "\($0.0)=\(strictlyEncoded($0.1))" }
        .joined(separator: "&")
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = query
        return components.url!
    }

    private nonisolated static func strictlyEncoded(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// Info.plist 의 `HolidayAPIKey`. 비어 있거나 빌드 변수가 치환되지 않았으면 `nil`.
    nonisolated static func bundledAPIKey(bundle: Bundle = .main) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: "HolidayAPIKey") as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
        return trimmed
    }
}
