import Foundation
import Testing
@testable import Ringee

struct RingeeTests {
    @Test func metadataIsCodable() throws {
        let data = try JSONEncoder().encode(RingeeAlarmMetadata())
        _ = try JSONDecoder().decode(RingeeAlarmMetadata.self, from: data)
    }
}
