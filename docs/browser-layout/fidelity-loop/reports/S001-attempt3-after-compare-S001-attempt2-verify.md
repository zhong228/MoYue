# Fidelity comparison — S001-attempt3-after against S001-attempt2-verify

COMPARE: PASS (33 of the base run's 249 chapters — partial: not a verdict on the whole corpus)

Left out: 9 chapters the legacy renderer drew in both runs (largest move 1.5); no slice reaches them.

| Book | Dev before | Dev after | Δ | Holdout before | Holdout after | Δ | All Δ | Browser chapters |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| ai-glossary | 97.3 | 97.7 | +0.3 | — | — | — | +0.3 | 10 → 10 |
| game-designer | 97.6 | 97.6 | +0.0 | — | — | — | +0.0 | 12 → 12 |
| the-deal | 99.9 | 99.9 | +0.0 | — | — | — | +0.0 | 2 → 2 |

## Progress

- ai-glossary: 97.3 → 97.7

## Failures

- none

## Chapters that moved most

| Book | Spine | Set | Before | After | Δ | Route before → after |
|---|---:|---|---:|---:|---:|---|
| ai-glossary | 8 | dev | 95.3 | 96.4 | +1.1 | browser |
| ai-glossary | 7 | dev | 96.7 | 97.6 | +0.9 | browser |
| ai-glossary | 2 | dev | 95.1 | 95.7 | +0.6 | browser |
| game-designer | 58 | dev | 79.9 | 80.5 | +0.6 | browser |
| ai-glossary | 3 | dev | 97.6 | 97.0 | -0.6 | browser |
| ai-glossary | 10 | dev | 99.0 | 99.3 | +0.4 | browser |
| ai-glossary | 12 | dev | 96.9 | 97.2 | +0.3 | browser |
| ai-glossary | 13 | dev | 97.1 | 97.4 | +0.3 | browser |
| ai-glossary | 15 | dev | 99.3 | 99.5 | +0.2 | browser |
| ai-glossary | 5 | dev | 96.3 | 96.5 | +0.2 | browser |
