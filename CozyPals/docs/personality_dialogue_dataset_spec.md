# CozyPals Personality Dialogue Dataset Spec (V1.7, No Integration)

Last updated: 2026-03-20

## Line Ingredients (Locked)
1. Speaker identity
2. Species vibe
3. Personality traits
4. Social style
5. Trust level
6. Current context
7. Topic hook
8. Emotional tone

## Current Context
- activity_state: working | idle | eating | sleeping | injured | depressed
- environment_tags: day/night/weather/base ambience
- social_tags: player relationship, coworker life, mood, social preference

## Record Shape
line_id, text, trigger, trust_band, san_band, size_bucket, genus_category, element_primary,
personality_tags, gender_style, species_scope, activity_state, environment_tags, social_tags,
topic_hook, emotional_tone, species_vibe, social_style, hook_tags, weight, cooldown_group,
repeat_lockout, tone_flags

## Fetch Quest Dialogue
- quest_request trigger: pal asks for item fetch.
- quest_thanks trigger: pal thanks player after item hand-in.
- item token usage: {item_name}
- fetch lines are stored in dedicated files:
  - dialogue_fetch_request_lines.jsonl
  - dialogue_fetch_thanks_lines.jsonl

## Trust x Personality Rule
- Personality must influence all dialogue lines (not just tags).
- Fetch asks/thanks must vary by trust level and social style.
- Example constraint:
  - shy + low trust -> hesitant ask
  - shy + high trust -> direct/confident ask

## Conversational Quality Guardrails
- Avoid rigid stock phrasing patterns across many lines.
- Prefer short, interaction-like turns that sound spoken to the player.
- Keep lines compact (generally 1-3 short sentences) and context-grounded.
