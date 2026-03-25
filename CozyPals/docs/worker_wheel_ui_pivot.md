# Worker Wheel UI Pivot

## Current Result

The runtime UE4SS/native path can reliably:

- identify the live base-pal worker wheel
- identify the `Add to Party` slot as worker-wheel index `1`
- intercept selection of that slot
- route that selection toward CozyPals behavior

The runtime path cannot reliably:

- relabel the visible worker-wheel text from `Add to Party` to `Talk`
- add a stable sixth visible worker-wheel entry

This means the current best architecture is hybrid:

- UE4SS/native/Lua for runtime behavior
- packaged UI asset override for visible wheel labels/icons/layout

## Why This Pivot Is Correct

The live wheel evidence is:

- wheel widget: `WBP_WorkerRadialMenu_C`
- root radial base: `WBP_RadialMenu_base`
- entry widgets: `WBP_WorkerRadialMenuContent_C`
- visible text widget inside each entry: `BP_PalTextBlock_C_41`

Runtime mutation proved the behavior seam works, because index `1` was intercepted.
Runtime mutation failed on the visual seam, because relabel attempts consistently returned `relabeled=0` while the original cooked UI remained visible.

That strongly suggests the visible label should be changed in the asset layer rather than by late runtime text mutation.

## Target Hybrid Split

### UI / Visual Layer

Use a packaged UI mod (`.pak` / LogicMod-style asset override) to change:

- `WBP_WorkerRadialMenu`
- `WBP_WorkerRadialMenuContent`

Primary goal:

- replace visible `Add to Party` with visible `Talk`

Secondary goals later:

- custom icon for `Talk`
- possibly a true sixth entry if the worker wheel blueprint/layout allows it cleanly

### Runtime / Logic Layer

Keep CozyPals runtime behavior in the existing UE4SS/native + Lua stack:

- detect base-pal wheel selection
- if worker-wheel index `1` is chosen, treat it as CozyPals `talk`
- submit `talk` request through the bridge
- server validates owned pal identity and returns dialogue
- client displays the response

## Immediate Rule

Do not leave the visual and behavioral layers desynced.

If the visible label is still `Add to Party`, the runtime must not suppress or repurpose that slot in the live client build.

Only re-enable runtime remapping of index `1` after the packaged UI layer visibly renames it to `Talk`.

## Packaging Direction

Use the normal packaged Palworld UI mod path for the visual layer:

- `Pal/Content/Paks/...`
- or `Pal/Content/Paks/LogicMods/...` depending on the chosen PMK/LogicMod packaging workflow

The UE4SS/Lua/C++ runtime mod remains in:

- `Mods/NativeMods/UE4SS/...`
- local dev installs may still mirror under UE4SS `Mods/...`

## Next Engineering Steps

1. Build a minimal packaged UI override for the worker wheel visuals.
2. Rename only the visible `Add to Party` label to `Talk`.
3. Verify the wheel displays `Talk` before any runtime remapping is turned back on.
4. Re-enable the index `1 -> talk` runtime behavior.
5. After that works, decide whether to keep replacement or continue pursuing a true sixth entry.

## What This Avoids

- further runtime relabel dead-ends
- half-broken wheel states where `Add to Party` does nothing
- more unsafe recursive entry injection attempts
