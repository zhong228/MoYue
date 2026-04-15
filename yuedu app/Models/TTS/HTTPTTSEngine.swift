import AVFoundation
import Combine
import Foundation

// MARK: - HTTP TTS 引擎（AVPlayer 串流播放）

/// 透過 HTTP URL 取得 TTS 音頻串流，使用 AVPlayer 播放。
/// URL 模板支援佔位符：{{text}}、{{title}}、{{speakSpeed}}
final class HTTPTTSEngine: NSObject, TTSPlayable {

    var isPlaying: Bool = false
    var onPageFinished: (() -> String?)?
    var onStop: (() -> Void)?

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var itemObserver: NSKeyValueObservation?
    private var endObserver: Any?
    private var lastRate: Float = 0.5

    // MARK: - TTSPlayable

    func speak(text: String, title: String, rate: Float) {
        let template = GlobalSettings.shared.httpTtsUrlTemplate
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !template.isEmpty, let url = buildURL(template: template, text: text, title: title, rate: rate) else {
            return
        }

        lastRate = rate
        stopInternal()

        let item = AVPlayerItem(url: url)
        playerItem = item

        // 監聽播放結束
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.handlePlaybackEnded()
        }

        // 監聽載入失敗
        itemObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            DispatchQueue.main.async { self?.stop() }
        }

        if player == nil {
            player = AVPlayer(playerItem: item)
        } else {
            player?.replaceCurrentItem(with: item)
        }

        player?.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func resume() {
        player?.play()
        isPlaying = true
    }

    func stop() {
        stopInternal()
        onStop?()
    }

    // MARK: - Internal helpers

    private func stopInternal() {
        player?.pause()
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
        itemObserver?.invalidate()
        itemObserver = nil
        player?.replaceCurrentItem(with: nil)
        isPlaying = false
    }

    private func handlePlaybackEnded() {
        isPlaying = false
        if let nextText = onPageFinished?(), !nextText.isEmpty {
            speak(text: nextText, title: "", rate: lastRate)
        } else {
            stop()
        }
    }

    /// 將模板佔位符替換為實際值並回傳 URL。
    func buildURL(template: String, text: String, title: String, rate: Float) -> URL? {
        guard !template.isEmpty else { return nil }
        var queryValueCS = CharacterSet.urlQueryAllowed
        queryValueCS.remove(charactersIn: "&+=?#%")
        let encodedText  = text.addingPercentEncoding(withAllowedCharacters: queryValueCS) ?? text
        let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: queryValueCS) ?? title
        let speedStr     = String(format: "%.2f", rate)

        let resolved = template
            .replacingOccurrences(of: "{{text}}",       with: encodedText)
            .replacingOccurrences(of: "{{title}}",      with: encodedTitle)
            .replacingOccurrences(of: "{{speakSpeed}}", with: speedStr)

        return URL(string: resolved)
    }
}
