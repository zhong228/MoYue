# Yuedu Reader

[English](README.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md)

Yuedu Reader 是一個使用 SwiftUI 和 CoreText 建構的 iOS 原生閱讀器，專注於 CJK 長文本閱讀、本地 EPUB/TXT 書庫、網頁內容轉碼、RSS 訂閱、TTS 聽書、WebDAV 同步，以及可細調的閱讀排版。

> 狀態說明：本專案是 CJK-first 閱讀器。中文閱讀、中英/數字混排、長篇小說場景是主要目標。英文 EPUB/TXT 基本可讀，但目前還不是主要驗證路徑。

## 能做什麼

- **原生 CoreText 閱讀器**：支援分頁閱讀和連續捲動，不以 WebView 作為主要閱讀介面。
- **CJK 中文排版**：處理段首縮排、標點、行距、頁邊距、中英混排和直排閱讀。
- **本地書庫**：匯入 EPUB、TXT 和類 Markdown 文字檔，支援解析、快取、封面、書籤、標註和閱讀位置恢復。
- **大體積書籍處理**：已針對長篇 TXT 和 EPUB 閱讀流程驗證，包含數百萬字級內容。
- **線上閱讀流程**：將使用者自行提供的網頁和規則化書源轉換成同一套閱讀器格式。
- **RSS 閱讀**：支援 RSS/Atom feed、規則化擷取、OPML 類工作流和文章渲染。
- **TTS 聽書**：支援本機 `AVSpeechSynthesizer` 和基於 HTTP 的自訂 TTS provider。
- **同步與備份**：以 WebDAV 為核心的備份、恢復、書庫同步和進度同步流程。
- **閱讀器客製化**：字體、字級、行高、段落間距、頁邊距、主題、分頁/捲動模式和直排模式。

## 專案邊界

Yuedu Reader 是閱讀器引擎和應用外殼，不內建、不託管、不推薦、也不散布任何受版權保護的內容來源。

使用者需要自行確保匯入檔案、RSS feed、網站、自訂規則、cookie、帳號和產生內容符合當地法律、版權要求和網站服務條款。

本專案不接受內建盜版源、DRM 繞過、付費牆繞過、私有 token 分享、cookie 擷取或反爬繞過邏輯等貢獻。

## 環境需求

- iOS 18.0+
- Xcode 16+
- Xcode 專案目前使用 Swift 5 language mode

## 快速開始

```bash
git clone https://github.com/CHANG-JUI-LIN/Yuedu-reader.git
cd Yuedu-reader
open Yuedu-Reader.xcodeproj
```

選擇 `Yuedu-Reader` scheme，然後在 iOS 模擬器或真機上建置執行。

也可以使用 app target 的建置腳本：

```bash
./scripts/build.sh
```

等價指令：

```bash
xcodebuild \
  -project "Yuedu-Reader.xcodeproj" \
  -scheme "Yuedu-Reader" \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  build
```

## 專案結構

```text
iOS/
├── Models/               # 資料模型、儲存、服務、渲染器、解析器
│   ├── App/              # 全域設定、設計 token、依賴注入
│   ├── Book/             # 書籍模型、BookStore、書籤、metadata
│   ├── BookSource/       # 使用者自訂來源抓取
│   ├── LocalBook/        # EPUB/TXT/Markdown 匯入
│   ├── Online/           # 線上閱讀與網頁內容轉碼流程
│   ├── RSS/              # RSS 模型、feed 抓取器、解析器、文章工具
│   ├── Reader/CoreText/  # CoreText 分頁、捲動排版、繪製
│   ├── RuleEngine/       # CSS/XPath/Regex/JSON 擷取
│   ├── Sync/             # WebDAV 與同步邏輯
│   └── TTS/              # 語音播放協調
├── Views/                # SwiftUI 畫面和共用 UI
│   ├── Reader/           # 閱讀器介面、控制列、設定、覆蓋層
│   ├── Bookshelf/        # 首頁書架與書籍管理
│   ├── BookSource/       # 書源管理與診斷
│   ├── Online/           # 瀏覽器/匯入流程
│   ├── RSS/              # RSS 訂閱與文章畫面
│   └── Settings/         # App 設定、個人資料、同步、TTS、遷移
├── ViewModels/           # ObservableObject ViewModel
├── Assets/               # Asset catalog 和規則引擎資源
└── *.lproj/              # 在地化：zh-Hant、zh-Hans、en

ShareExtension/           # iOS 分享擴充
Widget/                   # 主畫面 widget
Tests/                    # Unit test 和 UI test targets
Technotes/                # 架構筆記
scripts/                  # 本機自動化腳本
xcconfig/                 # 共用 Xcode 設定
```

## 架構筆記

- **EPUB**：使用 Readium 元件處理 EPUB package 解析與資源存取。
- **渲染**：`EPUBPageRenderer` 依閱讀模式分派到 `CoreTextPageEngine` 或 `CoreTextScrollEngine`。`CoreTextPageView` 和 chunk cell 負責繪製最終 CoreText frame。
- **閱讀位置**：穩定位置使用 `(spineIndex, charOffset)`，不使用頁碼，因為章節載入或版面變更後 page index 可能位移。
- **線上內容**：`BookSourceFetcher`、`OnlineReadingPipeline`、`ModernRuleEngine` 和 web fetcher 會把使用者提供的來源轉成標準化章節內容。
- **RSS**：feed XML 解析和規則化文章擷取，沿用和線上閱讀一致的清理與閱讀器渲染原則。
- **TTS**：播放狀態獨立於渲染層協調，讓閱讀器高亮和系統媒體控制能跟隨目前朗讀段落。
- **依賴注入**：透過 `AppDependencies` 和 SwiftUI environment 提供 app services；需要持久化或快取所有權的 manager 會集中管理。

更多細節見 [Technotes/Architecture.md](Technotes/Architecture.md)。

## 開發規則

- 使用 `localized()` 處理使用者可見文字，並同步更新三個在地化檔案：
  - `iOS/zh-Hant.lproj/Localizable.strings`
  - `iOS/zh-Hans.lproj/Localizable.strings`
  - `iOS/en.lproj/Localizable.strings`
- 閱讀位置要使用穩定內容座標，不要使用會變動的 page index。
- 優先使用 `Models/App/DesignTokens.swift` 內既有 design tokens。
- 書源和規則引擎相關工作必須限定在合法、使用者自行提供內容的流程。

貢獻規範見 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 授權

MIT。見 [LICENSE](LICENSE)。

本專案連結了 [Readium](https://github.com/readium) 元件，Readium 元件使用 BSD 授權。Readium 名稱和標誌是 Readium Foundation 的商標。
