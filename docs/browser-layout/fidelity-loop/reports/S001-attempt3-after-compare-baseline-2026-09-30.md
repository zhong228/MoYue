# Fidelity comparison — S001-attempt3-after against baseline-2026-09-30

COMPARE: PASS (33 of the base run's 249 chapters — partial: not a verdict on the whole corpus)

Left out: 9 chapters the legacy renderer drew in both runs (largest move 0.1); no slice reaches them.

| Book | Dev before | Dev after | Δ | Holdout before | Holdout after | Δ | All Δ | Browser chapters |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| ai-glossary | 72.0 | 97.7 | +25.6 | — | — | — | +25.6 | 0 → 10 |
| game-designer | 97.6 | 97.6 | +0.0 | — | — | — | +0.0 | 12 → 12 |
| the-deal | 99.9 | 99.9 | +0.0 | — | — | — | +0.0 | 2 → 2 |

## Progress

- ai-glossary: 72.0 → 97.7
- ai-glossary: fallback reason 'media-queries' gone from 10 chapters, none lower

## Failures

- none

## Chapters that moved most

| Book | Spine | Set | Before | After | Δ | Route before → after |
|---|---:|---|---:|---:|---:|---|
| ai-glossary | 0 | dev | 4.0 | 100.0 | +96.0 | legacy: capability media-queries → browser |
| ai-glossary | 8 | dev | 76.7 | 96.4 | +19.7 | legacy: capability media-queries → browser |
| ai-glossary | 3 | dev | 77.6 | 97.0 | +19.4 | legacy: capability media-queries → browser |
| ai-glossary | 7 | dev | 78.6 | 97.6 | +19.0 | legacy: capability media-queries → browser |
| ai-glossary | 13 | dev | 78.8 | 97.4 | +18.6 | legacy: capability media-queries → browser |
| ai-glossary | 12 | dev | 79.2 | 97.2 | +18.1 | legacy: capability media-queries → browser |
| ai-glossary | 2 | dev | 77.9 | 95.7 | +17.8 | legacy: capability media-queries → browser |
| ai-glossary | 5 | dev | 79.3 | 96.5 | +17.2 | legacy: capability media-queries → browser |
| ai-glossary | 15 | dev | 83.4 | 99.5 | +16.1 | legacy: capability media-queries → browser |
| ai-glossary | 10 | dev | 84.9 | 99.3 | +14.4 | legacy: capability media-queries → browser |
| game-designer | 58 | dev | 79.9 | 80.5 | +0.6 | browser |
