import Foundation
import ActivityKit

struct LyricsAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        var line: String
        var nextLine: String
        var track: String
        var artist: String
    }

    var service: String
}
