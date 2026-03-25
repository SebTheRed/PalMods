# CozyPals UI LogicMod

This folder is the planned home for the packaged UI side of CozyPals.

Purpose:

- handle visible worker-wheel presentation changes that are not behaving reliably through late runtime mutation

Initial target:

- worker wheel `Add to Party` entry visually renamed to `Talk`

Runtime behavior remains in the existing CozyPals UE4SS/native/Lua mod.

## Planned Asset Targets

- `WBP_WorkerRadialMenu`
- `WBP_WorkerRadialMenuContent`

## Packaging Goal

Produce a packaged UI mod that installs under Palworld's `Paks`/`LogicMods` path while the existing CozyPals logic mod remains under UE4SS/native.

This repo does not currently contain a PMK/Unreal asset project yet. This folder is the pivot point for that work.
