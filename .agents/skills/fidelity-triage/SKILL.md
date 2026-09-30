---
name: fidelity-triage
description: Use when turning a render-fidelity report into the ordered work queue in docs/browser-layout/fidelity-loop/STATE.md, or when that queue is empty or stale. Produces slices; does not change code.
---

# Fidelity Triage

Turns the latest full report into a short, ordered list of slices. Signal only: no fixes, no architecture proposals beyond naming the capability a slice needs.

## Inputs

- The latest full run's `report.json` (all books, dev chapters; see the `fidelity-measure` skill).
- `STATE.md` in the main checkout's `docs/browser-layout/fidelity-loop/` (`$MAIN`; see `LOOP.md`, "在哪裡做") as it stands: keep attempts, decisions and everything under "等你決定". The copy inside a loop worktree is stale; never read or write that one.
- `docs/browser-layout/STATUS.md` and `PHASES.md` §5 and §8 for what is already built, deferred or decided. Do not re-open a finished capability or contradict a recorded decision.

## How to cut slices

1. Start from the books below 80, lowest first, then from `gaps` (points lost by cause and CSS context).
2. Group by root cause, not by book. A cause that appears in several books is one slice. A cause that appears in one chapter of one book goes last unless that book cannot pass without it.
3. One slice is one CSS or HTML rule, or one defect, small enough for one reviewable change (at most 12 files). A missing layout mode (table, flex, grid, positioned, bidirectional text, media-query evaluation) is a design note plus several slices, each independently verifiable.
4. For chapters on `legacy: capability …`, the slice is the smallest engine capability that lets the scanner admit them, not a change to the legacy renderer.
5. Separate what the oracle cannot see well from real defects (`ORACLE.md`, "它看不到的東西"). A loss caused by an oracle limit is not a slice; list it under "雜訊".

## Order

Rank by expected gain in book-score points across the corpus, then by how many failing books it helps, then by risk (smaller and better-tested areas first). Put anything that needs a product decision under "等你決定" with 2–4 options and a recommendation, not in the queue.

## Write to STATE.md

Replace only the "佇列" and "雜訊" sections; leave the rest intact. Each queue entry:

```markdown
### S0NN — <the rule or defect, one line>
- 依據：<cause> × <context>，約 <points> 分；影響 <books>
- 代表章節：<book>:<spine>, <book>:<spine>
- 假設的根因：<which layer, in CSS terms — marked as a hypothesis until reproduced>
- 完成的樣子：<what the report should show afterwards>
- 嘗試：0
```

Number slices in the order created and never reuse a number. Keep the queue to the next ten; more than that is a plan nobody will read.
