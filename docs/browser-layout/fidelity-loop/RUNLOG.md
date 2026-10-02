---
title: 渲染相似度 loop 執行紀錄
tags: [yuedu, browser-layout, fidelity-loop]
---

# 執行紀錄

[Loop 首頁](README.md) · [目前佇列](STATE.md) · [操作手冊](LOOP.md)

只往下加，不改舊的。每一輪一行：做了什麼、結果、量測的 run 編號。分數一定附 run 編號，才查得到。

| 時間 | 誰 | 切片 | 結果 | 量測 run | 備註 |
|---|---|---|---|---|---|
| 2026-10-01 01:21 | Claude | —（基線） | 量法完成、基線量完：11／16 本過關；佇列 S001–S010 寫進 STATE.md | `baseline-2026-09-30` | 同機重量 `repeat-2026-10-01`：新引擎章節分數完全相同，舊引擎章節最多漂移 2.8 |
| 2026-10-01 02:32 | Claude | —（前置） | 提交 `e00db072`（按需字型）、`f94a6133`（loop）；建立工作副本；在工作副本量一次，引擎是工作副本那份（`@ local`），和基線比較 NO PROGRESS、無失敗 | `loop-start` | 可以開始第一個切片 S001 |
| 2026-10-01 03:11 | Codex／fidelity-verifier | S001（第 1 次） | REJECT；scanner 回歸 31 tests／2 failures，還原後基底 29 tests／同樣 2 failures；未 commit | `S001-before`、`S001-after`（對 `baseline-2026-09-30`；沒有完整 verify run） | ai-glossary dev 72.0（`baseline-2026-09-30`）→97.3（`S001-after`），10 章全 Browser；候選已存 loop 的 patch，兩副本乾淨；[證據](reports/S001-attempt-1.md)，S001 嘗試 1，本輪停下 |
| 2026-10-01 15:20 | Codex | S001（恢復開工檢查） | 等待：純 runtime 下載 xcodebuild 尚未結束；已提出排除下載程序的確認，基底測試與第二次實作未開始 | —（無新 run） | PAUSE／lock／乾淨副本／143GB 通過；PID 35173 下載 iOS 26.5，選用模擬器仍為 iOS 27.0；未增拒絕次數，未改程式碼 |
| 2026-10-01 16:33 | Codex／fidelity-verifier | S001（第 2 次） | ESCALATE_HUMAN；獨立 87 tests／16 suites、458 章斷行未變，full compare PASS；章標題兩行→三行，未 commit | `S001-attempt2-before`、`S001-attempt2-after`、`S001-attempt2-verify`（對 `baseline-2026-09-30`） | ai-glossary 75.2→97.4、dev 72.0→97.3、holdout 80.4→97.4；ai-glossary 16 章轉 Browser，覆蓋 177→193；候選 3 檔保留，S001 移到 D4，記分板未換；[證據](reports/S001-attempt-2.md)。純 runtime 下載排除已獲使用者同意；未做 S002 |
| 2026-10-01 21:11 | Codex／fidelity-verifier | S001（第 3 次／字距前置修正） | ESCALATE_HUMAN；字距標題恢復兩行，獨立 186 tests／28 suites、458 章未變，full compare PASS；spine 15 有序清單 1–6 編號缺失，未 commit | `S001-attempt3-after`、`S001-attempt3-verify`（對 `baseline-2026-09-30`） | ai-glossary 75.2→97.7、dev 72.0→97.7、holdout 80.4→97.9，16 章全 Browser；game-designer:58 79.9→80.5，全書 96.7→96.7；候選 8 檔保留，拒絕計數仍 1，記分板未換；[證據](reports/S001-attempt-3.md)、[裁決](reports/S001-attempt3-verdict.md)。圖像控制章關卡未完成，未做 S002；不 push／不發版／未改量法，本輪停止 |
