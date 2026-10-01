---
name: fidelity-fix
description: Use when implementing one slice from docs/browser-layout/fidelity-loop/STATE.md in the BrowserLayout engine to bring Yuedu's EPUB rendering closer to WKWebView.
---

# Fidelity Fix

Implements exactly one slice, in the loop's worktrees, and hands it to the verifier. The queue it comes from is `STATE.md` in the main checkout's `docs/browser-layout/fidelity-loop/`, not the stale copy inside the worktree. The cycle, paths, thresholds and commit format are in `docs/browser-layout/fidelity-loop/LOOP.md`; this skill is the part about doing the change well.

## Before writing code

1. Reproduce. Measure the slice's representative chapters (`fidelity-measure`) and open the side-by-side page. State the visible difference in one sentence.
2. Explain WebKit's result from the CSS specification: which property, which value after the cascade, which used value, which box. WebKit's computed values are in the reference `dump.json` (`blocks`); the reader's geometry is in the run's `dump.json`.
3. Find the earliest layer where the reader diverges: parsing, cascade, computed style, used values, box tree, inline layout, fragmentation, paint. Fix it there. A later layer compensating for an earlier one is a fallback.
4. Write a failing synthetic test in the package or `Tests/iOS/yuedu appTests/`. Derive every expected number from the CSS rule and the box model, and say how in a comment. An expectation copied from current output proves nothing.

## The change

- A general HTML/CSS rule. No condition on a book, author, class name, file name, image name or chapter index: those are inputs to reproduce with, never inputs to the engine.
- One implementation path. If the rule already exists for the legacy renderer or the other frontend, share the semantics (`ResolvedStyle` / `RenderStyle` / `ComputedStyle` must agree) instead of adding a parallel parser, cache or branch.
- No fallback, retry, delay or `try?` that hides a failure. An unsupported sub-case is reported by the capability scanner so the chapter falls back whole; it is never laid out approximately.
- Admit a capability in `BrowserLayoutCapabilityScanner` only in the change that implements and tests its layout.
- Smallest diff that is correct. No drive-by cleanup, renaming or reformatting.
- Stay inside what the gate allows (`fidelity.py gate`): the package sources and tests, the reader's `BrowserLayout/` adapters, reader tests. Anything else, including the legacy renderer, recorded baselines and the oracle, is not yours to change in a slice. The one exception is the Red Chamber line-break baseline, which a slice re-records only when its rule is meant to move line breaks (`LOOP.md`, "斷行基線").

## Before handing over

- The new test fails without the change and passes with it.
- The regression classes for the area, and the always-run set, pass (`LOOP.md`, "回歸測試"). Report each class with its test count.
- The line-break baseline passes, run with `-testLanguage zh-Hant -testRegion TW` (`LOOP.md`, "斷行基線"). If it fails and the slice is not meant to move line breaks, that is a regression to fix. If the slice is meant to, re-record it and put in the report the number of changed chapters, every changed spine, and three chapters with the CSS or HTML in them that the rule applies to.
- Re-measure the affected books. The targeted loss went down; nothing else got worse.
- `python3 $MAIN/scripts/fidelity/fidelity.py gate …` prints `GATE: PASS`.

Then call the `fidelity-verifier` subagent with: the slice id and one-line description, both repositories' base commits, and the commands you ran with their results. Do not commit, and do not describe the slice as done, before it answers `APPROVE`.

## When it does not work

If the measured loss does not move, the hypothesis was wrong: go back to step 2 rather than adding a second change on top. Undo your own edits by editing them back; never `git checkout --`, `git restore` or `git reset --hard`. After a `REJECT`, address the stated reasons specifically; the third rejection parks the slice for a person.
