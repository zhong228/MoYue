# S001 第一次嘗試：REJECT

日期：2026-10-01。這是未合入候選的紀錄，未更新記分板。

## 範圍與根因

- Reader 基底：`3066cd5c24a38d1750cee1ca24834eca1b53e1d8`。
- YueduCoreText 基底：`d7e16bd9aa64b80c4d0bc70fa0fc069409c34ea7`。
- 兩個 repo 都是 loop 工作副本的 `loop/fidelity`；只動候選規則與合成測試，共 3 檔。
- 能力掃描器看見任何 `@media` 就整章拒絕；CSSParser 原本已把深色規則分離，Browser frontend 的淺色 cascade 不套用它們。候選讓掃描器使用同一個 at-rule 解析邊界，只放行單獨深色查詢中的配色屬性；其他媒體條件、巢狀 at-rule、字級／margin／display／border 寬度等仍拒絕。
- CSS 依據：[Media Queries 5 §11.5](https://www.w3.org/TR/mediaqueries-5/#prefers-color-scheme)。淺色模式下 dark-only 規則不參與 cascade。WebKit 的 body 字級為 17px、左右 padding 1.3em = 22.1px；366px viewport 的正文寬度是 321.8px。標題字級 1.8em = 30.6px。修正前回退路徑的標題與圖片貼到左右邊緣，換行和目錄間距不同；本地並排圖 tiles 確認和扣分原因一致。
- 合成期望值來自 CSS 盒模型：300 - 2×10 padding - 2×2 border = 276px；20px × 1.5 = 30px 行高，配色維持淺色 cascade 的 RGB 值。新測試在基底的能力誤拒上失敗，候選版本兩個新測試通過。

## 實作方量測

固定 scorer v1；reference `ios27.0-32c823fa58959671`。全部使用 loop workspace、第二台模擬器 `C01C0272-859E-4465-BCEB-53C054C686BE`。

| 範圍 | Before run | Before | After run | After | 新引擎章節 |
|---|---|---:|---|---:|---|
| ai-glossary，10 個 dev | `baseline-2026-09-30` | 72.0 | `S001-after` | 97.3 | 0 → 10 |
| ai-glossary，兩 run 共同量到的 spine 3／8 | `S001-before` | 77.1 | `S001-after` | 96.4 | 0 → 2 |
| ai-glossary:3 | `S001-before` | 77.4 | `S001-after` | 97.6 | legacy → browser |
| ai-glossary:8 | `S001-before` | 76.9 | `S001-after` | 95.3 | legacy → browser |

- `S001-before` 另量 spine 1；三章平均 78.9。spine 1 未包含在 `S001-after` 的 dev 清單，沒有拿三章平均與十章平均直接相比。
- spine 3 的 line-break 扣分 11.03 → 0.63；spine 8 為 10.19 → 1.06（`S001-before` → `S001-after`）。
- `S001-after` 的 media-queries 回退原因消失；沒有分數下降的已比較章節。
- 兩次 compare 均 `COMPARE: PASS`，分別 partial 2/3 章、10/249 章，不能當作完整驗證。
- 本輪 before／after：閱讀器擷取失敗 0、對照組未量測 0、Reference caveats 0。
- 沒有重測其他書或 holdout。基線既有 Reference caveats：harry-potter 有 8 章「fonts still loading when the reference was measured」。

## 測試與關卡

| 執行者／版本 | 類別 | 數量 | 結果 |
|---|---|---:|---|
| 實作者，候選 | BrowserLayoutCapabilityScannerTests | 31 | 2 failures，兩個新增測試通過 |
| 驗證者，候選 | BrowserLayoutCapabilityScannerTests | 31 | 2 failures，兩個新增測試通過 |
| 實作者，還原後基底 | BrowserLayoutCapabilityScannerTests | 29 | 同樣 2 failures |

- 初次方法篩選空跑，0 tests，沒有當成驗證證據。完整類別的修正前失敗證據保存在 `/tmp/S001-red-class.log`。
- 候選最後版本：`/tmp/S001-scanner.log`。
- 驗證者：`/tmp/S001-verify-scanner.log`。
- 還原後基底：`/tmp/S001-base-scanner.log`。
- Oracle：`oracle lock ok (7 files, 2 trees)`；主工作目錄凍結檔案無變更。
- Gate：`GATE: PASS (3 files)`，無 note。驗證者讀過兩個 repo 的完整 diff。
- 因必跑 scanner 類別失敗，其他 always-run 類別尚未全數執行；驗證者依「第一項失敗即停止」未進入獨立完整量測與並排圖關卡。沒有 `S001-verify` 的完整分數。

## 驗證者判定：REJECT

1. `rejectsRubyOutsideSupportedSubset` 預期 `.ruby`，實際 unsupportedFeatures 為空（候選與基底第 113 行）。
2. `rejectsEffectiveUnsupportedTextIndent` 的 `-1px` 預期 `.textIndent`，實際 unsupportedFeatures 為空（候選第 308 行、基底第 251 行）。

驗證者指出：這些結果未證明失敗由 S001 引起，但必跑回歸未全數通過，因此不能批准切片。下一步先另案釐清既有測試與實際支援規則，不能為通關削弱斷言。

## 收尾

未 commit、未 push、未發版、未改量法或版本。候選 diff 保存在 `~/Desktop/Yuedu-fidelity-loop/S001-attempt-1-rejected.patch`，僅以編輯方式還原本輪三個檔案；兩個工作副本乾淨。S001 嘗試次數加為 1，留在佇列首位；記分板維持 `baseline-2026-09-30`，本輪停止。
