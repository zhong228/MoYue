---
title: 渲染相似度 loop 操作手冊
updated: 2026-09-30
status: 由人維護；代理照做，不自行修改
tags: [yuedu, browser-layout, fidelity-loop]
---

# 操作手冊

[Loop 首頁](README.md) · [目標](GOAL.md) · [量法](ORACLE.md) · [目前佇列](STATE.md) · [執行紀錄](RUNLOG.md)

這是給執行 loop 的代理（Codex）看的。每一輪開始先讀主工作目錄裡的 [GOAL.md](GOAL.md)、這一頁和 [STATE.md](STATE.md)（工作副本裡的那幾份是建立分支當時的舊版，不要讀也不要改）；專案規則照 repo 根目錄的 `AGENTS.md` 與 `CLAUDE.md`，這裡只寫 loop 特有的部分。回覆使用者一律用繁體中文。

## 誰做什麼

| 角色 | 是誰 | 能做 | 不能做 |
|---|---|---|---|
| 量測 | `scripts/fidelity/measure.sh` | 產生分數與報告 | — |
| 實作 | 主代理 | 在 loop 工作副本裡改引擎、寫測試；在主工作目錄的 `docs/browser-layout/fidelity-loop/` 更新 `STATE.md`、`RUNLOG.md`、`reports/`、`designs/` | 宣稱自己的修改通過；改量法；動主工作目錄的其他任何東西 |
| 驗證 | 子代理 `fidelity-verifier`（另一個對話脈絡） | 跑 gate、跑量測與回歸、讀 diff、下判定 | 改任何程式碼 |
| 人 | 使用者 | 合併、發版、改目標與量法、回答「等你決定」 | — |

實作的人不能替自己打分數。每一個切片都要由驗證者重新量過才算數。

## 在哪裡做

| 位置 | 用途 |
|---|---|
| `~/Desktop/Yuedu-reader`、`~/Desktop/YueduCoreText` | 主工作目錄。使用者與其他對話在這裡工作，**loop 不改這裡的程式碼**。驗證時用這裡的 `scripts/fidelity/` 評分 |
| `~/Desktop/Yuedu-reader/docs/browser-layout/fidelity-loop/` | loop 的文書：`STATE.md`、`RUNLOG.md`、`reports/`、`designs/`。這是使用者的筆記庫，他在這裡看進度、回答「等你決定」。loop 在主工作目錄裡**只准寫這四樣**；`GOAL.md`、`ORACLE.md`、`LOOP.md`、`README.md` 不准改 |
| `~/Desktop/Yuedu-fidelity-loop/Yuedu-reader` | loop 的閱讀器工作副本，分支 `loop/fidelity` |
| `~/Desktop/Yuedu-fidelity-loop/YueduCoreText` | loop 的引擎工作副本，分支 `loop/fidelity` |
| `~/Desktop/Yuedu-fidelity-loop/Loop.xcworkspace` | 把上面兩個配在一起編譯；引擎改動不必先發版 |
| `~/Library/Caches/YueduFidelity` | 擷取、對照組、報告、並排圖（含書的內容，不進 git） |

工作副本由 `bash scripts/fidelity/loop-worktrees.sh create` 建立。下面用 `$LOOP` 代表 `~/Desktop/Yuedu-fidelity-loop`，`$MAIN` 代表 `~/Desktop/Yuedu-reader`。

## 一輪做一個切片

一個切片＝一條 CSS／HTML 規則或一個缺陷，改動不超過 12 個檔案。太大就先拆。

### 0. 開工檢查

任何一項不成立就停下，在 [RUNLOG.md](RUNLOG.md) 記一行原因：

- `$MAIN/docs/browser-layout/fidelity-loop/PAUSE` 不存在（存在＝使用者要 loop 暫停）。
- `python3 $MAIN/scripts/fidelity/fidelity.py lock --check --tree $LOOP/Yuedu-reader` 通過。
- 兩個工作副本都沒有上一輪留下的未提交改動。
- 磁碟剩餘空間 ≥ 10GB（`df -g ~`）。
- 沒有別的 `xcodebuild` 在跑（`pgrep -x xcodebuild`）；有就等它結束，不要同時編譯。

### 1. 選一項

拿 [STATE.md](STATE.md)「佇列」最上面一項。佇列空了，或上次量測之後已經合入過切片，就照 `fidelity-triage` skill 從最新報告重排。

### 2. 找到根因

- 只量受影響的章節：`bash scripts/fidelity/measure.sh --run <切片編號>-before --only <書>:<章>,<章>`。
- 打開 `~/Library/Caches/YueduFidelity/runs/<run>/index.html` 的並排圖，確認分數說的和眼睛看到的是同一件事。不一致是量法的問題：停下來回報，不要湊分數。
- 用 CSS 規格說明 WebKit 為什麼那樣排，再找引擎裡最早出錯的那一層（解析、cascade、used value、排版、繪製）。截圖只用來定位現象，不當根因（[PHASES.md](../PHASES.md) D-11）。
- 先寫一個會失敗的合成測試。期望值從 CSS 規則與盒模型推出來，不是抄目前的輸出。

### 3. 實作

照 `fidelity-fix` skill。重點：

- 改的是通用規則。不准出現書名、作者、class 名稱、檔名的判斷。
- 先修主路徑，不加兜底、重試、延遲。
- 一件事只留一條實作路徑；不新增第二套 parser、快取或排版分支。
- 新的排版模式（table、flex／grid、positioned、雙向文字、media query 求值）先在 `designs/` 寫一頁設計筆記：支援的子集、不支援時怎麼回退、測試清單。寫完就照它分切片做；只有會改變現有已支援章節的行為，或需要產品決定時，才停下來等人。
- 能力判斷（`BrowserLayoutCapabilityScanner`）只在對應的排版真的實作並有測試之後才放行。放行但排不對，比回退 Legacy 更糟。

### 4. 自己先驗

- 跑切片直接相關的回歸測試類別（見下表），以及「每次都跑」那一組。
- 重量一次受影響的書：`--run <切片編號>-after --books <書>,<書>`。
- 和 before 比：目標項目的扣分要下降，其他項目不能變差。

### 5. 交給驗證者

叫出子代理 `fidelity-verifier`（定義在 `.codex/agents/fidelity-verifier.toml`）。找不到這個角色時，開一個新的子代理，要它只照 `$fidelity-verify` 做、不准改任何檔案。只給它：切片編號、切片說明、兩個 repo 的起始 commit、你跑過的指令與結果。它從主工作目錄重新量測並下判定。

不要把自己的推論或「應該會過」交給它；它要的是能重跑的指令。

### 6. 依判定處理

| 判定 | 動作 |
|---|---|
| `APPROVE` | 兩個工作副本各自 commit 到 `loop/fidelity`（訊息格式見下），把這一項移到「已合入」並寫上分數變化，把「記分板」換成這次驗證的 run，把驗證的報告存一份到 `reports/`，在 RUNLOG 記一行 |
| `REJECT` | 這一項的嘗試次數加一，把驗證者的理由寫進 STATE。第三次被退回就移到「等你決定」，附上三次各試了什麼 |
| `ESCALATE_HUMAN` | 改動留在工作副本**不 commit**，移到「等你決定」，寫清楚需要人看什麼 |

被退回後不要用 `git checkout --`、`git restore`、`git reset --hard` 清掉改動；用編輯把自己加的部分改回去。

### 7. 下一輪

回到步驟 0。符合 [GOAL.md](GOAL.md) 的任何一個停止條件就停。

## 一個切片要過的關

| 關卡 | 標準 |
|---|---|
| Gate | `fidelity.py gate` 印出 `GATE: PASS` |
| 比較 | `fidelity.py compare --full` 印出 `COMPARE: PASS`。下面四列就是它檢查的內容；數字由它算，不要自己心算 |
| 目標有進步 | 至少一本書的分數上升 ≥ 0.3，或某個回退原因從該書的量測章節裡消失而且那些章節的分數沒有下降 |
| 沒有退步（dev） | 沒有任何一本書下降超過 0.5 |
| 沒有退步（holdout） | 沒有任何一本書下降超過 1.0 |
| 新引擎的覆蓋不倒退 | 報告裡走新引擎的章節數（Browser / Legacy）不比上一次合入的量測少。不准用「讓更多章節回退 Legacy」換分數；唯一的例外是修正「放行但排錯」，那種切片一律 `ESCALATE_HUMAN` |
| 回歸測試 | 相關類別與「每次都跑」全部通過，沒有被停用或跳過的測試 |
| 規則是通用的 | diff 裡沒有針對特定書的條件；新行為有合成測試，而且期望值有出處 |

## 回歸測試

都在 loop 的閱讀器工作副本裡跑，一次一個類別：

```bash
cd $LOOP/Yuedu-reader
YUEDU_WORKSPACE=$LOOP/Loop.xcworkspace bash scripts/xctest.sh -- -only-testing:'yuedu appTests/<類別>'
```

`-only-testing` 寫 struct／class 名稱；跑完核對 log 裡的測試數不是 0（空跑不算通過）。

| 什麼時候 | 類別 |
|---|---|
| 每次都跑 | `BrowserLayoutEngineTests`、`BrowserLayoutPageEngineTests`、`EPUBAutoRoutingTests`、`BrowserLayoutCapabilityScannerTests`、`BrowserAutoSupportedSubsetCorrectnessGateTests`、`BrowserLayoutDeterminismTests` |
| 斷行、行內排版 | `BrowserLayoutLineBreakerClusterTests`、`BrowserLayoutJustificationTests`、`BrowserLayoutInlineRunGeometryTests`、`BrowserLayoutInlineFormattingContextParityTests`、`BrowserLayoutWhiteSpaceTests` |
| 字型、字級、行高 | `BrowserLayoutFontFallbackTests`、`BrowserReaderTypographyTests`、`BrowserFontDemandTests`、`BrowserLayoutUsedValueResolutionTests` |
| 邊距、縮排、float | `BrowserLayoutTextIndentTests`、`BrowserLayoutFloatLayoutTests`、`BrowserLayoutFloatStyleTests`、`BrowserLayoutLogicalGeometryTests` |
| 圖片 | `BrowserLayoutImageTests`、`BrowserLayoutProductionCorrectnessTests` |
| 背景、邊框、裝飾 | `BrowserLayoutInlineDecorationTests`、`BrowserLayoutFragmentedDecorationTests`、`BrowserScrollPageBackgroundTests` |
| 注音 | `BrowserLayoutRubyLayoutTests` |
| 直排 | `CoreTextWritingModeTests`、`BrowserVerticalReaderRouteTests` |
| 捲動與 viewport | `BrowserScrollDocumentTests`、`BrowserViewportSessionTests`、`BrowserViewportRegressionTests` |
| 連結、選字 | `BrowserLayoutLinkInteractionTests`、`BrowserLayoutSelectionContractTests`、`BrowserTextInteractionTests` |

`BrowserLayoutSnapshotTests` 與斷行基線（`BrowserLayoutLineBreakBaselineTests`、`BrowserLayoutRedChamberRegressionTests`）比的是已錄製的結果。它們因為一個正確的修正而失敗時，不要重錄：把失敗的列與原因寫進「等你決定」。

## 量測指令

```bash
# 實作者：在 loop 工作副本裡，只量 dev
cd $LOOP/Yuedu-reader
YUEDU_WORKSPACE=$LOOP/Loop.xcworkspace bash scripts/fidelity/measure.sh --run S012-after --books guimi,quanzhi

# 驗證者：用主工作目錄的量法去量 loop 的工作副本，dev 和 holdout 都量
YUEDU_WORKSPACE=$LOOP/Loop.xcworkspace bash $MAIN/scripts/fidelity/measure.sh \
  --tree $LOOP/Yuedu-reader --sets dev,holdout --run S012-verify

# 只重新評分已經擷取過的 run
python3 scripts/fidelity/fidelity.py score --run S012-after --verbose

# 兩次量測比較：哪些書變了、有沒有過關。實作時比受影響的書（結果會標 partial）；
# 驗證時加 --full，和 STATE.md 記的「上一次合入的完整量測」比
python3 $MAIN/scripts/fidelity/fidelity.py compare --run S012-after --base S012-before
python3 $MAIN/scripts/fidelity/fidelity.py compare --run S012-verify --base <上一次合入的完整量測> --full
```

`compare` 的結束碼：0＝`PASS`；4＝`FAIL` 或 `NO PROGRESS`。它只比兩次都量到的章節，結果另存在 `runs/<run>/compare-<base>.md`。

對照組（WebKit）擷取一次後會重複使用；每一輪只重新跑引擎這一邊。

## Commit

- 只 commit 到兩個工作副本的 `loop/fidelity`。**不 push、不發版、不改 `Package.resolved` 或套件版本號**；那是使用者合併時的事。
- 引擎：`fix(layout): <規則一句話> [fidelity S012]`（新能力用 `feat`）。
- 閱讀器：`test(fidelity): S012 <一句話>`，或接線改動用 `fix(browser-layout): …`。
- 訊息本文寫：根因、改了哪條規則、哪幾本書的分數從多少到多少、跑了哪些測試。

## 預算與暫停

| 項目 | 上限 |
|---|---|
| 同一項的嘗試次數 | 3 |
| 一個切片改動的檔案數 | 12（兩個 repo 合計） |
| 一輪裡完整量測（全部書、dev＋holdout）的次數 | 驗證時 1 次；實作時只量受影響的書 |
| 連續沒有進展的切片 | 連續 3 個切片都被退回或升級 → 整個 loop 停下，在 STATE 最上面寫明 |
| Token 預算 | 由使用者在 Codex 的 Goal 設定；用完就停 |

暫停：使用者在主工作目錄建立 `docs/browser-layout/fidelity-loop/PAUSE`（內容隨意）。刪掉就恢復。

## 不能讓載入變慢

載入效能是另一條主線（[基線](../loading-benchmark-2026-09-30.md)、[按需字型第一輪](../loading-benchmark-2026-09-30-font-demand.md)），這個 loop 不做效能優化，但也不能把它已經拿回來的時間還回去。

- 每合入 5 個切片，以及宣告完成之前，在 loop 工作副本裡重跑一次那份報告最後的量測指令（`EPUBEngineLoadingBenchmarkTests`，把 `YUEDU_WORKSPACE` 換成 `$LOOP/Loop.xcworkspace`，輸出檔名換成自己的）。
- 和「按需字型第一輪」表裡的「本輪 Auto」中位數比。任何一個案例慢超過 15%，把數字寫進「等你決定」並停下；不要自己動手優化，也不要為了分數把它記成雜訊。
- 能力回退的章節不准開始替新引擎準備字型或圖片。那是上一輪才修掉的成本。
- 效能主線接下來要動 `BrowserLayoutCapabilityScanner` 與 CSS 前端的共用求值，和這個 loop 改的是同一批檔案。合併 main 時在這些檔案遇到衝突，一律停下來等人，不要自己解。

## 和別人共用這台機器

- 主工作目錄裡常有使用者和其他對話的未提交改動。不要碰，也不要把主目錄的改動帶進工作副本。你在主工作目錄寫的那四樣文書也不要 commit；使用者自己決定什麼時候提交。
- **量測和測試都跑在第二台模擬器上。** 主工作目錄的測試用預設那一台；兩邊對同一台跑測試時，後開始的那一個會重裝 App，把先開始的測試行程砍掉，三四十分鐘的量測就白跑了。每一輪開頭設定一次，之後的 `xctest.sh` 和 `measure.sh` 都會用它：
  ```bash
  SECOND="$(bash scripts/sim.sh list | awk 'NR==2 {print $NF}')"
  [ -n "$SECOND" ] && export YUEDU_DEST="id=$SECOND"
  ```
  只有一台可用時不設定，照預設跑，並在開工檢查多確認一次沒有別的測試在跑。換模擬器不影響分數：版面固定成 390×800、語言環境固定成繁體中文，在一台英文介面、一台中文介面的模擬器上量同樣的 6 章，分數完全相同（2026-10-01 驗證）。
- DerivedData 不另開：不要傳 `-derivedDataPath`。
- 測試一律用 `scripts/xctest.sh`，超過 5 分鐘沒有輸出先 `grep -E "Test run with|TEST (SUCCEEDED|FAILED)"` log，再判斷是不是卡住。
- 同步主線：只在切片之間、兩個工作副本都乾淨時，`git merge main` 進 `loop/fidelity`。有衝突就停下，寫進「等你決定」，不要自己選邊。
