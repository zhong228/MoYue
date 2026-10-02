---
title: S001 第 2 次嘗試證據
updated: 2026-10-01
---

# S001 — 獨立深色配色 media 的能力判斷

**判定：ESCALATE_HUMAN。候選保留在兩個 loop 工作副本，不 commit；未 push、未發版、未改量法。**

## 開工與範圍

- 主目錄 GOAL／LOOP／STATE 已讀；本輪只做佇列首位 S001。
- Reader 基底：`df002297f160b16b46c4bae34dbd47ef55247d34`；package 基底：`d7e16bd9aa64b80c4d0bc70fa0fc069409c34ea7`。
- PAUSE 不存在；oracle lock 7 檔／2 trees 通過；兩副本乾淨，磁碟 143GB。
- 使用者明確同意排除純 `xcodebuild -downloadPlatform iOS -buildVersion 26.5` 下載程序於等待條件；其他編譯／測試仍串行等待。排除只在 `/tmp/fidelity-exclude-runtime-downloads.sh`，不修改凍結腳本。
- 第二台模擬器：`C01C0272-859E-4465-BCEB-53C054C686BE`（iOS 27.0）；工作區 `~/Desktop/Yuedu-fidelity-loop/Loop.xcworkspace`，不另設 DerivedData。
- 基底先跑 85 tests／16 suites，全過；斷行基線 458 章、跳過 0，log `/tmp/S001-attempt2-base.log`。

## 根因與規則

修改前並排圖：舊引擎的標題與圖片貼到兩側；WebKit 有 body 留白，內文換行也不同。來源 `AI术语词典-第一册.epub` 的 `OEBPS/styles/book.css`：`body { font-size: 1em; padding: 1.1em 1.3em 2.4em }`。對照 dump 的字級 17px，左右 padding 是 `17 × 1.3 = 22.1px`；366px viewport 的內容寬度是 `366 - 2 × 22.1 = 321.8px`。

[Media Queries 5 §12.5](https://www.w3.org/TR/mediaqueries-5/#prefers-color-scheme) 的 dark preference query 在 light palette 不成立。既有 `CSSParser` 已把深色規則標成 `isDarkMedia`；`CurrentCSSFrontend` 既有 light cascade 會排除它們。最早偏離的層是能力掃描器把任何 `@media` 拒絕，整章改走 Legacy。

本輪讓能力判斷沿用同一個 at-rule 邊界，只放行獨立 `(prefers-color-scheme: dark)` 的配色宣告。其他查詢、合併條件、巢狀條件、版面宣告與自訂變數仍拒絕。沒有新增 media 求值模式、書名／class 特判、fallback、重試或延遲。

## 合成測試與回歸

新增兩個測試：外部與行內深色配色的 admission／light cascade／盒模型，以及不支援查詢與版面宣告的拒絕邊界。期望值來自規格：300px 寬度扣左右 10px padding 與 2px border 得 276px；20px 字級與 1.5 行高得 30px。

只加測試、套件仍在基底時：31 tests／1 suite；只有兩個新方法失敗（3 個 supported 斷言），原有 29 個全過。log `/tmp/S001-attempt2-red.log`。最後程式碼修改後：87 tests／16 suites 全過、跳過 0；斷行基線覆蓋 458 章且未改。log `/tmp/S001-attempt2-regression.log`。

| 類別 | 通過測試數 |
|---|---:|
| `BrowserAutoSupportedSubsetCorrectnessGateTests` | 4 |
| `BrowserLayoutCapabilityScannerTests` | 31 |
| `BrowserLayoutDeterminismTests` | 4 |
| `BrowserLayoutFeatureTests` | 1 |
| `CSSLengthResolverTests` | 2 |
| `ComputedStyleTests` | 2 |
| `ComputedStyleTreeTests` | 1 |
| `BlockLayoutTests` | 8 |
| `CoreTextLineBreakerTests` | 4 |
| `InlineLayoutTests` | 2 |
| `PageFragmentationTests` | 1 |
| `BrowserLayoutDocumentTests` | 4 |
| `DisplayListTests` | 1 |
| `BrowserLayoutLineBreakBaselineTests` | 1 |
| `BrowserLayoutPageEngineTests` | 17 |
| `EPUBAutoRoutingTests` | 4 |

Gate：`GATE: PASS (3 files)`；兩個 repo 的 `git diff --check` 通過。

## 實作方量測（部分比較，尚非驗證判定）

對照組 `ios27.0-32c823fa58959671`；scorer v1。`S001-attempt2-before` 僅代表 spine 1／3／8；`S001-attempt2-after` 僅全書 dev 10 章。兩個 run 都沒有 engine failed、unmeasured、skipped 或 reference caveats。

| 範圍 | Before run／分數 | After run／分數 | 比較 |
|---|---|---|---|
| ai-glossary dev 10 章 | `baseline-2026-09-30`：72.0 | `S001-attempt2-after`：97.3 | partial PASS；Browser 0→10 |
| 共同代表章節 3／8 | `S001-attempt2-before`：77.1 | `S001-attempt2-after`：96.4 | partial PASS；Browser 0→2 |

| Spine | Before total | After total | Before line-break loss | After line-break loss |
|---|---:|---:|---:|---:|
| 3 | 77.3425 | 97.5883 | 11.0322 | 0.6301 |
| 8 | 76.8770 | 95.2895 | 10.1938 | 1.0586 |

修改後並排圖可見 body 留白與內文換行改善；標題、漸層與圖片圓角仍有差異，沒有另改這些規則。

## 獨立驗證與收尾

驗證者 `/root/fidelity_verifier_attempt2`（`fidelity-verifier` role，獨立脈絡）判定 **ESCALATE_HUMAN**。以下為它自己執行的證據：

- Oracle lock 7 檔／2 trees 通過；MAIN 凍結路徑 Git status 空白。
- Gate：PASS 3 檔，沒有 note；完整 diff 沒有特判、fallback、削弱既有斷言或錄製基線變動。
- 必跑組逐類執行（每類獨立 invocation），86 tests／15 suites 全過、跳過 0；逐類計數與上表相同（不含最後的斷行基線）。logs `/tmp/S001-attempt2-verify-<類別>.log`。
- 繁中斷行基線獨立通過：1 test／1 suite，458 章、跳過 0；相對 Reader base 的基線檔 diff 空白。log `/tmp/S001-attempt2-verify-linebreak.log`。合計 87 tests／16 suites。
- 從 MAIN 執行凍結量法對 LOOP 的唯一完整 run：`S001-attempt2-verify`，16 本／249 章，engine failed 0、unmeasured 0、skipped 0；對照組 `ios27.0-32c823fa58959671`、scorer v1，loop 本地套件。
- `compare --full --base baseline-2026-09-30`：**COMPARE: PASS (249 of 249 chapters)**。ai-glossary 的 media-queries 回退從 16 章消失，沒有一章分數下降；其他可比較 Browser 章節 Δ 都是 0.0。
- 新引擎覆蓋 177→193；Legacy 72→56。

### 升級原因與並排檢查範圍

驗證者打開 `index.html` 並讀它列出的實際 tile，檢視 ai-glossary:1、:3 的 WebKit／基線／候選。第 1 章的欄寬、列表分隔線與內距更接近 WebKit；第 3 章則有可見退步：WebKit 與基線的章標題都是兩行，候選變成三行，末行只剩「型”」，插圖因此向下移。

- [候選第 3 章圖](/Users/zhangruilin/Library/Caches/YueduFidelity/runs/S001-attempt2-verify/ai-glossary/3/tile-000.jpg)
- [WebKit 第 3 章圖](/Users/zhangruilin/Library/Caches/YueduFidelity/ref/ios27.0-32c823fa58959671/ai-glossary/3/tile-000.jpg)
- [接受基線第 3 章圖](/Users/zhangruilin/Library/Caches/YueduFidelity/runs/baseline-2026-09-30/ai-glossary/3/tile-000.jpg)

依 [fidelity-verify SKILL.md](/Users/zhangruilin/Desktop/Yuedu-fidelity-loop/Yuedu-reader/.agents/skills/fidelity-verify/SKILL.md) 的「score improves but the side-by-side looks worse」條件，需 **ESCALATE_HUMAN**。依第一項失敗即停止，未繼續檢視 ai-glossary:8，以及驗證者自行選的 quanzhi:418、hail-mary:40；不能宣稱完整並排圖關卡通過。

插圖圓角是仍與 WebKit 不同的既有差異；驗證者已更正，沒有把它當作候選新增退步。標題斷行的程式根因尚未釐清，本輪未追加其他規則。

### 完整量測分數

下表是全部章節的原始書分數；正式門檻由比較器判定，不自行重算。兩次皆走 Legacy 的 56 章由既有比較器排除，最大原始章節漂移 3.7；因此其他書原始總分有少量漂移，不能當成此規則改善或退步。正式比較的全部表另存 [full compare](S001-attempt2-compare-baseline-2026-09-30.md)，完整數字報告見 [verify report](S001-attempt2-verify.md)。

| 書 | baseline-2026-09-30 | S001-attempt2-verify | dev 前→後 | holdout 前→後 | Browser 前→後 |
|---|---:|---:|---:|---:|---:|

| ai-glossary | 75.2 | 97.4 | 72.0→97.3 | 80.4→97.4 | 0→16 |
| game-designer | 96.7 | 96.6 | 95.8→95.7 | 98.7→98.7 | 18→18 |
| georgia | 58.3 | 58.3 | 58.3→58.3 | —→— | 0→0 |
| guimi | 94.5 | 94.5 | 93.4→93.4 | 97.0→97.0 | 21→21 |
| hail-mary | 98.8 | 98.8 | 98.3→98.3 | 99.8→99.8 | 17→17 |
| harry-potter | 88.9 | 88.9 | 90.6→90.6 | 86.2→86.2 | 4→4 |
| hongwu | 88.3 | 88.3 | 85.8→85.9 | 92.5→92.5 | 14→14 |
| israelsailing | 93.8 | 93.8 | 92.9→92.9 | 98.5→98.5 | 12→12 |
| kusamakura | 65.3 | 65.0 | 64.0→63.7 | 67.7→67.7 | 13→13 |
| mahabharata | 78.5 | 78.5 | 79.8→79.8 | 76.4→76.4 | 16→16 |
| orv | 86.7 | 86.7 | 87.6→87.6 | 84.6→84.6 | 5→5 |
| quanzhi | 96.8 | 96.8 | 96.0→96.0 | 98.4→98.4 | 18→18 |
| redchamber | 91.1 | 91.1 | 89.8→89.8 | 93.6→93.6 | 18→18 |
| redchamber-vertical | 76.6 | 76.5 | 77.5→77.6 | 74.9→74.6 | 2→2 |
| sherlock | 96.4 | 96.4 | 96.8→96.8 | 95.8→95.8 | 16→16 |
| the-deal | 86.7 | 86.7 | 85.4→85.4 | 88.8→88.8 | 3→3 |

### Reference caveats（沿用）

| Book | Chapters | Caveat |
|---|---:|---|
| harry-potter | 8 | fonts still loading when the reference was measured |

### 收尾與待人決定

未 commit；兩副本保留本輪 3 檔候選，分支仍為原 `loop/fidelity` 基底。主 STATE 的最後接受 run 與記分板維持 `baseline-2026-09-30`；S001 移到「等你決定」，沒有做 S002。

1. **先另案釐清並修好章標題退步，再重試 S001（推薦）**：讓分數改善同時保有可見品質。
2. **用編輯撤回候選，等標題排版修正後再重試**：先讓 loop 工作副本回到乾淨狀態。
