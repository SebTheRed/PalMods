local Config = {
    mod_name = "CozyPals",
    mod_version = "0.1.0-m1",
    data_schema_version = 1,

    authority = {
        mode = "auto", -- auto | force_server | force_client
        allow_unknown_as_server = false,
    },

    world = {
        server_identity = "dedicated_default",
        world_key_override = nil,
    },

    logging = {
        level = "DISCOVERY", -- ERR | WARN | INFO | DEBUG | DISCOVERY
        default_throttle_seconds = 5,
    },

    persistence = {
        data_directory = "Mods/CozyPals/data",
        file_prefix = "cozypals_state_",
        backup_suffix = ".bak",
        temp_suffix = ".tmp",
        autosave_seconds = 30,
        flush_on_dirty = false,
    },

    verification = {
        require_run_count = 2,
        require_world_cycle_count = 2,
        require_move_check = true,
    },

    discovery = {
        enabled = true,
        log_top_candidates = 3,
        pal_keywords = {
            "Pal",
            "Otomo",
            "Worker",
            "BaseCamp",
        },
        candidate_properties = {
            "IndividualId.InstanceId",
            "InstanceId",
            "Guid",
            "GUID",
            "Uid",
            "UID",
            "IndividualId",
            "CharacterID",
            "CharacterId",
            "SaveId",
            "CharacterContainerId",
            "OwnerPlayerUId",
            "OwnerPlayerUid",
            "SlotIndex",
            "Slot",
        },
        preferred_guid_paths = {
            "IndividualId.InstanceId",
            "CharacterParameterComponent.IndividualId.InstanceId",
            "PalCharacterParameter.IndividualId.InstanceId",
            "IndividualCharacterParameter.IndividualId.InstanceId",
            "IndividualCharacterParameterComponent.IndividualId.InstanceId",
            "StaticCharacterParameterComponent.IndividualId.InstanceId",
        },
        context_properties = {
            "CharacterContainerId",
            "ContainerId",
            "OwnerPlayerUId",
            "OwnerPlayerUid",
            "SlotIndex",
            "Slot",
            "BaseCampId",
            "BaseCampID",
            "SaveParameter.OwnerPlayerUId",
            "IndividualId.PlayerUId",
        },
        species_properties = {
            "Species",
            "PalName",
            "CharacterName",
            "CharacterID",
            "CharacterId",
        },
        component_properties = {
            "OtomoPalHolderComponent",
            "CharacterParameterComponent",
            "IndividualCharacterParameter",
            "IndividualCharacterParameterComponent",
            "StaticCharacterParameterComponent",
            "WorkerComponent",
            "BaseCampComponent",
            "PalCharacterParameter",
        },
        property_score = {
            ["IndividualId.InstanceId"] = 140,
            InstanceId = 100,
            Guid = 95,
            GUID = 95,
            IndividualId = 90,
            CharacterID = 85,
            CharacterId = 85,
            SaveId = 80,
            Uid = 75,
            UID = 75,
            CharacterContainerId = 45,
            OwnerPlayerUId = 35,
            OwnerPlayerUid = 35,
            SlotIndex = 20,
            Slot = 15,
        },
    },

    personality = {
        work_attitudes = {
            "diligent",
            "proud",
            "playful",
            "anxious",
            "lazy",
            "clingy",
            "stoic",
            "chaotic",
            "sensitive",
            "perfectionist",
        },
        social_preferences = {
            "loves_petting",
            "loves_talking",
            "loves_fetch_quests",
            "shy_but_warms_up",
            "gift_focused",
            "independent",
            "praise_seeking",
            "comfort_seeking",
        },
        temperaments = {
            "gentle",
            "bold",
            "moody",
            "sunny",
            "timid",
            "stubborn",
        },
        species_bias = {
            Depresso = {
                work_attitude = { stoic = 3, anxious = 2, sensitive = 1 },
                social_preference = { independent = 2, comfort_seeking = 2 },
                temperament = { moody = 3, timid = 1 },
            },
            Penking = {
                work_attitude = { proud = 3, diligent = 2 },
                social_preference = { praise_seeking = 2, independent = 1 },
                temperament = { bold = 2, stubborn = 1 },
            },
            Lamball = {
                work_attitude = { diligent = 1, clingy = 1 },
                social_preference = { loves_petting = 2, comfort_seeking = 1 },
                temperament = { gentle = 2, sunny = 1 },
            },
        },
    },
}

return Config
