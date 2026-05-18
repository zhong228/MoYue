# Vertical Writing

Vertical EPUB/TXT pages use `ReaderWritingMode.verticalRTL`,
`kCTFrameProgressionAttributeName = rightToLeft`, and
`kCTVerticalFormsAttributeName = true`.

## Coordinate Rules

CoreText reuses horizontal API names, but vertical mode changes their axis
meaning:

| API value | Horizontal meaning | Vertical-rl meaning |
| --- | --- | --- |
| `CTLineGetOffsetForStringIndex` | x advance | inline advance from column top downward |
| `CTLineGetTypographicBounds width` | x extent | inline column length |
| `ascent` | above baseline | block-start/right extent |
| `descent` | below baseline | block-end/left extent |
| `lineOrigin.x` | line start x | column baseline x |
| `lineOrigin.y` | baseline y | column top y in CoreText coordinates |

When converting to UIKit coordinates:

- column top y = `layoutHeight - (contentPathRect.minY + lineOrigin.y)`
- vertical text advance from the top is `CTLineGetOffsetForStringIndex(...)`
- column x extents come from `baselineX - descent` and `baselineX + ascent`

## Punctuation and Latin Runs

`CoreTextPaginator.preparedAttributedString` applies vertical forms globally,
then removes vertical forms from non-CJK Latin/number/ASCII runs so strings like
`BookDNA`, `PDF`, `DNA-BN`, and `N00004905` stay sideways as one run.

Those sideways runs also receive:

- `kCTBaselineClassIdeographicCentered`
- a tuned `.baselineOffset` equal to half the font-derived centering offset

This avoids the common CoreText problem where synthetic vertical Latin glyphs
sit to one side of the CJK column center.

## Inline Images

For vertical run delegates:

- `getWidth` is the inline advance downward.
- `getAscent` / `getDescent` are block-direction x extents.
- inline image rect y is computed from the column top plus text advance.
- padding-left/right from CSS must not move the image away from the column
  center in x.

## Inline Annotation Spans

Vertical `.small*` spans are represented as custom annotation delegate runs. The
main CoreText frame reserves one column-width placeholder; `CoreTextPageView`
draws the annotation content manually after the frame is drawn.

Important details:

- Strip `.baselineOffset` and `.paragraphStyle` from annotation content before
  manual drawing.
- Use font `lineHeight` as the per-character advance, not raw `pointSize`, to
  avoid clipping small red note glyphs.
- Split oversized annotation delegate runs in `CoreTextPaginator` so a long note
  can paginate instead of becoming an impossible single run.
