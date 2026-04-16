# scripts/ — 書源解析 Diff 工具

這裡的工具讓你對比 **Android Legado（原版）** 和 **iOS yuedu app（移植版）** 的書源解析管道輸出，找到第一個分歧點。

---

## 快速開始（3 步驟）

### 步驟 1 — 啟動 Android Legado，捕獲日誌

```bash
# 在 Android Studio 裡啟動 AVD，安裝 Legado APK，然後：
./scripts/capture_legado_log.sh scripts/logs/legado_raw.txt
```

腳本會自動過濾 logcat，只保留 `AppLog`、`AnalyzeRule`、`BookSourceDebug` 三個 tag。  
在 Legado App 裡打開書源管理 → 偵錯 → 執行搜尋，然後按 Ctrl+C 停止捕獲。

### 步驟 2 — 跑 iOS 管道日誌

在 Xcode 裡，透過書源調試頁面（書源管理 → 偵錯）執行相同操作，然後呼叫：

```swift
let url = debugEngine.exportLogsAsText()
print(url)   // 複製路徑
```

或直接跑 XCTest：

```bash
xcodebuild test \
  -project "yuedu app.xcodeproj" \
  -scheme "yuedu app" \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:"yuedu appTests/LegadoAlignmentTests/LegadoAlignmentExportTests"
# 輸出路徑在 Console 裡（/tmp/yuedu_all_fixtures.txt）
```

### 步驟 3 — 對比兩份日誌

```bash
# 快速終端對比（彩色輸出）
python3 scripts/compare_logs.py \
  --android scripts/logs/legado_raw.txt \
  --ios     /tmp/yuedu_all_fixtures.txt

# 輸出 HTML 報告（方便分享）
python3 scripts/compare_logs.py \
  --android scripts/logs/legado_raw.txt \
  --ios     /tmp/yuedu_all_fixtures.txt \
  --out     scripts/logs/report_$(date +%Y%m%d).html
open scripts/logs/report_*.html
```

---

## 工具說明

| 檔案 | 功能 |
|------|------|
| `capture_legado_log.sh` | adb logcat 捕獲腳本，自動過濾 Legado 相關 tag |
| `normalize_log.py` | 將 Android / iOS 日誌正規化為統一格式（`STEP: value`）|
| `compare_logs.py` | Diff 兩份正規化日誌，輸出終端彩色報告或 HTML |
| `logs/` | 日誌存放目錄（已加入 .gitignore）|

---

## 新增 XCTest Fixture（收到 Legado 日誌後）

1. 在 Legado 偵錯頁找到某個書源的解析結果（例如書名 `三體`）。  
2. 打開 `yuedu appTests/LegadoAlignmentTests.swift`。  
3. 在 `fixtures` 陣列中新增一個：

```swift
Fixture(
    "起點: 搜索結果書名",
    html: "<從 Legado Log 貼上原始 HTML>",
    rule: "div.bookName@text",           // 書源 JSON 裡的規則
    expected: "三體"                      // Legado 輸出的結果
),
```

4. 跑測試，看 ✅ 還是 ❌。

---

## 常見分歧點

| 症狀 | 可能原因 | 修復位置 |
|------|---------|----------|
| iOS 結果為空，Android 有值 | 選擇器推斷不同（XPath / CSS 混淆）| `SourceRule.detectMode()` |
| 有噪音字串殘留 | `##` 正則替換沒跑完 | `ModernRuleEngine.replaceRegex()` |
| JS 解析返回 `undefined` | `java.*` API 未實作 | `LegadoJSBridge.swift` |
| URL 拼接錯誤 | `@put`/`@get` 變數生命週期 | `BookSourceRuleData` |
| 亂碼 | GBK 編碼沒處理 | `WebFetcher` encoding detection |
