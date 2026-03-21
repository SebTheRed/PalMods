# Fetch Item Dataset Generation Notes

Generated: 2026-03-20 21:40:58 -0400

## Sources
- Primary machine-readable source: https://paldb.cc/en/Items
- Secondary reference URL: https://palworld.wiki.gg/wiki/Items

## Locked Design Choices
- Fetch pool currently excludes crafted/processed outputs.
- Fetch pool excludes key/quest/blueprint/equipment and other non-fetchable categories.
- Trust is a rarity gate only; common remains dominant even at high trust.
- Requested quantity scales down by rarity: common 1-30, uncommon 1-7, rare+ 1-3.
- Duplicate display slugs are preserved with master_item_key disambiguation.

## Outputs
- Master items: 1973
- Eligible gatherable fetch items: 84
- Trust-band roll rows: 326

