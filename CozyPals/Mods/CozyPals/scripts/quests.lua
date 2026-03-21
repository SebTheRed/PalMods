local Quests = {}

local _config = nil
local _logger = nil
local _util = nil
local _json = nil
local _dialogue = nil

local _loaded = false
local _script_dir = "./"
local _fetch_roll_rows = {}
local _fetch_rows_by_band = {}
local _fetch_rules = {}

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

local function parse_json_lines(path)
    local payload = _util.read_file(path)
    if not payload or payload == "" then
        return {}
    end

    local rows = {}
    for line in string.gmatch(payload, "[^\r\n]+") do
        if line ~= "" then
            local decoded = _json.decode(line)
            if decoded ~= nil then
                rows[#rows + 1] = decoded
            end
        end
    end

    return rows
end

local function resolve_data_root()
    local configured_paths = (_config.quest and _config.quest.data_paths) or (_config.dialogue and _config.dialogue.data_paths) or {}
    local candidates = {}

    for i = 1, #configured_paths do
        candidates[#candidates + 1] = _util.path_join(_script_dir, configured_paths[i])
    end

    return first_existing_path(candidates)
end

local function trust_band_from_value(trust_value)
    if _dialogue and type(_dialogue.get_trust_band) == "function" then
        return _dialogue.get_trust_band(trust_value)
    end

    local value = math.max(1, math.min(99, math.floor(tonumber(trust_value) or 40)))
    if value <= 20 then
        return "trust_01_20"
    end
    if value <= 40 then
        return "trust_21_40"
    end
    if value <= 60 then
        return "trust_41_60"
    end
    if value <= 80 then
        return "trust_61_80"
    end
    return "trust_81_99"
end

local function build_rows_by_band(rows)
    local lookup = {}
    for i = 1, #rows do
        local row = rows[i]
        local band = tostring(row.trust_band or "")
        if band ~= "" then
            lookup[band] = lookup[band] or {}
            lookup[band][#lookup[band] + 1] = row
        end
    end
    return lookup
end

local function ensure_loaded()
    if _loaded then
        return true
    end

    local root = resolve_data_root()
    if not root then
        _logger.warn("Quest data directory not found. Fetch quest generation disabled.")
        _loaded = true
        _fetch_roll_rows = {}
        _fetch_rows_by_band = {}
        _fetch_rules = {}
        return false
    end

    local roll_table_path = _util.path_join(root, (_config.quest and _config.quest.roll_table_file) or "fetch_item_roll_table_by_trust.jsonl")
    local rules_path = _util.path_join(root, (_config.quest and _config.quest.rules_file) or "fetch_item_draw_rules.json")

    _fetch_roll_rows = parse_json_lines(roll_table_path)
    _fetch_rows_by_band = build_rows_by_band(_fetch_roll_rows)

    local rules_payload = _util.read_file(rules_path)
    _fetch_rules = {}
    if rules_payload and rules_payload ~= "" then
        _fetch_rules = _json.decode(rules_payload) or {}
    end

    _loaded = true
    _logger.info("Quest dataset loaded. fetch_rows=" .. tostring(#_fetch_roll_rows))
    return #_fetch_roll_rows > 0
end

local function ensure_quest_state(record)
    record.quests = record.quests or {
        version = 1,
        active_fetch = nil,
        history = {},
        last_fetch_issued_at = 0,
        last_fetch_completed_at = 0,
        counters = {
            issued = 0,
            completed = 0,
            abandoned = 0,
        },
    }

    record.quests.version = record.quests.version or 1
    record.quests.history = record.quests.history or {}
    record.quests.last_fetch_issued_at = tonumber(record.quests.last_fetch_issued_at) or 0
    record.quests.last_fetch_completed_at = tonumber(record.quests.last_fetch_completed_at) or 0
    record.quests.counters = record.quests.counters or {}
    record.quests.counters.issued = math.floor(tonumber(record.quests.counters.issued) or 0)
    record.quests.counters.completed = math.floor(tonumber(record.quests.counters.completed) or 0)
    record.quests.counters.abandoned = math.floor(tonumber(record.quests.counters.abandoned) or 0)

    return record.quests
end

local function archive_fetch(quest_state, fetch, archive_status)
    if not fetch then
        return
    end

    quest_state.history = quest_state.history or {}
    local archived = {}
    for key, value in pairs(fetch) do
        archived[key] = value
    end
    archived.archived_at = _util.now()
    archived.status = archive_status or archived.status or "archived"

    quest_state.history[#quest_state.history + 1] = archived

    local max_history = ((_config.quest or {}).max_history) or 20
    while #quest_state.history > max_history do
        table.remove(quest_state.history, 1)
    end
end

local function weighted_choice(rows)
    if #rows == 0 then
        return nil
    end

    local total_weight = 0
    for i = 1, #rows do
        total_weight = total_weight + math.max(0, tonumber(rows[i].draw_weight) or 0)
    end

    if total_weight <= 0 then
        return rows[math.random(1, #rows)]
    end

    local cursor = math.random() * total_weight
    for i = 1, #rows do
        cursor = cursor - math.max(0, tonumber(rows[i].draw_weight) or 0)
        if cursor <= 0 then
            return rows[i]
        end
    end

    return rows[#rows]
end

local function roll_required_count(row)
    local minimum = math.max(1, math.floor(tonumber(row.quest_quantity_min) or 1))
    local maximum = math.max(minimum, math.floor(tonumber(row.quest_quantity_max) or minimum))
    if maximum == minimum then
        return minimum
    end
    return math.random(minimum, maximum)
end

local function display_name(item_name, required_count)
    local count = math.max(1, math.floor(tonumber(required_count) or 1))
    local name = tostring(item_name or "that item")
    if count <= 1 then
        return name
    end
    return tostring(count) .. " " .. name
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

local function fetch_request_chance_for_band(trust_band)
    local quest_config = _config.quest or {}
    local by_band = quest_config.fetch_request_chance_by_trust or {}
    local chance = tonumber(by_band[trust_band])
    if chance == nil then
        chance = tonumber(quest_config.fetch_request_chance)
    end
    return clamp(tonumber(chance) or 0, 0, 1)
end

local function can_issue_new_fetch(quest_state)
    local cooldown_seconds = math.max(0, math.floor(tonumber(((_config.quest or {}).reissue_after_completion_seconds)) or 0))
    if cooldown_seconds <= 0 then
        return true
    end

    local last_completed_at = tonumber(quest_state.last_fetch_completed_at) or 0
    if last_completed_at <= 0 then
        return true
    end

    return (_util.now() - last_completed_at) >= cooldown_seconds
end

local function active_fetch(record)
    local quest_state = ensure_quest_state(record)
    local fetch = quest_state.active_fetch
    if type(fetch) ~= "table" then
        return nil
    end
    if tostring(fetch.status or "active") ~= "active" then
        return nil
    end
    return fetch
end

function Quests.init(config, logger, util, json, dialogue)
    _config = config
    _logger = logger
    _util = util
    _json = json
    _dialogue = dialogue
    _script_dir = detect_script_dir()
end

function Quests.ensure_record(record)
    return ensure_quest_state(record)
end

function Quests.get_active_fetch(record)
    return active_fetch(record)
end

function Quests.prepare_talk(context)
    if not context or not context.record then
        return false, "missing_record"
    end

    if (_config.quest and _config.quest.enabled) == false then
        return true, {
            trigger = "talk",
            quest = nil,
            created = false,
            dirty = false,
        }
    end

    local quest_state = ensure_quest_state(context.record)
    local current_fetch = active_fetch(context.record)
    if current_fetch then
        current_fetch.last_talk_at = _util.now()
        current_fetch.updated_at = _util.now()
        return true, {
            trigger = "quest_pending",
            quest = current_fetch,
            created = false,
            dirty = true,
        }
    end

    if (_config.quest and _config.quest.auto_issue_on_talk) == false then
        return true, {
            trigger = "talk",
            quest = nil,
            created = false,
            dirty = false,
        }
    end

    if not can_issue_new_fetch(quest_state) then
        return true, {
            trigger = "talk",
            quest = nil,
            created = false,
            dirty = false,
        }
    end

    if not ensure_loaded() then
        return true, {
            trigger = "talk",
            quest = nil,
            created = false,
            dirty = false,
        }
    end

    local trust_band = trust_band_from_value(context.trust_value)
    local rows = _fetch_rows_by_band[trust_band] or {}
    if #rows == 0 then
        return true, {
            trigger = "talk",
            quest = nil,
            created = false,
            dirty = false,
        }
    end

    local fetch_chance = fetch_request_chance_for_band(trust_band)
    if fetch_chance <= 0 or math.random() > fetch_chance then
        return true, {
            trigger = "talk",
            quest = nil,
            created = false,
            dirty = false,
        }
    end

    local row = weighted_choice(rows)
    if not row then
        return true, {
            trigger = "talk",
            quest = nil,
            created = false,
            dirty = false,
        }
    end

    local now = _util.now()
    local required_count = roll_required_count(row)
    local fetch = {
        version = 1,
        kind = "fetch",
        status = "active",
        quest_id = tostring(context.guid or "pal") .. "_fetch_" .. tostring(now),
        item_key = tostring(row.master_item_key or ""),
        item_slug = tostring(row.item_slug or ""),
        item_name = tostring(row.item_name or "that item"),
        item_display_name = display_name(row.item_name, required_count),
        rarity_tier = tostring(row.rarity_tier or "common"),
        required_count = required_count,
        delivered_count = 0,
        trust_band = trust_band,
        trust_points_reward = math.floor(tonumber(row.trust_points_reward) or 0),
        gatherable_kind = tostring(row.gatherable_kind or ""),
        source = "fetch_item_roll_table_by_trust",
        created_at = now,
        updated_at = now,
        issued_by = tostring(context.player_name or _config.dialogue.default_player_name or "Trainer"),
    }

    quest_state.active_fetch = fetch
    quest_state.last_fetch_issued_at = now
    quest_state.counters.issued = quest_state.counters.issued + 1

    return true, {
        trigger = "quest_request",
        quest = fetch,
        created = true,
        dirty = true,
    }
end

function Quests.complete_active_fetch(context)
    if not context or not context.record then
        return false, "missing_record"
    end

    local quest_state = ensure_quest_state(context.record)
    local fetch = active_fetch(context.record)
    if not fetch then
        return false, "no_active_fetch"
    end

    fetch.status = "completed"
    fetch.completed_at = _util.now()
    fetch.updated_at = fetch.completed_at
    fetch.delivered_count = math.max(fetch.required_count or 1, math.floor(tonumber(fetch.delivered_count) or 0))
    archive_fetch(quest_state, fetch, "completed")
    quest_state.active_fetch = nil
    quest_state.last_fetch_completed_at = fetch.completed_at
    quest_state.counters.completed = quest_state.counters.completed + 1

    return true, fetch
end

function Quests.abandon_active_fetch(context)
    if not context or not context.record then
        return false, "missing_record"
    end

    local quest_state = ensure_quest_state(context.record)
    local fetch = active_fetch(context.record)
    if not fetch then
        return false, "no_active_fetch"
    end

    fetch.status = "abandoned"
    fetch.updated_at = _util.now()
    archive_fetch(quest_state, fetch, "abandoned")
    quest_state.active_fetch = nil
    quest_state.counters.abandoned = quest_state.counters.abandoned + 1

    return true, fetch
end

return Quests
