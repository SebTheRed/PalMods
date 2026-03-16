# AGENTS.md - CozyPals Handoff (March 16, 2026)

## Context
- Repo: `PalMods`
- Active project: `CozyPals`
- Goal: Palworld UE4SS Lua mod for persistent per-pal identity/personality.
- Current phase: Milestone 1 implementation (identity persistence foundation), dedicated-server first.

## Non-Negotiable Product Decisions (already chosen)
- Dedicated server support is mandatory from the first implementation wave.
- Server-authoritative data flow only for persistence/state mutation.
- No fallback identity keys allowed.
- Persistence is hard-blocked until a true GUID source is verified.
- Discovery priority is `IndividualId.InstanceId` (including component paths ending in `.IndividualId.InstanceId`).

## What Is Implemented
- UE4SS mod scaffold at `CozyPals/Mods/CozyPals`.
- Entrypoint: `CozyPals/Mods/CozyPals/scripts/main.lua`.
- Core modules implemented:
- `config.lua`
- `util.lua`
- `logger.lua`
- `json.lua`
- `discovery.lua`
- `identity.lua`
- `persistence.lua`
- `traits.lua`
- Future stubs implemented:
- `dialogue.lua`
- `interactions.lua`
- `quests.lua`
- `trust.lua`
- `debug_mod.lua` and `debug.lua`
- Enabled marker: `CozyPals/Mods/CozyPals/enabled.txt` with value `1`.

## Key Technical Behavior
- Authority detection is in `main.lua` with auto/force modes.
- Runtime hooks register discovery on actor BeginPlay and periodic autosave tick attempts.
- Discovery now supports nested property traversal (`A.B.C`), not just flat properties.
- Discovery ranks preferred GUID paths above generic GUID-ish fields.
- Identity verification state machine tracks evidence by:
- distinct run IDs
- distinct world cycle IDs
- distinct context hashes (for move checks)
- Verification thresholds are configurable in `config.lua` under `verification`.
- Persistence uses per-world JSON in `Mods/CozyPals/data`.
- Save writes are atomic via temp + backup + replace.
- Personality seed is deterministic from GUID/species (`traits.lua`).

## Milestone 1 Log Signals
- Blocked candidate: `[M1][BLOCKED]`
- Verified GUID source: `[M1][GUID VERIFIED]`
- Record creation/rebind success: `[M1][PASS]`

## High-Value Research Result Used
- Public code evidence indicates `FPalInstanceID` with `IndividualId.InstanceId` is a real and likely stable target.
- This was incorporated into discovery priority config and scan logic.

## Docs Added
- `CozyPals/README.md`
- `CozyPals/legwork-checklist.md` (operator runbook with exact dedicated test steps and log commands)
- `CozyPals/docs/architecture.md`
- `CozyPals/docs/data_schema.md`
- `CozyPals/docs/reverse_engineering_notes.md`
- `CozyPals/docs/testing_m1.md`
- `CozyPals/data/sample_save_schema.json`

## Environment Notes
- LuaJIT installed via winget package `DEVCOM.LuaJIT`.
- Executable path: `C:\Users\sebbe\AppData\Local\Programs\LuaJIT\bin\luajit.exe`.
- In this automation shell, `luajit` command may not resolve by bare name immediately.
- Absolute executable path works reliably.

## Validation Already Performed
- Bytecode compile checks (`luajit -b`) passed for all CozyPals Lua scripts.
- Discovery smoke test confirms best candidate can resolve to `IndividualId.InstanceId`.
- Identity smoke test confirms `candidate -> verified` transition after required evidence counts.
- No live in-game/dedicated runtime logs have been validated yet in this repo session.

## Operator Instructions for Next Loop
- Use `CozyPals/legwork-checklist.md` exactly.
- Collect and provide:
- latest `[CozyPals]` log lines
- all `[M1][BLOCKED]`, `[M1][GUID VERIFIED]`, `[M1][PASS]` lines
- newest `cozypals_state_*.json`
- short note of pal move + restart timing

## Highest-Priority Next Engineering Steps
- Run first dedicated-server legwork cycle and inspect whether `IndividualId.InstanceId` is actually top/usable in live logs.
- If discovery misses the expected path, tune `discovery.component_properties` and `preferred_guid_paths` in `config.lua`.
- If authoritative detection misfires on dedicated, set `authority.mode = "force_server"` and retest.
- Confirm save file path and world key stability across restart.
- Only after GUID verification is truly proven in live logs, proceed to Milestone 2 interactions.

## Known Risks
- UE4SS reflection surface may expose the ID under different component/property names by game version.
- Tick hook path availability can vary by runtime; autosave falls back to event-driven dirty flush if no tick hook registers.
- World key derivation may still need tuning based on real dedicated world object names.

## Quick Commands
- Compile check all scripts:
- `C:\Users\sebbe\AppData\Local\Programs\LuaJIT\bin\luajit.exe -b CozyPals/Mods/CozyPals/scripts/main.lua NUL`
- Run full operator test flow:
- see `CozyPals/legwork-checklist.md`
