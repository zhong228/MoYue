import Foundation

/// TTS 引擎的統一介面。
/// TTSCoordinator 透過此 protocol 與底層引擎溝通，不感知具體實作。
protocol TTSPlayable: AnyObject {
    var isPlaying: Bool { get }
    /// 朗讀完當前段落後，呼叫此 closure 取得下一段文字。回傳 nil 表示結束。
    var onPageFinished: (() -> String?)? { get set }
    var onStop: (() -> Void)? { get set }

    /// 開始朗讀指定文字。rate 範圍與 AVSpeechUtterance 一致（0.0–1.0）。
    func speak(text: String, title: String, rate: Float)
    func pause()
    func resume()
    func stop()
}
