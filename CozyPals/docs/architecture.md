# CozyPals Architecture (Milestone 1)

## Runtime model
- Dedicated-first server-authoritative flow.
- Discovery and GUID verification run on all runtimes for observation.
- Persistence and state mutation run only on authoritative runtime.

## Core modules
- `main.lua`: lifecycle hooks, authority gating, actor pipeline, autosave loop.
- `discovery.lua`: candidate actor scanning, UID candidate ranking, structured reports.
- `identity.lua`: GUID verification state machine and source confidence tracking.
- `persistence.lua`: per-world JSON load/save, migration defaults, dirty-flag autosave, atomic writes.
- `traits.lua`: deterministic personality roll from verified GUID.
- `logger.lua`: leveled and throttled logs.
- `util.lua`: file/path/hash/context helpers.
- `json.lua`: JSON encode/decode for save payloads.

## Milestone 1 data contract
- `data_schema_version`
- `world_key`
- `pals[guid].personality.seed`
- `pals[guid].meta.first_seen`
- `pals[guid].meta.last_seen`
- `pals[guid].verification.guid_source`

## Status gating
- If GUID status is `candidate`, personality persistence is blocked.
- If GUID status is `verified`, pal record creation and deterministic personality assignment are enabled.

## Discovery priority
- First-class target path: `IndividualId.InstanceId`.
- Preferred traversal paths include:
  - actor-level `IndividualId.InstanceId`
  - component-level variants such as `CharacterParameterComponent.IndividualId.InstanceId` and `IndividualCharacterParameter.IndividualId.InstanceId`
- Generic UID/GUID candidates are still scanned, but ranked below preferred `IndividualId.InstanceId` paths.
