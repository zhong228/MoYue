import Foundation
import Combine

// MARK: - RSSFetcher

class RSSFetcher: ObservableObject {
    @Published var items: [RSSItem] = []
    @Published var isLoading: Bool = false
    @Published var error: String? = nil

    @MainActor
    func fetchItems(from source: RSSSource) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        guard let url = URL(string: source.url) else {
            error = "Invalid URL"
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let parser = RSSXMLParser(sourceId: source.id)
            items = parser.parse(data: data)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - RSSXMLParser

private class RSSXMLParser: NSObject, XMLParserDelegate {
    private let sourceId: String
    private var parsedItems: [RSSItem] = []

    // Feed type detection
    private var isAtom = false

    // Current element tracking
    private var currentElement = ""
    private var currentItem: [String: String] = [:]
    private var insideItem = false
    private var characterBuffer = ""

    // Atom link href captured via attributes
    private var currentLinkHref: String?

    private let dateFormatters: [DateFormatter] = {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        ]
        return formats.map { fmt in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = fmt
            return f
        }
    }()

    init(sourceId: String) {
        self.sourceId = sourceId
    }

    func parse(data: Data) -> [RSSItem] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return parsedItems
    }

    // MARK: XMLParserDelegate

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        characterBuffer = ""

        switch elementName {
        case "feed":
            isAtom = true
        case "item", "entry":
            insideItem = true
            currentItem = [:]
            currentLinkHref = nil
        case "link":
            if isAtom {
                // Atom <link href="..."/> is self-closing; capture href now
                currentLinkHref = attributeDict["href"]
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        characterBuffer += string
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        let text = characterBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        if insideItem {
            switch elementName {
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
            case "description", "summary", "content":
                if currentItem["description"] == nil || !text.isEmpty {
                    currentItem["description"] = text
                }
            case "pubDate", "published", "updated":
                if currentItem["pubDate"] == nil {
                    currentItem["pubDate"] = text
                }
            case "author", "dc:creator":
                currentItem["author"] = text
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
        }

        characterBuffer = ""
        currentElement = ""
    }

    // MARK: - Helpers

    private func buildItem() -> RSSItem? {
        guard let title = currentItem["title"], !title.isEmpty,
              let link = currentItem["link"], !link.isEmpty
        else { return nil }

        let pubDate: Date? = currentItem["pubDate"].flatMap { parseDate($0) }

        return RSSItem(
            title: title,
            link: link,
            pubDate: pubDate,
            description: currentItem["description"] ?? "",
            author: currentItem["author"],
            sourceId: sourceId
        )
    }

    private func parseDate(_ string: String) -> Date? {
        for formatter in dateFormatters {
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }
}
