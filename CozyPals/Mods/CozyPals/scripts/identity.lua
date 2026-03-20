local Identity = {}

local _config = nil
local _logger = nil
local _util = nil
local _discovery = nil

local _state = nil
local _runtime = nil

local function ensure_verification_tables(state)
    state.guid_verification = state.guid_verification or {}
    state.guid_verification.version = state.guid_verification.version or 1
    state.guid_verification.sources = state.guid_verification.sources or {}
    state.guid_verification.report = state.guid_verification.report or {}
    return state.guid_verification
end

local function set_add(set_table, key)
    if key == nil then
        return
    end
    set_table[tostring(key)] = true
end

local function set_count(set_table)
    return _util.table_size(set_table)
end

local function to_source_key(source_path, property)
    return tostring(source_path or "unknown") .. "::" .. tostring(property or "unknown")
end

local function split_native_source_path(source_path)
    local source_text = tostring(source_path or "")
    local property = "IndividualId.InstanceId"
    local suffix = ".IndividualId.InstanceId"
    if string.sub(source_text, -#suffix) == suffix then
        return string.sub(source_text, 1, #source_text - #suffix), property
    end
    return source_text, property
end

local function is_preferred_identity_property(property_name)
    local preferred = (_config and _config.discovery and _config.discovery.preferred_guid_paths) or {}
    for i = 1, #preferred do
        if property_name == preferred[i] then
            return true
        end
    end
    return false
end

local function is_native_trusted_source(source_path)
    local trusted = (_config and _config.native_bridge and _config.native_bridge.trusted_identity_source_substrings) or {}
    local source_text = tostring(source_path or "")
    for i = 1, #trusted do
        local needle = trusted[i]
        if needle and needle ~= "" and string.find(source_text, needle, 1, true) ~= nil then
            return true
        end
    end
    return false
end

local function ensure_source_record(source_key, source_path, property)
    local verification = ensure_verification_tables(_state)
    local sources = verification.sources
    local source = sources[source_key]
    if not source then
        source = {
            source_path = source_path,
            property = property,
            status = "candidate",
            verified_guid = nil,
            verified_at = 0,
            values = {},
            last_seen = 0,
        }
        sources[source_key] = source
    end
    return source
end

local function ensure_value_record(source_record, guid_text)
    local value_record = source_record.values[guid_text]
    if not value_record then
        value_record = {
            guid = guid_text,
            first_seen = _util.now(),
            last_seen = _util.now(),
            run_ids = {},
            world_cycle_ids = {},
            contexts = {},
            run_count = 0,
            world_cycle_count = 0,
            context_count = 0,
        }
        source_record.values[guid_text] = value_record
    end
    return value_record
end

local function update_value_record(value_record, context_hash)
    value_record.last_seen = _util.now()
    set_add(value_record.run_ids, _runtime.run_id)
    set_add(value_record.world_cycle_ids, _runtime.world_cycle_id)
    set_add(value_record.contexts, context_hash)
    value_record.run_count = set_count(value_record.run_ids)
    value_record.world_cycle_count = set_count(value_record.world_cycle_ids)
    value_record.context_count = set_count(value_record.contexts)
end

local function is_verified(value_record)
    local policy = _config.verification or {}
    local run_ok = value_record.run_count >= (policy.require_run_count or 2)
    local cycle_ok = value_record.world_cycle_count >= (policy.require_world_cycle_count or 2)
    local move_ok = true
    if policy.require_move_check then
        move_ok = value_record.context_count >= 2
    end
    return run_ok and cycle_ok and move_ok
end

local function update_report(source_key, source_record, value_record)
    local verification = ensure_verification_tables(_state)
    verification.report[source_key] = {
        source_path = source_record.source_path,
        property = source_record.property,
        status = source_record.status,
        verified_guid = source_record.verified_guid,
        run_count = value_record.run_count,
        world_cycle_count = value_record.world_cycle_count,
        context_count = value_record.context_count,
        last_seen = value_record.last_seen,
    }
end

function Identity.init(config, logger, util, discovery)
    _config = config
    _logger = logger
    _util = util
    _discovery = discovery
end

function Identity.bind_state(state, runtime)
    _state = state
    _runtime = runtime
    ensure_verification_tables(_state)
end

function Identity.set_runtime(runtime)
    _runtime = runtime
end

function Identity.resolve_pal_guid(actor, pre_scanned)
    if not _state or not _runtime then
        return {
            status = "none",
            guid = nil,
            source_path = nil,
            confidence = 0,
            reason = "identity_not_initialized",
        }
    end

    local result = pre_scanned or _discovery.scan_actor(actor)
    if not result then
        return {
            status = "none",
            guid = nil,
            source_path = nil,
            confidence = 0,
            reason = "not_candidate_actor",
        }
    end

    local best = result.best_candidate
    if not best or best.value == nil then
        return {
            status = "none",
            guid = nil,
            source_path = nil,
            confidence = 0,
            reason = "no_guid_candidates_found",
        }
    end

    local guid_text = tostring(best.value)
    if _util.is_unreal_param_text(guid_text) or _util.is_uobject_text(guid_text) then
        return {
            status = "none",
            guid = nil,
            source_path = nil,
            confidence = 0,
            reason = "unresolved_identity_wrapper",
        }
    end
    if not is_preferred_identity_property(best.property) then
        return {
            status = "none",
            guid = nil,
            source_path = nil,
            confidence = 0,
            reason = "non_preferred_identity_source",
        }
    end
    if not _util.guid_like(guid_text) then
        return {
            status = "none",
            guid = nil,
            source_path = nil,
            confidence = 0,
            reason = "candidate_not_guid_like",
        }
    end

    local source_key = to_source_key(best.source_path, best.property)
    local source_record = ensure_source_record(source_key, best.source_path, best.property)
    source_record.last_seen = _util.now()

    local context_hash = _util.serialize_context(result.context)
    local value_record = ensure_value_record(source_record, guid_text)
    update_value_record(value_record, context_hash)

    if is_native_trusted_source(best.source_path) or is_verified(value_record) then
        if source_record.status ~= "verified" then
            source_record.status = "verified"
            source_record.verified_guid = guid_text
            source_record.verified_at = _util.now()
            _logger.info(
                "[M1][GUID VERIFIED] source=" .. tostring(source_key) ..
                " sample_guid=" .. tostring(guid_text) ..
                " trusted_native=" .. tostring(is_native_trusted_source(best.source_path)) ..
                " runs=" .. tostring(value_record.run_count) ..
                " world_cycles=" .. tostring(value_record.world_cycle_count) ..
                " contexts=" .. tostring(value_record.context_count)
            )
        end
    elseif source_record.status ~= "verified" then
        source_record.status = "candidate"
        source_record.verified_guid = nil
    end

    update_report(source_key, source_record, value_record)

    if source_record.status == "verified" then
        return {
            status = "verified",
            guid = guid_text,
            source_path = tostring(best.source_path) .. "." .. tostring(best.property),
            confidence = best.confidence or 0,
        }
    end

    return {
        status = "candidate",
        guid = guid_text,
        source_path = tostring(best.source_path) .. "." .. tostring(best.property),
        confidence = best.confidence or 0,
        verification = {
            run_count = value_record.run_count,
            world_cycle_count = value_record.world_cycle_count,
            context_count = value_record.context_count,
        },
    }
end

function Identity.accept_native_guid(guid_text, source_path, context_hash)
    if not _state or not _runtime then
        return {
            status = "none",
            guid = nil,
            source_path = nil,
            confidence = 0,
            reason = "identity_not_initialized",
        }
    end

    local guid_value = tostring(guid_text or "")
    if not _util.guid_like(guid_value) then
        return {
            status = "none",
            guid = nil,
            source_path = nil,
            confidence = 0,
            reason = "candidate_not_guid_like",
        }
    end

    local normalized_source_path, property = split_native_source_path(source_path)
    local source_key = to_source_key(normalized_source_path, property)
    local source_record = ensure_source_record(source_key, normalized_source_path, property)
    source_record.last_seen = _util.now()

    local value_record = ensure_value_record(source_record, guid_value)
    update_value_record(value_record, context_hash or "native_cache")

    if source_record.status ~= "verified" then
        source_record.status = "verified"
        source_record.verified_guid = guid_value
        source_record.verified_at = _util.now()
        _logger.info(
            "[M1][GUID VERIFIED] source=" .. tostring(source_key) ..
            " sample_guid=" .. tostring(guid_value) ..
            " trusted_native=true" ..
            " runs=" .. tostring(value_record.run_count) ..
            " world_cycles=" .. tostring(value_record.world_cycle_count) ..
            " contexts=" .. tostring(value_record.context_count)
        )
    end

    update_report(source_key, source_record, value_record)

    return {
        status = "verified",
        guid = guid_value,
        source_path = tostring(normalized_source_path) .. "." .. tostring(property),
        confidence = 1000,
    }
end

function Identity.verification_summary()
    if not _state then
        return {
            sources = 0,
            verified_sources = 0,
        }
    end
    local verification = ensure_verification_tables(_state)
    local sources = verification.sources or {}
    local source_count = _util.table_size(sources)
    local verified_count = 0
    for _, source in pairs(sources) do
        if source.status == "verified" then
            verified_count = verified_count + 1
        end
    end
    return {
        sources = source_count,
        verified_sources = verified_count,
    }
end

function Identity.get_report()
    if not _state then
        return {}
    end
    local verification = ensure_verification_tables(_state)
    return verification.report
end

return Identity
