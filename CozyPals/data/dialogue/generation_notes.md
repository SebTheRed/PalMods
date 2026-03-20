# Dialogue Dataset Generation Notes

Generated: 2026-03-20 14:51:43 -0400

## Style Rewrite Goal
- Preserve flavor variance: genus, element, trust, sanity, personality, size, gender.
- Rewrite robotic phrasing into short conversational lines.
- Keep deterministic tagged selection with no runtime AI generation.
- Add fetch quest phases with explicit ask and thank-you triggers.
- Split fetch lines into dedicated files for easier authoring/review.
- Make trust + personality style affect all generated lines.

## Additional Style Polish (V1.7)
- Reduced repeated stock openers and outro phrases across all files.
- Replaced rigid phrasing with conversational alternatives using deterministic per-line variation.
- Preserved all tags, trigger routing, and trust/personality gating rules.

## Output
- Core dialogue lines: 3726
- Fetch request lines: 396
- Fetch thank-you lines: 396
- All lines total: 4518
