import Foundation
import Combine

// MARK: - RSSFetcher

@MainActor
final class RSSFetcher: ObservableObject {
    @Published var items: [RSSItem] = []
    @Published var isLoading: Bool = false
    @Published var error: String? = nil

    func fetchItems(from source: RSSSource) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        guard let url = URL(string: source.url) else {
            error = localized("RSS URL 無效")
            return
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse,
               !(200...299).contains(http.statusCode) {
                error = String(format: localized("RSS 請求失敗：HTTP %@"), "\(http.statusCode)")
                return
            }

            let parser = RSSXMLParser(sourceId: source.id)
            let parsedItems = parser.parse(data: data)

            if let parserError = parser.error {
                error = parserError
                items = []
                return
            }

            items = parsedItems

            if parsedItems.isEmpty {
                error = localized("RSS 解析成功，但沒有找到文章。")
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - RSSXMLParser

private final class RSSXMLParser: NSObject, XMLParserDelegate {
    private let sourceId: String
    private var parsedItems: [RSSItem] = []

    private var isAtom = false
    private var insideItem = false
    private var currentItem: [String: String] = [:]
    private var characterBuffer = ""
    private var currentLinkHref: String?

    private(set) var error: String?

    private let dateFormatters: [DateFormatter] = {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEE, d MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm:ss zzz",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        ]

        return formats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            return formatter
        }
    }()

    init(sourceId: String) {
        self.sourceId = sourceId
    }

    func parse(data: Data) -> [RSSItem] {
        let parser = XMLParser(data: data)
        parser.delegate = self

        let success = parser.parse()

        if !success {
            error = parser.parserError?.localizedDescription ?? localized("RSS XML 解析失敗。")
        }

        return parsedItems
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = elementName.lowercased()
        characterBuffer = ""

        switch name {
        case "feed":
            isAtom = true

        case "item", "entry":
            insideItem = true
            currentItem = [:]
            currentLinkHref = nil

        case "link":
            if isAtom {
                let rel = attributeDict["rel"] ?? "alternate"

                if rel == "alternate" || rel.isEmpty {
                    currentLinkHref = attributeDict["href"]
                }
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        characterBuffer += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let string = String(data: CDATABlock, encoding: .utf8) {
            characterBuffer += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.lowercased()
        let text = characterBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        guard insideItem else {
            characterBuffer = ""
            return
        }

        switch name {
        case "title":
            currentItem["title"] = text

        case "link":
            if isAtom {
                if let href = currentLinkHref, !href.isEmpty {
                    currentItem["link"] = href
                }
            } else {
                currentItem["link"] = text
            }

        case "description", "summary", "content", "content:encoded":
            if !text.isEmpty {
                currentItem["description"] = text
            }

        case "pubdate", "published", "updated":
            if !text.isEmpty, currentItem["pubDate"] == nil {
                currentItem["pubDate"] = text
            }

        case "author", "dc:creator":
            if !text.isEmpty {
                currentItem["author"] = text
            }

        case "item", "entry":
            if let item = buildItem() {
                parsedItems.append(item)
            }

            insideItem = false
            currentItem = [:]
            currentLinkHref = nil

        default:
            break
        }

        characterBuffer = ""
    }

    private func buildItem() -> RSSItem? {
        guard let title = currentItem["title"], !title.isEmpty,
              let link = currentItem["link"], !link.isEmpty
        else {
            return nil
        }

        return RSSItem(
            title: title,
            link: link,
            pubDate: currentItem["pubDate"].flatMap { parseDate($0) },
            description: currentItem["description"] ?? "",
            author: currentItem["author"],
            sourceId: sourceId
        )
    }

    private func parseDate(_ string: String) -> Date? {
        for formatter in dateFormatters {
            if let date = formatter.date(from: string) {
                return date
            }
        }

        return nil
    }
}
