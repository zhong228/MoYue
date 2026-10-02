---
title: S001 第 3 次 — 章標題字距依賴與重新驗證
updated: 2026-10-01
---

# 本輪結果

**ESCALATE_HUMAN，未 commit，本輪已停止。** 章標題字距修正有效；獨立 186 tests／28 suites、458 章基線、完整 compare 都通過。ai-glossary 全書 75.2→97.7（`baseline-2026-09-30`→`S001-attempt3-verify`），但 spine 15 的有序清單編號消失，因此 S001 admission 尚不能接受。候選 8 檔保留，記分板未替換。[裁決](S001-attempt3-verdict.md)。

# 範圍與授權

使用者在本對話選「1：先修標題退步再重試」。依此續修保留的 S001 候選，先處理作者 letter-spacing，再重新驗證配色 media 的 admission；不做 S002。兩條規則分別記錄，只有獨立驗證 APPROVE 才可 commit。

保留的兩 repo diff 已核對，與上一輪獨立驗證版本完全相同。本輪實際 Reader base `ce21cdfc91a2521a2f024224162f08bb187bc8c6`；package base `d7e16bd9aa64b80c4d0bc70fa0fc069409c34ea7`。Reader 相對上一輪的 `df002297` 只有人已提交的文件／lock 說明變更，詳見下文。PAUSE 不存在、oracle lock 7 檔／2 trees 通過、空間 113GB；SDK 與第二台 iOS 27.0 模擬器相同。續修時保留上輪候選是使用者選項 1 的授權，不是帶入不明改動。相關修改前沿用上輪基底 85 tests／候選 87 tests 證據；修改後將重跑。

# 重現與根因

修改前量測沿用同一份候選的 `S001-attempt2-verify`（16 本／249 章；ai-glossary dev 97.3、holdout 97.4）。已重新打開它的 index 與實際 spine 3 tile；標題在 WebKit 是兩行，在候選是三行，末行只剩「型”」。

來源 `AI术语词典-第一册.epub` 的 `OEBPS/styles/book.css`：h1 font-size 1.8em、letter-spacing -.05em。根字級 17px，標題 30.6px，因此 tracking 應為 -.05 × 30.6 = -1.53px。[CSS Text 3 §7.2](https://www.w3.org/TR/css-text-3/#letter-spacing-property) 定義字距可為負值，繼承的是絕對 computed length，normal 是零；不能在行首或行尾額外增加 tracking。這是 computed style 的缺口：CSSParser 已保存宣告，ComputedStylePropertyApplier 卻未處理 letter-spacing，InlineLayout 只拿 reader config 的字距。

合成測試期望由上述規則推出：final font .1 × 20px = 2px；子元素字級 40px 仍繼承 2px；自己宣告 -.05em 的子元素是 -2px；3pt × 96/72 = 4px；.1rem × 24px root = 2.4px；四個字只有三個 tracking gaps，-2px 應縮短 6px。

第一次測試編譯失敗（少了 app 的測試匯入、誤用不存在的 LayoutLine.width），已修正，不當作紅燈證據。`/tmp/S001-attempt3-title-red2.log`：4 tests／1 suite 全部因作者字距未生效而失敗，共 15 issues。之後把 invalid-value 測試限於兩條規則間的 cascade（不增加同宣告區塊重複 key 的另一個解析問題），精確最終測試的紅燈重跑排在主目錄 corpus 回歸之後，log `/tmp/S001-attempt3-title-red3.log`。

# 實作與驗證

字距修正與實作方回歸／dev 量測已完成，結果如下。獨立驗證者正在重新回歸；既有配色候選與字距修正皆未 commit，完整量測額度本輪僅留獨立驗證者使用一次。


## 實作與本輪測試（續）

- 實際 Reader HEAD 是 `ce21cdfc91a2521a2f024224162f08bb187bc8c6`：人於 18:05:56 在 loop 副本 fast-forward 了 main 的文件 commit。相對原先記錄的 `df002297` 只有 `ORACLE.md` 的 gate-only 版本說明及其 lock 雜湊兩檔；沒有程式碼、測試或分數算法變更。套件基底維持 `d7e16bd9aa64b80c4d0bc70fa0fc069409c34ea7`。開工回歸的程式碼與環境未變，沿用上輪 85 tests 的通過證據。
- Gate 一度使用舊 Reader 基底，因此把人的兩個已提交文件變更列為 ESCALATE；核對 reflog、兩個 commit 的 diff、main 的 frozen 檔案 status 為空及 oracle lock 後，以實際開工 HEAD `ce21cdfc` 執行，`GATE: PASS (6 files)`。沒有修改／撤回 frozen 檔案。
- 開工前等待主線 xcodebuild；曾詢問是否先寫 code、仍串行測試，尚未採用該例外便等到空檔。所有本輪測試在啟動前都等待其他 xcodebuild 退出；主線後來啟動的程序不由本輪中止。
- `/tmp/S001-attempt3-title-red3.log`：修正前 4 tests／1 suite，15 issues，符合作者字距沒有進入 computed style 的失敗。
- `/tmp/S001-attempt3-writing-mode-before.log`：共用文字屬性／斷行路徑修改前，`CoreTextWritingModeTests` 26 tests／1 suite 全過。
- 初次欄位改名造成實驗前端的編譯失敗（`/tmp/S001-attempt3-title-green.log`）；取消改名，沿用既有 `configLetterSpacing` 作為有效 computed tracking，沒有改實驗前端。
- 取值修正後，3 個字距測試通過、其餘剩下 rem fixture 與 terminal kern 誤差（`/tmp/S001-attempt3-title-green2.log`、`/tmp/S001-attempt3-title-diagnostics.log`）。rem fixture 是 helper 沒有保留 SwiftSoup document，弱 parent 提前消失；改為保留 document 到 style building 結束，沒有改 Legacy DOM parser。
- CoreText 邊界量值：Courier 20 的四字自然寬 `48.0078125`；-2px kern 原本得到 `40.0078125`，CSS 三個間隔應是 `42.0078125`。在既有 breaker 裡處理 terminal cluster：候選允許最大正 kern 的尾端空間，再移除行尾 kern、用 CSS 寬度核對。batch、viewport、hyphen 與 justification 共用同一個行尾處理 helper；未含 kern 的行沿用原 typesetter 的行與座標。
- 新增正字距與後續行 source offset 測試：四字自然寬 + 3×2px，兩行來源分別 0+4／4+4。
- `/tmp/S001-attempt3-title-green3.log`：最終 5 tests／1 suite 全過。正在跑必跑組、相關區域與繁中斷行基線（`/tmp/S001-attempt3-regressions.log`）。尚未量測或下本輪判定，尚未 commit。


- Gate 最新結果 `GATE: PASS (8 files)`；最終字距實作加上既有 S001 候選總共 8 檔，沒有基線檔改動。
- 合併回歸執行遭環境中斷：`/tmp/S001-attempt3-regressions.log`、`/tmp/S001-attempt3-regressions.xcresult`。結果包為 37 passed、3 failed、0 skipped：其中 2 個 `BrowserLayoutDeterminismTests` 收到 signal term，1 個為 CoreSimulatorService Connection interrupted（POSIX 53），沒有斷言失敗訊息。此執行不能作為完整通過證據。
- 重新解析 SDK／simulator：仍是 `/Applications/Xcode.app/Contents/Developer`、iOS 27.0、第二台 `C01C0272-859E-4465-BCEB-53C054C686BE`；沒有更換 runtime、沒有重置其他 simulator。接著以每個類別獨立啟動方式跑必要回歸，log `/tmp/S001-attempt3-self-<class>.log`，每次啟動前仍等待其他 xcodebuild。
- 獨立 `BrowserLayoutDeterminismTests` 已通過 4 tests／1 suite（278.447 秒）；probe 單章重複、整本前綴、不同前綴長度與所有疑似章節都一致。先前被 SIGTERM 中斷的兩個方法在此執行通過。log `/tmp/S001-attempt3-self-BrowserLayoutDeterminismTests.log`。
- 獨立必跑組＋繁中斷行基線全部通過：87 tests／16 suites；`LINEBREAK covered=458 skipped(unsupported)=0 stride=1`，179 秒，基線檔未變。各類別 log 依前述 self 命名。正在完成字距／相關區域的獨立回歸。

## 最終實作方回歸

145 tests／24 suites 全過，0 skipped。每個類別獨立執行，log `/tmp/S001-attempt3-self-<class>.log`。

| Class | Tests |
|---|---:|
| BlockLayoutTests | 8 |
| BrowserAutoSupportedSubsetCorrectnessGateTests | 4 |
| BrowserLayoutCapabilityScannerTests | 31 |
| BrowserLayoutDeterminismTests | 4 |
| BrowserLayoutDocumentTests | 4 |
| BrowserLayoutFeatureTests | 1 |
| BrowserLayoutInlineFormattingContextParityTests | 8 |
| BrowserLayoutInlineRunGeometryTests | 4 |
| BrowserLayoutJustificationTests | 5 |
| BrowserLayoutLetterSpacingTests | 5 |
| BrowserLayoutLineBreakBaselineTests | 1 |
| BrowserLayoutLineBreakerClusterTests | 5 |
| BrowserLayoutPageEngineTests | 17 |
| BrowserLayoutUsedValueResolutionTests | 16 |
| BrowserLayoutWhiteSpaceTests | 6 |
| BrowserReaderTypographyTests | 9 |
| CSSLengthResolverTests | 2 |
| ComputedStyleTests | 2 |
| ComputedStyleTreeTests | 1 |
| CoreTextLineBreakerTests | 4 |
| DisplayListTests | 1 |
| EPUBAutoRoutingTests | 4 |
| InlineLayoutTests | 2 |
| PageFragmentationTests | 1 |

斷行基線：458 章、跳過 0、未重錄；直接字距類別 5 tests 全過。開始 dev 量測 `S001-attempt3-after`，僅 ai-glossary、the-deal、game-designer。


## 實作方 dev 量測

`S001-attempt3-after`：僅 3 本／33 個 dev 章節，Browser 24／Legacy 9，unmeasured=0、engine failed=0。此子集的 3 本 ≥80 不代表整份 corpus 目標完成。provenance 確認本地 loop Reader `ce21cdfc` + dirty 與 package `d7e16bd` + dirty；log `/tmp/yuedu-fidelity-S001-attempt3-after.log`。

- 對 `S001-attempt2-verify` 的部分 compare PASS：ai-glossary dev 97.3→97.7（Δ+0.3）；game-designer 可比較 Browser dev 97.6→97.6；the-deal 可比較 Browser dev 99.9→99.9。9 個 Legacy／Legacy 章節被 compare 排除，最大漂移 1.5。
- 對已接受的 `baseline-2026-09-30` 的部分 compare PASS：ai-glossary dev 72.0→97.7，Browser 0→10，media-queries 回退消失；其他兩本 Browser 分數未退步。
- 已開啟新 index.html，並看 spine 3 的新圖、上次候選圖與 WebKit 圖。標題目前 2 行，和 WebKit 的兩行文字分配一致；上次候選 3 行、末行單獨「型”」的問題消失。既有 body 上緣位置、漸層／圖片圓角差異不在這次順手修正。
- 不隱藏單章下降：spine 3 97.6→97.0。其 layout 98.15→98.84、line-count 扣分消失，inline-size 0.220→0.032、line-break 0.630→0.250；visual 97.03→95.17、paint:image 2.537→4.320。spine 8 layout 97.43→98.89，line-break／line-count 扣分消失，visual 93.15→93.91。所有數字來自這兩個 run 的 report.json，保留給驗證者獨立判斷。
- 未量 holdout／全 corpus；本輪完整量測預算留給驗證者一次。尚未 commit。

## 獨立驗證進度

`fidelity-verifier_attempt3` 已獨立通過 oracle lock、main frozen status、Gate 8 檔並讀完整 diff；正在逐類別回歸，另涵蓋字型區域與直排共用路徑。必跑組 86 tests／15 suites 全過，0 skipped；determinism 4 tests 為 269.822 秒。正在完成其餘相關區域與繁中斷行基線。完整 run 保留為 `S001-attempt3-verify`，目前尚未執行／下判定。

## 可重跑的指令

以下命令使用本輪解析過且未變更的 SDK 與第二台模擬器；執行前仍依 LOOP 等待其他 `xcodebuild` 結束。

```bash
cd /Users/zhangruilin/Desktop/Yuedu-fidelity-loop/Yuedu-reader
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export YUEDU_DEST=id=C01C0272-859E-4465-BCEB-53C054C686BE
export YUEDU_WORKSPACE=/Users/zhangruilin/Desktop/Yuedu-fidelity-loop/Loop.xcworkspace
# 上表每個 class 逐一執行，包含繁中斷行基線。
bash scripts/xctest.sh -t 1500 -- -only-testing:'yuedu appTests/<class>' -testLanguage zh-Hant -testRegion TW

python3 /Users/zhangruilin/Desktop/Yuedu-reader/scripts/fidelity/fidelity.py lock --check --tree /Users/zhangruilin/Desktop/Yuedu-fidelity-loop/Yuedu-reader
python3 /Users/zhangruilin/Desktop/Yuedu-reader/scripts/fidelity/fidelity.py gate --reader /Users/zhangruilin/Desktop/Yuedu-fidelity-loop/Yuedu-reader --package /Users/zhangruilin/Desktop/Yuedu-fidelity-loop/YueduCoreText --reader-base ce21cdfc91a2521a2f024224162f08bb187bc8c6 --package-base d7e16bd9aa64b80c4d0bc70fa0fc069409c34ea7

bash /Users/zhangruilin/Desktop/Yuedu-reader/scripts/fidelity/measure.sh --tree /Users/zhangruilin/Desktop/Yuedu-fidelity-loop/Yuedu-reader --run S001-attempt3-after --sets dev --books ai-glossary,the-deal,game-designer
python3 /Users/zhangruilin/Desktop/Yuedu-reader/scripts/fidelity/fidelity.py compare --run S001-attempt3-after --base S001-attempt2-verify
python3 /Users/zhangruilin/Desktop/Yuedu-reader/scripts/fidelity/fidelity.py compare --run S001-attempt3-after --base baseline-2026-09-30
```

Browser Auto correctness gate 的 `/tmp/yuedu-run-browser-auto-correctness-gate` 在回歸前建立，避免 optional gate 跳過；驗證完成後已由本輪清除（原先不存在）。

- 獨立回歸最終全部 PASS：28 類別／186 tests／0 skipped；在實作方 24 類別之外另跑 FontFallback 9、FontDemand 4、CoreTextWritingMode 26、BrowserVerticalReaderRoute 2。繁中斷行基線 covered=458、skipped=0、stride=1（178.742 秒），基線未變未重錄。正在從 main 量法執行本輪唯一 `S001-attempt3-verify`（dev,holdout），將比較已接受 `baseline-2026-09-30 --full`。

## 獨立完整量測

`S001-attempt3-verify`：16 本／249 章完整，engine failed=0、unmeasured=0；擷取測試 1 test／1 suite PASS（732.261 秒）。Browser 193／Legacy 56，對照組沿用 `ios27.0-32c823fa58959671`。

`compare --full --base baseline-2026-09-30`：PASS（249／249）。ai-glossary 全書 75.2→97.7、dev 72.0→97.7、holdout 80.4→97.9；media-queries 回退從 16 章消失，這些章節沒有下降。game-designer:58 79.9→80.5（同為 Browser）；全書顯示分數 96.7→96.7，其餘可比較 Browser 章節未變。56 個 Legacy／Legacy 章節不在此切片的比較範圍，最大漂移 1.8；其書分數的小幅變動不算修正效果。

原有 Reference caveat 原文：`harry-potter: fonts still loading when the reference was measured (8 chapters)`。這是既有 WebKit 對照組的限制，本輪沒有改字型與量法。

完整報告：[S001-attempt3-verify](S001-attempt3-verify.md)；比較：[對已接受基線](S001-attempt3-compare-baseline-2026-09-30.md)。記分板尚未替換，code 尚未 commit；仍待驗證者完成圖像關卡並下判定。

## 最終判定與收尾

**ESCALATE_HUMAN** — `fidelity_verifier_attempt3`。獨立 lock／main frozen status／Gate 8 檔、28 類別／186 tests、458 章斷行及完整 compare 均通過；但圖像關卡不通過，未 commit。[驗證者裁決](S001-attempt3-verdict.md)。

- ai-glossary spine 3 標題已恢復 WebKit 的兩行；spine 8 標題分行亦吻合。
- ai-glossary spine 15 的原文 `OEBPS/chapter-13.xhtml` 使用 `<ol>` 與六個 `<li>`。WebKit 與已接受基線可見 1–6；本輪 Browser 候選完全沒有編號。上一輪未接受候選同樣缺失，因此不是字距修正造成，但 S001 放行後仍是相對已接受基線的新退步。
- 原圖：[WebKit](/Users/zhangruilin/Library/Caches/YueduFidelity/ref/ios27.0-32c823fa58959671/ai-glossary/15/tile-000.jpg)、[已接受基線](/Users/zhangruilin/Library/Caches/YueduFidelity/runs/baseline-2026-09-30/ai-glossary/15/tile-000.jpg)、[本輪候選](/Users/zhangruilin/Library/Caches/YueduFidelity/runs/S001-attempt3-verify/ai-glossary/15/tile-000.jpg)。主代理也看過三張原圖，確認缺失。
- 驗證者檢視全部 16 個 ai-glossary 章節首張圖，在 spine 15 遇到第一個失敗後停止；兩個控制章節的圖像關卡未完成，不能宣稱全部並排檢查通過。
- 依 fidelity-verify 的「the score improves but the side-by-side looks worse」條件升級；本輪唯一完整量測額度已用，不在此輪追加清單規則或重跑 full。
- 候選 8 檔完整保留、兩個 HEAD 未變；沒有 stage／commit／push／發版，未改量法、golden 或套件 pin。STATE 記分板仍是 `baseline-2026-09-30`，已合入仍空。拒絕計數仍 1，兩次升級不算 REJECT。
- 需要使用者決定：（1）先另案補齊通用有序清單 marker，再重試保留的 S001（推薦：保留閱讀資訊）；（2）用編輯撤回候選，暫停 S001。

本輪停止，未處理 S002。

收尾核對：候選 8 檔雜湊與驗證期間紀錄一致；Reader／package HEAD 維持 ce21cdfc／d7e16bd9，兩分支皆 loop/fidelity。報告檔案連結全部存在；本輪建立的 correctness gate 旗標已清除。
