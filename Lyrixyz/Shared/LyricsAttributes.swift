import Foundation
import ActivityKit

struct LyricsAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var line: String
        var nextLine: String
        var track: String
        var artist: String
    }

    var service: String
}
