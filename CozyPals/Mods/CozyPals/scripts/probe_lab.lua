local ProbeLab = {}

local _config = nil
local _logger = nil
local _util = nil

local _state = {
    target_runs = 0,
    runs_by_test = {},
    seen_targets = {},
}

local function safe_call(fn, ...)
    local ok, value = pcall(fn, ...)
    if ok then
        return true, value
    end
    return false, value
end

local function safe_method(target, method_name, ...)
    if target == nil then
        return nil, false
    end

    local ok_method, method = pcall(function()
        return target[method_name]
    end)
    if not ok_method or type(method) ~= "function" then
        return nil, false
    end

    local ok_call, value = pcall(method, target, ...)
    if ok_call then
        return value, true
    end
    return nil, false
end

local function has_method(target, method_name)
    if target == nil then
        return false
    end
    local ok_method, method = pcall(function()
        return target[method_name]
    end)
    return ok_method and type(method) == "function"
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

local function read_path(target, property_path)
    local parts = split_path(property_path)
    if #parts == 0 then
        return nil, false
    end

    local current = target
    for i = 1, #parts do
        local value, found = read_property(current, parts[i])
        if not found then
            return nil, false
        end
        current = value
    end

    return current, true
end

local function truncate_text(text, max_length)
    local value = tostring(text or "")
    if #value <= max_length then
        return value
    end
    return string.sub(value, 1, max_length - 3) .. "..."
end

local function get_probe_config()
    local discovery = (_config and _config.discovery) or {}
    local probe = discovery.live_probe or {}
    return probe
end

local function get_test_config()
    local probe = get_probe_config()
    return probe.tests or {}
end

local function safe_text(value)
    local probe = get_probe_config()
    return truncate_text(_util.safe_tostring(value), probe.max_value_length or 96)
end

local function string_value_from_object(value)
    if value == nil then
        return nil
    end

    local string_value, ok_to_string = safe_method(value, "ToString")
    if ok_to_string and string_value ~= nil then
        return safe_text(string_value)
    end

    local f_name, ok_name = safe_method(value, "GetFName")
    if ok_name and f_name ~= nil then
        local name_text, ok_name_text = safe_method(f_name, "ToString")
        if ok_name_text and name_text ~= nil then
            return safe_text(name_text)
        end
    end

    return nil
end

local function describe_object(label, value)
    local parts = {
        label .. ".text=" .. safe_text(value),
    }

    local full_name, ok_full_name = safe_method(value, "GetFullName")
    if ok_full_name and full_name ~= nil then
        parts[#parts + 1] = label .. ".full=" .. safe_text(full_name)
    end

    local class_value, ok_class = safe_method(value, "GetClass")
    if ok_class and class_value ~= nil then
        local class_full_name, ok_class_full = safe_method(class_value, "GetFullName")
        if ok_class_full and class_full_name ~= nil then
            parts[#parts + 1] = label .. ".class=" .. safe_text(class_full_name)
        else
            parts[#parts + 1] = label .. ".class=" .. safe_text(class_value)
        end
    end

    local text_value = string_value_from_object(value)
    if text_value ~= nil then
        parts[#parts + 1] = label .. ".name=" .. text_value
    end

    local is_valid, ok_valid = safe_method(value, "IsValid")
    if ok_valid and is_valid ~= nil then
        parts[#parts + 1] = label .. ".valid=" .. tostring(is_valid)
    end

    local is_mapped, ok_mapped = safe_method(value, "IsMappedToObject")
    if ok_mapped and is_mapped ~= nil then
        parts[#parts + 1] = label .. ".mapped=" .. tostring(is_mapped)
    end

    return table.concat(parts, " ")
end

local function get_property_container(value)
    if value == nil then
        return nil
    end

    local ok_for_each, method = pcall(function()
        return value["ForEachProperty"]
    end)
    if ok_for_each and type(method) == "function" then
        return value
    end

    local class_value, ok_class = safe_method(value, "GetClass")
    if ok_class and class_value ~= nil then
        local ok_class_each, class_method = pcall(function()
            return class_value["ForEachProperty"]
        end)
        if ok_class_each and type(class_method) == "function" then
            return class_value
        end
    end

    return nil
end

local function collect_property_names(value)
    local probe = get_probe_config()
    local max_properties = probe.max_properties_per_object or 16
    local container = get_property_container(value)
    if container == nil then
        return "unavailable"
    end

    local names = {}
    local ok_iter = pcall(function()
        container:ForEachProperty(function(property)
            if #names >= max_properties then
                return true
            end

            local property_name = nil
            local f_name, ok_f_name = safe_method(property, "GetFName")
            if ok_f_name and f_name ~= nil then
                local name_text, ok_name_text = safe_method(f_name, "ToString")
                if ok_name_text and name_text ~= nil then
                    property_name = tostring(name_text)
                end
            end
            if property_name == nil then
                property_name = safe_text(property)
            end

            local property_type = nil
            local class_value, ok_class = safe_method(property, "GetClass")
            if ok_class and class_value ~= nil then
                local class_name, ok_class_name = safe_method(class_value, "GetFName")
                if ok_class_name and class_name ~= nil then
                    local type_text, ok_type_text = safe_method(class_name, "ToString")
                    if ok_type_text and type_text ~= nil then
                        property_type = tostring(type_text)
                    end
                end
            end

            if property_type ~= nil then
                names[#names + 1] = property_name .. ":" .. property_type
            else
                names[#names + 1] = property_name
            end
        end)
    end)

    if not ok_iter then
        return "unavailable"
    end
    if #names == 0 then
        return "empty"
    end
    return table.concat(names, ",")
end

local function collect_selected_fields(label, value, field_names)
    local parts = {}
    for i = 1, #field_names do
        local field_name = field_names[i]
        local field_value, found = read_property(value, field_name)
        if found and field_value ~= nil then
            parts[#parts + 1] = label .. "." .. field_name .. "=" .. safe_text(field_value)
        end
    end

    if #parts == 0 then
        return label .. ".fields=none"
    end
    return table.concat(parts, " ")
end

local function collect_path_values(root, label, path_names)
    local parts = {}
    for i = 1, #path_names do
        local path_name = path_names[i]
        local path_value, found = read_path(root, path_name)
        if found and path_value ~= nil then
            parts[#parts + 1] = label .. "." .. path_name .. "=" .. safe_text(path_value)
        end
    end

    if #parts == 0 then
        return label .. ".paths=none"
    end
    return table.concat(parts, " ")
end

local function collect_nested_path_values(root, label, base_path, branches, leaf_names)
    local parts = {}
    for i = 1, #branches do
        local branch_name = branches[i]
        for j = 1, #leaf_names do
            local leaf_name = leaf_names[j]
            local path_name = base_path .. "." .. branch_name .. "." .. leaf_name
            local path_value, found = read_path(root, path_name)
            if found and path_value ~= nil then
                parts[#parts + 1] = label .. "." .. branch_name .. "." .. leaf_name .. "=" .. safe_text(path_value)
            end
        end
    end

    if #parts == 0 then
        return label .. ".paths=none"
    end
    return table.concat(parts, " ")
end

local function collect_double_nested_path_values(root, label, base_path, first_branches, second_branches, leaf_names)
    local parts = {}
    for i = 1, #first_branches do
        local first_branch = first_branches[i]
        for j = 1, #second_branches do
            local second_branch = second_branches[j]
            for k = 1, #leaf_names do
                local leaf_name = leaf_names[k]
                local path_name = base_path .. "." .. first_branch .. "." .. second_branch .. "." .. leaf_name
                local path_value, found = read_path(root, path_name)
                if found and path_value ~= nil then
                    parts[#parts + 1] = label .. "." .. first_branch .. "." .. second_branch .. "." .. leaf_name .. "=" .. safe_text(path_value)
                end
            end
        end
    end

    if #parts == 0 then
        return label .. ".paths=none"
    end
    return table.concat(parts, " ")
end

local function property_is_a(property, property_type)
    if property == nil or property_type == nil or not has_method(property, "IsA") then
        return false
    end
    local ok, value = safe_call(function()
        return property:IsA(property_type)
    end)
    return ok and value == true
end

local function property_name(property)
    local f_name, ok_f_name = safe_method(property, "GetFName")
    if ok_f_name and f_name ~= nil then
        local name_text, ok_name_text = safe_method(f_name, "ToString")
        if ok_name_text and name_text ~= nil then
            return tostring(name_text)
        end
    end
    return safe_text(property)
end

local function property_type_name(property)
    if type(PropertyTypes) ~= "table" then
        return "UnknownProperty"
    end

    local ordered_types = {
        { "Int8Property", PropertyTypes.Int8Property },
        { "Int16Property", PropertyTypes.Int16Property },
        { "IntProperty", PropertyTypes.IntProperty },
        { "Int64Property", PropertyTypes.Int64Property },
        { "FloatProperty", PropertyTypes.FloatProperty },
        { "BoolProperty", PropertyTypes.BoolProperty },
        { "ByteProperty", PropertyTypes.ByteProperty },
        { "EnumProperty", PropertyTypes.EnumProperty },
        { "NameProperty", PropertyTypes.NameProperty },
        { "StrProperty", PropertyTypes.StrProperty },
        { "TextProperty", PropertyTypes.TextProperty },
        { "StructProperty", PropertyTypes.StructProperty },
        { "ObjectProperty", PropertyTypes.ObjectProperty },
        { "WeakObjectProperty", PropertyTypes.WeakObjectProperty },
        { "ClassProperty", PropertyTypes.ClassProperty },
        { "ArrayProperty", PropertyTypes.ArrayProperty },
        { "MapProperty", PropertyTypes.MapProperty },
    }

    for i = 1, #ordered_types do
        local label = ordered_types[i][1]
        local property_type = ordered_types[i][2]
        if property_is_a(property, property_type) then
            return label
        end
    end

    return "UnknownProperty"
end

local function typed_property_value(target, property)
    if target == nil or property == nil then
        return "nil"
    end

    local name = property_name(property)
    local value, found = read_property(target, name)
    if not found then
        return "<unreadable>"
    end
    if value == nil then
        return "nil"
    end

    local property_type = property_type_name(property)
    if property_type == "NameProperty" or property_type == "StrProperty" or property_type == "TextProperty" then
        local text_value = string_value_from_object(value)
        if text_value ~= nil then
            return text_value
        end
    end

    if property_type == "BoolProperty"
        or property_type == "ByteProperty"
        or property_type == "Int8Property"
        or property_type == "Int16Property"
        or property_type == "IntProperty"
        or property_type == "Int64Property"
        or property_type == "FloatProperty"
        or property_type == "EnumProperty" then
        return safe_text(value)
    end

    return safe_text(value)
end

local function direct_property_summary(label, target)
    if target == nil then
        return label .. ".properties=nil"
    end
    if not has_method(target, "ForEachProperty") then
        return label .. ".properties=unavailable"
    end

    local probe = get_probe_config()
    local max_properties = probe.max_properties_per_object or 16
    local parts = {}

    local ok_iter = pcall(function()
        target:ForEachProperty(function(property)
            if #parts >= max_properties then
                return true
            end

            local name = property_name(property)
            local value = typed_property_value(target, property)
            parts[#parts + 1] = name .. ":" .. property_type_name(property) .. "=" .. value
        end)
    end)

    if not ok_iter then
        return label .. ".properties=failed"
    end
    if #parts == 0 then
        return label .. ".properties=empty"
    end
    return label .. ".properties=" .. table.concat(parts, " | ")
end

local function nested_direct_property_summary(label, target)
    if target == nil then
        return label .. ".children=nil"
    end
    if not has_method(target, "ForEachProperty") then
        return label .. ".children=unavailable"
    end

    local probe = get_probe_config()
    local max_properties = probe.max_properties_per_object or 16
    local parts = {}

    local ok_iter = pcall(function()
        target:ForEachProperty(function(property)
            if #parts >= max_properties then
                return true
            end

            local child_name = property_name(property)
            local child_value, found = read_property(target, child_name)
            if found and child_value ~= nil and has_method(child_value, "ForEachProperty") then
                parts[#parts + 1] = direct_property_summary(label .. "." .. child_name, child_value)
            end
        end)
    end)

    if not ok_iter then
        return label .. ".children=failed"
    end
    if #parts == 0 then
        return label .. ".children=none"
    end
    return table.concat(parts, " || ")
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

local function collect_guid_words(label, value)
    local fields = { "A", "B", "C", "D" }
    local words = {}
    for i = 1, #fields do
        local field_value, found = read_property(value, fields[i])
        if not found or field_value == nil then
            return label .. ".guid_words=missing"
        end

        local normalized = normalize_guid_word(field_value)
        if normalized == nil then
            return label .. ".guid_words=unusable"
        end
        words[#words + 1] = normalized
    end

    return label .. ".guid_words=" .. table.concat(words, "") .. " guid_like=" .. tostring(_util.guid_like(table.concat(words, "")))
end

local function test_chain_summary(context)
    return table.concat({
        "actor=" .. safe_text(context.actor),
        "best_property=" .. tostring(context.result.best_candidate and context.result.best_candidate.property),
        "best_value=" .. safe_text(context.best_value),
        "save_parameter=" .. safe_text(context.save_parameter),
        "individual_id=" .. safe_text(context.individual_id),
        "wrapper=" .. safe_text(context.instance_wrapper),
    }, " ")
end

local function test_actor_surface(context)
    return describe_object("actor", context.actor)
end

local function test_save_parameter_surface(context)
    return describe_object("save_parameter", context.save_parameter)
end

local function test_individual_id_surface(context)
    return describe_object("individual_id", context.individual_id)
end

local function test_instance_wrapper_surface(context)
    return describe_object("instance_wrapper", context.instance_wrapper)
end

local function test_save_parameter_selected_fields(context)
    return collect_selected_fields("save_parameter", context.save_parameter, {
        "OwnerPlayerUId",
        "OwnerPlayerUid",
        "CharacterID",
        "CharacterId",
        "SlotIndex",
        "Slot",
        "ContainerId",
        "CharacterContainerId",
        "IndividualId",
    })
end

local function test_individual_id_selected_fields(context)
    return collect_selected_fields("individual_id", context.individual_id, {
        "InstanceId",
        "PlayerUId",
        "OwnerPlayerUId",
        "OwnerPlayerUid",
        "A",
        "B",
        "C",
        "D",
    })
end

local function test_instance_wrapper_selected_fields(context)
    return collect_selected_fields("instance_wrapper", context.instance_wrapper, {
        "A",
        "B",
        "C",
        "D",
        "Value",
        "Guid",
        "GUID",
        "InstanceId",
    })
end

local function test_save_parameter_property_names(context)
    return "save_parameter.properties=" .. collect_property_names(context.save_parameter)
end

local function test_individual_id_property_names(context)
    return "individual_id.properties=" .. collect_property_names(context.individual_id)
end

local function test_instance_wrapper_property_names(context)
    return "instance_wrapper.properties=" .. collect_property_names(context.instance_wrapper)
end

local function test_instance_wrapper_guid_words(context)
    return collect_guid_words("instance_wrapper", context.instance_wrapper)
end

local function test_individual_id_guid_words(context)
    return collect_guid_words("individual_id", context.individual_id)
end

local function test_preferred_path_values(context)
    local preferred_paths = (_config.discovery and _config.discovery.preferred_guid_paths) or {}
    return collect_path_values(context.actor, "preferred", preferred_paths)
end

local function test_save_parameter_chain_paths(context)
    return collect_path_values(context.actor, "save_chain", {
        "SaveParameter.OwnerPlayerUId",
        "SaveParameter.OwnerPlayerUid",
        "SaveParameter.CharacterContainerId",
        "SaveParameter.ContainerId",
        "SaveParameter.SlotIndex",
        "SaveParameter.Slot",
        "SaveParameter.IndividualId",
        "SaveParameter.IndividualId.PlayerUId",
        "SaveParameter.IndividualId.InstanceId",
        "SaveParameter.IndividualId.InstanceId.A",
        "SaveParameter.IndividualId.InstanceId.B",
        "SaveParameter.IndividualId.InstanceId.C",
        "SaveParameter.IndividualId.InstanceId.D",
    })
end

local function test_instance_wrapper_deep_paths(context)
    return collect_nested_path_values(
        context.actor,
        "instance_deep",
        "SaveParameter.IndividualId.InstanceId",
        { "A", "B", "C", "D" },
        { "A", "B", "C", "D", "Value", "Guid", "GUID", "InstanceId" }
    )
end

local function test_instance_wrapper_terminal_paths(context)
    return collect_double_nested_path_values(
        context.actor,
        "instance_terminal",
        "SaveParameter.IndividualId.InstanceId",
        { "Value", "Guid", "GUID", "InstanceId" },
        { "A", "B", "C", "D", "Value", "Guid", "GUID", "InstanceId" },
        { "A", "B", "C", "D", "Value", "Guid", "GUID", "InstanceId" }
    )
end

local function test_individual_id_typed_properties(context)
    return direct_property_summary("individual_id", context.individual_id)
end

local function test_instance_wrapper_typed_properties(context)
    return direct_property_summary("instance_wrapper", context.instance_wrapper)
end

local function test_instance_wrapper_child_typed_properties(context)
    return nested_direct_property_summary("instance_wrapper", context.instance_wrapper)
end

local TESTS = {
    chain_summary = test_chain_summary,
    actor_surface = test_actor_surface,
    save_parameter_surface = test_save_parameter_surface,
    individual_id_surface = test_individual_id_surface,
    instance_wrapper_surface = test_instance_wrapper_surface,
    save_parameter_selected_fields = test_save_parameter_selected_fields,
    individual_id_selected_fields = test_individual_id_selected_fields,
    instance_wrapper_selected_fields = test_instance_wrapper_selected_fields,
    save_parameter_property_names = test_save_parameter_property_names,
    individual_id_property_names = test_individual_id_property_names,
    instance_wrapper_property_names = test_instance_wrapper_property_names,
    instance_wrapper_guid_words = test_instance_wrapper_guid_words,
    individual_id_guid_words = test_individual_id_guid_words,
    preferred_path_values = test_preferred_path_values,
    save_parameter_chain_paths = test_save_parameter_chain_paths,
    instance_wrapper_deep_paths = test_instance_wrapper_deep_paths,
    instance_wrapper_terminal_paths = test_instance_wrapper_terminal_paths,
    individual_id_typed_properties = test_individual_id_typed_properties,
    instance_wrapper_typed_properties = test_instance_wrapper_typed_properties,
    instance_wrapper_child_typed_properties = test_instance_wrapper_child_typed_properties,
}

local TEST_ORDER = {
    "chain_summary",
    "preferred_path_values",
    "save_parameter_chain_paths",
    "individual_id_typed_properties",
    "instance_wrapper_typed_properties",
    "instance_wrapper_child_typed_properties",
    "instance_wrapper_deep_paths",
    "instance_wrapper_terminal_paths",
    "actor_surface",
    "save_parameter_surface",
    "individual_id_surface",
    "instance_wrapper_surface",
    "save_parameter_selected_fields",
    "individual_id_selected_fields",
    "instance_wrapper_selected_fields",
    "save_parameter_property_names",
    "individual_id_property_names",
    "instance_wrapper_property_names",
    "instance_wrapper_guid_words",
    "individual_id_guid_words",
}

local function should_probe(result, resolved)
    local probe = get_probe_config()
    if not probe.enabled then
        return false
    end
    if not result or not result.best_candidate then
        return false
    end
    if probe.only_when_unresolved_wrapper ~= false then
        if not resolved or resolved.status ~= "none" or resolved.reason ~= "unresolved_identity_wrapper" then
            return false
        end
    end
    if probe.only_when_best_value_is_uobject ~= false then
        if not _util.is_uobject_text(result.best_candidate.value) then
            return false
        end
    end
    if probe.only_preferred_paths ~= false then
        local preferred = (_config.discovery and _config.discovery.preferred_guid_paths) or {}
        local property_name = result.best_candidate.property
        local matched = false
        for i = 1, #preferred do
            if preferred[i] == property_name then
                matched = true
                break
            end
        end
        if not matched then
            return false
        end
    end
    return true
end

local function build_target_key(result)
    local best = result.best_candidate or {}
    return table.concat({
        tostring(result.actor_key or "unknown_actor"),
        tostring(best.property or "unknown_property"),
        tostring(best.value or "unknown_value"),
    }, "|")
end

local function build_context(actor, result, trigger_name, resolved)
    local save_parameter = read_path(actor, "SaveParameter")
    local individual_id = nil
    local instance_wrapper = nil

    if save_parameter ~= nil then
        individual_id = read_path(save_parameter, "IndividualId")
        if individual_id ~= nil then
            instance_wrapper = read_path(individual_id, "InstanceId")
        end
    end

    if instance_wrapper == nil then
        instance_wrapper = result.best_candidate and result.best_candidate.value
    end

    return {
        actor = actor,
        result = result,
        trigger_name = trigger_name,
        resolved = resolved,
        save_parameter = save_parameter,
        individual_id = individual_id,
        instance_wrapper = instance_wrapper,
        best_value = result.best_candidate and result.best_candidate.value,
    }
end

local function run_test(test_name, context)
    local fn = TESTS[test_name]
    if type(fn) ~= "function" then
        return
    end

    local probe = get_probe_config()
    local max_runs_per_test = probe.max_runs_per_test or 4
    local current_runs = _state.runs_by_test[test_name] or 0
    if current_runs >= max_runs_per_test then
        return
    end

    local ok, message = safe_call(fn, context)
    _state.runs_by_test[test_name] = current_runs + 1

    if ok and message ~= nil and message ~= "" then
        _logger.discovery(
            "[PROBE][" .. tostring(test_name) .. "] trigger=" .. tostring(context.trigger_name) .. " " .. tostring(message),
            "probe_" .. tostring(test_name) .. "_" .. tostring(context.result.actor_key),
            1
        )
    else
        _logger.warn(
            "[PROBE][" .. tostring(test_name) .. "] failed trigger=" .. tostring(context.trigger_name),
            "probe_failed_" .. tostring(test_name),
            2
        )
    end
end

function ProbeLab.init(config, logger, util)
    _config = config
    _logger = logger
    _util = util
end

function ProbeLab.maybe_probe(actor, result, trigger_name, resolved)
    if not should_probe(result, resolved) then
        return
    end

    local probe = get_probe_config()
    local max_targets = probe.max_targets or 3
    local target_key = build_target_key(result)
    if _state.seen_targets[target_key] then
        return
    end
    if _state.target_runs >= max_targets then
        return
    end

    _state.seen_targets[target_key] = true
    _state.target_runs = _state.target_runs + 1

    local context = build_context(actor, result, trigger_name, resolved)
    local tests = get_test_config()
    for i = 1, #TEST_ORDER do
        local test_name = TEST_ORDER[i]
        local enabled = tests[test_name]
        if enabled then
            run_test(test_name, context)
        end
    end
end

return ProbeLab
