local Discovery = {}

local _config = nil
local _logger = nil
local _util = nil
local _seen_actor_keys = {}
local _native_target_entries = {}
local _native_target_path = nil
local _native_identity_path = nil
local _native_identity_cache = {
    by_address = {},
    by_full_name = {},
}
local read_property = nil

local function safe_call(fn, ...)
    local ok, value = pcall(fn, ...)
    if ok then
        return true, value
    end
    return false, nil
end

local function extract_actor_address(actor_text)
    local text = tostring(actor_text or "")
    return string.match(text, ":%s*([0-9A-Fa-f]+)$")
end

local function capture_actor_address(actor, actor_text)
    if actor ~= nil then
        local ok_method, method = pcall(function()
            return actor.GetAddress
        end)
        if ok_method and type(method) == "function" then
            local ok_value, value = safe_call(method, actor)
            if ok_value and type(value) == "number" and value ~= 0 then
                return string.format("%X", value)
            end
        end
    end

    return extract_actor_address(actor_text)
end

local function capture_actor_full_name(actor)
    if actor == nil then
        return nil
    end

    local ok_method, method = pcall(function()
        return actor.GetFullName
    end)
    if not ok_method or type(method) ~= "function" then
        return nil
    end

    local ok_value, value = safe_call(method, actor)
    if not ok_value or value == nil then
        return nil
    end

    local text = _util.safe_tostring(value)
    if text == "" or text == "<unprintable>" then
        return nil
    end
    return text
end

local function parse_pipe_fields(line, expected_fields)
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

local function load_native_identity_cache()
    if not _native_identity_path or _native_identity_path == "" then
        return
    end

    local payload = _util.read_file(_native_identity_path)
    local by_address = {}
    local by_full_name = {}

    if payload and payload ~= "" then
        for line in string.gmatch(payload, "[^\r\n]+") do
            local fields = parse_pipe_fields(line, 4)
            local address = fields[1] or ""
            local full_name = fields[2] or ""
            local guid = fields[3] or ""
            local source_path = fields[4] or ""
            if guid ~= "" then
                local record = {
                    guid = guid,
                    source_path = source_path ~= "" and source_path or "actor.CharacterParameterComponent.IndividualParameter",
                }
                if address ~= "" then
                    by_address[string.upper(address)] = record
                end
                if full_name ~= "" then
                    by_full_name[full_name] = record
                end
            end
        end
    end

    _native_identity_cache.by_address = by_address
    _native_identity_cache.by_full_name = by_full_name
end

local function lookup_native_identity(actor, result)
    load_native_identity_cache()

    local address = capture_actor_address(actor, result and result.actor_text)
    if address ~= nil then
        local by_address = _native_identity_cache.by_address or {}
        local match = by_address[string.upper(address)]
        if match then
            return match
        end
    end

    local full_name = (result and result.actor_full_name) or capture_actor_full_name(actor)
    if full_name ~= nil and full_name ~= "" then
        local by_full_name = _native_identity_cache.by_full_name or {}
        return by_full_name[full_name]
    end

    return nil
end

local function inject_native_identity_candidate(result)
    if not result or not result.actor_ref then
        return
    end

    local native_identity = lookup_native_identity(result.actor_ref, result)
    if not native_identity or not _util.guid_like(native_identity.guid) then
        return
    end

    result.candidates[#result.candidates + 1] = {
        source_path = native_identity.source_path or "actor.CharacterParameterComponent.IndividualParameter",
        property = "IndividualId.InstanceId",
        value = native_identity.guid,
        confidence = 1000,
    }
end

local function persist_native_targets()
    if not _native_target_path or _native_target_path == "" then
        return
    end

    local lines = {}
    for i = 1, #_native_target_entries do
        local entry = _native_target_entries[i]
        lines[#lines + 1] = table.concat({
            tostring(entry.address or ""),
            tostring(entry.full_name or ""),
            tostring(entry.actor_text or ""),
            tostring(entry.species_hint or ""),
            tostring(entry.best_property or ""),
            tostring(entry.best_value or ""),
        }, "|")
    end

    _util.atomic_write(_native_target_path, table.concat(lines, "\n"), ".bak", ".tmp")
end

local function remember_native_target(result)
    if not result then
        return
    end

    local address = capture_actor_address(result.actor_ref, result.actor_text)
    if not address then
        return
    end

    local full_name = result.actor_full_name or ""

    local updated = false
    for i = 1, #_native_target_entries do
        local entry = _native_target_entries[i]
        if entry.address == address then
            entry.full_name = full_name
            entry.actor_text = result.actor_text
            entry.species_hint = result.species_hint
            entry.best_property = result.best_candidate and result.best_candidate.property or ""
            entry.best_value = result.best_candidate and result.best_candidate.value or ""
            updated = true
            break
        end
    end

    if not updated then
        _native_target_entries[#_native_target_entries + 1] = {
            address = address,
            full_name = full_name,
            actor_text = result.actor_text,
            species_hint = result.species_hint,
            best_property = result.best_candidate and result.best_candidate.property or "",
            best_value = result.best_candidate and result.best_candidate.value or "",
        }
    end

    local max_targets = (_config.native_bridge and _config.native_bridge.max_targets) or 32
    while #_native_target_entries > max_targets do
        table.remove(_native_target_entries, 1)
    end

    persist_native_targets()
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

local function is_pal_actor(actor, actor_text)
    if actor == nil then
        return false
    end

    if _util.contains_text(actor_text, "PalCharacter") then
        return true
    end

    local static_params, found = read_property(actor, "StaticCharacterParameterComponent")
    if found and static_params ~= nil then
        local is_pal, is_pal_found = read_property(static_params, "IsPal")
        if is_pal_found and is_pal == true then
            return true
        end
    end

    return false
end

read_property = function(target, property_name)
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

local function normalize_guid_word(value)
    if type(value) == "number" then
        local number_value = value
        if number_value < 0 then
            number_value = number_value + 4294967296
        end
        return string.format("%08X", number_value)
    end

    local text = tostring(value or "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    if text == "" then
        return nil
    end
    if _util.is_unreal_param_text(text) or _util.is_uobject_text(text) then
        return nil
    end

    if string.match(text, "^%d+$") then
        local number_value = tonumber(text)
        if number_value ~= nil then
            return string.format("%08X", number_value)
        end
    end

    if string.match(text, "^0[xX]%x+$") then
        text = string.sub(text, 3)
    end

    if string.match(text, "^[%x]+$") and #text <= 8 then
        return string.rep("0", 8 - #text) .. string.upper(text)
    end

    return nil
end

local function try_extract_guid_from_struct(value)
    local parts = {}
    local field_names = { "A", "B", "C", "D" }

    for i = 1, #field_names do
        local field_name = field_names[i]
        local field_value, found = read_property(value, field_name)
        if not found or field_value == nil then
            return nil
        end

        local normalized = normalize_guid_word(field_value)
        if normalized == nil then
            return nil
        end

        parts[#parts + 1] = normalized
    end

    return table.concat(parts, "")
end

local function extract_candidate_text(value)
    local text = _util.safe_tostring(value)
    if _util.is_uobject_text(text) then
        local assembled_guid = try_extract_guid_from_struct(value)
        if assembled_guid ~= nil then
            return assembled_guid
        end
    end
    return text
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
    local text = tostring(value or "")

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
            local text = extract_candidate_text(value)
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
    _native_target_path = _config.native_bridge and _config.native_bridge.targets_file or nil
    _native_identity_path = _config.native_bridge and _config.native_bridge.identities_file or nil
    if _native_target_path and _native_target_path ~= "" then
        _util.ensure_directory(_config.persistence and _config.persistence.data_directory or "Mods/CozyPals/data")
        _util.write_file(_native_target_path, "")
    end
    if _native_identity_path and _native_identity_path ~= "" then
        _util.ensure_directory(_config.persistence and _config.persistence.data_directory or "Mods/CozyPals/data")
    end
end

function Discovery.is_candidate_actor(actor)
    if not _config.discovery.enabled then
        return false
    end
    local actor_text = _util.safe_tostring(actor)
    return is_pal_actor(actor, actor_text) or is_candidate_text(actor_text)
end

function Discovery.scan_actor(actor)
    if not actor then
        return nil
    end
    local actor_text = _util.safe_tostring(actor)
    if not is_pal_actor(actor, actor_text) then
        return nil
    end

    local result = {
        actor_key = _util.sanitize_key(actor_text),
        actor_ref = actor,
        actor_text = actor_text,
        actor_full_name = capture_actor_full_name(actor),
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
            local text = extract_candidate_text(value)
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
                    local nested_text = extract_candidate_text(nested_value)
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

    inject_native_identity_candidate(result)
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
    remember_native_target(result)

    local count = #result.candidates
    _logger.discovery("Pal actor observed: " .. result.actor_text .. " | candidates=" .. tostring(count))

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
