---
title: S001 第 3 次獨立驗證裁決
updated: 2026-10-01
---

# 判定：ESCALATE_HUMAN

判定者：`fidelity_verifier_attempt3`（fidelity-verifier，獨立脈絡、未改 code）。Reader base `ce21cdfc91a2521a2f024224162f08bb187bc8c6`；package base `d7e16bd9aa64b80c4d0bc70fa0fc069409c34ea7`。

## 證據

- Oracle：開工及收尾皆通過，7 files／2 trees；main frozen status 空。
- Gate：PASS，8 檔、沒有 note；完整 diff 與新測試已讀，前後 diff 雜湊一致。
- 合成測試：字距期望由最終字級、CSS 單位及四字三間隙推導，基底缺少作者 letter-spacing 處理。深色配色測試核對淺色 cascade、盒模型與拒絕邊界；沒有書名特判、削弱斷言、改量法或掩蓋失敗的 fallback。
- 回歸：28 類別／186 tests 全過，skipped 0；log `/tmp/S001-attempt3-verify-<class>.log`。
- 斷行：covered=458、skipped=0、stride=1；基線未變未重錄。
- 量測：`S001-attempt3-verify`，249／249；engine failed=0、unmeasured=0。

| Class | Passed |
|---|---:|
| BlockLayoutTests | 8 |
| BrowserAutoSupportedSubsetCorrectnessGateTests | 4 |
| BrowserFontDemandTests | 4 |
| BrowserLayoutCapabilityScannerTests | 31 |
| BrowserLayoutDeterminismTests | 4 |
| BrowserLayoutDocumentTests | 4 |
| BrowserLayoutFeatureTests | 1 |
| BrowserLayoutFontFallbackTests | 9 |
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
| BrowserVerticalReaderRouteTests | 2 |
| CSSLengthResolverTests | 2 |
| ComputedStyleTests | 2 |
| ComputedStyleTreeTests | 1 |
| CoreTextLineBreakerTests | 4 |
| CoreTextWritingModeTests | 26 |
| DisplayListTests | 1 |
| EPUBAutoRoutingTests | 4 |
| InlineLayoutTests | 2 |
| PageFragmentationTests | 1 |

## 工具完整比較表

# Fidelity comparison — S001-attempt3-verify against baseline-2026-09-30

COMPARE: PASS (249 of the base run's 249 chapters)

Left out: 56 chapters the legacy renderer drew in both runs (largest move 1.8); no slice reaches them.

| Book | Dev before | Dev after | Δ | Holdout before | Holdout after | Δ | All Δ | Browser chapters |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| ai-glossary | 72.0 | 97.7 | +25.6 | 80.4 | 97.9 | +17.5 | +22.6 | 0 → 16 |
| game-designer | 97.6 | 97.6 | +0.0 | 98.7 | 98.7 | +0.0 | +0.0 | 18 → 18 |
| georgia | — | — | — | — | — | — | — | 0 → 0 |
| guimi | 93.4 | 93.4 | +0.0 | 97.0 | 97.0 | +0.0 | +0.0 | 21 → 21 |
| hail-mary | 98.3 | 98.3 | +0.0 | 99.8 | 99.8 | +0.0 | +0.0 | 17 → 17 |
| harry-potter | 91.1 | 91.1 | +0.0 | — | — | — | +0.0 | 4 → 4 |
| hongwu | 93.9 | 93.9 | +0.0 | 92.5 | 92.5 | +0.0 | +0.0 | 14 → 14 |
| israelsailing | 92.9 | 92.9 | +0.0 | 98.5 | 98.5 | +0.0 | +0.0 | 12 → 12 |
| kusamakura | 67.3 | 67.3 | +0.0 | 67.7 | 67.7 | +0.0 | +0.0 | 13 → 13 |
| mahabharata | 79.8 | 79.8 | +0.0 | 76.4 | 76.4 | +0.0 | +0.0 | 16 → 16 |
| orv | 98.9 | 98.9 | +0.0 | 95.4 | 95.4 | +0.0 | +0.0 | 5 → 5 |
| quanzhi | 96.0 | 96.0 | +0.0 | 98.4 | 98.4 | +0.0 | +0.0 | 18 → 18 |
| redchamber | 89.8 | 89.8 | +0.0 | 93.6 | 93.6 | +0.0 | +0.0 | 18 → 18 |
| redchamber-vertical | 91.2 | 91.2 | +0.0 | — | — | — | +0.0 | 2 → 2 |
| sherlock | 96.8 | 96.8 | +0.0 | 95.8 | 95.8 | +0.0 | +0.0 | 16 → 16 |
| the-deal | 99.9 | 99.9 | +0.0 | 100.0 | 100.0 | +0.0 | +0.0 | 3 → 3 |

## Progress

- ai-glossary: 75.2 → 97.7
- ai-glossary: fallback reason 'media-queries' gone from 16 chapters, none lower

## Failures

- none

## Chapters that moved most

| Book | Spine | Set | Before | After | Δ | Route before → after |
|---|---:|---|---:|---:|---:|---|
| ai-glossary | 0 | dev | 4.0 | 100.0 | +96.0 | legacy: capability media-queries → browser |
| ai-glossary | 6 | holdout | 78.1 | 98.2 | +20.1 | legacy: capability media-queries → browser |
| ai-glossary | 8 | dev | 76.7 | 96.4 | +19.7 | legacy: capability media-queries → browser |
| ai-glossary | 3 | dev | 77.6 | 97.0 | +19.4 | legacy: capability media-queries → browser |
| ai-glossary | 9 | holdout | 78.0 | 97.1 | +19.0 | legacy: capability media-queries → browser |
| ai-glossary | 7 | dev | 78.6 | 97.6 | +19.0 | legacy: capability media-queries → browser |
| ai-glossary | 13 | dev | 78.8 | 97.4 | +18.6 | legacy: capability media-queries → browser |
| ai-glossary | 12 | dev | 79.2 | 97.2 | +18.1 | legacy: capability media-queries → browser |
| ai-glossary | 4 | holdout | 79.6 | 97.5 | +17.9 | legacy: capability media-queries → browser |
| ai-glossary | 2 | dev | 77.9 | 95.7 | +17.8 | legacy: capability media-queries → browser |
| ai-glossary | 5 | dev | 79.3 | 96.5 | +17.2 | legacy: capability media-queries → browser |
| ai-glossary | 14 | holdout | 81.7 | 98.2 | +16.4 | legacy: capability media-queries → browser |
| ai-glossary | 11 | holdout | 82.5 | 98.8 | +16.2 | legacy: capability media-queries → browser |
| ai-glossary | 15 | dev | 83.4 | 99.5 | +16.1 | legacy: capability media-queries → browser |
| ai-glossary | 1 | holdout | 82.5 | 97.5 | +15.1 | legacy: capability media-queries → browser |
| ai-glossary | 10 | dev | 84.9 | 99.3 | +14.4 | legacy: capability media-queries → browser |
| game-designer | 58 | dev | 79.9 | 80.5 | +0.6 | browser |

## 並排圖與升級理由

已讀 index 並看全部 16 個 ai-glossary 章節首圖。spine 3 標題恢復兩行，spine 8 標題分行與 WebKit 吻合。spine 15 卻缺少有序清單 1–6 編號：原文 [chapter-13.xhtml](/Users/zhangruilin/Library/Caches/YueduFidelity/corpus/ai-glossary/OEBPS/chapter-13.xhtml:6) 是 `<ol>` 包住六個 `<li>`。WebKit 與已接受 baseline 都看得到編號，Browser 候選看不到；第 2 次未接受候選也有此缺陷。

原圖：[WebKit](/Users/zhangruilin/Library/Caches/YueduFidelity/ref/ios27.0-32c823fa58959671/ai-glossary/15/tile-000.jpg)、[已接受基線](/Users/zhangruilin/Library/Caches/YueduFidelity/runs/baseline-2026-09-30/ai-glossary/15/tile-000.jpg)、[本輪候選](/Users/zhangruilin/Library/Caches/YueduFidelity/runs/S001-attempt3-verify/ai-glossary/15/tile-000.jpg)。

[fidelity-verify](/Users/zhangruilin/Desktop/Yuedu-fidelity-loop/Yuedu-reader/.agents/skills/fidelity-verify/SKILL.md) 規定「the score improves but the side-by-side looks worse」時為 ESCALATE_HUMAN。依第一個失敗即停止，未完成兩個控制章節的圖像關卡。標題修正已確認有效，S001 admission 尚不能接受。

## 下一步

保留候選，不提交；將清單 marker 缺失與三張比較圖記入待決定事項。續修清單需另行確認範圍，本輪完整量測額度已使用。
