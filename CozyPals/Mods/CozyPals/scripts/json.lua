local Json = {}

local function encode_string(value)
    local escaped = value
    escaped = string.gsub(escaped, "\\", "\\\\")
    escaped = string.gsub(escaped, "\"", "\\\"")
    escaped = string.gsub(escaped, "\b", "\\b")
    escaped = string.gsub(escaped, "\f", "\\f")
    escaped = string.gsub(escaped, "\n", "\\n")
    escaped = string.gsub(escaped, "\r", "\\r")
    escaped = string.gsub(escaped, "\t", "\\t")
    return "\"" .. escaped .. "\""
end

local function is_array(tbl)
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

local function encode_value(value)
    local t = type(value)
    if t == "nil" then
        return "null"
    end
    if t == "boolean" then
        return value and "true" or "false"
    end
    if t == "number" then
        return tostring(value)
    end
    if t == "string" then
        return encode_string(value)
    end
    if t ~= "table" then
        return "null"
    end

    if is_array(value) then
        local parts = {}
        for i = 1, #value do
            parts[#parts + 1] = encode_value(value[i])
        end
        return "[" .. table.concat(parts, ",") .. "]"
    end

    local keys = {}
    for k in pairs(value) do
        keys[#keys + 1] = tostring(k)
    end
    table.sort(keys)

    local fields = {}
    for i = 1, #keys do
        local key = keys[i]
        fields[#fields + 1] = encode_string(key) .. ":" .. encode_value(value[key])
    end
    return "{" .. table.concat(fields, ",") .. "}"
end

function Json.encode(value)
    return encode_value(value)
end

local function parse_error(index, reason)
    return nil, "json parse error at " .. tostring(index) .. ": " .. tostring(reason)
end

local function decode_impl(text)
    local index = 1
    local length = #text

    local function skip_ws()
        while index <= length do
            local c = string.sub(text, index, index)
            if c == " " or c == "\t" or c == "\n" or c == "\r" then
                index = index + 1
            else
                break
            end
        end
    end

    local parse_value

    local function parse_string()
        if string.sub(text, index, index) ~= "\"" then
            return parse_error(index, "expected string")
        end
        index = index + 1
        local chars = {}
        while index <= length do
            local c = string.sub(text, index, index)
            if c == "\"" then
                index = index + 1
                return table.concat(chars), nil
            end
            if c == "\\" then
                index = index + 1
                local esc = string.sub(text, index, index)
                if esc == "\"" then
                    chars[#chars + 1] = "\""
                elseif esc == "\\" then
                    chars[#chars + 1] = "\\"
                elseif esc == "/" then
                    chars[#chars + 1] = "/"
                elseif esc == "b" then
                    chars[#chars + 1] = "\b"
                elseif esc == "f" then
                    chars[#chars + 1] = "\f"
                elseif esc == "n" then
                    chars[#chars + 1] = "\n"
                elseif esc == "r" then
                    chars[#chars + 1] = "\r"
                elseif esc == "t" then
                    chars[#chars + 1] = "\t"
                else
                    return parse_error(index, "invalid escape")
                end
                index = index + 1
            else
                chars[#chars + 1] = c
                index = index + 1
            end
        end
        return parse_error(index, "unterminated string")
    end

    local function parse_number()
        local start = index
        local c = string.sub(text, index, index)
        if c == "-" then
            index = index + 1
        end
        while index <= length do
            c = string.sub(text, index, index)
            if string.match(c, "%d") then
                index = index + 1
            else
                break
            end
        end
        if string.sub(text, index, index) == "." then
            index = index + 1
            while index <= length do
                c = string.sub(text, index, index)
                if string.match(c, "%d") then
                    index = index + 1
                else
                    break
                end
            end
        end
        c = string.sub(text, index, index)
        if c == "e" or c == "E" then
            index = index + 1
            c = string.sub(text, index, index)
            if c == "+" or c == "-" then
                index = index + 1
            end
            while index <= length do
                c = string.sub(text, index, index)
                if string.match(c, "%d") then
                    index = index + 1
                else
                    break
                end
            end
        end
        local raw = string.sub(text, start, index - 1)
        local value = tonumber(raw)
        if value == nil then
            return parse_error(index, "invalid number")
        end
        return value, nil
    end

    local function parse_array()
        if string.sub(text, index, index) ~= "[" then
            return parse_error(index, "expected array")
        end
        index = index + 1
        skip_ws()
        local arr = {}
        if string.sub(text, index, index) == "]" then
            index = index + 1
            return arr, nil
        end
        while index <= length do
            local value, value_err = parse_value()
            if value_err then
                return nil, value_err
            end
            arr[#arr + 1] = value
            skip_ws()
            local c = string.sub(text, index, index)
            if c == "," then
                index = index + 1
                skip_ws()
            elseif c == "]" then
                index = index + 1
                return arr, nil
            else
                return parse_error(index, "expected ',' or ']'")
            end
        end
        return parse_error(index, "unterminated array")
    end

    local function parse_object()
        if string.sub(text, index, index) ~= "{" then
            return parse_error(index, "expected object")
        end
        index = index + 1
        skip_ws()
        local obj = {}
        if string.sub(text, index, index) == "}" then
            index = index + 1
            return obj, nil
        end
        while index <= length do
            local key, key_err = parse_string()
            if key_err then
                return nil, key_err
            end
            skip_ws()
            if string.sub(text, index, index) ~= ":" then
                return parse_error(index, "expected ':'")
            end
            index = index + 1
            skip_ws()
            local value, value_err = parse_value()
            if value_err then
                return nil, value_err
            end
            obj[key] = value
            skip_ws()
            local c = string.sub(text, index, index)
            if c == "," then
                index = index + 1
                skip_ws()
            elseif c == "}" then
                index = index + 1
                return obj, nil
            else
                return parse_error(index, "expected ',' or '}'")
            end
        end
        return parse_error(index, "unterminated object")
    end

    parse_value = function()
        skip_ws()
        if index > length then
            return parse_error(index, "unexpected end of input")
        end
        local c = string.sub(text, index, index)
        if c == "\"" then
            return parse_string()
        end
        if c == "{" then
            return parse_object()
        end
        if c == "[" then
            return parse_array()
        end
        if c == "-" or string.match(c, "%d") then
            return parse_number()
        end
        if string.sub(text, index, index + 3) == "true" then
            index = index + 4
            return true, nil
        end
        if string.sub(text, index, index + 4) == "false" then
            index = index + 5
            return false, nil
        end
        if string.sub(text, index, index + 3) == "null" then
            index = index + 4
            return nil, nil
        end
        return parse_error(index, "unexpected token")
    end

    local result, err = parse_value()
    if err then
        return nil, err
    end

    skip_ws()
    if index <= length then
        return parse_error(index, "trailing characters")
    end
    return result, nil
end

function Json.decode(text)
    if type(text) ~= "string" then
        return nil, "json decode expects a string"
    end
    return decode_impl(text)
end

return Json
