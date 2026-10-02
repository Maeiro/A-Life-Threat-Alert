require "PZAPI/ModOptions"

local MOD_ID = "ALifeThreatAlert"
local DEFAULT_RANGE = 40
local MIN_RANGE = 5
local MAX_RANGE = 100
local SCAN_INTERVAL = 5
local STANCES = { friendly = true, neutral = true, careful = true, hostile = true }
local SHADOW_OFFSETS = { {-1, 0}, {1, 0}, {0, -1}, {0, 1} }

local modOptions
if PZAPI and PZAPI.ModOptions then
    modOptions = PZAPI.ModOptions:create(MOD_ID, "A-Life Threat Alert")
    modOptions:addTickBox("EnableHostileWarning", "Warn about nearby hostile NPCs", true)
    modOptions:addSlider(
        "WarningDistance",
        "Maximum warning distance (tiles)",
        MIN_RANGE,
        MAX_RANGE,
        1,
        DEFAULT_RANGE,
        "Maximum horizontal distance at which A-Life NPCs trigger a warning."
    )
    modOptions:addTickBox("WarnCarefulNPCs", "Also warn about careful NPCs", true)
end

local function getOption(name, fallback)
    if not PZAPI or not PZAPI.ModOptions then return fallback end
    local ok, value = pcall(function()
        local currentOptions = PZAPI.ModOptions:getOptions(MOD_ID) or modOptions
        local option = currentOptions and currentOptions:getOption(name)
        if not option then return nil end
        return option:getValue()
    end)
    if not ok or value == nil then return fallback end
    return value
end

local function warningRange()
    local value = tonumber(getOption("WarningDistance", DEFAULT_RANGE))
    if not value then return DEFAULT_RANGE end
    return math.max(MIN_RANGE, math.min(MAX_RANGE, math.floor(value + 0.5)))
end

local function normalizeStance(value)
    if type(value) ~= "string" then return nil end
    value = string.lower(value)
    if value == "allied" then return "friendly" end
    if value == "suspicious" then return "careful" end
    return STANCES[value] and value or nil
end

local function playerKey(player)
    if type(isClient) == "function" then
        local ok, client = pcall(isClient)
        if ok and client then
            local okUsername, username = pcall(function() return player:getUsername() end)
            if okUsername and username ~= nil and tostring(username) ~= "" then
                return tostring(username)
            end
        end
    end
    local ok, number = pcall(function() return player:getPlayerNum() end)
    return "sp:" .. tostring(math.max(0, math.floor(tonumber(ok and number or 0) or 0)))
end

local function reputationStance(project, factionId)
    local store = project.StatusStore
    local reputation = type(store) == "table" and store.reputation or nil
    local relations = type(reputation) == "table" and reputation.relations or nil
    if type(relations) ~= "table" then return nil end
    for _, row in ipairs(relations) do
        if type(row) == "table" and row.factionId == factionId then
            local stance = normalizeStance(row.status)
            if stance then return stance end
        end
    end
    return nil
end

local function fallbackStance(project, record, player)
    local memory = type(record.memory) == "table" and record.memory or {}
    if memory.hostileOverride == true then return "hostile" end
    local key = playerKey(player)
    if type(memory.hostileToPlayerKeys) == "table" and memory.hostileToPlayerKeys[key] == true then
        return "hostile"
    end
    if memory.hostileOverride == false then return "friendly" end

    local catalog = project.Catalog
    local faction
    if type(catalog) == "table" and type(catalog.faction) == "function" then
        local ok, value = pcall(catalog.faction, record.factionId)
        if ok and type(value) == "table" then faction = value end
    end
    local relations = faction and faction.relations or nil
    local declared = type(relations) == "table" and normalizeStance(relations.player) or nil
    local spawn = faction and faction.spawn or nil
    local default = declared or (type(spawn) == "table" and spawn.friendly == true and "friendly" or "hostile")
    local stance = normalizeStance(memory.spawnStance) or default
    return reputationStance(project, record.factionId) or stance
end

local function stanceOf(project, record, player)
    local relations = project.Relations
    if type(relations) == "table" and type(relations.playerStance) == "function" then
        local ok, stance = pcall(relations.playerStance, record, player)
        if ok then
            stance = normalizeStance(stance)
            if stance then return stance end
        end
    end

    local dots = ALifeStanceDots
    if type(dots) == "table" and type(dots.stanceOf) == "function" then
        local ok, stance = pcall(dots.stanceOf, record, player)
        if ok then
            stance = normalizeStance(stance)
            if stance then return stance end
        end
    end
    return fallbackStance(project, record, player)
end

local function actorFor(project, uid)
    local executor = project.Executor
    local mirror = type(executor) == "table" and executor.mirror or nil
    local records = type(mirror) == "table" and mirror.records or nil
    local record = type(records) == "table" and records[uid] or nil
    if type(record) == "table" then return record end

    local registry = project.ActorRegistry
    if type(registry) == "table" and type(registry.read) == "function" then
        local ok, value = pcall(registry.read, uid)
        if ok and type(value) == "table" then return value end
    end
    return nil
end

local function uidOf(project, shell)
    local speech = project.Speech
    if type(speech) == "table" and type(speech.variable) == "function" then
        local ok, uid = pcall(speech.variable, shell, "ALifeUID")
        if ok and uid ~= nil and tostring(uid) ~= "" then return tostring(uid) end
    end
    local ok, data = pcall(function() return shell:getModData() end)
    if ok and type(data) == "table" and type(data.ProjectALifeUID) == "string" then
        return data.ProjectALifeUID
    end
    return nil
end

local warning
local errorLogged = false

local function scanNearbyNPCs()
    warning = nil
    if not getOption("EnableHostileWarning", true) then return end

    local project = ProjectALife
    if type(project) ~= "table" then return end
    local player = getSpecificPlayer(0)
    if player == nil or player:isDead() then return end
    local cell = getCell()
    local list = cell and cell:getZombieList() or nil
    if list == nil then return end

    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local range = warningRange()
    local rangeSquared = range * range
    local warnCareful = getOption("WarnCarefulNPCs", true)
    local hostiles, careful = 0, 0
    local nearestHostile, nearestCareful = rangeSquared, rangeSquared
    for index = 0, list:size() - 1 do
        local shell = list:get(index)
        if shell ~= nil and not shell:isDead() then
            local x, y, z = shell:getX(), shell:getY(), shell:getZ()
            local dx, dy = x - px, y - py
            local distanceSquared = dx * dx + dy * dy
            if math.abs(z - pz) <= 1 and distanceSquared <= rangeSquared then
                local uid = uidOf(project, shell)
                local record = uid and actorFor(project, uid) or nil
                if record then
                    local stance = stanceOf(project, record, player)
                    if stance == "hostile" then
                        hostiles = hostiles + 1
                        nearestHostile = math.min(nearestHostile, distanceSquared)
                    elseif stance == "careful" and warnCareful then
                        careful = careful + 1
                        nearestCareful = math.min(nearestCareful, distanceSquared)
                    end
                end
            end
        end
    end

    if hostiles > 0 then
        warning = { stance = "hostile", count = hostiles, distance = math.sqrt(nearestHostile) }
    elseif careful > 0 then
        warning = { stance = "careful", count = careful, distance = math.sqrt(nearestCareful) }
    end
end

local function updateWarning()
    local ok, err = pcall(scanNearbyNPCs)
    if not ok then
        warning = nil
        if not errorLogged then
            print("[A-Life Threat Alert] Detection failed: " .. tostring(err))
            errorLogged = true
        end
    end
end

local function drawWarning()
    if warning == nil then return end
    local ok, err = pcall(function()
        local message
        local colour
        if warning.stance == "hostile" then
            message = warning.count == 1 and "HOSTILE A-LIFE NPC NEARBY"
                or "HOSTILE A-LIFE NPCs NEARBY (" .. tostring(warning.count) .. ")"
            colour = { 1, 0.12, 0.08 }
        else
            message = warning.count == 1 and "CAREFUL A-LIFE NPC NEARBY"
                or "CAREFUL A-LIFE NPCs NEARBY (" .. tostring(warning.count) .. ")"
            colour = { 1, 0.68, 0.12 }
        end
        message = message .. "  " .. tostring(math.floor(warning.distance + 0.5)) .. " tiles"

        local core = getCore()
        local x = core:getScreenWidth() * 0.5
        local text = getTextManager()
        for _, offset in ipairs(SHADOW_OFFSETS) do
            text:DrawStringCentre(UIFont.Large, x + offset[1], 24 + offset[2], message, 0, 0, 0, 1)
        end
        text:DrawStringCentre(UIFont.Large, x, 24, message, colour[1], colour[2], colour[3], 1)
    end)
    if not ok and not errorLogged then
        print("[A-Life Threat Alert] Warning display failed: " .. tostring(err))
        errorLogged = true
    end
end

local ticks = 0
if Events and Events.OnTick then
    Events.OnTick.Add(function()
        ticks = ticks + 1
        if ticks % SCAN_INTERVAL == 0 then updateWarning() end
    end)
end

if Events and Events.OnPreUIDraw then
    Events.OnPreUIDraw.Add(drawWarning)
end
