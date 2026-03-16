# CozyPals - Pal ID Discovery Guide

## Goal
Find the most stable identifier for an **individual pal** so the mod can persist personality, dialogue history, and quests.

## Reliable tools we have
- **UE4SS Live Viewer**: lets you search, view, and watch reflected object properties at runtime.
- **UE4SS Header Dumpers**: generate headers for classes/structs so you can search for likely property names.
- **UE4SS Object Dump**: dumps all loaded objects and properties.
- **UE4SS Hooks**: lets you hook known functions once the right classes/functions are identified.

## Step 1 - Turn on the right UE4SS UI settings
In `UE4SS-settings.ini` make sure:
- `GuiConsoleEnabled = 1`
- `GuiConsoleVisible = 1`

Optional but useful:
- set `GraphicsAPI = dx11` if the UI is blank/white
- increase `GuiConsoleFontScaling` if the text is tiny

## Step 2 - Open Live Viewer near your base pals
Stand near a base where several pals are currently loaded.

Recommended search settings:
- **Instances only** = ON
- **Include inheritance** = ON if useful
- optionally **Has property** filters later

Search terms to try first:
- `Pal`
- `Otomo`
- `Character`
- `Worker`
- `BaseCamp`

What we want to find:
- the *live actor instance* representing each visible base pal
- any components or save-parameter objects hanging off that pal

## Step 3 - Inspect likely object/class names
Once you find a likely pal actor, inspect these areas first:
- actor full name / class name
- child components
- any properties with names containing:
  - `Guid`
  - `UID`
  - `ID`
  - `Instance`
  - `Individual`
  - `Character`
  - `Save`
  - `Container`
  - `Slot`
  - `Owner`

## Step 4 - Rank candidate identifiers
Use this priority order:

### Best-case candidates
1. `InstanceId`
2. `Guid`
3. `IndividualId`
4. `CharacterID` / `CharacterId`
5. `SaveId`

### Good fallback candidates
6. `CharacterContainerId`
7. `OwnerPlayerUId`
8. `SlotIndex` / container slot

### Last-resort fallback
Build a composite key from multiple semi-stable values:
- owner UID
- species/internal name
- container ID
- slot index
- first-seen timestamp

## Step 5 - Validate persistence
Do **not** trust a candidate until you prove it survives a reload.

Validation procedure:
1. Record the candidate ID for one specific base pal.
2. Exit to menu / reload world.
3. Revisit the same pal.
4. Check whether the same ID still appears.
5. Move the pal between base and box if possible and re-check.

A true persistent pal key should ideally survive:
- game restart
- world reload
- base reload
- moving between box/base/party (if the same underlying pal is preserved)

## Step 6 - Header/Object dump search terms
After generating UE4SS dumps, search for these strings:
- `Trust`
- `Sanity`
- `Condition`
- `Mood`
- `Worker`
- `BaseCamp`
- `CharacterSaveParameter`
- `CharacterContainer`
- `InstanceId`
- `Guid`
- `Individual`
- `OwnerPlayerUId`
- `Otomo`

## What to capture in your reverse engineering notes
For every promising object/class, record:
- class name
- full path
- which visible pal it corresponded to
- candidate ID property names and example values
- whether the values looked GUID-like
- whether the values survived reload

## What success looks like
A strong result would be something like:
- visible base pal actor
- property `InstanceId`
- value looks GUID-like
- same value appears after reload

If that fails, the next best result is:
- stable owner/container/slot tuple
- proven to map back to the same pal after reload

## Next research target after ID
Once the stable pal identity is confirmed, the next discovery targets are:
1. current trust value location
2. current mood / SAN / negative condition location
3. current work assignment/state location
4. player-to-pal interaction function(s)
