local script_source = ""
if type(debug) == "table" and type(debug.getinfo) == "function" then
    local info = debug.getinfo(1, "S")
    if info and info.source then
        script_source = info.source
    end
end
local script_dir = string.match(script_source, "@(.+[\\/])") or "./"
package.path = script_dir .. "?.lua;" .. package.path

local config = require("config")
local util = require("util")
local logger = require("logger")
local json = require("json")
local discovery = require("discovery")
local identity = require("identity")
local persistence = require("persistence")
local traits = require("traits")
local debug_mod = require("debug_mod")

local dialogue = require("dialogue")
local interactions = require("interactions")
local quests = require("quests")
local trust = require("trust")

logger.init(config)
discovery.init(config, logger, util)
identity.init(config, logger, util, discovery)
persistence.init(config, logger, util, json)
traits.init(config, util)
debug_mod.init(logger, util, identity)
dialogue.init(config)
interactions.init(config)
quests.init(config)
trust.init(config)

local Runtime = {
    run_id = tostring(util.now()) .. "_" .. tostring(math.floor((os.clock() * 1000000) % 1000000)),
    world_cycle_index = 0,
    world_cycle_id = "boot",
    is_server = false,
    authority_reason = "unknown",
    world_key = nil,
    state = nil,
    tick_count = 0,
}

local function call_probe(probe_fn)
    local ok, value = pcall(probe_fn)
    if ok and type(value) == "boolean" then
        return true, value
    end
    return false, nil
end

local function detect_server_authority()
    if config.authority.mode == "force_server" then
        return true, "forced_server"
    end
    if config.authority.mode == "force_client" then
        return false, "forced_client"
    end

    local probes = {
        function()
            if type(IsRunningDedicatedServer) == "function" then
                return IsRunningDedicatedServer()
            end
            return nil
        end,
        function()
            if type(IsServer) == "function" then
                return IsServer()
            end
            return nil
        end,
        function()
            if UEHelpers and type(UEHelpers.IsServer) == "function" then
                return UEHelpers:IsServer()
            end
            return nil
        end,
    }

    for i = 1, #probes do
        local ok, value = call_probe(probes[i])
        if ok then
            return value, "probe_" .. tostring(i)
        end
    end

    if config.authority.allow_unknown_as_server then
        return true, "auto_unknown_allowed"
    end
    return false, "auto_unknown_blocked"
end

local function read_world_hint()
    if config.world.world_key_override and config.world.world_key_override ~= "" then
        return util.sanitize_key(config.world.world_key_override)
    end

    local world_text = nil
    local ok_world, world_obj = pcall(function()
        if type(GetWorld) == "function" then
            return GetWorld()
        end
        return nil
    end)
    if ok_world and world_obj ~= nil then
        world_text = util.safe_tostring(world_obj)
    end

    if not world_text or world_text == "" then
        world_text = "unknown_world"
    else
        world_text = string.gsub(world_text, "0x[%x]+", "")
        world_text = string.gsub(world_text, "%s+", "_")
    end

    local server_identity = util.sanitize_key(config.world.server_identity or "dedicated_default")
    local world_part = util.sanitize_key(world_text)
    if world_part == "unknown" or world_part == "" then
        world_part = "unknown_world"
    end
    if #world_part > 64 then
        world_part = string.sub(world_part, 1, 40) .. "_" .. tostring(util.hash_text(world_part))
    end
    return server_identity .. "__" .. world_part
end

local function mark_state_dirty(reason)
    if not Runtime.state then
        return
    end
    persistence.mark_dirty(Runtime.state, reason)
end

local function ensure_world_state_loaded()
    if not Runtime.is_server then
        return false
    end

    if Runtime.state then
        return true
    end

    Runtime.world_key = read_world_hint()
    Runtime.state = persistence.load_world_state(Runtime.world_key)
    identity.bind_state(Runtime.state, Runtime)

    logger.info(
        "CozyPals state initialized. world_key=" .. tostring(Runtime.world_key) ..
        " run_id=" .. tostring(Runtime.run_id)
    )
    return true
end

local function process_verified_guid(result, resolved)
    if not ensure_world_state_loaded() then
        return
    end

    local guid = resolved.guid
    local meta = {
        home_base_id = result.context and (result.context.BaseCampId or result.context.BaseCampID),
    }

    local record, created = persistence.get_or_create_pal_record(
        Runtime.state,
        guid,
        result.species_hint,
        meta
    )

    record.verification = record.verification or {}
    record.verification.guid_source = resolved.source_path
    record.meta.last_seen = util.now()

    if not record.personality or not record.personality.seed then
        record.personality = traits.roll_personality(guid, record.species)
        mark_state_dirty("personality_rolled:" .. tostring(guid))
        logger.info("[M1][PASS] Personality assigned guid=" .. tostring(guid) .. " seed=" .. tostring(record.personality.seed))
    end

    if created then
        mark_state_dirty("pal_record_created:" .. tostring(guid))
        logger.info("[M1][PASS] New persistent pal record created guid=" .. tostring(guid))
    else
        mark_state_dirty("pal_record_rebound:" .. tostring(guid))
        logger.info("[M1][PASS] Existing pal record rebound guid=" .. tostring(guid), "m1_rebound_" .. tostring(guid), 30)
    end
end

local function on_world_ready(trigger_name)
    Runtime.world_cycle_index = Runtime.world_cycle_index + 1
    Runtime.world_cycle_id = Runtime.run_id .. "_wc" .. tostring(Runtime.world_cycle_index)
    identity.set_runtime(Runtime)

    if not Runtime.is_server then
        logger.warn(
            "CozyPals in observer mode (not authoritative). trigger=" .. tostring(trigger_name) ..
            " reason=" .. tostring(Runtime.authority_reason),
            "observer_mode_" .. tostring(trigger_name),
            60
        )
        return
    end

    ensure_world_state_loaded()
    logger.info(
        "World ready cycle started. trigger=" .. tostring(trigger_name) ..
        " world_cycle_id=" .. tostring(Runtime.world_cycle_id)
    )
end

local function on_actor_begin_play(actor)
    if not config.discovery.enabled then
        return
    end
    if not actor then
        return
    end

    local result = discovery.scan_actor(actor)
    if not result then
        return
    end

    discovery.log_result(result)
    local report_line = discovery.format_structured_report(result)
    logger.discovery("report " .. tostring(report_line), "disc_report_" .. tostring(result.actor_key), 20)

    local resolved = identity.resolve_pal_guid(actor, result)
    if resolved.status == "verified" then
        process_verified_guid(result, resolved)
    elseif resolved.status == "candidate" then
        logger.warn(
            "[M1][BLOCKED] GUID candidate not verified yet. guid=" .. tostring(resolved.guid) ..
            " source=" .. tostring(resolved.source_path) ..
            " runs=" .. tostring(resolved.verification and resolved.verification.run_count) ..
            " world_cycles=" .. tostring(resolved.verification and resolved.verification.world_cycle_count) ..
            " contexts=" .. tostring(resolved.verification and resolved.verification.context_count),
            "m1_blocked_" .. tostring(resolved.guid),
            30
        )
        if Runtime.state then
            mark_state_dirty("verification_progress")
        end
    end
end

local function periodic_tick()
    Runtime.tick_count = Runtime.tick_count + 1
    if Runtime.is_server and Runtime.state then
        persistence.autosave_if_needed(Runtime.state)
    end
end

local function safe_wrap(fn, label)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            logger.err("Callback failure (" .. tostring(label) .. "): " .. tostring(err))
        end
    end
end

local function try_register_hooks()
    local begin_ok, begin_err = pcall(function()
        RegisterBeginPlayPreHook(safe_wrap(on_actor_begin_play, "BeginPlayPre"))
    end)
    if begin_ok then
        logger.info("Registered BeginPlay pre-hook for actor discovery.")
    else
        logger.err("Failed to register BeginPlay pre-hook: " .. tostring(begin_err))
    end

    local restart_ok, restart_err = pcall(function()
        RegisterHook("/Script/Engine.PlayerController:ClientRestart", safe_wrap(function()
            on_world_ready("ClientRestart")
        end, "ClientRestart"))
    end)
    if restart_ok then
        logger.info("Registered ClientRestart hook.")
    else
        logger.warn("ClientRestart hook unavailable: " .. tostring(restart_err))
    end

    local tick_paths = {
        "/Script/Engine.World:Tick",
        "/Script/Engine.Actor:ReceiveTick",
    }
    local tick_registered = false
    for i = 1, #tick_paths do
        local path = tick_paths[i]
        local ok = pcall(function()
            RegisterHook(path, safe_wrap(function()
                periodic_tick()
            end, "Tick"))
        end)
        if ok then
            tick_registered = true
            logger.info("Registered tick hook path=" .. tostring(path))
            break
        end
    end
    if not tick_registered then
        logger.warn("No supported tick hook found; autosave depends on event-driven dirty flush.")
    end
end

Runtime.is_server, Runtime.authority_reason = detect_server_authority()
identity.set_runtime(Runtime)

logger.info(
    "Starting CozyPals " .. tostring(config.mod_version) ..
    " | server_authority=" .. tostring(Runtime.is_server) ..
    " reason=" .. tostring(Runtime.authority_reason)
)

try_register_hooks()
on_world_ready("module_load")

_G.CozyPals = _G.CozyPals or {}
_G.CozyPals.on_world_ready = on_world_ready
_G.CozyPals.on_actor_begin_play = on_actor_begin_play
_G.CozyPals.periodic_tick = periodic_tick
_G.CozyPals.force_save = function()
    if not Runtime.state then
        logger.warn("No state loaded to save.")
        return false
    end
    local ok, err = persistence.save_world_state(Runtime.state)
    if ok then
        logger.info("Manual save complete.")
    else
        logger.err("Manual save failed: " .. tostring(err))
    end
    return ok
end
_G.CozyPals.debug_dump_all_pals = function()
    debug_mod.dump_all_pals(Runtime.state)
end
_G.CozyPals.debug_dump_pal = function(guid)
    debug_mod.dump_pal_state(Runtime.state, guid)
end
_G.CozyPals.debug_dump_verification = function()
    debug_mod.dump_verification_report()
end
