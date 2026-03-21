from __future__ import annotations

import html
import json
import re
import urllib.request
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path('CozyPals/data/dialogue')
MASTER_JSONL = ROOT / 'fetch_items_master.jsonl'
ROLL_JSONL = ROOT / 'fetch_item_roll_table_by_trust.jsonl'
RULES_JSON = ROOT / 'fetch_item_draw_rules.json'
SUMMARY_JSON = ROOT / 'fetch_item_roll_summary.json'
NOTES_MD = ROOT / 'fetch_generation_notes.md'
INDEX_JSON = ROOT / 'dialogue_index.json'
DOC_SPEC = Path('CozyPals/docs/fetch_item_dataset_spec.md')

SOURCE_URLS = {
    'paldb_items': 'https://paldb.cc/en/Items',
    'wiki_items_reference': 'https://palworld.wiki.gg/wiki/Items',
}

TRUST_BANDS = [
    {'id': 'trust_01_20', 'min': 1, 'max': 20},
    {'id': 'trust_21_40', 'min': 21, 'max': 40},
    {'id': 'trust_41_60', 'min': 41, 'max': 60},
    {'id': 'trust_61_80', 'min': 61, 'max': 80},
    {'id': 'trust_81_99', 'min': 81, 'max': 99},
]

RARITY_BY_VALUE = {
    0: 'common',
    1: 'uncommon',
    2: 'rare',
    3: 'epic',
    4: 'legendary',
    99: 'special',
}

RARITY_TRUST_POINTS = {
    'common': 1,
    'uncommon': 2,
    'rare': 4,
    'epic': 7,
    'legendary': 12,
    'special': 0,
}

BASE_RARITY_WEIGHT = {
    'common': 100.0,
    'uncommon': 70.0,
    'rare': 45.0,
    'epic': 30.0,
    'legendary': 18.0,
    'special': 0.0,
}

QUEST_QUANTITY_RANGE_BY_RARITY = {
    'common': {'min': 1, 'max': 30},
    'uncommon': {'min': 1, 'max': 7},
    'rare': {'min': 1, 'max': 3},
    'epic': {'min': 1, 'max': 3},
    'legendary': {'min': 1, 'max': 3},
    'special': {'min': 0, 'max': 0},
}

# Trust as gate, not default bias. Common remains the dominant request class even at high trust.
TRUST_RARITY_MULTIPLIER = {
    'trust_01_20': {'common': 1.00, 'uncommon': 0.45, 'rare': 0.00, 'epic': 0.00, 'legendary': 0.00, 'special': 0.00},
    'trust_21_40': {'common': 1.00, 'uncommon': 0.55, 'rare': 0.00, 'epic': 0.00, 'legendary': 0.00, 'special': 0.00},
    'trust_41_60': {'common': 1.00, 'uncommon': 0.65, 'rare': 0.35, 'epic': 0.00, 'legendary': 0.00, 'special': 0.00},
    'trust_61_80': {'common': 1.00, 'uncommon': 0.75, 'rare': 0.55, 'epic': 0.30, 'legendary': 0.00, 'special': 0.00},
    'trust_81_99': {'common': 1.00, 'uncommon': 0.90, 'rare': 0.75, 'epic': 0.55, 'legendary': 0.35, 'special': 0.00},
}

ALLOWED_ICON_GROUPS = {'Material', 'Food', 'food'}

BLOCK_RE = re.compile(
    r'(token|schematic|blueprint|saddle|harness|ticket|manual|effigy|emblem|costume|quest|bounty|dummy|npc|test|converter|'
    r'sphere|glider|armor|helm|helmet|weapon|ammo|bow|rifle|sword|katana|shotgun|spear|launcher|pistol|baton|grenade|'
    r'mine|trap|rod|coin|implant|module|relic|jewelry|necklace|pendant|ring|crown|goggles|hat|boots|gloves|medal|'
    r'certificate|halloween)',
    re.IGNORECASE,
)

GATHERABLE_SIGNAL_RE = re.compile(
    r'(berry|berries|wheat|tomato|lettuce|mushroom|honey|milk|egg|meat|fish|kelpsea|dumud|ore|coal|sulfur|quartz|stone|'
    r'wood|fiber|paldium|crude\s*oil|pal\s*oil|ancient\s*civilization\s*(parts|core)|pal\s*fluid|fluid|horn|bone|claw|'
    r'fang|pelt|wool|leather|hide|organ|flower|ruby|sapphire|emerald|diamond|dragon\s*stone|precious|predator\s*core)',
    re.IGNORECASE,
)

# Excludes cooked/refined/crafted outputs for the initial gatherable-focused quest pool.
CRAFTED_RE = re.compile(
    r'(baked|fried|grilled|stew|roast|saute|saute|burger|gyoza|fries|salad|soup|chowder|pizza|sandwich|cake|jam|bread|'
    r'skewer|noodle|pasta|pie|pudding|sundae|latte|tea|coffee|med\b|medicine|medical|juice|wiping|mind\s*control|'
    r'gunpowder|ingot|cloth|nail|circuit|board|polymer|cement|pal\s*metal|alloy|plasteel|processed|refined|kit|'
    r'hot\s+milk|marinated|nikujaga|quiche|bacon|omelet|omelette|toast|pickled|stir[-\s]?fried|charcoal)',
    re.IGNORECASE,
)

INTERNALISH_NAME_RE = re.compile(r'\b[A-Za-z]+\d+\b')


@dataclass
class ItemRecord:
    item_index: int
    item_key: str
    item_slug: str
    item_name: str
    item_url: str
    rarity_value: int
    rarity_tier: str
    icon_src: str
    icon_token: str
    icon_group: str
    description: str
    source: str
    fetch_eligible: bool
    exclusion_reasons: list[str]
    gatherable_kind: str
    trust_points_reward: int
    base_rarity_weight: float
    quest_quantity_min: int
    quest_quantity_max: int


def fetch_html(url: str) -> str:
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req, timeout=45) as response:
        return response.read().decode('utf-8', 'ignore')


def clean_text(raw: str) -> str:
    txt = re.sub(r'<[^>]+>', ' ', raw)
    txt = html.unescape(txt)
    txt = re.sub(r'\s+', ' ', txt).strip()
    return txt


def parse_items(html_doc: str) -> list[ItemRecord]:
    cards = html_doc.split('<div class="col"><div class="d-flex border rounded">')[1:]
    out: list[ItemRecord] = []

    for i, card in enumerate(cards, start=1):
        img_match = re.search(
            r'<img[^>]*src="([^"]+)"[^>]*class="([^"]*bg_rarity(\d+)[^"]*)"[^>]*>',
            card,
            re.IGNORECASE,
        )
        name_match = re.search(
            r'<a class="itemname"[^>]*href="([^"]+)"[^>]*>([^<]+)</a>',
            card,
            re.IGNORECASE,
        )

        if not img_match or not name_match:
            continue

        icon_src = img_match.group(1)
        rarity_value = int(img_match.group(3))
        rarity_tier = RARITY_BY_VALUE.get(rarity_value, 'special')

        item_slug = name_match.group(1).strip()
        item_name = clean_text(name_match.group(2))

        desc_match = re.search(r'</a><div>(.*?)</div>', card, re.IGNORECASE | re.DOTALL)
        description = clean_text(desc_match.group(1)) if desc_match else ''

        icon_token_match = re.search(r'/T_itemicon_([^"\.]+)\.webp', icon_src, re.IGNORECASE)
        icon_token = icon_token_match.group(1) if icon_token_match else ''
        icon_group = icon_token.split('_')[0] if icon_token else 'UNKNOWN'

        fetch_eligible, exclusion_reasons = classify_fetch_eligibility(
            item_name=item_name,
            item_slug=item_slug,
            description=description,
            rarity_tier=rarity_tier,
            icon_group=icon_group,
        )

        gatherable_kind = infer_gatherable_kind(item_name, item_slug)
        quest_quantity_min, quest_quantity_max = quantity_range_for_rarity(rarity_tier)

        out.append(
            ItemRecord(
                item_index=i,
                item_key=f'{item_slug}__{i}',
                item_slug=item_slug,
                item_name=item_name,
                item_url=f'https://paldb.cc/en/{item_slug}',
                rarity_value=rarity_value,
                rarity_tier=rarity_tier,
                icon_src=icon_src,
                icon_token=icon_token,
                icon_group=icon_group,
                description=description,
                source='paldb:Items',
                fetch_eligible=fetch_eligible,
                exclusion_reasons=exclusion_reasons,
                gatherable_kind=gatherable_kind,
                trust_points_reward=RARITY_TRUST_POINTS[rarity_tier],
                base_rarity_weight=BASE_RARITY_WEIGHT[rarity_tier],
                quest_quantity_min=quest_quantity_min,
                quest_quantity_max=quest_quantity_max,
            )
        )

    return out


def classify_fetch_eligibility(
    item_name: str,
    item_slug: str,
    description: str,
    rarity_tier: str,
    icon_group: str,
) -> tuple[bool, list[str]]:
    reasons: list[str] = []
    text = f'{item_name} {item_slug.replace("_", " ")} {description}'.lower()

    if rarity_tier == 'special':
        reasons.append('special_rarity')

    if icon_group not in ALLOWED_ICON_GROUPS:
        reasons.append(f'icon_group:{icon_group}')

    if BLOCK_RE.search(text):
        reasons.append('blocked_keyword')

    if CRAFTED_RE.search(text):
        reasons.append('crafted_or_processed')

    if not GATHERABLE_SIGNAL_RE.search(text):
        reasons.append('no_gatherable_signal')

    if INTERNALISH_NAME_RE.search(item_name):
        reasons.append('internal_placeholder_name')

    return (len(reasons) == 0), reasons


def infer_gatherable_kind(item_name: str, item_slug: str) -> str:
    text = f'{item_name} {item_slug.replace("_", " ")}'.lower()
    if re.search(r'(ore|coal|sulfur|quartz|stone|paldium|ruby|sapphire|emerald|diamond|crude\s*oil|dragon\s*stone)', text):
        return 'node_resource'
    if re.search(r'(berry|wheat|tomato|lettuce|mushroom|flower|honey|seed)', text):
        return 'forage_or_farm'
    if re.search(r'(egg|milk|meat|fish|wool|leather|hide|bone|claw|fang|horn|organ|fluid|pelt|pal\s*oil|ancient\s*civilization|predator\s*core)', text):
        return 'pal_drop_or_loot'
    return 'gatherable_misc'


def quantity_range_for_rarity(rarity_tier: str) -> tuple[int, int]:
    quantity = QUEST_QUANTITY_RANGE_BY_RARITY.get(rarity_tier, {'min': 1, 'max': 1})
    return int(quantity['min']), int(quantity['max'])


def build_roll_table(items: list[ItemRecord]) -> tuple[list[dict], dict]:
    eligible_items = [it for it in items if it.fetch_eligible]

    rows: list[dict] = []
    summary = {
        'trust_bands': {},
        'eligible_items_total': len(eligible_items),
        'eligible_items_total_pre_dedupe': len(eligible_items),
        'dedupe_policy': 'none',
        'eligible_by_rarity': {},
        'quantity_range_by_rarity': QUEST_QUANTITY_RANGE_BY_RARITY,
    }

    rarity_counter = Counter(it.rarity_tier for it in eligible_items)
    summary['eligible_by_rarity'] = dict(sorted(rarity_counter.items()))

    for band in TRUST_BANDS:
        band_id = band['id']
        multipliers = TRUST_RARITY_MULTIPLIER[band_id]

        weighted = []
        for item in eligible_items:
            mult = multipliers.get(item.rarity_tier, 0.0)
            weight = item.base_rarity_weight * mult
            if weight <= 0:
                continue
            weighted.append((item, weight))

        total_weight = sum(w for _, w in weighted)

        band_rarity_weight = defaultdict(float)
        band_rarity_prob = defaultdict(float)

        for item, weight in weighted:
            prob = (weight / total_weight) if total_weight > 0 else 0.0
            band_rarity_weight[item.rarity_tier] += weight
            band_rarity_prob[item.rarity_tier] += prob
            rows.append(
                {
                    'trust_band': band_id,
                    'trust_min': band['min'],
                    'trust_max': band['max'],
                    'master_item_index': item.item_index,
                    'master_item_key': item.item_key,
                    'item_slug': item.item_slug,
                    'item_name': item.item_name,
                    'rarity_tier': item.rarity_tier,
                    'trust_points_reward': item.trust_points_reward,
                    'quest_quantity_min': item.quest_quantity_min,
                    'quest_quantity_max': item.quest_quantity_max,
                    'draw_weight': round(weight, 6),
                    'draw_probability': round(prob, 10),
                    'gatherable_kind': item.gatherable_kind,
                }
            )

        summary['trust_bands'][band_id] = {
            'trust_min': band['min'],
            'trust_max': band['max'],
            'item_count_in_band': len(weighted),
            'total_weight': round(total_weight, 6),
            'rarity_weight_totals': {k: round(v, 6) for k, v in sorted(band_rarity_weight.items())},
            'rarity_probability_share': {k: round(v, 10) for k, v in sorted(band_rarity_prob.items())},
            'allowed_rarities': [k for k, v in sorted(band_rarity_weight.items()) if v > 0],
        }

    return rows, summary


def write_jsonl(path: Path, rows: list[dict]) -> None:
    with path.open('w', encoding='utf-8', newline='\n') as f:
        for row in rows:
            f.write(json.dumps(row, ensure_ascii=False, separators=(',', ':')) + '\n')


def main() -> None:
    ROOT.mkdir(parents=True, exist_ok=True)

    html_doc = fetch_html(SOURCE_URLS['paldb_items'])
    items = parse_items(html_doc)

    master_rows = [
        {
            'item_index': it.item_index,
            'item_key': it.item_key,
            'item_slug': it.item_slug,
            'item_name': it.item_name,
            'item_url': it.item_url,
            'rarity_value': it.rarity_value,
            'rarity_tier': it.rarity_tier,
            'icon_group': it.icon_group,
            'icon_token': it.icon_token,
            'icon_src': it.icon_src,
            'description': it.description,
            'fetch_eligible': it.fetch_eligible,
            'exclusion_reasons': it.exclusion_reasons,
            'gatherable_kind': it.gatherable_kind,
            'trust_points_reward': it.trust_points_reward,
            'base_rarity_weight': it.base_rarity_weight,
            'quest_quantity_min': it.quest_quantity_min,
            'quest_quantity_max': it.quest_quantity_max,
            'source': it.source,
        }
        for it in items
    ]
    write_jsonl(MASTER_JSONL, master_rows)

    roll_rows, roll_summary = build_roll_table(items)
    write_jsonl(ROLL_JSONL, roll_rows)

    rules = {
        'version': 1,
        'generated_at_utc': datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace('+00:00', 'Z'),
        'sources': SOURCE_URLS,
        'non_crafting_focus': True,
        'notes': [
            'Master file includes all parsed items from source snapshot.',
            'Fetch pool is restricted to gatherable and non-crafted items.',
            'Trust gates rarity availability; common remains dominant at all trust levels.',
            'Requested quantity shrinks as rarity rises: common 1-30, uncommon 1-7, rare+ 1-3.',
        ],
        'trust_points_by_rarity': RARITY_TRUST_POINTS,
        'base_rarity_weight': BASE_RARITY_WEIGHT,
        'quest_quantity_range_by_rarity': QUEST_QUANTITY_RANGE_BY_RARITY,
        'trust_rarity_multiplier': TRUST_RARITY_MULTIPLIER,
        'allowed_icon_groups_for_fetch': sorted(ALLOWED_ICON_GROUPS),
        'filters': {
            'blocked_keyword_regex': BLOCK_RE.pattern,
            'crafted_regex': CRAFTED_RE.pattern,
            'gatherable_signal_regex': GATHERABLE_SIGNAL_RE.pattern,
            'internal_placeholder_name_regex': INTERNALISH_NAME_RE.pattern,
        },
        'trust_band_gates': {
            band['id']: {
                'trust_min': band['min'],
                'trust_max': band['max'],
                'allowed_rarities': [
                    rarity
                    for rarity, mult in TRUST_RARITY_MULTIPLIER[band['id']].items()
                    if mult > 0 and rarity != 'special'
                ],
            }
            for band in TRUST_BANDS
        },
    }
    RULES_JSON.write_text(json.dumps(rules, ensure_ascii=False, indent=4) + '\n', encoding='utf-8')

    SUMMARY_JSON.write_text(json.dumps(roll_summary, ensure_ascii=False, indent=4) + '\n', encoding='utf-8')

    notes = []
    notes.append('# Fetch Item Dataset Generation Notes')
    notes.append('')
    notes.append(f"Generated: {datetime.now().astimezone().strftime('%Y-%m-%d %H:%M:%S %z')}")
    notes.append('')
    notes.append('## Sources')
    notes.append(f"- Primary machine-readable source: {SOURCE_URLS['paldb_items']}")
    notes.append(f"- Secondary reference URL: {SOURCE_URLS['wiki_items_reference']}")
    notes.append('')
    notes.append('## Locked Design Choices')
    notes.append('- Fetch pool currently excludes crafted/processed outputs.')
    notes.append('- Fetch pool excludes key/quest/blueprint/equipment and other non-fetchable categories.')
    notes.append('- Trust is a rarity gate only; common remains dominant even at high trust.')
    notes.append('- Requested quantity scales down by rarity: common 1-30, uncommon 1-7, rare+ 1-3.')
    notes.append('- Duplicate display slugs are preserved with master_item_key disambiguation.')
    notes.append('')
    notes.append('## Outputs')
    notes.append(f"- Master items: {len(master_rows)}")
    notes.append(f"- Eligible gatherable fetch items: {roll_summary['eligible_items_total']}")
    notes.append(f"- Trust-band roll rows: {len(roll_rows)}")
    notes.append('')
    NOTES_MD.write_text('\n'.join(notes) + '\n', encoding='utf-8')

    update_dialogue_index(master_count=len(master_rows), summary=roll_summary)
    write_spec_doc(master_count=len(master_rows), eligible_count=roll_summary['eligible_items_total'])

    print(f'Master rows: {len(master_rows)}')
    print(f'Eligible fetch items: {roll_summary["eligible_items_total"]}')
    print(f'Roll rows: {len(roll_rows)}')


def update_dialogue_index(master_count: int, summary: dict) -> None:
    if not INDEX_JSON.exists():
        return

    idx = json.loads(INDEX_JSON.read_text(encoding='utf-8'))
    idx['version'] = int(idx.get('version', 0)) + 1
    idx['generated_at_utc'] = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace('+00:00', 'Z')

    file_manifest = idx.setdefault('file_manifest', {})
    file_manifest['fetch_items_master'] = MASTER_JSONL.name
    file_manifest['fetch_item_draw_rules'] = RULES_JSON.name
    file_manifest['fetch_item_roll_table_by_trust'] = ROLL_JSONL.name
    file_manifest['fetch_item_roll_summary'] = SUMMARY_JSON.name
    file_manifest['fetch_generation_notes'] = NOTES_MD.name

    idx['fetch_item_dataset'] = {
        'master_items_total': master_count,
        'eligible_fetch_items_total': summary['eligible_items_total'],
        'eligible_fetch_items_total_pre_dedupe': summary.get('eligible_items_total_pre_dedupe', summary['eligible_items_total']),
        'dedupe_policy': summary.get('dedupe_policy', ''),
        'eligible_by_rarity': summary['eligible_by_rarity'],
        'policy': {
            'non_crafting_focus': True,
            'trust_gate_not_rarity_bias': True,
            'legendary_unlocked_only_at': 'trust_81_99',
            'low_trust_allowed_rarities': ['common', 'uncommon'],
            'quest_quantity_range_by_rarity': QUEST_QUANTITY_RANGE_BY_RARITY,
        },
        'files': {
            'master': MASTER_JSONL.name,
            'rules': RULES_JSON.name,
            'roll_table': ROLL_JSONL.name,
            'summary': SUMMARY_JSON.name,
        },
    }

    INDEX_JSON.write_text(json.dumps(idx, ensure_ascii=False, indent=4) + '\n', encoding='utf-8')


def write_spec_doc(master_count: int, eligible_count: int) -> None:
    content = f'''# CozyPals Fetch Item Dataset Spec (V1, No Integration)

Last updated: {datetime.now().date().isoformat()}

## Goal
- Define a deterministic fetch quest item dataset with trust-gated rarity and rarity-based trust rewards.
- Keep the first pool gatherable-first and non-crafting.

## Source Scope
- Primary source snapshot: {SOURCE_URLS['paldb_items']}
- Secondary reference URL: {SOURCE_URLS['wiki_items_reference']}
- Master source count from snapshot: {master_count}

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
- Eligible fetch items: {eligible_count}
'''
    DOC_SPEC.write_text(content, encoding='utf-8')


if __name__ == '__main__':
    main()
