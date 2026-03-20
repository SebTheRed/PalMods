# https://paldb.cc/en/
# https://palworld.wiki.gg/wiki/Game_Files/Folder_Structure/Data_Tables
# https://palworld.wiki.gg/wiki/Game_Files/Reading/Creature_Parameters
# CozyPals Weekend Data Hardening Master Plan

Last updated: 2026-03-20  
Status: Planning baseline locked, implementation deferred to weekend

This document is the canonical weekend prep artifact for CozyPals data hardening.  
It is intentionally planning-only and designed to be decision-complete for coding handoff.

---

## 1) Summary

- Target artifact: this file (`CozyPals/docs/weekend_data_hardening_master_plan.md`).
- Goal: lock a decision-complete data contract for trust-driven behavior before feature coding.
- Scope: feature-focused for CozyPals priorities, plus a structured inventory of additional mutable fields for future work.
- Authority model: dedicated-server authoritative only.
- Mutation model: overlay-first; additive rank paths before any direct base overwrite.
- Trust model: use built-in friendship/trust as source of truth, extend mod-side non-combat progression to Lv.99, no extra combat scaling beyond vanilla trust behavior.

---

## 2) Product Rules (Locked)

- `IndividualId.InstanceId` remains the only persistent pal identity key.
- No fallback identity keys.
- No client-authoritative persistence or mutation.
- No direct mutation of identity/ownership/core combat fields unless explicitly approved later by a high-risk test gate.
- Work suitability progression uses milestone unlocks with manual selection.
- Ranch output progression is tiered (Lv-style), not flat multipliers by default.
- Sickness behavior is prevention + recovery acceleration, no auto-cure by default.
- UI target is custom UI first for milestone trait choice.

---

## 3) Public Interfaces And Types To Add

### 3.1 Config surfaces

- `config.trust`
- `config.trust.source_field = "FriendshipPoint"`
- `config.trust.level_curve_mode = "piecewise_linear"`
- `config.trust.max_level = 99`
- `config.trust.combat_scaling_cap_level = 10`
- `config.trust.milestone_interval = 10`

- `config.effects`
- `config.effects.work_speed_curve`
- `config.effects.sanity_drain_curve`
- `config.effects.sickness_prevention_curve`
- `config.effects.sickness_recovery_curve`
- `config.effects.ranch_tier_curve`

- `config.work_progression`
- `config.work_progression.allowed_traits`
- `config.work_progression.rank_cap_mode = "configurable"`
- `config.work_progression.default_rank_cap = "vanilla_safe"`
- `config.work_progression.primary_write_path = "additive_list"`

- `config.ui`
- `config.ui.milestone_selection_mode = "custom_ui"`

### 3.2 State schema surfaces

- `state.pals[guid].progression`
- `state.pals[guid].progression.trust_level_99`
- `state.pals[guid].progression.friendship_snapshot`
- `state.pals[guid].progression.milestones_earned`
- `state.pals[guid].progression.milestones_spent`
- `state.pals[guid].progression.pending_milestone_choices`
- `state.pals[guid].progression.work_rank_allocations`

- `state.pals[guid].effects`
- `state.pals[guid].effects.work_speed_mult`
- `state.pals[guid].effects.sanity_drain_mult`
- `state.pals[guid].effects.sickness_prevention_mult`
- `state.pals[guid].effects.sickness_recovery_mult`
- `state.pals[guid].effects.ranch_tier_bonus`

### 3.3 Suggested companion metadata (for auditability)

- `state.pals[guid].meta.last_effect_apply_at`
- `state.pals[guid].meta.last_effect_apply_source`
- `state.pals[guid].meta.last_validation_tag`

---

## 4) Mutable Data Matrix (Feature-Critical First)

Schema for each row:

`field_path | runtime_type | domain/range | known_values | write_policy | risk | source | validation_status`

| field_path | runtime_type | domain/range | known_values | write_policy | risk | source | validation_status |
|---|---|---|---|---|---|---|---|
| `FriendshipPoint` | numeric | non-negative numeric (upper bound runtime-confirmed) | drives in-game trust UI | read-first, controlled write tests later | medium | SaveParameter + UI behavior | partially verified |
| `FriendshipOtomoSec` | numeric | non-negative seconds | companion-time counter | read-only initially | low | SaveParameter | pending runtime type confirm |
| `FriendshipActiveOtomoSec` | numeric | non-negative seconds | active companion-time counter | read-only initially | low | SaveParameter | pending runtime type confirm |
| `FriendshipBasecampSec` | numeric | non-negative seconds | basecamp-time counter | read-only initially | low | SaveParameter | pending runtime type confirm |
| `CraftSpeed` | numeric | positive numeric | work speed stat | overlay-driven effect output preferred | medium | SaveParameter | pending exact type/range test |
| `CraftSpeedRates` | array/list/struct modifiers | modifier entries | contextual work-speed modifiers | primary runtime effect application surface | medium | SaveParameter | pending structure decoding |
| `CurrentWorkSuitability` | enum-like | suitability identifier | suitability family names | avoid direct writes initially | medium | SaveParameter | pending enum map |
| `WorkSuitabilityOptionInfo` | struct | toggle map/state container | enable/disable flags by suitability | guarded writes only | medium-high | SaveParameter | pending struct layout |
| `CraftSpeeds` | map/struct ranks | suitability -> rank/value | `EmitFlame`, `Watering`, etc. | secondary/fallback write target | high | SaveParameter | pending layout + replication tests |
| `GotWorkSuitabilityAddRankList` | additive rank list | list entries per trait | externally granted rank boosts | primary permanent rank-up target | medium | SaveParameter | priority validation item |
| `SanityValue` | numeric | likely 0-100 (runtime clamp confirm) | SAN meter | overlay-friendly | medium | SaveParameter + UI behavior | needs hard min/max test |
| `AffectSanityRates` | list/struct modifiers | modifier entries | contextual SAN rate modifiers | primary SAN drain modulation surface | medium | SaveParameter | pending structure mapping |
| `FullStomach` | numeric | bounded meter | hunger meter | secondary condition interaction surface | low-medium | SaveParameter | mostly understood |
| `DecreaseFullStomachRates` | list/struct modifiers | modifier entries | hunger depletion modifiers | optional overlay surface | medium | SaveParameter | pending layout mapping |
| `WorkerSick` | likely bool or compact state flag | likely `True/False` or bit/state | illness flag candidate | do not treat as sole disease authority until validated | medium | SaveParameter + dump evidence | unresolved (critical) |
| `PhysicalHealth` | enum/state container | condition state set | disease/condition state candidate | read-first, conservative writes only | medium-high | SaveParameter | unresolved (critical) |
| ranch/drop table surfaces | table-driven + progression-driven | tiered values | Lv1-Lv5 style progression references | trust->tier mapping first; avoid loot rewrite in v1 | medium | external data + runtime mapping | table/key mapping pending |

### 4.1 Extended mutable inventory queue (not v1-critical, still track)

- `WorkSuitabilityOptionInfo` subkeys not yet decoded
- `BaseCampWorkerEventType`
- `BaseCampWorkerEventProgressTime`
- `FoodWithStatusEffect`
- `Tiemr_FoodWithStatusEffect`
- `FoodRegeneEffectInfo`
- `DecreaseFullStomachRates` full key map
- `AffectSanityRates` full key map
- `CraftSpeedRates` full key map

---

## 5) Work Suitability Canonical Set (UI + Allocation)

- Kindling (`EmitFlame`)
- Watering (`Watering`)
- Planting (`Seeding`)
- Generating Electricity (`GenerateElectricity`)
- Handiwork (`Handcraft`)
- Gathering (`Collection`)
- Lumbering (`Deforest`)
- Mining (`Mining`)
- Medicine Production (`ProductMedicine`)
- Cooling (`Cool`)
- Transporting (`Transport`)
- Farming (`MonsterFarm`)

Policy note:

- Oil Extraction appears in data naming in some references but is generally excluded from default allocation until runtime validation confirms active gameplay behavior in current target version.

---

## 6) Trust Progression Spec

### 6.1 Source and derivation

- Source input: built-in friendship/trust state (`FriendshipPoint` + UI-correlated level behavior).
- Derived output: `trust_level_99`.

### 6.2 Baseline behavior

- Levels 1-10: track vanilla trust behavior.
- Levels 11-99: CozyPals non-combat progression only.

### 6.3 Combat guardrail

- No extra CozyPals scaling to HP/Attack/Defense beyond vanilla trust behavior.

### 6.4 Milestones

- Default interval: every 10 levels (configurable).
- Each milestone grants one permanent work-trait rank allocation.
- Manual selection is required.
- If selection is deferred, milestone remains pending and spendable later.

### 6.5 Cap model

- Rank cap mode: configurable.
- Default cap: vanilla-safe.
- Overspending prevention: block allocation when trait is capped.

---

## 7) Effect Specs (Non-Combat)

### 7.1 Work speed

- Increase effective productivity via configured curve from trust level and condition modifiers.
- Apply through overlay/runtime modifier surfaces first.

### 7.2 SAN drain

- Higher trust reduces SAN drain rate.
- Lower trust remains close to vanilla behavior.
- No forced SAN hard-set unless explicitly configured.

### 7.3 Sickness prevention and recovery

- Higher trust lowers sickness incidence probability.
- Higher trust improves recovery speed.
- No instant cure behavior by default.

### 7.4 Ranch output

- Trust maps to tiered output progression (Lv-style tiers) for ranch-capable pals.
- Tier mapping is deterministic and configurable.
- No custom per-item loot pool rewrite in v1 baseline.

---

## 8) UI Spec (Custom UI First)

### 8.1 Entry and placement

- UI entrypoint near pal details trust area.
- Include CozyPals milestone indicator.

### 8.2 Milestone panel

- Displays:
- current trust level
- next milestone threshold
- pending milestone points
- current trait allocations

### 8.3 Trait selection modal

- Shows allowed work traits.
- Shows current rank, cap, and projected result.
- Shows disabled reasons (at cap, no pending point, invalid state).

### 8.4 Confirm and authority flow

- Confirm action is server-authoritative only.
- Client receives success/failure response and refreshed authoritative state.

### 8.5 Accessibility and clarity

- Clear text reasons for blocked actions.
- No hidden auto-spend behavior.

---

## 9) Data Table / External Mapping Backlog

Required mapping targets:

- Creature parameter table(s) for base pal stats/work suitability keys.
- Pal drop/item table(s) for ranch/drop behavior.
- Worker condition/health state table(s) tied to sickness semantics.

Mapping row format:

`table_name | key_field | relevant_columns | cozy_effect_mapping | confidence`

Important inference note:

- Some wiki-driven names/structures are inferred from public references and must be confirmed from local extracted game data before final lock.

---

## 10) Test Cases And Scenarios

### A) Data typing and domain lock

1. Confirm runtime types for every feature-critical field in the matrix.
2. Confirm numeric bounds/clamps for trust, SAN, and work-speed related fields.
3. Confirm enum/state values for sickness and physical health surfaces.

### B) Server authority and replication

1. Apply each effect server-side and verify expected client-visible results.
2. Verify no client-origin writes alter persistent progression.
3. Verify stability through reconnect cycles.

### C) Persistence and identity safety

1. Progression persists and rebinds only by verified `IndividualId.InstanceId`.
2. Move pal between base/box/party and confirm same record is used.
3. Restart dedicated server and confirm stable rebind + effect reapplication.

### D) Progression rules

1. Milestone grants occur at configured intervals.
2. Manual trait allocation consumes exactly one point.
3. Allocation blocked at cap with explicit reason.
4. Deferred milestones remain pending and can be spent later.

### E) Balance and guardrails

1. Combat stats remain vanilla-capped relative to trust behavior.
2. Non-combat modifiers stay within configured min/max constraints.
3. Ranch tier transitions occur at expected trust breakpoints.

### F) Failure and recovery

1. Reflection failures degrade safely without state corruption.
2. Invalid config values fall back to sane defaults with warnings.
3. Save/load backup flow remains intact under repeated restart cycles.

---

## 11) Weekend Execution Plan

No gameplay coding is required by this plan document itself.  
This section defines implementation sequence for weekend execution.

### Saturday

1. Finalize mutable matrix with runtime-confirmed types and value domains.
2. Finalize trust-to-99 curve and milestone policy defaults.
3. Finalize sickness/SAN/work-speed curve defaults and caps.
4. Finalize ranch tier mapping model and per-pal applicability rules.
5. Finalize custom UI interaction flow and payload contracts.

### Sunday

1. Implement schema/config additions and migration guards.
2. Implement server-authoritative trust/effect pipeline.
3. Implement milestone spending pipeline with additive rank write path.
4. Implement custom UI for milestone selection.
5. Run dedicated-server validation suite and freeze v1 tuning defaults.

---

## 12) Assumptions And Defaults

- Built-in trust/friendship is the canonical progression source.
- Non-combat progression continues to Lv.99.
- Combat scaling remains vanilla-bounded.
- Permanent work rank-ups use additive list paths first.
- Rank caps are configurable with vanilla-safe defaults.
- Custom UI is first release path for milestone choices.
- External wiki-derived details are provisional until validated against local extracted data/runtime observation.

---

## 13) Existing Local References

- `CozyPals/docs/pal_save_parameter_reference.md`
- `CozyPals/docs/architecture.md`
- `CozyPals/docs/data_schema.md`
- `CozyPals/docs/reverse_engineering_notes.md`
- `CozyPals/docs/testing_m1.md`

---

## 14) External References

- https://paldb.cc/en/Pals_Table
- https://paldb.cc/en/Work_Suitability
- https://paldb.cc/en/SAN
- https://paldb.cc/en/Drop_Rate
- https://paldb.cc/en/Pal_Stats
- https://palworld.wiki.gg/wiki/Game_Files/Reading/Creature_Parameters
- https://palworld.wiki.gg/wiki/Game_Files/Folder_Structure/Data_Tables

---

## 15) Immediate Next Actions When Coding Starts

1. Convert Section 4 rows from "pending" to concrete runtime types through dedicated reflection checks.
2. Lock trust curve breakpoints and milestone interval defaults in config.
3. Validate `GotWorkSuitabilityAddRankList` as safe primary write path.
4. Resolve sickness authority split (`WorkerSick` vs `PhysicalHealth`) before any sickness mutation implementation.
5. Implement and validate custom milestone UI workflow end-to-end on dedicated.

