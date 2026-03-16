local Discovery = {}

local _config = nil
local _logger = nil
local _util = nil
local _seen_actor_keys = {}

local function safe_call(fn, ...)
    local ok, value = pcall(fn, ...)
    if ok then
        return true, value
    end
    return false, nil
end

local function sort_candidates(candidates)
    table.sort(candidates, function(a, b)
        if a.confidence == b.confidence then
            return tostring(a.property) < tostring(b.property)
        end
        return a.confidence > b.confidence
    end)
end

local function dedupe_candidates(candidates)
    local filtered = {}
    local seen = {}
    for i = 1, #candidates do
        local candidate = candidates[i]
        local key = tostring(candidate.source_path) .. "|" .. tostring(candidate.property) .. "|" .. tostring(candidate.value)
        if not seen[key] then
            seen[key] = true
            filtered[#filtered + 1] = candidate
        end
    end
    return filtered
end

local function read_property(target, property_name)
    if target == nil then
        return nil, false
    end

    local ok_index, indexed = pcall(function()
        return target[property_name]
    end)
    if ok_index and indexed ~= nil then
        return indexed, true
    end

    local getter_names = { "GetPropertyValue", "get", "GetValue" }
    for i = 1, #getter_names do
        local getter_name = getter_names[i]
        local ok_method, method = pcall(function()
            return target[getter_name]
        end)
        if ok_method and type(method) == "function" then
            local ok_get, value = safe_call(method, target, property_name)
            if ok_get and value ~= nil then
                return value, true
            end
        end
    end

    return nil, false
end

local function split_path(path_text)
    local parts = {}
    if not path_text or path_text == "" then
        return parts
    end
    for part in string.gmatch(path_text, "[^%.]+") do
        parts[#parts + 1] = part
    end
    return parts
end

local function read_property_path(target, property_path)
    local parts = split_path(property_path)
    if #parts == 0 then
        return nil, false
    end

    local current = target
    for i = 1, #parts do
        local segment = parts[i]
        local value, found = read_property(current, segment)
        if not found then
            return nil, false
        end
        current = value
    end
    return current, true
end

local function basename(path_text)
    if not path_text or path_text == "" then
        return path_text
    end
    local parts = split_path(path_text)
    return parts[#parts]
end

local function score_candidate(property_name, value, source_path)
    local score_map = _config.discovery.property_score or {}
    local base_name = basename(property_name)
    local base = score_map[property_name] or score_map[base_name] or 10
    local text = _util.safe_tostring(value)

    if _util.guid_like(text) then
        base = base + 30
    end
    if #text >= 16 then
        base = base + 10
    elseif #text >= 8 then
        base = base + 5
    end

    if source_path ~= "actor" then
        base = base + 5
    end

    local preferred = _config.discovery.preferred_guid_paths or {}
    for i = 1, #preferred do
        if property_name == preferred[i] then
            base = base + 40
            break
        end
    end

    if string.match(text, "^0+$") then
        base = base - 20
    end
    if text == "None" or text == "nil" or text == "<unprintable>" then
        base = base - 20
    end

    return base
end

local function add_candidates_from_target(result, target, source_path)
    local props = _config.discovery.candidate_properties or {}
    for i = 1, #props do
        local prop = props[i]
        local value, found = read_property_path(target, prop)
        if found and value ~= nil then
            local text = _util.safe_tostring(value)
            local confidence = score_candidate(prop, text, source_path)
            result.candidates[#result.candidates + 1] = {
                source_path = source_path,
                property = prop,
                value = text,
                confidence = confidence,
            }
        end
    end
end

local function read_context(result, target)
    local context = result.context or {}
    local props = _config.discovery.context_properties or {}
    for i = 1, #props do
        local prop = props[i]
        local value, found = read_property_path(target, prop)
        if found and value ~= nil then
            context[prop] = _util.safe_tostring(value)
        end
    end
    result.context = context
end

local function read_species_hint(result, target, actor_text)
    local props = _config.discovery.species_properties or {}
    for i = 1, #props do
        local prop = props[i]
        local value, found = read_property_path(target, prop)
        if found and value ~= nil then
            result.species_hint = _util.safe_tostring(value)
            return
        end
    end

    -- Typical actor format includes species signal in class text when no direct property is available.
    local species_match = string.match(actor_text, "([A-Za-z0-9_]+)_C")
    if species_match then
        result.species_hint = species_match
    end
end

local function is_candidate_text(actor_text)
    local keywords = _config.discovery.pal_keywords or {}
    for i = 1, #keywords do
        if _util.contains_text(actor_text, keywords[i]) then
            return true
        end
    end
    return false
end

function Discovery.init(config, logger, util)
    _config = config
    _logger = logger
    _util = util
end

function Discovery.is_candidate_actor(actor)
    if not _config.discovery.enabled then
        return false
    end
    local actor_text = _util.safe_tostring(actor)
    return is_candidate_text(actor_text)
end

function Discovery.scan_actor(actor)
    if not actor then
        return nil
    end
    local actor_text = _util.safe_tostring(actor)
    if not is_candidate_text(actor_text) then
        return nil
    end

    local result = {
        actor_key = _util.sanitize_key(actor_text),
        actor_text = actor_text,
        class_text = actor_text,
        species_hint = "Unknown",
        context = {},
        candidates = {},
        timestamp = _util.now(),
    }

    local preferred_paths = _config.discovery.preferred_guid_paths or {}
    for i = 1, #preferred_paths do
        local path = preferred_paths[i]
        local value, found = read_property_path(actor, path)
        if found and value ~= nil then
            local text = _util.safe_tostring(value)
            local confidence = score_candidate(path, text, "actor")
            result.candidates[#result.candidates + 1] = {
                source_path = "actor",
                property = path,
                value = text,
                confidence = confidence,
            }
        end
    end

    add_candidates_from_target(result, actor, "actor")
    read_context(result, actor)
    read_species_hint(result, actor, actor_text)

    local component_names = _config.discovery.component_properties or {}
    for i = 1, #component_names do
        local component_name = component_names[i]
        local component, found = read_property(actor, component_name)
        if found and component ~= nil then
            for j = 1, #preferred_paths do
                local preferred_path = preferred_paths[j]
                local nested_path = preferred_path
                if string.sub(preferred_path, 1, #component_name + 1) == component_name .. "." then
                    nested_path = string.sub(preferred_path, #component_name + 2)
                end
                local nested_value, nested_found = read_property_path(component, nested_path)
                if nested_found and nested_value ~= nil then
                    local nested_text = _util.safe_tostring(nested_value)
                    local nested_confidence = score_candidate(preferred_path, nested_text, "actor." .. component_name)
                    result.candidates[#result.candidates + 1] = {
                        source_path = "actor." .. component_name,
                        property = preferred_path,
                        value = nested_text,
                        confidence = nested_confidence,
                    }
                end
            end
            add_candidates_from_target(result, component, "actor." .. component_name)
            read_context(result, component)
        end
    end

    result.candidates = dedupe_candidates(result.candidates)
    sort_candidates(result.candidates)
    result.best_candidate = result.candidates[1]
    return result
end

function Discovery.log_result(result)
    if not result then
        return
    end

    local actor_key = result.actor_key or "unknown_actor"
    if _seen_actor_keys[actor_key] then
        _logger.discovery("Discovery heartbeat for actor " .. result.actor_text, "disc_hb_" .. actor_key, 30)
        return
    end

    _seen_actor_keys[actor_key] = true

    local count = #result.candidates
    _logger.discovery("Actor candidate: " .. result.actor_text .. " | candidates=" .. tostring(count))

    if count == 0 then
        _logger.discovery("No UID-like properties found for actor.", "disc_none_" .. actor_key, 20)
        return
    end

    local top_count = math.min(_config.discovery.log_top_candidates or 3, count)
    for i = 1, top_count do
        local c = result.candidates[i]
        local line = string.format(
            "Candidate #%d source=%s property=%s value=%s confidence=%d",
            i,
            tostring(c.source_path),
            tostring(c.property),
            tostring(c.value),
            tonumber(c.confidence or 0)
        )
        _logger.discovery(line, "disc_top_" .. actor_key .. "_" .. tostring(i), 20)
    end
end

function Discovery.format_structured_report(result)
    if not result then
        return nil
    end
    local best = result.best_candidate or {}
    local context_text = _util.serialize_context(result.context)
    return string.format(
        "actor=%s species=%s best_source=%s best_property=%s best_value=%s confidence=%s context={%s}",
        tostring(result.actor_text),
        tostring(result.species_hint),
        tostring(best.source_path),
        tostring(best.property),
        tostring(best.value),
        tostring(best.confidence),
        tostring(context_text)
    )
end

return Discovery
