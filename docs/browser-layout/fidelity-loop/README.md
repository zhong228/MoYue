---
title: 渲染相似度 loop
updated: 2026-10-01
tags: [yuedu, browser-layout, fidelity-loop, index]
---

# 渲染相似度 loop

[BrowserLayout 目前狀態](../STATUS.md) · [歷史台帳](../PHASES.md)

讓 Codex 自己一輪一輪地把新引擎修到：測試資料夾裡每一本 EPUB，渲染結果和 WebView 至少八成相似。

它由三樣東西組成：一個誰都不能偷改的**量法**、一份**工作佇列**、和一套**每個修改都要被另一個代理重新量過才算數**的流程。做法參考 [loop-engineering](https://github.com/cobusgreyling/loop-engineering)，但照這個專案和 Codex 目前的規格重寫過。

## 現在的分數

基線 `baseline-2026-09-30`：閱讀器是 `main eb960673` 加上當時還沒提交的改動（含按需字型），引擎是 YueduCoreText 0.6.1；語言環境固定為繁體中文。

| 書 | 分數 | 過關 | 最低的一章 | 走新引擎／回退舊引擎的章數 | 低於 60 的章 |
|---|---:|:---:|---:|---:|---|
| Georgia（EPUB 3 範例，表格） `georgia` | **58.3** | ✗ | 58.3 | 0／1 | 0 |
| 草枕（日文直排範例） `kusamakura` | **65.3** | ✗ | 45.1 | 13／2 | 0、14 |
| AI 術語詞典 第一冊 `ai-glossary` | **75.2** | ✗ | 4.0 | 0／16 | 0 |
| 紅樓夢脂評匯校本（繁體直排） `redchamber-vertical` | **76.6** | ✗ | 64.5 | 2／14 | — |
| Mahabharata（梵文詩行） `mahabharata` | **78.5** | ✗ | 74.3 | 16／0 | — |
| The Deal `the-deal` | **86.7** | ✓ | 50.3 | 3／13 | 50 |
| 全知讀者視角 01 `orv` | **86.7** | ✓ | 74.6 | 5／11 | — |
| 洪武大帝 `hongwu` | **88.3** | ✓ | 21.7 | 14／2 | 43 |
| 哈利波特全集 `harry-potter` | **88.9** | ✓ | 65.6 | 4／12 | — |
| 紅樓夢＋大觀紅樓 `redchamber` | **91.1** | ✓ | 81.3 | 18／0 | — |
| israelsailing（希伯來文，由右至左） `israelsailing` | **93.8** | ✓ | 44.8 | 12／0 | 1 |
| 詭秘之主 4 `guimi` | **94.5** | ✓ | 84.5 | 21／0 | — |
| 福爾摩斯探案全集（圖註本） `sherlock` | **96.4** | ✓ | 86.6 | 16／0 | — |
| 全能遊戲設計師 1 `game-designer` | **96.7** | ✓ | 74.3 | 18／1 | — |
| 全職高手 3 `quanzhi` | **96.8** | ✓ | 79.2 | 18／0 | — |
| Project Hail Mary `hail-mary` | **98.8** | ✓ | 85.7 | 17／0 | — |

11 / 16 本過關；量到 249 章，其中 177 章走新引擎（平均 91.8）、72 章回退舊引擎（平均 78.2）。

完整報告：[基線 2026-09-30](reports/baseline-2026-09-30.md)。並排圖（WebView 在左、閱讀器在右，最差的章節排最前面）在本機：`~/Library/Caches/YueduFidelity/runs/baseline-2026-09-30/index.html`。

讀這張表要知道的三件事：

- **卡住沒過的五本的原因，就是佇列的前六項**，見 [STATE.md](STATE.md)。
- **回退舊引擎的章節分數偏低，有一部分是量法看不到。** 舊引擎把表格畫成一張圖，裡面的字量不到（georgia、洪武大帝第 43 章）。這些章節改走新引擎之後才量得準。
- **分數是穩定的。** 同一台模擬器把整份基線重量一次，走新引擎的 177 章每一章分數完全相同；走舊引擎的章節會小幅漂移（最多一章差 2.8），比較兩次量測時這些章節不算進去。換一台語言設定不同的模擬器重量同樣的章節，分數也一樣（抽 6 章驗證）。

## 這幾頁各是什麼

| 頁面 | 內容 | 誰可以改 |
|---|---|---|
| [GOAL.md](GOAL.md) | 目標、完成條件、範圍、什麼時候停 | 只有你 |
| [ORACLE.md](ORACLE.md) | 「幾成像」怎麼算、看不到什麼 | 只有你 |
| [LOOP.md](LOOP.md) | 給代理的操作手冊：一輪怎麼做、要過哪些關、預算 | 只有你 |
| [STATE.md](STATE.md) | 記分板、佇列、進行中、等你決定、已合入 | loop；「等你決定」由你回答 |
| [RUNLOG.md](RUNLOG.md) | 每一輪一行的紀錄 | loop |
| `reports/` | 只有數字的量測報告 | loop |
| `designs/` | 新排版模式動工前的設計筆記 | loop |

程式碼的修改都在另外的工作副本裡（`~/Desktop/Yuedu-fidelity-loop/`，分支 `loop/fidelity`）。上面後四樣 loop 會直接寫在這個資料夾，所以你在 Obsidian 裡看到的就是最新的；它不會自己提交這些檔案。

## 怎麼啟動

前置作業只要做一次，見最下面「還沒做的事」。

在 ChatGPT App 的 Codex 開一個**新對話**，專案資料夾選 `~/Desktop/Yuedu-fidelity-loop/Yuedu-reader`。第一次開這個資料夾時 Codex 會問要不要信任它，選信任，專案裡的 skill 才會載入。然後貼下面其中一段。

### 先一次跑一個切片（建議前兩三次這樣跑）

```text
照 ~/Desktop/Yuedu-reader/docs/browser-layout/fidelity-loop/LOOP.md 做一輪：只做 STATE.md 佇列最上面的一個切片。
先讀同一個資料夾裡的 GOAL.md、LOOP.md、STATE.md（讀主工作目錄的那幾份，不是這個工作副本裡的），做完「開工檢查」再動手。
用 $fidelity-fix 實作、$fidelity-measure 量測，然後交給子代理 fidelity-verifier 判定；只有 APPROVE 才 commit 到 loop/fidelity。
做完更新主工作目錄的 STATE.md 和 RUNLOG.md，然後停下來，用繁體中文告訴我：改了哪條規則、哪幾本書的分數從多少到多少（附 run 編號）、驗證者的判定。
程式碼只在 ~/Desktop/Yuedu-fidelity-loop 底下改；不 push、不發版、不改量法。
```

### 連續跑到完成或預算用完

在輸入框打 `/goal`，目標文字貼這段，並在 Goal 的設定裡給一個 token 預算：

```text
讓 ~/Desktop/Test document/EPUB Format 裡每一本 EPUB 達到 ~/Desktop/Yuedu-reader/docs/browser-layout/fidelity-loop/GOAL.md 的完成條件。
照同一個資料夾裡 LOOP.md 的流程，一輪一個切片，反覆做：
每一輪先讀主工作目錄的 GOAL.md、LOOP.md、STATE.md 並做「開工檢查」；用 $fidelity-triage 維護佇列、$fidelity-fix 實作最上面一項、$fidelity-measure 量測；每個切片交給子代理 fidelity-verifier 判定，只有 APPROVE 才 commit 到 loop/fidelity；每一輪結束更新主工作目錄的 STATE.md 和 RUNLOG.md。
程式碼只在 ~/Desktop/Yuedu-fidelity-loop 底下改；不 push、不發版、不改量法。
遇到 GOAL.md 的任何一個停止條件就停下，用繁體中文告訴我停在哪裡、為什麼。
```

### 每天固定跑一輪

在 Codex 的排程（Automations）新增一個每日任務，執行位置選本機專案 `~/Desktop/Yuedu-fidelity-loop/Yuedu-reader`，提示用「一次跑一個切片」那一段。電腦要開著、App 要在執行。

### 會遇到的放行要求

Codex 的沙盒只讓它寫專案資料夾。loop 還要寫三個地方：引擎的工作副本（`~/Desktop/Yuedu-fidelity-loop/YueduCoreText`）、量測快取（`~/Library/Caches/YueduFidelity`）、這個資料夾裡的狀態檔。你現在的設定是自動審核，通常不用你按；如果它停下來問，這三個地方可以放行，其他地方不該出現。

## 怎麼暫停和停止

- **暫停**：在這個資料夾（`~/Desktop/Yuedu-reader/docs/browser-layout/fidelity-loop/`）建一個叫 `PAUSE` 的空檔案。loop 在下一輪開工檢查時會停下。刪掉就恢復。
- **立刻停**：在 Codex 裡停止那個對話，或在 Goal 上按暫停。做到一半的改動會留在工作副本裡沒有 commit；下一輪的開工檢查會因此停下來，等你決定怎麼處理。
- **整個收掉**：`bash scripts/fidelity/loop-worktrees.sh remove`（工作副本裡還有沒提交的東西時會拒絕）。分支 `loop/fidelity` 會留著。

## 你要做的事

1. 偶爾看 [STATE.md](STATE.md) 的「等你決定」。那裡的項目沒有你回答不會動；直接在那一項底下寫你的決定就可以。
2. 看分數有沒有在動：[RUNLOG.md](RUNLOG.md) 每輪一行，STATE.md 最上面是記分板。
3. 想把成果收回主線時，告訴我或 Codex「把 loop/fidelity 合回 main」。引擎那邊（YueduCoreText）合併後還要照平常的流程發版、更新 App 的版本要求，這一步 loop 不會自己做。

## 自己量一次

```bash
bash scripts/fidelity/measure.sh --run 我的測試 --books guimi,quanzhi
```

比較兩次量測：

```bash
python3 scripts/fidelity/fidelity.py compare --run 我的測試 --base baseline-2026-09-30
```

量法自己的測試（不需要 Xcode）：

```bash
python3 scripts/fidelity/test_fidelity.py
```

## 還沒做的事

這些做完 loop 才能開始，都只要做一次。

1. **把這批檔案提交到 main。** 工作副本是從已提交的 main 建出來的，沒提交的東西不會在那邊。要一起進去的有三組：
   - loop 本身：`scripts/fidelity/`、`docs/browser-layout/fidelity-loop/`、`Tests/iOS/yuedu appTests/RenderFidelityOracleTests.swift`、`.agents/skills/fidelity-*`（`.agents/` 被 gitignore，要 `git add -f`）
   - Codex 已經做完、還沒提交的按需字型改動（基線量的就是含這些改動的引擎）
   - `scripts/xctest.sh` 的 workspace 支援（loop 靠它才編得到自己那份引擎；`loop-worktrees.sh` 會檢查）
2. **建立工作副本**：`bash scripts/fidelity/loop-worktrees.sh create`
3. **在工作副本量一次，確認量的是工作副本裡的引擎、而且分數和基線一樣**：
   ```bash
   YUEDU_WORKSPACE=~/Desktop/Yuedu-fidelity-loop/Loop.xcworkspace bash scripts/fidelity/measure.sh \
     --tree ~/Desktop/Yuedu-fidelity-loop/Yuedu-reader --sets dev,holdout --run loop-start
   python3 scripts/fidelity/fidelity.py compare --run loop-start --base baseline-2026-09-30 --full
   ```
   報告開頭的 engine package 要是 `…/Yuedu-fidelity-loop/YueduCoreText @ local`，比較結果要是 `NO PROGRESS` 而且沒有失敗。
4. **在 Codex 開新對話**，貼上面「先一次跑一個切片」那一段。
