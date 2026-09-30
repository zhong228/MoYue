---
name: fidelity-measure
description: Use when measuring how closely Yuedu's EPUB rendering matches WKWebView, reading a render-fidelity report, or comparing two fidelity runs. Not for changing the engine.
---

# Fidelity Measure

Produces the score the fidelity loop is judged by. The definition of the score is `docs/browser-layout/fidelity-loop/ORACLE.md`; do not restate or reinterpret it, and never edit anything it lists as frozen.

## Run

Resolve the loop paths from `docs/browser-layout/fidelity-loop/LOOP.md` ("在哪裡做"). Then:

```bash
# Inside the loop's reader worktree: the books a slice touches, dev chapters only
YUEDU_WORKSPACE=$LOOP/Loop.xcworkspace bash scripts/fidelity/measure.sh --run <id> --books <id>,<id>

# A few chapters while diagnosing
YUEDU_WORKSPACE=$LOOP/Loop.xcworkspace bash scripts/fidelity/measure.sh --run <id> --only <book>:<spine>,<spine>

# Re-score a finished capture without building
python3 scripts/fidelity/fidelity.py score --run <id> --verbose
```

`measure.sh` waits for any other `xcodebuild`, builds through `scripts/xctest.sh`, captures, and prints the report. The WebKit side is captured once and reused; a run re-renders only the reader's side. Exit 2 means a frozen oracle file changed: stop and report, do not repair it.

## Read the result

Everything lands in `~/Library/Caches/YueduFidelity/runs/<id>/`:

| File | Use |
|---|---|
| `report.md` | Book scores, where the points go, largest gaps by CSS context, engine route per chapter, anything not measured |
| `report.json` | The same, plus per-chapter `lost`, `context`, `paintLost` and `worstItems` (the paragraphs and images that cost the most) |
| `index.html` | Both renderings side by side, worst chapter first |
| `<book>/<spine>/dump.json` | The reader's geometry for one chapter; the WebKit one is under `ref/<refKey>/` |

Before acting on a number, open `index.html` for that chapter and confirm the difference the report names is the difference you can see. If they disagree, the oracle is wrong for that case: stop and write it under "等你決定" in `STATE.md`. Never adjust the engine to satisfy a number you cannot see.

## Compare two runs

```bash
python3 $MAIN/scripts/fidelity/fidelity.py compare --run <after> --base <before>
```

It prints each book's dev and holdout change over the chapters both runs measured, what counts as progress, what failed, and the chapters that moved most; exit 0 is `COMPARE: PASS`. A run that covers only some books is marked partial: useful while implementing, not a verdict. Then read the `lost` entries of the chapters the slice targeted in both `report.json` files to see which cause moved. Report both runs' ids with every number you quote; a score without its run id cannot be checked.

Chapters listed under "Not measured" are not passes. A chapter the reader failed to capture (side `engine`) fails its book; one the reference could not render (side `reference`) is left out of the book's score. Say how many of each there are, and quote the "Reference caveats" section when it is not empty.
