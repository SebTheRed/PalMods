# Pal SaveParameter Reference

This document explains the fields exported in the one-time native dump at:

- `D:\SteamLibrary\steamapps\common\PalServer\Pal\Binaries\Win64\Mods\CozyPals\data\pal_dump_pretty.json`

The dump comes from this live path on a spawned pal:

- `actor.CharacterParameterComponent.IndividualParameter.SaveParameter`

The stable identity key for the same pal is separate:

- `actor.CharacterParameterComponent.IndividualParameter.IndividualId.InstanceId`

That distinction matters:

- `IndividualId.InstanceId` answers "which exact pal is this?"
- `SaveParameter` answers "what state does this pal currently have?"

## Confidence Levels

- `Confirmed`: directly supported by the live dump and runtime behavior we already validated.
- `High-confidence inference`: strongly suggested by field names, values, and common Unreal/Pocketpair conventions.
- `Needs validation`: probably correct, but should be treated carefully until we test read/write behavior directly.

## How To Read The Dump

The pretty dump is a text-exported Unreal struct snapshot, not a typed JSON schema. That means:

- numbers are exported as strings
- booleans are exported as `"True"` or `"False"`
- structs are flattened into Unreal text like `(ID=...)`
- arrays and lists are flattened into Unreal text like `("Nocturnal")`

Do not assume the JSON string types match the true in-memory types. They are a debug/export format.

## Field Groups

### Identity And Ownership

These fields tell you what the pal is, who has touched it, and where it currently lives.

- `CharacterID`
  - Meaning: species/game data ID such as `Kitsunebi`, `CowPal`, `ChickenPal`.
  - Confidence: `Confirmed`
  - Use: good for species-based logic, not identity.

- `UniqueNPCID`
  - Meaning: likely a unique story/NPC variant identifier for special non-generic creatures.
  - Confidence: `High-confidence inference`
  - Notes: `None` on ordinary owned pals is expected.

- `CharacterClass`
  - Meaning: exact Blueprint class path for the spawned actor class.
  - Confidence: `Confirmed`
  - Use: useful for debugging and mod compatibility checks.

- `OwnerPlayerUId`
  - Meaning: current owner player UID.
  - Confidence: `Confirmed`
  - Important: a value of all zeroes does not reliably mean "not player-owned" for base pals on dedicated.

- `OldOwnerPlayerUIds`
  - Meaning: prior owner history.
  - Confidence: `Confirmed`
  - Important: this is one of the best ownership markers for base/boxed pals when `OwnerPlayerUId` is zero.

- `LastNickNameModifierPlayerUid`
  - Meaning: last player who changed nickname or otherwise directly modified this pal's player-facing state.
  - Confidence: `High-confidence inference`
  - Use: useful ownership evidence.

- `SlotId`
  - Meaning: current container slot assignment, including the container GUID and slot index.
  - Confidence: `Confirmed`
  - Use: useful for box/base tracking.
  - Warning: do not use as identity. It can change when the pal moves.

- `ItemContainerId`
  - Meaning: attached inventory container.
  - Confidence: `High-confidence inference`

- `EquipItemContainerId`
  - Meaning: attached equipment container.
  - Confidence: `High-confidence inference`

- `OwnedTime`
  - Meaning: ownership/capture timestamp.
  - Confidence: `High-confidence inference`
  - Important: `0001.01.01-00.00.00` should be treated as an unset/default value, not a meaningful timestamp.

### Basic Pal Metadata

- `Gender`
  - Meaning: literal biological/character gender.
  - Confidence: `Confirmed`

- `NickName`
  - Meaning: user-visible nickname.
  - Confidence: `Confirmed`

- `FilteredNickName`
  - Meaning: sanitized/filtered nickname variant used for display or moderation-safe output.
  - Confidence: `High-confidence inference`

- `IsRarePal`
  - Meaning: lucky/rare pal flag.
  - Confidence: `Confirmed`

- `VoiceID`
  - Meaning: voice selection index.
  - Confidence: `High-confidence inference`

- `SkinAppliedCharacterId`
  - Meaning: skin/cosmetic override reference.
  - Confidence: `High-confidence inference`

- `SkinName`
  - Meaning: cosmetic skin name identifier.
  - Confidence: `High-confidence inference`

- `IsFavoritePal`
  - Meaning: favorite/starred flag.
  - Confidence: `High-confidence inference`

- `FavoriteIndex`
  - Meaning: favorite ordering or favorite slot index.
  - Confidence: `Needs validation`

### Progression And Power

- `Level`
  - Meaning: current level.
  - Confidence: `Confirmed`

- `Exp`
  - Meaning: current experience.
  - Confidence: `Confirmed`

- `Rank`
  - Meaning: condenser/star rank.
  - Confidence: `High-confidence inference`

- `RankUpExp`
  - Meaning: rank-related exp or pending rank advancement accumulator.
  - Confidence: `Needs validation`

- `Rank_HP`
- `Rank_Attack`
- `Rank_Defence`
- `Rank_CraftSpeed`
  - Meaning: upgrade ranks applied to individual stat categories.
  - Confidence: `High-confidence inference`

- `Talent_HP`
- `Talent_Melee`
- `Talent_Shot`
- `Talent_Defense`
  - Meaning: IV-style innate rolls or permanent hidden stat affinities.
  - Confidence: `High-confidence inference`
  - Use: very good candidate inputs for CozyPals temperament/personality flavor.

- `Support`
  - Meaning: likely partner-skill or support-related rank/value.
  - Confidence: `Needs validation`

- `UnusedStatusPoint`
  - Meaning: unspent upgrade points.
  - Confidence: `High-confidence inference`

- `GotStatusPointList`
- `GotExStatusPointList`
  - Meaning: status upgrades the pal has unlocked or been granted.
  - Confidence: `High-confidence inference`
  - Note: these are localized display names in the dump.

### Combat And Resources

- `Hp`
  - Meaning: current HP.
  - Confidence: `Confirmed`

- `MaxHP`
  - Meaning: max HP snapshot or cached max HP field.
  - Confidence: `High-confidence inference`
  - Important: `0.000` does not necessarily mean the pal has zero max HP. This may be recalculated elsewhere rather than persisted here in a useful form.

- `MP`
- `MaxMP`
- `MaxSP`
  - Meaning: secondary resource pools.
  - Confidence: `Needs validation`

- `ShieldHP`
- `ShieldMaxHP`
- `bApplyShieldDamage`
  - Meaning: shield system state.
  - Confidence: `High-confidence inference`

- `DyingTimer`
  - Meaning: downed/death countdown.
  - Confidence: `High-confidence inference`

- `PalReviveTimer`
  - Meaning: revive timer.
  - Confidence: `High-confidence inference`

- `ArenaRankPoint`
  - Meaning: arena/ranked progression value.
  - Confidence: `High-confidence inference`

- `ArenaRestoreParameter`
  - Meaning: saved restore snapshot for arena transitions.
  - Confidence: `High-confidence inference`

- `Dynamic`
  - Meaning: runtime arena/police/override state container.
  - Confidence: `High-confidence inference`
  - Important: this looks like dynamic/runtime state, not a good CozyPals identity or personality source.

### Skills, Passives, And Work

- `EquipWaza`
  - Meaning: currently equipped active skills.
  - Confidence: `Confirmed`

- `MasteredWaza`
  - Meaning: learned skill list beyond currently equipped skills.
  - Confidence: `High-confidence inference`

- `PassiveSkillList`
  - Meaning: passive traits.
  - Confidence: `Confirmed`
  - Use: excellent input for mood/personality flavor if you want some grounded mechanical tie-in.

- `CraftSpeed`
  - Meaning: effective work speed stat.
  - Confidence: `High-confidence inference`

- `CraftSpeeds`
  - Meaning: per-work-suitability rank table.
  - Confidence: `Confirmed`
  - Example: `EmitFlame` has rank `1` in the sample dump.

- `CurrentWorkSuitability`
  - Meaning: the job type the pal is currently assigned or recognized as doing.
  - Confidence: `High-confidence inference`

- `WorkSuitabilityOptionInfo`
  - Meaning: work behavior toggles such as disabled work categories and whether base battle participation is allowed.
  - Confidence: `High-confidence inference`

- `BaseCampWorkerEventType`
- `BaseCampWorkerEventProgressTime`
  - Meaning: current worker/basecamp scripted state.
  - Confidence: `High-confidence inference`

- `GotWorkSuitabilityAddRankList`
  - Meaning: list of work suitability rank boosts granted externally.
  - Confidence: `Needs validation`

### Needs, Condition, And Base Behavior

- `FullStomach`
  - Meaning: current hunger meter.
  - Confidence: `Confirmed`

- `MaxFullStomach`
  - Meaning: max hunger meter.
  - Confidence: `Confirmed`

- `FullStomachDecreaseRate_Tribe`
  - Meaning: hunger decay multiplier.
  - Confidence: `High-confidence inference`

- `HungerType`
  - Meaning: hunger behavior profile.
  - Confidence: `High-confidence inference`

- `SanityValue`
  - Meaning: SAN / sanity meter.
  - Confidence: `Confirmed`

- `PhysicalHealth`
  - Meaning: overall health condition state.
  - Confidence: `Confirmed`

- `WorkerSick`
  - Meaning: sickness/debuff state affecting work.
  - Confidence: `Confirmed`

- `DecreaseFullStomachRates`
  - Meaning: contextual hunger decay modifiers.
  - Confidence: `High-confidence inference`

- `AffectSanityRates`
  - Meaning: contextual sanity modifiers.
  - Confidence: `High-confidence inference`

- `CraftSpeedRates`
  - Meaning: contextual work speed modifiers.
  - Confidence: `High-confidence inference`

- `FoodWithStatusEffect`
- `Tiemr_FoodWithStatusEffect`
- `FoodRegeneEffectInfo`
  - Meaning: currently active food effect and its remaining timer/effect payload.
  - Confidence: `High-confidence inference`
  - Note: `Tiemr_` and `RegeneEfect` are likely upstream spelling mistakes in the original field names.

### Friendship And Relationship Tracking

These are some of the highest-value fields for CozyPals behavior.

- `FriendshipPoint`
  - Meaning: overall friendship score.
  - Confidence: `High-confidence inference`

- `FriendshipOtomoSec`
  - Meaning: time spent as an otomo/companion in seconds.
  - Confidence: `High-confidence inference`

- `FriendshipActiveOtomoSec`
  - Meaning: active companion time in seconds.
  - Confidence: `High-confidence inference`

- `FriendshipBasecampSec`
  - Meaning: time spent as a base pal in seconds.
  - Confidence: `High-confidence inference`

- `bFavoriteChangedByFriendship`
  - Meaning: whether favorite state was auto-adjusted by friendship logic.
  - Confidence: `Needs validation`

### Miscellaneous System Fields

- `IsPlayer`
  - Meaning: whether this save blob represents a player character rather than a pal.
  - Confidence: `High-confidence inference`
  - Expected value for pals: `False`

- `LastJumpedLocation`
  - Meaning: last saved jump location or last mobility reference point.
  - Confidence: `Needs validation`

- `MapObjectConcreteInstanceIdAssignedToExpedition`
  - Meaning: expedition assignment reference.
  - Confidence: `High-confidence inference`

- `bImportedCharacter`
  - Meaning: imported/migrated character marker.
  - Confidence: `High-confidence inference`

- `bAppliedDeathPenarty`
  - Meaning: death penalty applied flag.
  - Confidence: `High-confidence inference`

- `bEnablePlayerRespawnInHardcore`
  - Meaning: hardcore respawn-related flag.
  - Confidence: `Needs validation`

- `bDisableSaleInPalLost`
  - Meaning: sell restriction flag for lost-pal handling.
  - Confidence: `Needs validation`

## Best Fields For CozyPals Logic

If the goal is personality/trust/social simulation, these are the best live data points to read:

- `CharacterID`
- `Gender`
- `IsRarePal`
- `PassiveSkillList`
- `Talent_HP`
- `Talent_Melee`
- `Talent_Shot`
- `Talent_Defense`
- `Level`
- `Rank`
- `FullStomach`
- `SanityValue`
- `PhysicalHealth`
- `WorkerSick`
- `CurrentWorkSuitability`
- `BaseCampWorkerEventType`
- `FriendshipPoint`
- `FriendshipOtomoSec`
- `FriendshipActiveOtomoSec`
- `FriendshipBasecampSec`
- `SlotId`

These let CozyPals react to:

- who the pal is
- how gifted it is
- how hungry/stressed/sick it is
- whether it is being used as a companion or base worker
- whether it has a real history with the player

## What Not To Use As Identity

Use `IndividualId.InstanceId` only.

Do not use these as a substitute identity key:

- `CharacterID`
- `CharacterClass`
- `SlotId`
- `OwnerPlayerUId`
- `OldOwnerPlayerUIds`
- `NickName`
- `OwnedTime`

They can collide, change, or be defaulted.

## Safe Vs Risky Write Targets

We can now mutate live pal state server-side through native reflection, but not every field is equally safe.

### Best First Write Candidates

- `FriendshipPoint`
- `FullStomach`
- `SanityValue`
- `NickName`

These are the cleanest first experiments because they are understandable and unlikely to be identity-critical.

### Medium-Risk Write Candidates

- `PassiveSkillList`
- `EquipWaza`
- `CurrentWorkSuitability`
- `WorkSuitabilityOptionInfo`

These may work, but they may also require extra game-side refresh/recalc behavior.

### High-Risk Write Candidates

- `Level`
- `Exp`
- `Rank`
- `Rank_HP`
- `Rank_Attack`
- `Rank_Defence`
- `Rank_CraftSpeed`
- `Talent_HP`
- `Talent_Melee`
- `Talent_Shot`
- `Talent_Defense`
- `Hp`
- `MaxHP`
- `SlotId`
- `OwnerPlayerUId`
- `OldOwnerPlayerUIds`
- `CharacterID`
- `CharacterClass`
- `IndividualId.InstanceId`

These fields can affect progression rules, replication, save integrity, ownership, or identity.

## Practical Recommendations

For CozyPals itself:

- treat `IndividualId.InstanceId` as the permanent primary key
- store CozyPals-specific trust/personality data in CozyPals JSON, not by rewriting game identity fields
- read live state from `SaveParameter`
- only write game fields when there is a clear design reason and a server-side test proves the game accepts the change cleanly

If we do controlled write tests, the first three fields to try should be:

- `FriendshipPoint`
- `FullStomach`
- `SanityValue`

## Current Known Good Paths

- Stable identity:
  - `actor.CharacterParameterComponent.IndividualParameter.IndividualId.InstanceId`

- Full pal state:
  - `actor.CharacterParameterComponent.IndividualParameter.SaveParameter`
