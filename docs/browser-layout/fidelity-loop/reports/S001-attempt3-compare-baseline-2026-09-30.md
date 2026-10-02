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
