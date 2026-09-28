import Foundation
import Testing
@testable import CallLibrary

@Test func updatesNeedBothAnHTTPSFeedAndAKey() {
    let key = "pfIShU4dEXqPd5ObYNfDBiQWcXozk7estwzTnF9BamQ="
    #expect(UpdateConfiguration(infoDictionary: ["SUFeedURL": "https://example.org/appcast.xml", "SUPublicEDKey": key]).isComplete)
    #expect(!UpdateConfiguration(infoDictionary: ["SUFeedURL": "https://example.org/appcast.xml", "SUPublicEDKey": ""]).isComplete)
    #expect(!UpdateConfiguration(infoDictionary: ["SUFeedURL": "", "SUPublicEDKey": key]).isComplete)
    #expect(!UpdateConfiguration(infoDictionary: ["SUFeedURL": "http://example.org/appcast.xml", "SUPublicEDKey": key]).isComplete)
    #expect(!UpdateConfiguration(infoDictionary: [:]).isComplete)
}
