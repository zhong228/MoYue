# HTTP TTS 設計文件

**日期**：2026-04-15  
**範圍**：在現有系統 TTS 基礎上，加入 HTTP TTS 引擎（串流播放），並提供全域設定頁讓使用者切換引擎與設定 URL 模板。

---

## 背景

現有 `TTSManager` 使用 `AVSpeechSynthesizer`（系統語音），品質受限於 iOS 內建聲音。`HTTPTTSEngine.swift` 已存在但只有 URL 建構骨架，沒有連接 UI 或播放器。本次實作補齊這條路徑。

---

## 架構

```
TTSEngine (protocol)
├── SystemTTSEngine     ← 現有 TTSManager 邏輯，重新包裝符合 protocol
└── HTTPTTSEngine       ← 重寫：AVPlayer 串流播放，符合 protocol

GlobalSettings
└── ttsEngine: TTSEngineType   (.system / .http)
└── httpTtsUrlTemplate: String

TTSSettingsView (新)   ← App 設定頁的子頁面
TTSPanelView (小調整)  ← 頂部顯示目前引擎名稱
ReaderView (小調整)    ← 根據 GlobalSettings 建立對應引擎
```

---

## 元件設計

### 1. `TTSEngine` protocol

```swift
protocol TTSEngine: AnyObject, ObservableObject {
    var isPlaying: Bool { get }
    var onPageFinished: (() -> String?)? { get set }
    var onStop: (() -> Void)? { get set }

    func speak(text: String, title: String)
    func pause()
    func resume()
    func stop()
    func updateRate(_ rate: Float)
}
```

統一介面，讓 `TTSPanelView` / `ReaderView` 不感知底層引擎。

---

### 2. `SystemTTSEngine`

將現有 `TTSManager` 的邏輯提取為符合 `TTSEngine` 的類別。  
`TTSManager` 保留為 `SystemTTSEngine` 的 typealias 或直接重命名，視影響範圍而定。  
**不改變任何現有行為。**

---

### 3. `HTTPTTSEngine`（重寫）

- 接受 URL 模板字串，透過 `buildAudioUrl(template:text:title:speed:)` 建構串流 URL
- 使用 `AVPlayer(url:)` 播放串流音頻（AVPlayer 原生支援 HTTP 串流）
- 監聽 `AVPlayerItem.didPlayToEndTimeNotification`，播完自動呼叫 `onPageFinished`
- 實作 `TTSEngine` protocol
- URL 模板佔位符：`{{text}}`、`{{title}}`、`{{speakSpeed}}`
- 若 `httpTtsUrlTemplate` 為空，`speak()` 直接回傳不播放

**錯誤處理**：
- URL 建構失敗 → 靜默忽略，停止播放
- AVPlayer 載入錯誤（`AVPlayerItem.status == .failed`）→ 停止播放，不 crash

**鎖屏控制面板**：與 `SystemTTSEngine` 相同，透過 `MPNowPlayingInfoCenter` 顯示書名與播放狀態。

---

### 4. `GlobalSettings` 新增欄位

```swift
enum TTSEngineType: String, CaseIterable {
    case system = "system"
    case http   = "http"
}

@AppStorage("ttsEngine") var ttsEngine: TTSEngineType = .system
@AppStorage("httpTtsUrlTemplate") var httpTtsUrlTemplate: String = ""
```

---

### 5. `TTSSettingsView`（新）

放在 App 設定頁（`SettingsView`）作為 `NavigationLink` 子頁。

內容：
- **引擎選擇**：`Picker`，選項「系統語音」/ 「HTTP TTS」
- **URL 模板輸入框**（HTTP TTS 選中時才顯示）：`TextField`，multi-line
- **佔位符說明**：`{{text}}` 段落文字、`{{title}}` 章節標題、`{{speakSpeed}}` 語速（0.1–2.0）
- **測試按鈕**：填入固定測試文字，呼叫引擎播放 3 秒後停止

---

### 6. `TTSPanelView` 調整

頂部新增一行小字顯示目前引擎：「系統語音」或「HTTP TTS」（點擊可跳到 `TTSSettingsView`）。  
其餘 section（語速、定時停止）不變。

語速 slider 對 HTTP TTS 仍有效（透過 `{{speakSpeed}}` 佔位符傳給 URL）。

---

### 7. `ReaderView` 調整

目前 `@StateObject private var tts = TTSManager()`，改為根據 `GlobalSettings.ttsEngine` 建立對應引擎。  
因為 `@StateObject` 不能條件建立，改用 **type-erased wrapper** 或 **直接用 `TTSCoordinator`**：

```swift
@StateObject private var ttsCoordinator = TTSCoordinator()
```

`TTSCoordinator` 內部持有當前 engine（`any TTSEngine`），監聽 `GlobalSettings.ttsEngine` 變化時切換引擎。切換時若正在播放，先 stop 再換。

---

## 資料流

```
使用者點 TTS 按鈕
  → TTSPanelView.play 按鈕
  → TTSCoordinator.speak(text:title:)
  → 轉發給 currentEngine（SystemTTSEngine 或 HTTPTTSEngine）
  → 播放完 → onPageFinished() → ReaderView 取下一頁文字 → 繼續 speak
```

---

## 不在本次範圍

- 書源型有聲書（type=2 書源）
- 多引擎並行 / fallback
- 音量控制（使用系統音量）
- 下載快取（純串流，不快取）
