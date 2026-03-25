local Interactions = {}

local _config = nil
local _logger = nil
local _util = nil
local _json = nil
local _dialogue = nil
local _trust = nil
local _persistence = nil
local _quests = nil
local _identity = nil
local _runtime = nil

local _bridge_dir = nil
local _requests_path = nil
local _responses_path = nil
local _native_actions_path = nil
local _input_state_path = nil
local _client_state_path = nil

local _ue_helpers = nil
local _kismet_system = nil
local _kismet_math = nil
local _native_identity_by_full_name = {}
local _native_identity_by_guid = {}
local _client = {
    last_native_load = 0,
    last_response_load = 0,
    last_input_poll = 0,
    request_counter = 0,
    last_native_action_load = 0,
    menu_open = false,
    menu_opened_at = 0,
    hold_started_at = 0,
    hold_target_key = nil,
    last_focus_key = nil,
    last_input_counts = {
        interact = 0,
        alt = 0,
    },
    handled_responses = {},
    handled_native_actions = {},
    last_state_payload = nil,
}
local _server = {
    seen_request_ids = {},
    live_owned_guids = {},
    last_request_poll = 0,
    last_live_guid_refresh = 0,
}

local function now_seconds()
    return os.clock()
end

local function parse_json_lines(path)
    local payload = _util.read_file(path)
    if not payload or payload == "" then
        return {}
    end

    local rows = {}
    for line in string.gmatch(payload, "[^\r\n]+") do
        if line ~= "" then
            local decoded = _json.decode(line)
            if decoded ~= nil then
                rows[#rows + 1] = decoded
            end
        end
    end
    return rows
end

local function append_json_line(path, row)
    return _util.append_file(path, _json.encode(row) .. "\n")
end

local function infer_bridge_directory()
    local configured = _config.interaction and _config.interaction.bridge_directory
    if configured and configured ~= "" then
        return configured
    end
    return _util.default_bridge_directory()
end

local function ensure_bridge()
    _bridge_dir = _bridge_dir or infer_bridge_directory()
    _requests_path = _requests_path or _util.path_join(_bridge_dir, _config.interaction.requests_file)
    _responses_path = _responses_path or _util.path_join(_bridge_dir, _config.interaction.responses_file)
    _native_actions_path = _native_actions_path or _util.path_join(_bridge_dir, (_config.interaction.native_wheel_actions_file or "native_wheel_actions.jsonl"))
    _input_state_path = _input_state_path or _util.path_join(_bridge_dir, _config.interaction.input_state_file)
    _client_state_path = _client_state_path or _util.path_join(_bridge_dir, _config.interaction.client_state_file)
    _util.ensure_directory(_bridge_dir)
end

local function safe_decode_file(path, fallback)
    local payload = _util.read_file(path)
    if not payload or payload == "" then
        return fallback
    end

    local decoded = _json.decode(payload)
    if decoded == nil then
        return fallback
    end
    return decoded
end

local function pipe_fields(line, expected_fields)
    local fields = {}
    local start_index = 1
    expected_fields = expected_fields or 0

    while true do
        local separator_index = string.find(line, "|", start_index, true)
        if not separator_index then
            fields[#fields + 1] = string.sub(line, start_index)
            break
        end
        fields[#fields + 1] = string.sub(line, start_index, separator_index - 1)
        start_index = separator_index + 1
        if expected_fields > 0 and #fields >= expected_fields - 1 then
            fields[#fields + 1] = string.sub(line, start_index)
            break
        end
    end

    return fields
end

local function normalize_species(species)
    local text = tostring(species or "")
    text = string.gsub(text, "^species:", "")
    text = string.gsub(text, "^BP_", "")
    text = string.gsub(text, "_C$", "")
    return text
end

local function species_label(species)
    local normalized = normalize_species(species)
    if normalized == "" then
        return "Pal"
    end
    return normalized
end

local function load_native_identity_lookup()
    local path = _config.native_bridge and _config.native_bridge.identities_file
    if not path or path == "" then
        return
    end

    local payload = _util.read_file(path)
    if not payload or payload == "" then
        return
    end

    _native_identity_by_full_name = {}
    _native_identity_by_guid = {}

    for line in string.gmatch(payload, "[^\r\n]+") do
        local fields = pipe_fields(line, 4)
        local raw_address = tostring(fields[1] or "")
        local full_name = tostring(fields[2] or "")
        local guid = tostring(fields[3] or "")
        local source_path = tostring(fields[4] or "")

        if full_name ~= "" and guid ~= "" then
            local entry = {
                address = raw_address,
                full_name = full_name,
                guid = guid,
                source_path = source_path,
            }
            _native_identity_by_full_name[full_name] = entry
            _native_identity_by_guid[guid] = entry
        end
    end
end

local function ensure_ue_helpers()
    if _ue_helpers then
        return true
    end

    local ok, helper_module = pcall(require, "UEHelpers")
    if ok then
        _ue_helpers = helper_module
        return true
    end
    return false
end

local function get_player_controller()
    if not ensure_ue_helpers() then
        return nil
    end
    local ok, controller = pcall(_ue_helpers.GetPlayerController)
    if ok then
        return controller
    end
    return nil
end

local function get_player_pawn()
    local controller = get_player_controller()
    if controller and controller.Pawn and controller.Pawn:IsValid() then
        return controller.Pawn
    end
    return nil
end

local function get_kismet_system()
    if _kismet_system then
        return _kismet_system
    end
    if not ensure_ue_helpers() then
        return nil
    end
    local ok, value = pcall(_ue_helpers.GetKismetSystemLibrary)
    if ok then
        _kismet_system = value
    end
    return _kismet_system
end

local function get_kismet_math()
    if _kismet_math then
        return _kismet_math
    end
    if not ensure_ue_helpers() then
        return nil
    end
    local ok, value = pcall(_ue_helpers.GetKismetMathLibrary)
    if ok then
        _kismet_math = value
    end
    return _kismet_math
end

local function get_actor_from_hit_result(hit_result)
    if UnrealVersion and type(UnrealVersion.IsBelow) == "function" and UnrealVersion:IsBelow(5, 0) then
        return hit_result.Actor and hit_result.Actor:Get() or nil
    end
    return hit_result.HitObjectHandle and hit_result.HitObjectHandle.Actor and hit_result.HitObjectHandle.Actor:Get() or nil
end

local function distance_between(actor, pawn)
    if not actor or not pawn then
        return nil
    end

    local ok_actor, actor_location = pcall(function()
        return actor:K2_GetActorLocation()
    end)
    local ok_pawn, pawn_location = pcall(function()
        return pawn:K2_GetActorLocation()
    end)
    if not ok_actor or not ok_pawn or not actor_location or not pawn_location then
        return nil
    end

    local dx = (tonumber(actor_location.X) or 0) - (tonumber(pawn_location.X) or 0)
    local dy = (tonumber(actor_location.Y) or 0) - (tonumber(pawn_location.Y) or 0)
    local dz = (tonumber(actor_location.Z) or 0) - (tonumber(pawn_location.Z) or 0)
    return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
end

local function get_focused_actor()
    local controller = get_player_controller()
    local pawn = get_player_pawn()
    local kismet_system = get_kismet_system()
    local kismet_math = get_kismet_math()

    if not controller or not pawn or not kismet_system or not kismet_math then
        return nil
    end

    local camera_manager = controller.PlayerCameraManager
    if not camera_manager or not camera_manager:IsValid() then
        return nil
    end

    local start_vector = camera_manager:GetCameraLocation()
    local forward_vector = kismet_math:GetForwardVector(camera_manager:GetCameraRotation())
    local add_value = kismet_math:Multiply_VectorFloat(forward_vector, _config.interaction.line_trace_distance or 2200)
    local end_vector = kismet_math:Add_VectorVector(start_vector, add_value)
    local trace_color = { R = 0, G = 0, B = 0, A = 0 }
    local hit_result = {}
    local actors_to_ignore = {}
    local e_draw_debug_none = 0
    local e_trace_type_query1 = 0

    local ok, was_hit = pcall(function()
        return kismet_system:LineTraceSingle(
            pawn,
            start_vector,
            end_vector,
            e_trace_type_query1,
            false,
            actors_to_ignore,
            e_draw_debug_none,
            hit_result,
            true,
            trace_color,
            trace_color,
            0.0
        )
    end)

    if not ok or not was_hit then
        return nil
    end

    local actor = get_actor_from_hit_result(hit_result)
    if not actor or not actor:IsValid() then
        return nil
    end

    return actor
end

local function focused_target()
    local actor = get_focused_actor()
    if not actor then
        return nil
    end

    local full_name = _util.safe_tostring(actor.GetFullName and actor:GetFullName() or actor)
    local guid_entry = _native_identity_by_full_name[full_name]
    if not guid_entry then
        return nil
    end

    local pawn = get_player_pawn()
    local distance = distance_between(actor, pawn)
    if distance and distance > (_config.interaction.interaction_max_range or 1200) then
        return nil
    end

    return {
        actor = actor,
        full_name = full_name,
        guid = guid_entry.guid,
        source_path = guid_entry.source_path,
        distance = distance,
        species = species_label(full_name),
    }
end

local function read_input_state()
    ensure_bridge()
    return safe_decode_file(_input_state_path, {
        updated_at = 0,
        interact_down = false,
        interact_press_count = 0,
        alt_down = false,
        alt_press_count = 0,
    })
end

local function interaction_prompt_text(target)
    if not target then
        return ""
    end
    return "Talk [" .. tostring((_config.interaction.wheel_actions or {})[1] or "Talk") .. "] / Pet [" .. tostring((_config.interaction.wheel_actions or {})[2] or "Pet") .. "]"
end

local function write_client_state(target, extra)
    ensure_bridge()

    local state = {
        updated_at = _util.now(),
        menu_open = _client.menu_open,
        hold_target_guid = target and target.guid or nil,
        hold_target_name = target and target.full_name or nil,
        prompt_text = interaction_prompt_text(target),
    }

    if type(extra) == "table" then
        for key, value in pairs(extra) do
            state[key] = value
        end
    end

    local payload = _json.encode(state)
    if payload ~= _client.last_state_payload then
        _util.write_file(_client_state_path, payload)
        _client.last_state_payload = payload
    end
end

local function resolve_actor_by_guid(guid)
    local entry = _native_identity_by_guid[guid]
    if not entry then
        return nil
    end

    local ok, object = pcall(function()
        return StaticFindObject(entry.full_name)
    end)
    if ok and object and object:IsValid() then
        return object
    end

    return nil
end

local function best_effort_stop_actor(actor)
    if not actor then
        return
    end

    pcall(function()
        if actor.CharacterMovement and actor.CharacterMovement:IsValid() and actor.CharacterMovement.StopMovementImmediately then
            actor.CharacterMovement:StopMovementImmediately()
        end
    end)
end

local function best_effort_face_player(actor)
    if not actor or not _config.interaction.talk_face_player then
        return
    end

    local pawn = get_player_pawn()
    local kismet_math = get_kismet_math()
    if not pawn or not kismet_math then
        return
    end

    local ok = pcall(function()
        local actor_location = actor:K2_GetActorLocation()
        local pawn_location = pawn:K2_GetActorLocation()
        local look_rotation = kismet_math:FindLookAtRotation(actor_location, pawn_location)
        actor:K2_SetActorRotation(look_rotation, false)
    end)

    if not ok then
        return
    end
end

local function show_client_message(text)
    local player_controller = get_player_controller()
    if player_controller then
        local ok = pcall(function()
            player_controller:ClientMessage(text)
        end)
        if ok then
            return
        end
    end

    _logger.info("[Interaction][ClientUI] " .. tostring(text))
end

local function make_request_id()
    _client.request_counter = _client.request_counter + 1
    return tostring(_util.now()) .. "_" .. tostring(_client.request_counter)
end

local function submit_request(action, target)
    ensure_bridge()

    local request = {
        id = make_request_id(),
        action = action,
        guid = target.guid,
        actor_full_name = target.full_name,
        requested_at = _util.now(),
        requested_by = "local_client",
        player_name = _config.dialogue.default_player_name or "Trainer",
    }

    append_json_line(_requests_path, request)
    _client.menu_open = false
    _client.menu_opened_at = 0
    write_client_state(target, {
        pending_request_id = request.id,
        pending_action = action,
    })
end

local function refresh_server_live_guids()
    local path = _config.native_bridge and _config.native_bridge.identities_file
    if not path or path == "" then
        return
    end

    local payload = _util.read_file(path)
    if not payload or payload == "" then
        _server.live_owned_guids = {}
        return
    end

    local live = {}
    for line in string.gmatch(payload, "[^\r\n]+") do
        local fields = pipe_fields(line, 4)
        local guid = tostring(fields[3] or "")
        if guid ~= "" then
            live[guid] = true
        end
    end
    _server.live_owned_guids = live
end

local function interaction_record_meta(record, guid)
    local trust_value = _trust.current_value(record)
    return {
        guid = guid,
        trust_value = trust_value,
        personality = record.personality or {},
    }
end

function Interactions.handle_interaction(context)
    local action = tostring(context.action or "")
    local guid = tostring(context.guid or "")
    if guid == "" then
        return false, "missing_guid"
    end
    if not _runtime or not _runtime.state or not _runtime.state.pals then
        return false, "state_unavailable"
    end

    local record = _runtime.state.pals[guid]
    if not record then
        return false, "unknown_guid"
    end

    local trust_state = interaction_record_meta(record, guid)
    local species = normalize_species(record.species)

    if action == "talk" then
        local trust_ok, trust_result = _trust.apply_effects({
            action = "talk",
            guid = guid,
            record = record,
        })
        if not trust_ok then
            return false, trust_result
        end

        local quest_result = {
            trigger = "talk",
            quest = nil,
            created = false,
            dirty = false,
        }
        if _quests and type(_quests.prepare_talk) == "function" then
            local quest_ok, prepared = _quests.prepare_talk({
                guid = guid,
                record = record,
                trust_value = trust_result.trust_value,
                player_name = context.player_name,
                species = species,
            })
            if not quest_ok then
                return false, prepared
            end
            quest_result = prepared or quest_result
        end

        local active_fetch = quest_result.quest
        local trigger = tostring(quest_result.trigger or "talk")
        local line = _dialogue.get_line({
            trigger = trigger,
            species = species,
            pal_name = species_label(species),
            player_name = context.player_name,
            trust_value = trust_result.trust_value,
            personality = record.personality,
            activity_state = "idle",
            item_name = active_fetch and active_fetch.item_display_name or nil,
            item_base_name = active_fetch and active_fetch.item_name or nil,
            item_label = active_fetch and active_fetch.item_display_name or nil,
            item_count = active_fetch and active_fetch.required_count or nil,
        })
        if not line then
            if trigger == "quest_request" and active_fetch then
                line = {
                    text = "Could you bring me " .. tostring(active_fetch.item_display_name or active_fetch.item_name or "that item") .. "?",
                    line_id = "fallback_quest_request",
                }
            elseif trigger == "quest_pending" and active_fetch then
                line = {
                    text = "I'm still waiting for " .. tostring(active_fetch.item_display_name or active_fetch.item_name or "that item") .. ".",
                    line_id = "fallback_quest_pending",
                }
            else
                return false, "no_dialogue_line"
            end
        end

        _persistence.mark_dirty(_runtime.state, "interaction_talk:" .. guid)
        return true, {
            kind = "talk",
            guid = guid,
            text = line.text,
            line_id = line.line_id,
            trust_value = trust_result.trust_value,
            quest_trigger = trigger,
            quest_id = active_fetch and active_fetch.quest_id or nil,
            quest_item_name = active_fetch and active_fetch.item_name or nil,
            quest_item_display_name = active_fetch and active_fetch.item_display_name or nil,
            quest_required_count = active_fetch and active_fetch.required_count or nil,
            should_face_player = _config.interaction.talk_face_player,
            should_emote = _config.interaction.talk_emote_enabled,
        }
    end

    if action == "pet" then
        local ok, effect = _trust.apply_effects({
            action = "pet",
            guid = guid,
            record = record,
        })
        if not ok then
            return false, effect
        end

        local line = _dialogue.get_line({
            trigger = "pet",
            species = species,
            pal_name = species_label(species),
            player_name = context.player_name,
            trust_value = effect.trust_value,
            personality = record.personality,
            activity_state = "idle",
        })

        _persistence.mark_dirty(_runtime.state, "interaction_pet:" .. guid)
        return true, {
            kind = "pet",
            guid = guid,
            text = line and line.text or ("You pet " .. species_label(species) .. "."),
            line_id = line and line.line_id or nil,
            trust_value = effect.trust_value,
            affection_points = effect.affection_points,
            should_face_player = true,
            should_emote = _config.interaction.pet_affection_enabled,
        }
    end

    return false, "unsupported_action"
end

local function handle_server_requests()
    if not _runtime or not _runtime.is_server or not _config.interaction.enabled then
        return
    end

    ensure_bridge()
    refresh_server_live_guids()

    local rows = parse_json_lines(_requests_path)
    for i = 1, #rows do
        local request = rows[i]
        local request_id = tostring(request.id or "")
        local guid = tostring(request.guid or "")
        if request_id ~= "" and not _server.seen_request_ids[request_id] then
            _server.seen_request_ids[request_id] = true

            local status = "rejected"
            local payload = {
                request_id = request_id,
                guid = guid,
                action = request.action,
                processed_at = _util.now(),
            }

            if guid ~= "" and _server.live_owned_guids[guid] and _runtime.state and _runtime.state.pals and _runtime.state.pals[guid] then
                local ok, result = Interactions.handle_interaction(request)
                if ok then
                    status = "ok"
                    for key, value in pairs(result) do
                        payload[key] = value
                    end
                else
                    payload.reason = tostring(result)
                end
            else
                payload.reason = "guid_not_live_or_owned"
            end

            payload.status = status
            append_json_line(_responses_path, payload)
        end
    end
end

local function handle_client_responses()
    if _runtime and _runtime.is_server then
        return
    end

    local rows = parse_json_lines(_responses_path)
    for i = 1, #rows do
        local response = rows[i]
        local request_id = tostring(response.request_id or "")
        if request_id ~= "" and not _client.handled_responses[request_id] then
            _client.handled_responses[request_id] = true
            if tostring(response.status or "") == "ok" then
                local actor = resolve_actor_by_guid(response.guid)
                if actor then
                    best_effort_stop_actor(actor)
                    if response.should_face_player then
                        best_effort_face_player(actor)
                    end
                end
                show_client_message(tostring(response.text or ""))
                write_client_state(nil, {
                    last_response_id = request_id,
                    last_response_text = response.text,
                    last_response_kind = response.kind,
                })
            end
        end
    end
end

local function handle_native_wheel_actions()
    ensure_bridge()

    local rows = parse_json_lines(_native_actions_path)
    for i = 1, #rows do
        local action_row = rows[i]
        local action_id = tostring(action_row.id or "")
        if action_id ~= "" and not _client.handled_native_actions[action_id] then
            _client.handled_native_actions[action_id] = true

            local action = tostring(action_row.action or "")
            if action == "talk" then
                local target = focused_target()
                if target then
                    submit_request("talk", target)
                else
                    show_client_message("Couldn't find a pal to talk to.")
                end
            elseif action == "pet" then
                local target = focused_target()
                if target then
                    submit_request("pet", target)
                else
                    show_client_message("Couldn't find a pal to interact with.")
                end
            end
        end
    end
end

local function client_tick()
    if _runtime and _runtime.is_server then
        return
    end

    ensure_bridge()
    if now_seconds() - _client.last_native_load >= (_config.interaction.identities_poll_interval_seconds or 0.5) then
        load_native_identity_lookup()
        _client.last_native_load = now_seconds()
    end

    if now_seconds() - _client.last_response_load >= (_config.interaction.response_poll_interval_seconds or 0.25) then
        handle_client_responses()
        _client.last_response_load = now_seconds()
    end

    if now_seconds() - _client.last_native_action_load >= (_config.interaction.response_poll_interval_seconds or 0.25) then
        handle_native_wheel_actions()
        _client.last_native_action_load = now_seconds()
    end

    if _config.interaction.legacy_hold_interaction_enabled == false then
        write_client_state(nil, {
            client_ready = true,
            interaction_mode = "builtin_radial_probe",
        })
        return
    end

    local target = focused_target()
    local focus_key = target and (target.guid .. "|" .. target.full_name) or nil
    local input_state = read_input_state()
    local interact_down = input_state.interact_down == true
    local alt_down = input_state.alt_down == true
    local interact_pressed = (tonumber(input_state.interact_press_count) or 0) > (_client.last_input_counts.interact or 0)
    local alt_pressed = (tonumber(input_state.alt_press_count) or 0) > (_client.last_input_counts.alt or 0)
    _client.last_input_counts.interact = tonumber(input_state.interact_press_count) or 0
    _client.last_input_counts.alt = tonumber(input_state.alt_press_count) or 0

    if not target then
        _client.menu_open = false
        _client.hold_started_at = 0
        _client.hold_target_key = nil
        write_client_state(nil)
        return
    end

    if interact_down then
        if _client.hold_target_key ~= focus_key then
            _client.hold_target_key = focus_key
            _client.hold_started_at = now_seconds()
        end

        if not _client.menu_open and (now_seconds() - _client.hold_started_at) >= (_config.interaction.hold_seconds or 0.45) then
            _client.menu_open = true
            _client.menu_opened_at = now_seconds()
            write_client_state(target, {
                selection_mode = "quick_select",
                talk_binding = "interact",
                pet_binding = "alt",
            })
        end
    elseif not _client.menu_open then
        _client.hold_started_at = 0
        _client.hold_target_key = nil
    end

    if _client.menu_open and (now_seconds() - _client.menu_opened_at) > (_config.interaction.hold_reset_seconds or 0.75) then
        _client.menu_open = false
        write_client_state(target, { dismissed = true })
        return
    end

    if _client.menu_open then
        if interact_pressed then
            submit_request("talk", target)
            return
        end
        if alt_pressed or alt_down then
            submit_request("pet", target)
            return
        end
    end

    if _config.interaction.debug_log_focus then
        _logger.debug("[Interaction][Focus] " .. tostring(target.full_name), "interaction_focus_" .. tostring(target.guid), 1)
    end
end

function Interactions.init(config, logger, util, json, dialogue, trust, persistence, quests)
    _config = config
    _logger = logger
    _util = util
    _json = json
    _dialogue = dialogue
    _trust = trust
    _persistence = persistence
    _quests = quests
    ensure_bridge()
end

function Interactions.bind_runtime(runtime, identity)
    _runtime = runtime
    _identity = identity
end

function Interactions.on_world_ready(runtime)
    _runtime = runtime or _runtime
    ensure_bridge()
    if _runtime and _runtime.is_server then
        _util.write_file(_requests_path, "")
        _util.write_file(_responses_path, "")
        _util.write_file(_native_actions_path, "")
        _server.seen_request_ids = {}
    else
        _util.write_file(_requests_path, "")
        _util.write_file(_native_actions_path, "")
        _client.handled_responses = {}
        _client.handled_native_actions = {}
        load_native_identity_lookup()
        write_client_state(nil, {
            client_ready = true,
        })
    end
end

function Interactions.periodic_tick(runtime)
    _runtime = runtime or _runtime
    if not _config.interaction.enabled then
        return
    end

    if _runtime and _runtime.is_server then
        if now_seconds() - _server.last_request_poll >= (_config.interaction.requests_poll_interval_seconds or 0.25) then
            handle_server_requests()
            _server.last_request_poll = now_seconds()
        end
    else
        client_tick()
    end
end

return Interactions
