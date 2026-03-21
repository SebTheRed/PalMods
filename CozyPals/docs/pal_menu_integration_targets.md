# Pal Menu Integration Targets

This file records the concrete Palworld runtime/assets we surfaced while pivoting away from the broken custom `F`-hold interaction seam and toward the real in-game pal menu.

## Why This Pivot Happened

The temporary client bridge had two problems:

- the client copy of CozyPals was accidentally running in `force_server` mode, so the client interaction loop never executed
- even if it had, that bridge was only a quick-select seam and not the real in-game radial/menu UI

The correct direction is to add CozyPals actions to the same pal wheel the game already opens from the existing `Open Menu` interaction.

## Likely Wheel / HUD / Interaction UI Targets

These were found in the live client install and are the strongest current candidates for the existing pal radial flow:

- `Pal/Content/Pal/Blueprint/UI/WBP_PalInteractiveObjectIndicatorCanvas`
- `Pal/Content/Pal/Blueprint/UI/WBP_PalInteractiveObjectIndicatorUI`
- `Pal/Content/Pal/Blueprint/UI/WBP_PalHUD_InGame_InputListener`
- `Pal/Content/Pal/Blueprint/UI/WBP_PalHUD_InGame_GeneralDispatchEventReciever`
- `Pal/Content/Pal/Blueprint/UI/WBP_PlayerUI`

Related runtime classes seen by the native probe:

- `/Script/Pal.PalUserWidgetWorldHUD`
- `/Script/Pal.PalHUDDispatchParameterBase`
- `/Script/Pal.PalWaitInfoWorldHUDParameter`

## Likely Talk / Pet Action Targets

These asset names strongly suggest the shipped talk/pet action path:

- `Pal/Content/Pal/Blueprint/Action/NPC/BP_Action_NPC_Talk`
- `Pal/Content/Pal/Blueprint/Action/NPC/BP_NPCAction_PlayerTalk`
- `Pal/Content/Pal/Blueprint/Action/NPC/BP_NPCAction_PlayerTalk_Sit`
- `Pal/Content/Pal/Blueprint/Action/NPC/BP_Action_NPC_Petting`
- `Pal/Content/Pal/Blueprint/Character/Base/BP_PettingCamera`
- `Pal/Content/Pal/Blueprint/Character/Base/BP_PettingPreset`

Supporting NPC talk content assets found in the client install:

- `Pal/Content/Pal/DataTable/Text/DT_NpcTalkText`
- `Pal/Content/Pal/DataTable/Text/DT_NpcTalkText_Common`
- `Pal/Content/Pal/Blueprint/Component/NPCTalk/DT_NPCMultiTalk`
- `Pal/Content/Pal/Blueprint/Component/NPCTalk/DT_NPCOneTalk`
- `Pal/Content/Pal/Blueprint/Component/NPCTalk/DT_NPCTalkFlow`
- `Pal/Content/Pal/Blueprint/Component/NPCTalk/BP_NPCEmoteDetectionComponent`

## Likely Quest / Request Targets

These are the best current quest/request system candidates from the runtime probe:

- `/Script/Pal.PalItemRequestNPCComponent`
- `/Script/Pal.PalDisplayRequestDataAsset`
- `/Script/Pal.PalCircumRequestDataAsset`
- `/Script/Pal.PalLevelObjectQuestItem`
- `/Script/Pal.PalLocationPoint_QuestBase`
- `/Script/Pal.PalLocationPoint_QuestTracking`
- `/Script/Pal.PalMapObjectCharacterTeamMissionModel`

## Immediate Next Technical Goal

Do not keep investing in the custom hold interaction.

Next implementation pass should:

1. hook the existing pal `Open Menu` path
2. identify the widget/action list used by that radial wheel
3. inject CozyPals entries such as `Talk` and `Quest`
4. route those selections into the already-working server-authoritative GUID + dialogue + quest state layer
