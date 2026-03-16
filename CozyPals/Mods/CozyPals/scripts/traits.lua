local Traits = {}

local _config = nil
local _util = nil

local function make_rng(seed)
    local value = tonumber(seed) or 1
    local modulus = 2147483647
    local multiplier = 48271

    return function(max)
        value = (value * multiplier) % modulus
        local result = value
        if max and max > 0 then
            result = (value % max) + 1
        end
        return result
    end
end

local function weighted_pick(options, bias_map, rng)
    local weighted = {}
    local total = 0

    for i = 1, #options do
        local option = options[i]
        local bias = 0
        if type(bias_map) == "table" then
            bias = tonumber(bias_map[option]) or 0
        end
        local weight = 1 + math.max(0, bias)
        weighted[#weighted + 1] = { option = option, weight = weight }
        total = total + weight
    end

    if total <= 0 then
        return options[1]
    end

    local roll = rng(total)
    local running = 0
    for i = 1, #weighted do
        running = running + weighted[i].weight
        if roll <= running then
            return weighted[i].option
        end
    end
    return weighted[#weighted].option
end

function Traits.init(config, util)
    _config = config
    _util = util
end

function Traits.roll_personality(guid, species)
    local species_name = tostring(species or "Unknown")
    local seed = _util.hash_text(tostring(guid or "") .. "::" .. species_name)
    local rng = make_rng(seed)

    local bias = (_config.personality.species_bias or {})[species_name] or {}
    local personality = {
        seed = seed,
        work_attitude = weighted_pick(
            _config.personality.work_attitudes,
            bias.work_attitude,
            rng
        ),
        social_preference = weighted_pick(
            _config.personality.social_preferences,
            bias.social_preference,
            rng
        ),
        temperament = weighted_pick(
            _config.personality.temperaments,
            bias.temperament,
            rng
        ),
    }

    return personality
end

return Traits
