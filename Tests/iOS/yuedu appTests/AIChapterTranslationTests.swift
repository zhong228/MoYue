import Combine
import Foundation
import Testing
@testable import yuedu_app

@Suite("AI chapter translation", .serialized)
struct AIChapterTranslationTests {

    private let chapter = "第一段。\n第二段。\n第三段。\n第二段。\n第五段。"

    private func raw(_ json: String) -> LLMRawResponse {
        .init(content: json, provider: "fake", model: "fake", finishReason: "stop")
    }

    @Test("what is on screen is translated first, then the rest; repeated text once")
    func pendingOrder() {
        let reading = (chapter as NSString).range(of: "第三段").location + 1
        let pending = AIChapterTranslation.pending(in: chapter, readingOffset: reading) { $0 == "第五段。" }
        #expect(pending.map(\.key) == ["第三段。", "第二段。", "第一段。"])
        #expect(AIChapterTranslation.pending(in: chapter, readingOffset: 0) { _ in true }.isEmpty)
    }

    @Test("batches stay within the character and paragraph limits; a long paragraph goes alone")
    func batching() {
        func paragraphs(_ lengths: [Int]) -> [AIChapterTranslation.Paragraph] {
            ReaderTranslationText.paragraphs(in: lengths.map { String(repeating: "字", count: $0) }.joined(separator: "\n"))
        }
        #expect(AIChapterTranslation.batches(paragraphs(Array(repeating: 100, count: 30))).map(\.count) == [20, 10])
        #expect(AIChapterTranslation.batches(paragraphs(Array(repeating: 5, count: 90))).map(\.count) == [40, 40, 10])
        #expect(AIChapterTranslation.batches(paragraphs([10, 5_000, 10])).map(\.count) == [1, 1, 1])
    }

    @Test("the request numbers paragraphs and names the book and the language")
    func requestContents() throws {
        let batch = ReaderTranslationText.paragraphs(in: "Call me Ishmael.\nSome years ago.")
        let request = try AIChapterTranslation.request(batch, bookTitle: "Moby-Dick", language: .traditionalChinese)
        #expect(request.messages[0].content.contains("翻譯成繁體中文"))
        #expect(request.messages[1].content == "{\"book\":\"Moby-Dick\",\"paragraphs\":[{\"id\":\"p1\",\"text\":\"Call me Ishmael.\"},{\"id\":\"p2\",\"text\":\"Some years ago.\"}]}")
    }

    @Test("every paragraph must come back exactly once, with text")
    func strictParsing() throws {
        let batch = ReaderTranslationText.paragraphs(in: "Call me Ishmael.\nSome years ago.")
        let parsed = try AIChapterTranslation.parse(raw("```json\n{\"translations\":[{\"id\":\"p2\",\"text\":\"幾年前。\"},{\"id\":\"p1\",\"text\":\"叫我以實瑪利。\"}]}\n```"), batch: batch)
        #expect(parsed == ["Call me Ishmael.": "叫我以實瑪利。", "Some years ago.": "幾年前。"])
        for answer in [
            "{\"translations\":[{\"id\":\"p1\",\"text\":\"叫我以實瑪利。\"}]}",
            "{\"translations\":[{\"id\":\"p1\",\"text\":\"甲\"},{\"id\":\"p1\",\"text\":\"乙\"}]}",
            "{\"translations\":[{\"id\":\"p1\",\"text\":\"甲\"},{\"id\":\"p9\",\"text\":\"乙\"}]}",
            "{\"translations\":[{\"id\":\"p1\",\"text\":\" \"},{\"id\":\"p2\",\"text\":\"乙\"}]}",
            "譯文：叫我以實瑪利。",
        ] {
            #expect(throws: LLMError.invalidSchema) { try AIChapterTranslation.parse(raw(answer), batch: batch) }
        }
    }

    @Test @MainActor func runTranslatesKeepsAndNeverAsksTwice() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = TranslationProvider()
        let service = AIChapterTranslationService(store: AIChapterTranslationStore(directory: directory), provider: provider, origin: .testFixture)
        let book = UUID()
        let key = AIChapterTranslationService.Chapter(book: book, spine: 3, language: .english)
        var updates: [AIChapterTranslationService.Chapter] = []
        let subscription = service.updates.sink { updates.append($0) }
        defer { subscription.cancel() }

        service.translate(key, text: chapter, readingOffset: 0, bookTitle: nil)
        await service.wait(book: book)
        #expect(service.runs[key] == .finished)
        #expect(updates == [key])
        #expect(service.translation(book: book, language: .english, paragraph: "第三段。") == "T:第三段。")
        #expect(await provider.calls == 1)

        // Stored: a fresh service reads it back, and asks for nothing.
        let reopened = AIChapterTranslationService(store: AIChapterTranslationStore(directory: directory), provider: provider, origin: .testFixture)
        #expect(reopened.translation(book: book, language: .english, paragraph: "第一段。") == "T:第一段。")
        reopened.translate(key, text: chapter, readingOffset: 0, bookTitle: nil)
        #expect(reopened.runs[key] == .finished)
        #expect(await provider.calls == 1)

        try await reopened.clear(book: book)
        #expect(reopened.translation(book: book, language: .english, paragraph: "第一段。") == nil)
    }

    /// Translates every paragraph to "T:" + its text, counting requests.
    private actor TranslationProvider: LLMProviding {
        let identifier = "translation-fixture"
        let defaultModel = "fixture"
        private(set) var calls = 0

        func generate(_ request: LLMGenerationRequest, model: String?) async throws -> LLMRawResponse {
            calls += 1
            let data = try #require(request.messages.last?.content.data(using: .utf8))
            let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let items = (payload?["paragraphs"] as? [[String: String]]) ?? []
            let translations = items.map { ["id": $0["id"] ?? "", "text": "T:" + ($0["text"] ?? "")] }
            let json = try JSONSerialization.data(withJSONObject: ["translations": translations])
            return .init(content: String(decoding: json, as: UTF8.self), provider: identifier, model: defaultModel, finishReason: "stop")
        }

        nonisolated func stream(_ request: LLMGenerationRequest, model: String?) -> AsyncThrowingStream<String, Error> {
            AsyncThrowingStream { $0.finish() }
        }
    }
}
