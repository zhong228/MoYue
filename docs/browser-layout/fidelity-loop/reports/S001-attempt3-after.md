# Render fidelity — S001-attempt3-after

Generated 2026-10-01T20:03:51 · scorer v1 · reference `ios27.0-32c823fa58959671`

Measured: reader `~/Desktop/Yuedu-fidelity-loop/Yuedu-reader (loop/fidelity ce21cdfc + uncommitted changes)` · engine package `~/Desktop/Yuedu-fidelity-loop/YueduCoreText @ local (loop/fidelity d7e16bd + uncommitted changes)`

**Goal (every book ≥ 80): MET** — 3 of 3 books pass.

| Book | Score | Dev | Holdout | Layout | Visual | Lowest chapter | Chapters | Browser / Legacy | Below 60 (spine) | Unmeasured |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|---:|
| the-deal | **85.4** | 85.4 | — | 89.1 | 78.2 | 50.3 | 10 | 2 / 8 | 50 | 0 |
| game-designer | **95.8** | 95.8 | — | 97.7 | 94.0 | 74.3 | 13 | 12 / 1 | — | 0 |
| ai-glossary | **97.7** | 97.7 | — | 98.8 | 96.5 | 95.7 | 10 | 10 / 0 | — | 0 |

## Where the points go

Points are book-score points: what one book loses on average to each cause.

| Cause | Points |
|---|---:|
| paint:image | 2.08 |
| line-break | 1.81 |
| paint:other | 1.20 |
| block-gap | 0.47 |
| inline-size | 0.39 |
| paint:background | 0.35 |
| inline-start | 0.27 |
| line-count | 0.12 |
| image-missing | 0.07 |
| indent | 0.05 |

## Largest gaps by CSS context

| Cause | Context of the reference block | Points |
|---|---|---:|
| line-break | plain | 1.81 |
| block-gap | plain | 0.40 |
| inline-size | plain | 0.39 |
| inline-start | plain | 0.25 |
| line-count | plain | 0.12 |
| image-missing | plain | 0.07 |
| indent | plain | 0.05 |

## Engine route of the measured chapters

Browser engine: 24 chapters, mean 97.8. Legacy fallback: 9 chapters, mean 81.0.

A chapter falls back whole when the capability scanner finds any of these; one chapter can name several.

| Fallback reason | Chapters | Books | Mean score of those chapters |
|---|---:|---|---:|
| float | 8 | the-deal | 81.8 |
| flex-grid | 1 | game-designer | 74.3 |
| unknown-block-display | 1 | game-designer | 74.3 |
| positioned | 1 | game-designer | 74.3 |

| Route as reported | Chapters |
|---|---:|
| browser | 24 |
| legacy: capability float | 8 |
| legacy: capability positioned,unknown-block-display,flex-grid | 1 |
