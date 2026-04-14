import Foundation

struct RSSSource: Codable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var url: String
    var customRule: String?
    var sortOrder: Int = 0
    var enabled: Bool = true
}

struct RSSItem: Codable, Identifiable {
    var id: String = UUID().uuidString
    var title: String
    var link: String
    var pubDate: Date?
    var description: String
    var author: String?
    var sourceId: String
}
