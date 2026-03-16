-- CozyPals Discovery Skeleton
-- Purpose:
--   1) give you a clean place to start reverse engineering
--   2) log candidate pal actors/classes as they enter play
--   3) remind you where to inspect objects manually in Live Viewer
--
-- IMPORTANT:
--   This file is intentionally conservative. It only uses documented hook entry points.
--   You will still need Live Viewer / object dumps / header dumps to confirm the exact class names
--   and property names for Palworld's pal actors and save-related objects.

local DISCOVERY_ENABLED = true
local LOG_PAL_KEYWORDS = {
    "Pal",
    "Otomo",
    "Worker",
    "BaseCamp"
}

local function cp_log(msg)
    print("[CozyPals][DISCOVERY] " .. tostring(msg))
end

local function safe_tostring(v)
    local ok, result = pcall(function()
        return tostring(v)
    end)
    if ok then return result end
    return "<unprintable>"
end

local function matches_keyword(text)
    if not text then return false end
    for _, kw in ipairs(LOG_PAL_KEYWORDS) do
        if string.find(text, kw) then
            return true
        end
    end
    return false
end

-- Fires before any actor BeginPlay. This is useful for discovering candidate actor classes.
RegisterBeginPlayPreHook(function(Actor)
    if not DISCOVERY_ENABLED or not Actor then return end

    local actor_text = safe_tostring(Actor)
    if matches_keyword(actor_text) then
        cp_log("BeginPlay candidate actor: " .. actor_text)
        cp_log("Inspect this actor in Live Viewer and search its properties for: Guid / UID / ID / Instance / Individual / Container / Slot / Owner")
    end
end)

-- A convenient moment to tell the player to run manual discovery steps.
RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
    if not DISCOVERY_ENABLED then return end
    cp_log("ClientRestart fired. If you are standing near your base, now is a good time to use Live Viewer.")
    cp_log("Recommended Live Viewer filters: Instances only = ON, search Pal / Otomo / Worker / BaseCamp")
    cp_log("Recommended dump actions: CTRL+J for object dump, CTRL+H or CTRL+Numpad9 for header dumps depending on your setup")
end)
