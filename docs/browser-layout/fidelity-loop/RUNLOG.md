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
