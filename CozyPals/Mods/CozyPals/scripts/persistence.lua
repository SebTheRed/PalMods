local Persistence = {}

local _config = nil
local _logger = nil
local _util = nil
local _json = nil

local function state_defaults(world_key)
    return {
        data_schema_version = _config.data_schema_version,
        world_key = world_key,
        meta = {
            mod_version = _config.mod_version,
            created_at = _util.now(),
            last_saved_at = 0,
        },
        pals = {},
        guid_verification = {
            version = 1,
            sources = {},
            report = {},
        },
        _dirty = false,
        _last_save_attempt = 0,
        _last_saved_at = 0,
        _dirty_reason = nil,
        _path = nil,
    }
end

local function remove_runtime_keys(table_value)
    if type(table_value) ~= "table" then
        return table_value
    end

    local copy = {}
    for key, value in pairs(table_value) do
        if type(key) == "string" and string.sub(key, 1, 1) == "_" then
            -- Skip runtime-only keys.
        else
            copy[key] = remove_runtime_keys(value)
        end
    end
    return copy
end

local function build_path(world_key)
    local directory = _config.persistence.data_directory
    local file_name = _config.persistence.file_prefix .. tostring(world_key) .. ".json"
    return _util.path_join(directory, file_name)
end

local function migrate_state(state, world_key)
    if type(state) ~= "table" then
        state = {}
    end
    state.data_schema_version = state.data_schema_version or _config.data_schema_version
    state.world_key = state.world_key or world_key
    state.meta = state.meta or {}
    state.meta.mod_version = state.meta.mod_version or _config.mod_version
    state.meta.created_at = state.meta.created_at or _util.now()
    state.meta.last_saved_at = state.meta.last_saved_at or 0
    state.pals = state.pals or {}
    state.guid_verification = state.guid_verification or {}
    state.guid_verification.version = state.guid_verification.version or 1
    state.guid_verification.sources = state.guid_verification.sources or {}
    state.guid_verification.report = state.guid_verification.report or {}

    state._dirty = false
    state._last_save_attempt = 0
    state._last_saved_at = 0
    state._dirty_reason = nil
    state._path = build_path(world_key)

    return state
end

function Persistence.init(config, logger, util, json)
    _config = config
    _logger = logger
    _util = util
    _json = json
end

function Persistence.load_world_state(world_key)
    _util.ensure_directory(_config.persistence.data_directory)

    local path = build_path(world_key)
    local payload, read_err = _util.read_file(path)
    if not payload then
        local state = state_defaults(world_key)
        state._path = path
        _logger.info("No existing CozyPals save found. Starting new state at " .. path)
        return state
    end

    local decoded, parse_err = _json.decode(payload)
    if decoded == nil then
        _logger.err("Failed parsing save file. " .. tostring(parse_err) .. " | path=" .. path)
        local backup_path = path .. _config.persistence.backup_suffix
        local backup_payload = nil
        local backup_read_err = nil
        backup_payload, backup_read_err = _util.read_file(backup_path)
        if not backup_payload then
            _logger.err("No backup save available. " .. tostring(backup_read_err))
            local state = state_defaults(world_key)
            state._path = path
            return state
        end

        local backup_decoded, backup_parse_err = _json.decode(backup_payload)
        if backup_decoded == nil then
            _logger.err("Backup save parse failed. " .. tostring(backup_parse_err))
            local state = state_defaults(world_key)
            state._path = path
            return state
        end

        _logger.warn("Recovered CozyPals state from backup file.")
        return migrate_state(backup_decoded, world_key)
    end

    local state = migrate_state(decoded, world_key)
    _logger.info("Loaded CozyPals state from " .. path)
    return state
end

function Persistence.save_world_state(state)
    if not state then
        return false, "state is nil"
    end

    local path = state._path
    if not path then
        return false, "state path is unset"
    end

    state.meta = state.meta or {}
    state.meta.last_saved_at = _util.now()
    state.meta.mod_version = _config.mod_version

    local serializable = remove_runtime_keys(state)
    local payload = _json.encode(serializable)

    local ok, err = _util.atomic_write(
        path,
        payload,
        _config.persistence.backup_suffix,
        _config.persistence.temp_suffix
    )
    state._last_save_attempt = _util.now()

    if not ok then
        return false, err
    end

    state._dirty = false
    state._dirty_reason = nil
    state._last_saved_at = _util.now()
    return true, nil
end

function Persistence.mark_dirty(state, reason)
    if not state then
        return
    end
    state._dirty = true
    state._dirty_reason = reason or "unspecified"
    if _config.persistence.flush_on_dirty then
        local ok, err = Persistence.save_world_state(state)
        if not ok then
            _logger.err("Immediate save failed: " .. tostring(err))
        end
    end
end

function Persistence.autosave_if_needed(state)
    if not state then
        return
    end
    if not state._dirty then
        return
    end

    local now = _util.now()
    local interval = _config.persistence.autosave_seconds or 30
    local last_attempt = state._last_save_attempt or 0
    if now - last_attempt < interval then
        return
    end

    local ok, err = Persistence.save_world_state(state)
    if ok then
        _logger.info("Autosave complete.")
    else
        _logger.err("Autosave failed: " .. tostring(err))
    end
end

function Persistence.get_or_create_pal_record(state, guid, species, meta)
    state.pals = state.pals or {}
    local record = state.pals[guid]
    local created = false
    local now = _util.now()

    if not record then
        record = {
            version = 1,
            species = species or "Unknown",
            personality = {},
            meta = {
                first_seen = now,
                last_seen = now,
                home_base_id = nil,
            },
            verification = {
                guid_source = nil,
            },
        }
        state.pals[guid] = record
        created = true
    end

    record.species = record.species or species or "Unknown"
    record.meta = record.meta or {}
    record.meta.first_seen = record.meta.first_seen or now
    record.meta.last_seen = now

    if type(meta) == "table" then
        if meta.home_base_id ~= nil then
            record.meta.home_base_id = meta.home_base_id
        end
    end

    return record, created
end

return Persistence
