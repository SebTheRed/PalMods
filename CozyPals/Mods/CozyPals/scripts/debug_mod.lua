local DebugMod = {}

local _logger = nil
local _util = nil
local _identity = nil

function DebugMod.init(logger, util, identity)
    _logger = logger
    _util = util
    _identity = identity
end

function DebugMod.dump_pal_state(state, guid)
    if not state or not state.pals then
        _logger.warn("No pal state loaded.")
        return
    end

    local record = state.pals[guid]
    if not record then
        _logger.warn("No pal record found for guid=" .. tostring(guid))
        return
    end

    _logger.info(
        "[Debug] guid=" .. tostring(guid) ..
        " species=" .. tostring(record.species) ..
        " seed=" .. tostring(record.personality and record.personality.seed) ..
        " first_seen=" .. tostring(record.meta and record.meta.first_seen) ..
        " last_seen=" .. tostring(record.meta and record.meta.last_seen) ..
        " guid_source=" .. tostring(record.verification and record.verification.guid_source)
    )
end

function DebugMod.dump_all_pals(state)
    if not state or not state.pals then
        _logger.info("[Debug] No state loaded.")
        return
    end

    local count = _util.table_size(state.pals)
    _logger.info("[Debug] pal_count=" .. tostring(count))
    for guid in pairs(state.pals) do
        DebugMod.dump_pal_state(state, guid)
    end
end

function DebugMod.dump_verification_report()
    local report = _identity.get_report()
    local count = _util.table_size(report)
    _logger.info("[Debug] verification_source_count=" .. tostring(count))
    for source_key, entry in pairs(report) do
        _logger.info(
            "[Debug] source=" .. tostring(source_key) ..
            " status=" .. tostring(entry.status) ..
            " guid=" .. tostring(entry.verified_guid) ..
            " runs=" .. tostring(entry.run_count) ..
            " world_cycles=" .. tostring(entry.world_cycle_count) ..
            " contexts=" .. tostring(entry.context_count)
        )
    end
end

return DebugMod
