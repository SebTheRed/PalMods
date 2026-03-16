local Util = {}

local function execute_silent(command)
    local ok = os.execute(command)
    if ok == true or ok == 0 then
        return true
    end
    return false
end

function Util.now()
    return os.time()
end

function Util.safe_tostring(value)
    local ok, text = pcall(function()
        return tostring(value)
    end)
    if ok then
        return text
    end
    return "<unprintable>"
end

function Util.contains_text(text, needle)
    if text == nil or needle == nil then
        return false
    end
    return string.find(text, needle, 1, true) ~= nil
end

function Util.sanitize_key(text)
    local raw = tostring(text or "unknown")
    raw = string.gsub(raw, "[^%w%._%-]+", "_")
    raw = string.gsub(raw, "_+", "_")
    raw = string.gsub(raw, "^_+", "")
    raw = string.gsub(raw, "_+$", "")
    if raw == "" then
        return "unknown"
    end
    return string.lower(raw)
end

function Util.path_join(a, b)
    if not a or a == "" then
        return b
    end
    if not b or b == "" then
        return a
    end
    if string.sub(a, -1) == "/" or string.sub(a, -1) == "\\" then
        return a .. b
    end
    return a .. "/" .. b
end

function Util.file_exists(path)
    local file = io.open(path, "rb")
    if file then
        file:close()
        return true
    end
    return false
end

function Util.read_file(path)
    local file, open_err = io.open(path, "rb")
    if not file then
        return nil, open_err
    end
    local text = file:read("*a")
    file:close()
    return text, nil
end

function Util.write_file(path, text)
    local file, open_err = io.open(path, "wb")
    if not file then
        return false, open_err
    end
    file:write(text)
    file:close()
    return true, nil
end

function Util.ensure_directory(path)
    if not path or path == "" then
        return false, "missing path"
    end

    local is_windows = package.config and string.sub(package.config, 1, 1) == "\\"
    if is_windows then
        return execute_silent('if not exist "' .. path .. '" mkdir "' .. path .. '"')
    end
    return execute_silent('mkdir -p "' .. path .. '"')
end

function Util.atomic_write(path, text, backup_suffix, temp_suffix)
    local tmp_path = path .. (temp_suffix or ".tmp")
    local backup_path = path .. (backup_suffix or ".bak")

    local write_ok, write_err = Util.write_file(tmp_path, text)
    if not write_ok then
        return false, "failed writing temp file: " .. tostring(write_err)
    end

    if Util.file_exists(backup_path) then
        os.remove(backup_path)
    end

    if Util.file_exists(path) then
        local moved = os.rename(path, backup_path)
        if not moved then
            os.remove(tmp_path)
            return false, "failed creating backup file"
        end
    end

    local renamed = os.rename(tmp_path, path)
    if not renamed then
        os.remove(tmp_path)
        if Util.file_exists(backup_path) then
            os.rename(backup_path, path)
        end
        return false, "failed replacing save file"
    end

    return true, nil
end

function Util.table_size(tbl)
    if type(tbl) ~= "table" then
        return 0
    end
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

function Util.ensure_table(target, key)
    if target[key] == nil then
        target[key] = {}
    end
    return target[key]
end

function Util.deep_copy(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for k, v in pairs(value) do
        result[Util.deep_copy(k)] = Util.deep_copy(v)
    end
    return result
end

function Util.is_array(tbl)
    if type(tbl) ~= "table" then
        return false
    end
    local count = 0
    for k in pairs(tbl) do
        if type(k) ~= "number" then
            return false
        end
        if k <= 0 or math.floor(k) ~= k then
            return false
        end
        count = count + 1
    end
    if count == 0 then
        return true
    end
    for i = 1, count do
        if tbl[i] == nil then
            return false
        end
    end
    return true
end

function Util.hash_text(text)
    local value = tostring(text or "")
    local hash = 5381
    for i = 1, #value do
        hash = ((hash * 33) + string.byte(value, i)) % 2147483647
    end
    if hash < 0 then
        hash = hash * -1
    end
    return hash
end

function Util.guid_like(text)
    local value = tostring(text or "")
    if value == "" then
        return false
    end
    if string.match(value, "^[%x]+%-%x+%-%x+%-%x+%-%x+$") then
        return true
    end
    if string.match(value, "^[%x]+$") and #value >= 16 then
        return true
    end
    return false
end

function Util.serialize_context(context)
    if type(context) ~= "table" then
        return "none"
    end
    local keys = {}
    for k in pairs(context) do
        keys[#keys + 1] = tostring(k)
    end
    table.sort(keys)

    local parts = {}
    for i = 1, #keys do
        local key = keys[i]
        parts[#parts + 1] = key .. "=" .. tostring(context[key])
    end
    return table.concat(parts, "|")
end

return Util
