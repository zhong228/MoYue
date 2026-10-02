# Render fidelity — S001-attempt2-verify

Generated 2026-10-01T16:27:22 · scorer v1 · reference `ios27.0-32c823fa58959671`

Measured: reader `~/Desktop/Yuedu-fidelity-loop/Yuedu-reader (loop/fidelity df002297 + uncommitted changes)` · engine package `~/Desktop/Yuedu-fidelity-loop/YueduCoreText @ local (loop/fidelity d7e16bd + uncommitted changes)`

**Goal (every book ≥ 80): not met** — 12 of 16 books pass.

| Book | Score | Dev | Holdout | Layout | Visual | Lowest chapter | Chapters | Browser / Legacy | Below 60 (spine) | Unmeasured |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|---:|
| georgia ✗ | **58.3** | 58.3 | — | 54.9 | 66.4 | 58.3 | 1 | 0 / 1 | 0 | 0 |
| kusamakura ✗ | **65.0** | 63.7 | 67.7 | 60.6 | 69.4 | 41.4 | 15 | 13 / 2 | 0, 14 | 0 |
| redchamber-vertical ✗ | **76.5** | 77.6 | 74.6 | 72.5 | 81.5 | 64.0 | 16 | 2 / 14 | — | 0 |
| mahabharata ✗ | **78.5** | 79.8 | 76.4 | 77.9 | 97.0 | 74.3 | 16 | 16 / 0 | — | 0 |
| orv | **86.7** | 87.6 | 84.6 | 85.2 | 88.1 | 74.6 | 16 | 5 / 11 | — | 0 |
| the-deal | **86.7** | 85.4 | 88.8 | 89.4 | 79.5 | 50.3 | 16 | 3 / 13 | 50 | 0 |
| hongwu | **88.3** | 85.9 | 92.5 | 88.7 | 87.6 | 21.7 | 16 | 14 / 2 | 43 | 0 |
| harry-potter | **88.9** | 90.6 | 86.2 | 88.9 | 89.3 | 65.6 | 16 | 4 / 12 | — | 0 |
| redchamber | **91.1** | 89.8 | 93.6 | 96.2 | 86.0 | 81.3 | 18 | 18 / 0 | — | 0 |
| israelsailing | **93.8** | 92.9 | 98.5 | 97.1 | 90.3 | 44.8 | 12 | 12 / 0 | 1 | 0 |
| guimi | **94.5** | 93.4 | 97.0 | 96.9 | 92.1 | 84.5 | 21 | 21 / 0 | — | 0 |
| sherlock | **96.4** | 96.8 | 95.8 | 97.3 | 97.0 | 86.6 | 16 | 16 / 0 | — | 0 |
| game-designer | **96.6** | 95.7 | 98.7 | 98.3 | 94.9 | 72.8 | 19 | 18 / 1 | — | 0 |
| quanzhi | **96.8** | 96.0 | 98.4 | 98.4 | 95.1 | 79.2 | 18 | 18 / 0 | — | 0 |
| ai-glossary | **97.4** | 97.3 | 97.4 | 98.3 | 96.4 | 95.1 | 16 | 16 / 0 | — | 0 |
| hail-mary | **98.8** | 98.3 | 99.8 | 99.5 | 97.2 | 85.7 | 17 | 17 / 0 | — | 0 |

## Where the points go

Points are book-score points: what one book loses on average to each cause.

| Cause | Points |
|---|---:|
| paint:other | 2.85 |
| line-break | 2.24 |
| paint:image | 1.58 |
| block-gap | 1.45 |
| missing-text | 1.10 |
| inline-start | 0.85 |
| inline-size | 0.72 |
| line-count | 0.55 |
| paint:background | 0.36 |
| line-pitch | 0.29 |
| paint:border | 0.22 |
| font-size | 0.19 |
| extra-text | 0.15 |
| alignment | 0.09 |
| indent | 0.08 |
| image-missing | 0.05 |

## Largest gaps by CSS context

| Cause | Context of the reference block | Points |
|---|---|---:|
| line-break | plain | 2.21 |
| block-gap | plain | 1.40 |
| missing-text | table | 0.89 |
| inline-start | plain | 0.81 |
| inline-size | plain | 0.71 |
| line-count | plain | 0.55 |
| line-pitch | plain | 0.29 |
| missing-text | plain | 0.21 |
| font-size | plain | 0.18 |
| extra-text | plain | 0.15 |
| alignment | plain | 0.08 |
| indent | plain | 0.06 |

## Engine route of the measured chapters

Browser engine: 193 chapters, mean 92.3. Legacy fallback: 56 chapters, mean 78.9.

A chapter falls back whole when the capability scanner finds any of these; one chapter can name several.

| Fallback reason | Chapters | Books | Mean score of those chapters |
|---|---:|---|---:|
| float | 26 | harry-potter, orv, the-deal | 85.4 |
| vertical-writing-mode | 16 | kusamakura, redchamber-vertical | 71.2 |
| unknown-block-display | 13 | game-designer, hongwu, orv | 77.0 |
| table | 12 | georgia, hongwu, orv | 75.3 |
| flex-grid | 11 | game-designer, orv | 81.2 |
| positioned | 1 | game-designer | 72.8 |

| Route as reported | Chapters |
|---|---:|
| browser | 193 |
| legacy: capability float | 26 |
| legacy: capability vertical-writing-mode | 16 |
| legacy: capability table,unknown-block-display,flex-grid | 9 |
| legacy: capability table,unknown-block-display | 2 |
| legacy: capability positioned,unknown-block-display,flex-grid | 1 |
| legacy: capability table | 1 |
| legacy: capability unknown-block-display,flex-grid | 1 |

## Reference caveats

| Book | Chapters | Caveat |
|---|---:|---|
| harry-potter | 8 | fonts still loading when the reference was measured |
