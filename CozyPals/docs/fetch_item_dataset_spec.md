# CozyPals Fetch Item Dataset Spec (V1, No Integration)

Last updated: 2026-03-20

## Goal
- Define a deterministic fetch quest item dataset with trust-gated rarity and rarity-based trust rewards.
- Keep the first pool gatherable-first and non-crafting.

## Source Scope
- Primary source snapshot: https://paldb.cc/en/Items
- Secondary reference URL: https://palworld.wiki.gg/wiki/Items
- Master source count from snapshot: 1973

## Files
- `CozyPals/data/dialogue/fetch_items_master.jsonl`
- `CozyPals/data/dialogue/fetch_item_draw_rules.json`
- `CozyPals/data/dialogue/fetch_item_roll_table_by_trust.jsonl`
- `CozyPals/data/dialogue/fetch_item_roll_summary.json`
- `CozyPals/data/dialogue/fetch_generation_notes.md`

## Record Shapes
- `fetch_items_master.jsonl`:
- `item_index, item_key, item_slug, item_name, item_url, rarity_value, rarity_tier, icon_group, icon_token, icon_src, description, fetch_eligible, exclusion_reasons, gatherable_kind, trust_points_reward, base_rarity_weight, quest_quantity_min, quest_quantity_max, source`
- `fetch_item_roll_table_by_trust.jsonl`:
- `trust_band, trust_min, trust_max, master_item_index, master_item_key, item_slug, item_name, rarity_tier, trust_points_reward, quest_quantity_min, quest_quantity_max, draw_weight, draw_probability, gatherable_kind`

## Trust And Rarity Rules (Locked)
- Trust points by rarity:
- `common=1, uncommon=2, rare=4, epic=7, legendary=12`
- Quest quantity by rarity:
- `common=1-30, uncommon=1-7, rare=1-3, epic=1-3, legendary=1-3`
- Low trust (`1-40`) asks only `common|uncommon`.
- Mid trust (`41-60`) can include `rare`.
- High trust (`61-80`) can include `epic`.
- Very high trust (`81-99`) can include `legendary`.
- Common remains dominant in all trust bands; trust acts as a gate, not a default rarity bias.

## Non-Crafting Filter
- Excludes key/quest/equipment/blueprint/strange placeholder items.
- Excludes crafted/processed outputs (e.g., cooked dishes, refined manufactured materials).
- Includes gatherable resources, pal drops, farm/forage ingredients, eggs, and raw loot resources.

## Current Pool Size
- Eligible fetch items: 84
