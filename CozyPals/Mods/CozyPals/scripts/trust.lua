local Trust = {}

local _config = nil
local _logger = nil
local _util = nil

local function clamp(number_value, min_value, max_value)
    if number_value < min_value then
        return min_value
    end
    if number_value > max_value then
        return max_value
    end
    return number_value
end

local function ensure_trust_record(record)
    record.trust = record.trust or {
        value = 40,
        affection_points = 0,
        total_pet_count = 0,
        last_pet_at = 0,
        last_talk_at = 0,
    }
    record.trust.value = clamp(math.floor(tonumber(record.trust.value) or 40), 1, 99)
    record.trust.affection_points = math.floor(tonumber(record.trust.affection_points) or 0)
    record.trust.total_pet_count = math.floor(tonumber(record.trust.total_pet_count) or 0)
    record.trust.last_pet_at = tonumber(record.trust.last_pet_at) or 0
    record.trust.last_talk_at = tonumber(record.trust.last_talk_at) or 0
    return record.trust
end

function Trust.init(config, logger, util)
    _config = config
    _logger = logger
    _util = util
end

function Trust.ensure_record(record)
    return ensure_trust_record(record)
end

function Trust.current_value(record, live_context)
    local trust = ensure_trust_record(record)
    if live_context and live_context.friendship_point then
        local friendship = tonumber(live_context.friendship_point) or 0
        if friendship > 0 then
            local scaled = clamp(math.floor((friendship / 20000) * 98) + 1, 1, 99)
            if scaled > trust.value then
                trust.value = scaled
            end
        end
    end
    return trust.value
end

function Trust.apply_effects(context)
    local record = context and context.record
    if not record then
        return false, "missing_record"
    end

    local trust = ensure_trust_record(record)
    local action = tostring(context.action or "talk")
    local now = _util.now()

    if action == "pet" then
        local cooldown = (_config.interaction and _config.interaction.pet_cooldown_seconds) or 30
        if now - trust.last_pet_at < cooldown then
            return false, "pet_cooldown"
        end

        trust.last_pet_at = now
        trust.total_pet_count = trust.total_pet_count + 1
        trust.affection_points = trust.affection_points + ((_config.interaction and _config.interaction.pet_affection_gain) or 3)
        trust.value = clamp(trust.value + ((_config.interaction and _config.interaction.trust_gain_on_pet) or 1), 1, 99)

        _logger.info(
            "[Interaction][PET] guid=" .. tostring(context.guid) ..
            " trust=" .. tostring(trust.value) ..
            " affection_points=" .. tostring(trust.affection_points)
        )

        return true, {
            trust_value = trust.value,
            affection_points = trust.affection_points,
            total_pet_count = trust.total_pet_count,
        }
    end

    if action == "talk" then
        trust.last_talk_at = now
        return true, {
            trust_value = trust.value,
            affection_points = trust.affection_points,
        }
    end

    return false, "unsupported_action"
end

return Trust
