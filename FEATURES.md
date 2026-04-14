# 功能對比：yuedu app vs legado-ios

> 基於 2026-04-15 兩個專案的完整代碼掃描

## 已實現功能

| 功能 | yuedu app | legado-ios |
|------|-----------|------------|
| **書源規則引擎** (CSS/XPath/JSON/Regex/JS) | ✅ | ✅ |
| **JS Bridge** (java.ajax/get/put) | ✅ 有沙盒安全限制 | ✅ 完整 |
| **TOC formatJs** | ✅ 已移植 | ✅ |
| **書源管理 UI** (列表/編輯/匯入) | ✅ | ✅ |
| **書源規則調試器** | ✅ 已移植（4段 UI + 彩色日誌）| ✅ |
| **線上閱讀 Pipeline** (含 nextTocUrl 分頁) | ✅ | ✅ |
| **網路層** (重試/自動編碼偵測) | ✅ | ✅ |
| **WebView 抓取** (池化/Cloudflare 偵測) | ✅ | ✅ |
| **持久化 Cookie** (跨重啟) | ✅ 已移植 | ✅ |
| **本地 EPUB** | ✅ Readium | ✅ ZIPFoundation |
| **本地 TXT** (GBK/BIG5/memory-map) | ✅ | ✅ |
| **本地 Markdown** | ✅ | ❌ |
| **CoreText 排版引擎** | ✅ 自製 26 個檔案 | ❌ 用 WebView |
| **翻頁動畫** (滑動/覆蓋/捲曲) | ✅ | ✅ 8 種含物理模擬 |
| **替換規則** (含 UI + 7 條預設規則) | ✅ 已移植 | ✅ |
| **TTS** (系統 TTS + 硬體音量鍵) | ✅ | ✅ |
| **HTTP TTS / 有聲書** | ❌ | ✅ |
| **閱讀進度** (本機持久化) | ✅ | ✅ |
| **多格式搜尋** (多源並行 + 去重) | ✅ | ✅ |
| **書架** (網格/列表/排序) | ✅ | ✅ |

## 尚未移植（legado-ios 有，yuedu app 沒有）

| 功能 | 說明 |
|------|------|
| **雲端同步 (WebDAV)** | 備份/還原，含衝突處理 |
| **RSS 訂閱** | 完整規則解析，含 XPath/CSS/regex 自訂抽取 |
| **漫畫閱讀器** | type=2 書源，長條圖片捲動 |
| **影片播放** | type=3 書源，基本 AVPlayer |
| **閱讀統計** | 日/週/月閱讀時長、字數、書籍排名 |
| **WebServer (LAN)** | Port 1122，局域網訪問書架 |
| **Widget** | 進度小工具 + 書架小工具 |
| **ShareExtension** | 從其他 App 匯入書源/書籍 |
| **Legado 資料遷移** | 從 Android/iOS legado 備份匯入 |
| **書架分組** | 書籍分類管理 |
| **HTTP TTS / 有聲書** | 自訂 TTS 引擎 + 有聲書播放 |

## yuedu app 獨有優勢

| 功能 | 說明 |
|------|------|
| **CoreText 自製排版引擎** | 精確 CJK 排版，legado-ios 完全沒有 |
| **JS 沙盒安全** | 封鎖 XHR/fetch/localStorage/eval，防惡意書源 |
| **SSRF 防護** | 封鎖內網 IP，AppConfig 白名單 |
| **Markdown 支援** | legado-ios 不支援 |
| **記憶體映射 TXT** | 大型 TXT 低記憶體讀取 |
