# CozyPals (Milestone 1)

Dedicated-first UE4SS Lua mod scaffold for persistent pal identity.

## Install layout
Copy `Mods/CozyPals` into your Palworld `Mods` directory.

## Entry point
- `Mods/CozyPals/scripts/main.lua`

## Operator checklist
- `legwork-checklist.md` (exact dedicated test steps + log collection commands)

## What Milestone 1 does
- Scans candidate pal actors for UID/GUID-like properties.
- Prioritizes `IndividualId.InstanceId` lookup paths when available.
- Tracks verification evidence across run/world-cycle/context observations.
- Blocks persistence until a GUID source is verified.
- On verified GUID, creates a persistent record and deterministic personality seed.

## Debug helpers
- `CozyPals.debug_dump_all_pals()`
- `CozyPals.debug_dump_pal("<guid>")`
- `CozyPals.debug_dump_verification()`
- `CozyPals.force_save()`
