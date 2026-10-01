---
title: 渲染相似度 loop 狀態
updated: 2026-10-01
tags: [yuedu, browser-layout, fidelity-loop]
---

# 狀態

[Loop 首頁](README.md) · [目標](GOAL.md) · [操作手冊](LOOP.md) · [量法](ORACLE.md) · [執行紀錄](RUNLOG.md)

Loop 每一輪更新這一頁。「佇列」和「雜訊」由 `fidelity-triage` 重排；其他區塊只增不刪。

## 記分板

**上一次合入的完整量測：`baseline-2026-09-30`**（[報告](reports/baseline-2026-09-30.md)）。驗證者的 `compare --base` 用這個名字；每合入一個切片，把這裡換成那次驗證的 run。

量的是：閱讀器 `main eb960673 + uncommitted changes`（當時工作目錄的內容，含按需字型），引擎 YueduCoreText 0.6.1。16 本、249 章；對照組 `ios27.0-32c823fa58959671`（語言固定為繁體中文）。

| 書 | 分數 | dev | holdout | 過關 | 走新引擎／回退 |
|---|---:|---:|---:|:---:|---:|
| georgia | 58.3 | 58.3 | — | ✗ | 0／1 |
| kusamakura | 65.3 | 64.0 | 67.7 | ✗ | 13／2 |
| ai-glossary | 75.2 | 72.0 | 80.4 | ✗ | 0／16 |
| redchamber-vertical | 76.6 | 77.5 | 74.9 | ✗ | 2／14 |
| mahabharata | 78.5 | 79.8 | 76.4 | ✗ | 16／0 |
| the-deal | 86.7 | 85.4 | 88.8 | ✓ | 3／13 |
| orv | 86.7 | 87.6 | 84.6 | ✓ | 5／11 |
| hongwu | 88.3 | 85.8 | 92.5 | ✓ | 14／2 |
| harry-potter | 88.9 | 90.6 | 86.2 | ✓ | 4／12 |
| redchamber | 91.1 | 89.8 | 93.6 | ✓ | 18／0 |
| israelsailing | 93.8 | 92.9 | 98.5 | ✓ | 12／0 |
| guimi | 94.5 | 93.4 | 97.0 | ✓ | 21／0 |
| sherlock | 96.4 | 96.8 | 95.8 | ✓ | 16／0 |
| game-designer | 96.7 | 95.8 | 98.7 | ✓ | 18／1 |
| quanzhi | 96.8 | 96.0 | 98.4 | ✓ | 18／0 |
| hail-mary | 98.8 | 98.3 | 99.8 | ✓ | 17／0 |

11／16 本過關。走新引擎 177 章，平均 91.8；回退舊引擎 72 章，平均 78.2。

低於 60 分的章節：ai-glossary:0（4.0）、hongwu:43（21.7）、israelsailing:1（44.8）、kusamakura:0（45.1）、the-deal:50（50.3）、kusamakura:14（57.0）、georgia:0（58.3）。

## 進行中

（無）

## 佇列

前五項各對應一本還沒過關的書，從最小的改動排起。第六項之後是已經過關的書裡看得見的缺陷。每一項的「假設的根因」都還沒重現過，動手前先照 LOOP.md 第 2 步確認。

### S001 — 深色模式的 `@media` 被當成版面相關，整章回退
- 依據：回退原因 media-queries 共 16 章，全部是 ai-glossary（75.2 分，沒有任何一章走新引擎）
- 代表章節：ai-glossary:1、ai-glossary:3、ai-glossary:8
- 假設的根因：`BrowserLayoutCapabilityScanner.cssContainsMediaQuery` 看到任何 `@media` 就拒絕。這本書的樣式表只有一個 `@media (prefers-color-scheme: dark)`，裡面只改顏色；`CSSParser` 已經把這種區塊分流成 `isDarkMedia` 規則，不影響版面。
- 完成的樣子：ai-glossary 不再有 media-queries 回退。走新引擎後分數下降，或掃描器接著報出別的原因（這本書還用了 `max-width: 42em`、`min-height: 100vh`、`linear-gradient`），就把看到的寫在這一項底下再拆，不要順手一起改
- 嘗試：1（2026-10-01，驗證者 REJECT）
- 第一次結果：候選修正讓 CSSParser 與能力掃描器共用 at-rule 邊界，只放行獨立 `@media (prefers-color-scheme: dark)` 的配色宣告，其他查詢、巢狀條件及版面宣告維持拒絕。Gate 通過（3 檔）；兩個新合成測試通過。
- 實作方量測（未合入）：ai-glossary 的 10 個 dev 章節 72.0（`baseline-2026-09-30`）→ 97.3（`S001-after`），新引擎 0→10 章，media-queries 回退消失；部分比較 PASS。代表章節 3／8 的平均 77.1（`S001-before`）→ 96.4（`S001-after`）。未量 holdout，不能替換記分板。
- 驗證者理由：`BrowserLayoutCapabilityScannerTests` 31 tests、2 failures：`rejectsRubyOutsideSupportedSubset` 未回報 `.ruby`；`rejectsEffectiveUnsupportedTextIndent` 的 `-1px` 未回報 `.textIndent`。依第一項失敗即停止，未進入獨立完整量測與並排圖關卡。
- 基底核對：撤回本輪三檔後，原始類別 29 tests、同樣 2 failures（`/tmp/S001-base-scanner.log`），確認阻擋也存在於基底。沒有削弱斷言或順手修其他規則。
- 收尾：未 commit；兩個工作副本乾淨，仍在原 `loop/fidelity` commit。候選 diff 保存在 `~/Desktop/Yuedu-fidelity-loop/S001-attempt-1-rejected.patch`；[本輪證據](reports/S001-attempt-1.md)。本輪停下，S001 保留佇列首位，未做 S002。

### S002 — 行內盒的左右 margin 沒有佔位
- 依據：inline-start 5.8、line-count 5.3、inline-size 4.9、line-break 4.5（每本書的分數點數）；mahabharata 16 章全走新引擎，78.5 分
- 代表章節：mahabharata:1118、mahabharata:447
- 假設的根因：`span.lin { margin-left: 5em }`、`span.num { margin-left: 2em; margin-right: 1em }`。WebKit 把行內盒的水平 margin 算進行內排版，詩行因此縮排並多折一行（對照組 341 行，我們 192 行）；我們沒有把它算進去。章節的結構是 `<body>` 底下直接放 `<span>…</span><br/>`。padding、border 是同一條規則，一起確認
- 完成的樣子：mahabharata ≥ 80，行數和對照組一致
- 嘗試：0

### S003 — 根元素 `html` 的背景沒有鋪到整個畫面
- 依據：paint:other 14.7；kusamakura 走新引擎的 13 章平均不到 70
- 代表章節：kusamakura:3、kusamakura:8
- 假設的根因：`html { background-color: #fff4e7 }`。CSS 規定根元素的背景畫在整個 canvas 上；整頁背景目前看起來只從 `body` 取
- 完成的樣子：這 13 章的 paint:other 降到 3 以下
- 嘗試：0

### S004 — 根元素 `html` 自己的盒子沒有生效（margin、padding、max-height／max-width）
- 依據：line-break 5.2、inline-start 5.0、inline-size 3.1；kusamakura
- 代表章節：kusamakura:3、kusamakura:8
- 假設的根因：`html { margin: auto 1em; padding: 1em 0; max-height: 28em; font-size: 14pt }`。直排時 `max-height` 把每一行限制在 28em，上下的 auto margin 讓它置中；我們把字排滿整個高度。橫排版本的樣式表用的是 `max-width: 28em`，同一條規則
- 完成的樣子：每行字數和對照組一致；kusamakura 走新引擎的章節 ≥ 80
- 嘗試：0

### S005 — 直排章節只要有圖就整章回退
- 依據：回退原因 vertical-writing-mode 共 16 章（redchamber-vertical 14 章、kusamakura 2 章），平均 71.5；redchamber-vertical 76.6 分
- 代表章節：redchamber-vertical:51、redchamber-vertical:8、kusamakura:0
- 假設的根因：`VerticalTextSupport.accepts` 遇到 `img` 就拒絕。redchamber-vertical 的圖是一個字大小的行內標記（17×17 的 gif，一章幾十到幾百個）；kusamakura:0 是區塊圖和 `inline-block` 裡的圖
- 做法：這是新的排版能力，先在 `designs/` 寫設計筆記（行內圖在欄裡怎麼定位和佔行長、區塊圖、哪些情況繼續回退），再分切片。先做行內圖
- 完成的樣子：redchamber-vertical 的章節走新引擎，這本書 ≥ 80
- 嘗試：0

### S006 — 表格排版
- 依據：回退原因 table 共 12 章（georgia 全書、hongwu 2 章、orv 9 章）；georgia 58.3 分
- 代表章節：georgia:0、hongwu:43、orv:13
- 假設的根因：新引擎沒有表格排版，`table`／`tr`／`td` 一出現就回退；舊引擎把整張表畫成一張圖
- 做法：先寫設計筆記（支援的子集：固定與自動欄寬、`colspan`／`rowspan`、邊框模型；不支援時照舊回退），再分切片。orv 的章節同時還有 flex／grid，表格做完它們仍會回退
- 注意：舊引擎畫成圖的表格，量法看不到裡面的字（見「雜訊」），所以這些章節現在的分數偏低。走新引擎之後才量得到真正的差距
- 完成的樣子：georgia 走新引擎而且 ≥ 80
- 嘗試：0

### S007 — 帶 `:link` 的選擇器整條被丟掉
- 依據：font-size 5.1 與邊框位移；hail-mary:40（85.7，全書其他章節接近 100）
- 代表章節：hail-mary:40
- 假設的根因：`.pcalibre4:link { font-size: 1.2em }`。`CSSParser.parseComponent` 遇到 `:first-child`、`:first-of-type` 以外的偽類就放棄整條規則，所以連結拿到的是另一條規則的 1.125em。未造訪的連結（`a[href]`）符合 `:link`；`:visited`、`:hover`、`:active`、`:focus` 在靜態排版裡不成立
- 完成的樣子：hail-mary:40 的 font-size 扣分歸零
- 嘗試：0

### S008 — HTML 的 `dir` 屬性沒有決定區塊的方向
- 依據：image-position、inline-start、indent 與畫面分；israelsailing:1（44.8）
- 代表章節：israelsailing:1
- 假設的根因：`<div dir="rtl">`。行應該從右邊開始、行內圖靠右；我們當成由左至右。這本書其他章節同樣寫了 `dir="rtl"`，但段落另外有 `text-align: right`，所以分數是 94–100；這一頁只靠 `dir`
- 完成的樣子：israelsailing:1 ≥ 85
- 嘗試：0

### S009 — float 容器裡的圖片，百分比寬度算成一半
- 依據：image-size 與 paint:image 33.7；quanzhi:418（79.4）
- 代表章節：quanzhi:418
- 假設的根因：`<div class="ctleft">`（float，寬度是 body 的一半）裡的 `<img width="85%">`。WebKit 的圖寬 152.4（容器 179.3 的 85%）；我們是 76.2，剛好一半，像是容器的百分比被多套了一次
- 完成的樣子：兩張圖的寬度和對照組相差 2pt 以內
- 嘗試：0

### S010 — 首字放大這類非圖片的 float 需要 shrink-to-fit 寬度
- 依據：回退原因 float 共 26 章（the-deal 13、harry-potter 12、orv 1），平均 85.4
- 代表章節：the-deal:12、harry-potter:100
- 假設的根因：`float: left; font-size: 3em; line-height: 100%` 的 `<span>`，寬度是 auto。`validateFloats` 對非 replaced、`width: auto` 的 float 一律拒絕，因為還沒有 shrink-to-fit（CSS 2.1 §10.3.5）。只含行內文字的 float，寬度就是它的 max-content 寬度
- 完成的樣子：這 26 章走新引擎，而且 the-deal、harry-potter 的分數不下降
- 嘗試：0

候補（還沒排進前十）：flex／grid 與 `position`（orv 10 章、game-designer:10）；UA 預設的標題字級沒有跟著根字級（sherlock:21，34 對 32）；整頁背景圖的大小與位置（guimi:64、redchamber:305）；行內小圖相對容器左移沒有生效（game-designer:58）；版面相關的 `@media`（寬度查詢）求值。

## 等你決定

### D1 — 舊引擎在捲動模式漏畫「獨佔一塊的圖」，要不要另外修
- 看到的事：量測用的設定（段距 0、行距 1.5）下，舊引擎把一張圖單獨切成一塊時，那一塊的 CoreText frame 是 0 行，什麼都沒畫。ai-glossary 的封面（spine 0）和 the-deal 最後一章的章末圖（spine 50）都是這樣
- 還不知道的事：你平常的設定（段距不是 0）會不會遇到。沒有在 App 裡實際開書確認過
- 為什麼不在佇列裡：這是舊引擎的問題，loop 不准改舊引擎。ai-glossary 的章節走新引擎之後（S001）就不會經過這條路
- 選項：（a）另開一個工作先重現、再修主路徑（建議：它讓圖整張不見，而且回退的章節還有 72 章）；（b）不修，等這些章節都改走新引擎
- 狀態：2026-10-01 已在 Claude Code 裡建好一個可以一鍵開始的獨立工作（「Fix legacy scroll chunks that paint a lone image as nothing」），按下去就是選（a）

### D2 — S001 被基底的能力掃描回歸失敗阻擋
- 已確認：還原本輪修改後，原始 `BrowserLayoutCapabilityScannerTests` 仍有 ruby 與 `text-indent: -1px` 兩項失敗；不是新增深色配色測試才出現。
- 需要處理：釐清既有測試所宣告的支援邊界與實作的差異；這涉及 S001 以外的兩條規則，未在本輪順手修改。
- 選項：（a）先另案釐清並修正這兩項回歸，再重試 S001（建議：候選 dev 量測已改善，但必跑回歸必須通過）；（b）暫停 fidelity loop，等主線自行處理。
- 狀態：S001 第一次 REJECT，沒有合入；記分板與最後接受的 run 維持 `baseline-2026-09-30`。
- **2026-10-01 已處理（Claude，選 a）。** 把「每次都跑」整組在基底上跑過一次，共 5 個測試失敗，全部是測試的期望值停在舊版引擎；引擎是照 CSS 刻意改的，套件自己的測試都有涵蓋：
  - `rejectsRubyOutsideSupportedSubset`：`<rb>` 包住的注音從 YueduCoreText 0.4.0 起是支援的（橫直排共用一套判斷）。
  - `rejectsEffectiveUnsupportedTextIndent`：負值 `text-indent` 從 0.5.0 起支援，第一行往外凸（套件測試 `mixedInlineIndentAndNegativeAvailableWidth`）。
  - `producesWrappedLineBoxes`：0.5.0 的行框算法算出 23.999999999999996，和 24 差一個浮點誤差。
  - `legacyFrontendPreservesExistingStylesheetOrdering`：0.5.0 修正了樣式表的先後順序，後面的樣式表在同等特異性下勝出（CSS Cascade）；測試改名為 `laterStylesheetWinsAtEqualSpecificity`，改驗正確順序。
  - `EPUBAutoRoutingTests` 的捲動測試：9/23 起內容視圖包在一個允許字形超出的裁切容器裡，改成量它在 cell 裡的位置（仍是 12）。
  - 順手查了各區域的測試：注音 `rejectsRubyOutsidePhase4DSubset`、float 的 `floatOnNextPageExclusionCoordinates`、`actualLineBandHeightDrivesFloatExclusion`、`percentageInlineImageInsideExplicitWidthFloatUsesFloatContentWidth` 也是同樣原因（0.4.0 注音、0.5.0 行框），一起改成照 CSS 推出來的期望值。
  - 手冊的必跑清單原本寫了一個不存在的型別名稱（`BrowserLayoutEngineTests` 是檔名，裡面有 10 個測試型別），會空跑；已改成 15 個真的型別，main 上是 84 tests 全過。手冊也加了一條：基底的必跑測試不全過就不准開始切片。
  - loop 分支已同步到 main。S001 可以重試：候選 patch 還在 `~/Desktop/Yuedu-fidelity-loop/S001-attempt-1-rejected.patch`，它也改了 `BrowserLayoutCapabilityScannerTests.swift`，套用時那個檔案可能要手動合。

### D3 — 整本《紅樓夢》的斷行基線在現在的環境都過不了
- 看到的事：`BrowserLayoutLineBreakBaselineTests`（9/23 在 `14c7a441` 錄的 `docs/browser-layout/line-break-baseline/redchamber.tsv`）目前失敗。在系統語言是繁體中文（台灣）的模擬器上有 61 章不同；~~用 `-testLanguage` 指定任何語言（繁中、簡中、英文），或在英文介面的模擬器上，都是 196 章不同。不同的章節頁數、行數、第一行、最後一行都一樣，差在中間的行。~~
  - 更正（10/1 稍晚）：劃掉的兩句是錯的。指定語言的那幾次是在 zsh 的迴圈裡跑的，語言參數沒有被拆開，根本沒有生效。實際是：程序語言繁中 61 章、英文 196 章、簡中 246 章。61 章裡有 56 章只差在中間的行，另外 5 章的行數或頁數也變了。
- 還不知道的事：那 61 章是環境（模擬器的系統版本、語言）造成的，還是 9/23 之後的程式改動（0.6.0 整合、0.6.1 按需字型等）造成的。
- 為什麼要你決定：這是錄好的基線，手冊規定不准自己重錄。
- 影響：S001 不受影響。會擋住做斷行、行內排版的切片（S002 開始），因為驗證者會跑這個測試。
- 選項：（a）先把 `14c7a441` 在現在的環境重跑一次：結果也是 61 章就是環境造成的，照它重錄並寫清楚；如果是 0 章，就逐個 commit 找出是哪個改動改了斷行（建議：一兩個小時，能說清楚每一章為什麼變）；（b）直接在固定語言的環境下重錄，不追原因；（c）先把它從 loop 的回歸清單拿掉，靠相似度量測看《紅樓夢》。
- **2026-10-01 已處理（Claude，選 a）。** `14c7a441` 今天重建（套件一樣是 YueduCoreText 0.6.0），在繁中和英文下錄出來的結果都和 main 逐位元組相同，所以 9/23 之後沒有程式改動改了斷行。61 章是環境造成的；9/23 錄製的那台模擬器已經不在，是哪個環境因素沒有再追。
  - 已在 main 上固定繁中重錄。測試現在只要程序語言不是繁中就直接失敗，訊息會說要加的參數。
  - 舊基線留在 `redchamber-2026-09-23.tsv`。完整紀錄在 `docs/browser-layout/line-break-baseline/rerecord-2026-10-01.md`。
  - 這個測試在基底上已經是綠的，不會再因為環境的差異擋住斷行、行內排版的切片。跑它要加 `-testLanguage zh-Hant -testRegion TW`，手冊已經寫了。
  - 2026-10-01 在 loop 的工作副本、loop 的模擬器上跑開工檢查：必跑組加斷行基線 85 tests in 16 suites 全過。
- **2026-10-01 使用者決定：斷行基線每個切片都跑。** 不是要改斷行的切片讓它變了，就是回歸；本來就要改斷行的切片，在同一個 commit 重錄，報告列出全部變了的章，並抽 3 章說明規則用在哪裡；驗證者核對清單並自己再抽 2 章。閘門（`fidelity.py gate`）現在只放行 `redchamber.tsv` 這一個基線檔，其他錄製檔照舊要人看。細節在 [LOOP.md](LOOP.md)「斷行基線」。

## 已合入

（無）

## 雜訊

量法看不準、不該拿來當切片的扣分。完整的限制清單在 [ORACLE.md](ORACLE.md)「它看不到的東西」。

- **舊引擎的表格是一張圖。** 裡面的字量不到位置，算成缺字：georgia:0（missing-text 14.5）、hongwu:43（21.7 分）、orv 有表格的 9 章。實際看起來沒有分數說的那麼差。
- **舊引擎漏畫獨佔一塊的圖。** ai-glossary:0（4.0）、the-deal:50（50.3）的 image-missing 來自這裡，見 D1。
- **harry-potter 有 8 章指定了載不到的字型。** 對照組等了 8 秒後照替代字型量；這是 WebView 實際會顯示的樣子，不是誤差，只是列出來備查。
- **舊引擎的章節每次量會小幅漂移。** 在同一台模擬器上把整份基線重量一次（`repeat-2026-10-01`）：走新引擎的 177 章每一章分數都完全相同；走舊引擎的 72 章最多差 2.8（hongwu:43）。kusamakura:0 在更早的幾次量測裡，舊引擎排出的整塊寬度在 559–580pt 之間跳。`compare` 已經把兩次都走舊引擎的章節排除在外；看報告裡的書分數時，差 0.3 以內不要當真。
- **redchamber:305 這類整頁只有一條裝飾背景的章節。** 沒有文字可比，整章分數只看那條裝飾；一章的 81 分不代表版面有問題。
