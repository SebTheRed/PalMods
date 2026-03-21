local Dialogue = {}

local _config = nil
local _logger = nil
local _util = nil
local _json = nil

local _index = nil
local _lines = nil
local _lines_by_trigger = {}
local _species_profiles = {}
local _loaded = false
local _script_dir = "./"

local function detect_script_dir()
    local script_source = ""
    if type(debug) == "table" and type(debug.getinfo) == "function" then
        local info = debug.getinfo(1, "S")
        if info and info.source then
            script_source = info.source
        end
    end

    return string.match(script_source, "@(.+[\\/])") or "./"
end

local function first_existing_path(candidates)
    for i = 1, #candidates do
        if _util.file_exists(candidates[i]) then
            return candidates[i]
        end
    end
    return nil
end

local function resolve_dialogue_root()
    local configured_paths = (_config.dialogue and _config.dialogue.data_paths) or {}
    local candidates = {}

    for i = 1, #configured_paths do
        candidates[#candidates + 1] = _util.path_join(_script_dir, configured_paths[i])
    end

    return first_existing_path(candidates)
end

local function parse_json_lines(path, limit)
    local payload = _util.read_file(path)
    if not payload or payload == "" then
        return {}
    end

    local rows = {}
    local count = 0
    for line in string.gmatch(payload, "[^\r\n]+") do
        if line ~= "" then
            local decoded = _json.decode(line)
            if decoded ~= nil then
                rows[#rows + 1] = decoded
                count = count + 1
                if limit and limit > 0 and count >= limit then
                    break
                end
            end
        end
    end

    return rows
end

local function build_lines_by_trigger(lines)
    local result = {}
    for i = 1, #lines do
        local line = lines[i]
        local trigger = tostring(line.trigger or "unknown")
        result[trigger] = result[trigger] or {}
        result[trigger][#result[trigger] + 1] = line
    end
    return result
end

local function build_species_profile_lookup(rows)
    local lookup = {}
    for i = 1, #rows do
        local row = rows[i]
        local key = tostring(row.character_id or "")
        if key ~= "" then
            lookup[key] = row
        end
    end
    return lookup
end

local function normalize_species_id(species)
    local text = tostring(species or "")
    text = string.gsub(text, "^species:", "")
    text = string.gsub(text, "^BP_", "")
    text = string.gsub(text, "_C$", "")
    return text
end

local function clamp(number_value, min_value, max_value)
    if number_value < min_value then
        return min_value
    end
    if number_value > max_value then
        return max_value
    end
    return number_value
end

local function get_threshold_id(thresholds, numeric_value, fallback_id)
    for i = 1, #thresholds do
        local threshold = thresholds[i]
        if numeric_value >= (threshold.min or 0) and numeric_value <= (threshold.max or 999999) then
            return threshold.id
        end
    end
    return fallback_id
end

local function trust_band_from_value(trust_value)
    local thresholds = ((_index or {}).thresholds or {}).trust_bands or {}
    return get_threshold_id(thresholds, clamp(math.floor(tonumber(trust_value) or 50), 1, 99), "trust_41_60")
end

local function san_band_from_value(sanity_value)
    local thresholds = ((_index or {}).thresholds or {}).san_bands or {}
    return get_threshold_id(thresholds, clamp(math.floor(tonumber(sanity_value) or 100), 0, 100), "san_high")
end

local function profile_for_species(species_id)
    return _species_profiles[normalize_species_id(species_id)] or {}
end

local function as_lookup(values)
    local lookup = {}
    if type(values) ~= "table" then
        return lookup
    end

    for i = 1, #values do
        lookup[tostring(values[i])] = true
    end
    return lookup
end

local function replace_tokens(text, context)
    local item_base_name = tostring(context.item_base_name or context.item_name or "that item")
    local item_count = math.max(1, math.floor(tonumber(context.item_count) or 1))
    local item_label = tostring(context.item_label or ((item_count > 1 and (tostring(item_count) .. " " .. item_base_name)) or item_base_name))
    local substitutions = {
        pal_name = tostring(context.pal_name or _config.dialogue.default_pal_name or "Pal"),
        player_name = tostring(context.player_name or _config.dialogue.default_player_name or "Trainer"),
        item_name = tostring(context.item_name or item_label),
        item_base_name = item_base_name,
        item_label = item_label,
        item_count = tostring(item_count),
        location_name = tostring(context.location_name or _config.dialogue.default_location_name or "the base"),
        work_type = tostring(context.work_type or _config.dialogue.default_work_type or "work"),
        favorite_food = tostring(context.favorite_food or "snacks"),
        coworker_name = tostring(context.coworker_name or "the others"),
        base_zone = tostring(context.base_zone or "home"),
    }

    return (string.gsub(tostring(text or ""), "{([%w_]+)}", function(token)
        local replacement = substitutions[token]
        if replacement == nil or replacement == "" then
            return "something"
        end
        return replacement
    end))
end

local function score_line(line, context)
    if tostring(line.trigger or "") ~= tostring(context.trigger or "") then
        return nil
    end

    local score = tonumber(line.weight or 0) or 0
    local species_scope = tostring(line.species_scope or "archetype")
    local context_species_scope = tostring(context.species_scope or "archetype")
    if species_scope == context_species_scope then
        score = score + 120
    elseif species_scope == "archetype" then
        score = score + 40
    else
        return nil
    end

    if tostring(line.trust_band or "") == tostring(context.trust_band or "") then
        score = score + 80
    end
    if tostring(line.san_band or "") == tostring(context.san_band or "") then
        score = score + 50
    end
    if tostring(line.size_bucket or "") == tostring(context.size_bucket or "") then
        score = score + 25
    end
    if tostring(line.genus_category or "") == tostring(context.genus_category or "") then
        score = score + 20
    end
    if tostring(line.element_primary or "") == tostring(context.element_primary or "") then
        score = score + 20
    end
    if tostring(line.gender_style or "") == tostring(context.gender_style or "") then
        score = score + 10
    end
    if tostring(line.social_style or "") == tostring(context.social_style or "") then
        score = score + 30
    end
    if tostring(line.activity_state or "") == tostring(context.activity_state or "") then
        score = score + 20
    end

    local line_personality = as_lookup(line.personality_tags)
    local context_personality = as_lookup(context.personality_tags)
    for tag in pairs(context_personality) do
        if line_personality[tag] then
            score = score + 18
        end
    end

    local line_environment = as_lookup(line.environment_tags)
    local context_environment = as_lookup(context.environment_tags)
    for tag in pairs(context_environment) do
        if line_environment[tag] then
            score = score + 10
        end
    end

    local line_social = as_lookup(line.social_tags)
    local context_social = as_lookup(context.social_tags)
    for tag in pairs(context_social) do
        if line_social[tag] then
            score = score + 12
        end
    end

    return score
end

local function ensure_loaded()
    if _loaded then
        return true
    end

    local root = resolve_dialogue_root()
    if not root then
        _logger.warn("Dialogue data directory not found. Dialogue selection disabled.")
        _loaded = true
        _index = {}
        _lines = {}
        _lines_by_trigger = {}
        _species_profiles = {}
        return false
    end

    local index_path = _util.path_join(root, _config.dialogue.index_file or "dialogue_index.json")
    local lines_path = _util.path_join(root, _config.dialogue.lines_file or "dialogue_all_lines.jsonl")
    local species_profiles_path = _util.path_join(root, "species_profiles.jsonl")

    local index_payload = _util.read_file(index_path)
    _index = {}
    if index_payload and index_payload ~= "" then
        _index = _json.decode(index_payload) or {}
    end

    _lines = parse_json_lines(lines_path, _config.dialogue.max_loaded_lines)
    _lines_by_trigger = build_lines_by_trigger(_lines)
    _species_profiles = build_species_profile_lookup(parse_json_lines(species_profiles_path))
    _loaded = true

    _logger.info("Dialogue dataset loaded. lines=" .. tostring(#_lines))
    return #_lines > 0
end

local function make_context(raw_context)
    local context = raw_context or {}
    local species_id = normalize_species_id(context.species_id or context.species or context.character_id)
    local profile = profile_for_species(species_id)
    local pal_name = tostring(context.pal_name or species_id or _config.dialogue.default_pal_name or "Pal")
    local player_name = tostring(context.player_name or _config.dialogue.default_player_name or "Trainer")
    local personality = context.personality or {}
    local social_style_by_preference = {
        loves_petting = "social_loves_petting",
        loves_talking = "social_loves_talking",
        loves_fetch_quests = "social_loves_quests",
        shy_but_warms_up = "social_shy",
        independent = "social_independent",
        praise_seeking = "social_praise_seeking",
        comfort_seeking = "social_clingy",
    }

    local social_style = context.social_style
    if not social_style or social_style == "" then
        social_style = social_style_by_preference[personality.social_preference] or "social_loves_talking"
    end

    return {
        trigger = tostring(context.trigger or "talk"),
        species_id = species_id,
        species_scope = "species:" .. tostring(species_id),
        pal_name = pal_name,
        player_name = player_name,
        item_name = context.item_name,
        location_name = context.location_name,
        work_type = context.work_type,
        favorite_food = context.favorite_food,
        coworker_name = context.coworker_name,
        base_zone = context.base_zone,
        trust_band = trust_band_from_value(context.trust_value),
        san_band = san_band_from_value(context.sanity_value),
        size_bucket = tostring(context.size_bucket or profile.size_bucket or "medium"),
        genus_category = tostring(context.genus_category or profile.genus_category or "other"),
        element_primary = tostring(context.element_primary or profile.element_primary or "neutral"),
        gender_style = tostring(context.gender_style or profile.gender_mode or "neutral_style"),
        activity_state = tostring(context.activity_state or "idle"),
        social_style = social_style,
        personality_tags = {
            tostring(personality.work_attitude or ""),
            tostring(personality.social_preference or ""),
            tostring(personality.temperament or ""),
        },
        environment_tags = context.environment_tags or {},
        social_tags = context.social_tags or {},
        raw = context,
    }
end

function Dialogue.init(config, logger, util, json)
    _config = config
    _logger = logger
    _util = util
    _json = json
    _script_dir = detect_script_dir()
end

function Dialogue.ensure_loaded()
    return ensure_loaded()
end

function Dialogue.get_trust_band(trust_value)
    ensure_loaded()
    return trust_band_from_value(trust_value)
end

function Dialogue.get_san_band(sanity_value)
    ensure_loaded()
    return san_band_from_value(sanity_value)
end

function Dialogue.get_line(raw_context)
    if not ensure_loaded() then
        return nil
    end

    local context = make_context(raw_context)
    local trigger_lines = _lines_by_trigger[context.trigger] or {}
    if #trigger_lines == 0 then
        return nil
    end

    local ranked = {}
    for i = 1, #trigger_lines do
        local line = trigger_lines[i]
        local score = score_line(line, context)
        if score ~= nil then
            ranked[#ranked + 1] = {
                line = line,
                score = score,
            }
        end
    end

    table.sort(ranked, function(left, right)
        if left.score == right.score then
            return tostring(left.line.line_id or "") < tostring(right.line.line_id or "")
        end
        return left.score > right.score
    end)

    local limit = math.min(#ranked, _config.dialogue.max_candidates or 128)
    if limit == 0 then
        return nil
    end

    local total_weight = 0
    for i = 1, limit do
        total_weight = total_weight + math.max(1, math.floor(ranked[i].score))
    end

    local cursor = math.random(1, total_weight)
    local chosen = ranked[1]
    for i = 1, limit do
        cursor = cursor - math.max(1, math.floor(ranked[i].score))
        if cursor <= 0 then
            chosen = ranked[i]
            break
        end
    end

    return {
        line_id = chosen.line.line_id,
        trigger = chosen.line.trigger,
        text = replace_tokens(chosen.line.text, context),
        raw_text = chosen.line.text,
        score = chosen.score,
        trust_band = context.trust_band,
        san_band = context.san_band,
        species_scope = chosen.line.species_scope,
        cooldown_group = chosen.line.cooldown_group,
        repeat_lockout = chosen.line.repeat_lockout,
    }
end

return Dialogue
