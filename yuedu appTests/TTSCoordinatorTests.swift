import Testing
import Foundation
@testable import yuedu_app

struct TTSCoordinatorTests {

    // MARK: - HTTPTTSEngine.buildURL

    @Test func buildURL_replacesAllPlaceholders() {
        let engine = HTTPTTSEngine()
        let template = "https://tts.example.com/api?text={{text}}&title={{title}}&speed={{speakSpeed}}"
        let url = engine.buildURL(template: template, text: "你好世界", title: "第一章", rate: 0.5)
        #expect(url != nil)
        let str = url!.absoluteString
        #expect(str.contains("%E4%BD%A0%E5%A5%BD%E4%B8%96%E7%95%8C"))  // "你好世界" URL-encoded
        #expect(str.contains("%E7%AC%AC%E4%B8%80%E7%AB%A0"))            // "第一章" URL-encoded
        #expect(str.contains("0.50"))                                    // rate formatted
    }

    @Test func buildURL_emptyTemplate_returnsNil() {
        let engine = HTTPTTSEngine()
        let url = engine.buildURL(template: "", text: "test", title: "", rate: 0.5)
        #expect(url == nil)
    }

    @Test func buildURL_noPlaceholders_returnsBaseURL() {
        let engine = HTTPTTSEngine()
        let template = "https://tts.example.com/static.mp3"
        let url = engine.buildURL(template: template, text: "anything", title: "", rate: 0.5)
        #expect(url?.absoluteString == template)
    }

    // MARK: - TTSEngineType

    @Test func ttsEngineType_rawValues() {
        #expect(GlobalSettings.TTSEngineType(rawValue: "system") == .system)
        #expect(GlobalSettings.TTSEngineType(rawValue: "http") == .http)
        #expect(GlobalSettings.TTSEngineType(rawValue: "unknown") == nil)
    }

    @Test func ttsEngineType_displayName() {
        #expect(GlobalSettings.TTSEngineType.system.displayName == "系統語音")
        #expect(GlobalSettings.TTSEngineType.http.displayName == "HTTP TTS")
    }
}
