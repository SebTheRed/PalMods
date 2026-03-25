# CozyPals Interaction Split Mode

CozyPals interaction runtime is now split into two roles:

- server role:
  - validates that a pal GUID is live and player-owned
  - chooses dialogue lines
  - applies `pet` trust/affection effects
  - persists interaction state
- client role:
  - resolves the focused in-world pal under the crosshair
  - watches local input state
  - submits interaction requests
  - displays the returned dialogue/effect result

## Shared Bridge Directory

By default both roles communicate through:

`%LOCALAPPDATA%\CozyPalsBridge`

Files used there:

- `client_input_state.json`
- `interaction_requests.jsonl`
- `interaction_responses.jsonl`
- `client_interaction_state.json`

The path can be overridden in:

- [config.lua](C:\Users\sebbe\Documents\GitHub\PalMods\CozyPals\Mods\CozyPals\scripts\config.lua)

under:

- `interaction.bridge_directory`

## Current Input Bridge

The native helper now writes local input state for:

- keyboard `F` as interact
- keyboard `4` as the existing Palworld `Open Menu` wheel key
- keyboard `R` as alternate action
- Xbox `X` as interact
- Xbox `Y` as alternate action

This is a pragmatic bridge for local testing/probing. It is not yet remap-aware.

## Current Selection Flow

The old quick-select hold flow is now considered legacy.

If `interaction.legacy_hold_interaction_enabled = false` in [config.lua](C:\Users\sebbe\Documents\GitHub\PalMods\CozyPals\Mods\CozyPals\scripts\config.lua), CozyPals no longer tries to drive its own fake interaction menu and instead stays in probe mode while we target the real Palworld wheel.

Legacy behavior was:

1. look at an owned pal
2. hold interact for `0.45s`
3. while the quick-select window is open:
   - press interact again for `Talk`
   - press alternate action for `Pet`

The bridge also writes `client_interaction_state.json` so a proper radial/widget layer can consume the same state later.

## Current UI Status

Implemented now:

- client-side message display fallback via `PlayerController:ClientMessage`
- client-side focus/hold state export

Not fully implemented yet:

- shipped Palworld radial widget invocation
- shipped bottom-of-screen talk widget invocation
- reliable emote playback path

The runtime was structured so those can be swapped in without changing server validation or dialogue/trust logic.

## Safety Gate

The experimental client runtime is now hard-gated.

By default:

- client `CozyPals` is disabled in the live install
- client `CozyPalsNative` is disabled in the live install
- even if `CozyPalsNative` is re-enabled, the experimental client runtime path stays off unless this file exists:

`Mods/CozyPals/data/enable_client_runtime.flag`

That means normal play should stay safe, and the next wheel/talk runtime test must be an explicit opt-in step instead of something that silently boots every launch.

## Native Candidate Dumps

The native helper now also emits one-shot runtime candidate dumps for the next stage of real integration work:

- `Mods/CozyPals/data/native_ui_candidates.jsonl`
- `Mods/CozyPals/data/native_quest_candidates.jsonl`
- `Mods/CozyPals/data/native_pal_menu_candidates.jsonl`
- `Mods/CozyPals/data/native_talk_action_candidates.jsonl`
- `Mods/CozyPals/data/native_request_system_candidates.jsonl`

These files are meant to capture likely shipped Palworld classes/objects/functions related to:

- quest log / mission systems
- bottom-of-screen talk or chat UI
- radial / wheel / interaction widgets
