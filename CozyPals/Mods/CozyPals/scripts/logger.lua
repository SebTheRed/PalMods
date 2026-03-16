local Logger = {}

local level_weight = {
    ERR = 0,
    WARN = 1,
    INFO = 2,
    DEBUG = 3,
    DISCOVERY = 4,
}

local min_weight = level_weight.INFO
local default_throttle_seconds = 5
local last_log_by_key = {}

local function now()
    return os.time()
end

local function should_log(level)
    local weight = level_weight[level] or level_weight.INFO
    return weight <= min_weight
end

function Logger.init(config)
    local logging = config.logging or {}
    local level = string.upper(logging.level or "INFO")
    min_weight = level_weight[level] or level_weight.INFO
    default_throttle_seconds = logging.default_throttle_seconds or 5
end

function Logger.set_level(level)
    local upper = string.upper(level or "")
    min_weight = level_weight[upper] or min_weight
end

function Logger.log(level, message, throttle_key, throttle_seconds)
    local upper = string.upper(level or "INFO")
    if not should_log(upper) then
        return
    end

    local key = throttle_key
    if key ~= nil then
        local current_time = now()
        local window = throttle_seconds or default_throttle_seconds
        local last = last_log_by_key[key]
        if last ~= nil and current_time - last < window then
            return
        end
        last_log_by_key[key] = current_time
    end

    print("[CozyPals][" .. upper .. "] " .. tostring(message))
end

function Logger.err(message, throttle_key, throttle_seconds)
    Logger.log("ERR", message, throttle_key, throttle_seconds)
end

function Logger.warn(message, throttle_key, throttle_seconds)
    Logger.log("WARN", message, throttle_key, throttle_seconds)
end

function Logger.info(message, throttle_key, throttle_seconds)
    Logger.log("INFO", message, throttle_key, throttle_seconds)
end

function Logger.debug(message, throttle_key, throttle_seconds)
    Logger.log("DEBUG", message, throttle_key, throttle_seconds)
end

function Logger.discovery(message, throttle_key, throttle_seconds)
    Logger.log("DISCOVERY", message, throttle_key, throttle_seconds)
end

return Logger
