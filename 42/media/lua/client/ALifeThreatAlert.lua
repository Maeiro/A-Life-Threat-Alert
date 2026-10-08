require "PZAPI/ModOptions"
require "ISUI/ISUIElement"

local MOD_ID = "ALifeThreatAlert"
local DEFAULT_RANGE = 40
local DEFAULT_REAR_ZOMBIE_RANGE = 20
local DEFAULT_REAR_ZOMBIE_ANGLE = 180
local DEFAULT_ALARM_VOLUME = 150
local MAX_ALARM_VOLUME = 200
local MIN_RANGE = 5
local MAX_RANGE = 100
local MIN_REAR_ZOMBIE_ANGLE = 30
local MAX_REAR_ZOMBIE_ANGLE = 360
local REAR_ZOMBIE_ANGLE_STEP = 5
local ALERT_POSITION_FILE = "ViewpointThreatDetectorPosition.txt"
local ALARM_SOUND_IDS = {
    "ViewpointThreatDetectorRadarPing",
    "ViewpointThreatDetectorSiren",
    "ViewpointThreatDetectorHeartbeat",
    "ViewpointThreatDetectorSoftBeep",
}
local SCAN_INTERVAL = 5
local STANCES = { allied = true, friendly = true, neutral = true, careful = true, hostile = true }
local STANCE_PRIORITY = { "hostile", "careful", "neutral", "friendly", "allied" }
local STANCE_OPTION_KEYS = {
    hostile = "EnableHostileWarning",
    careful = "WarnCarefulNPCs",
    neutral = "WarnNeutralNPCs",
    friendly = "WarnFriendlyNPCs",
    allied = "WarnAlliedNPCs",
}
local STANCE_OPTION_DEFAULTS = {
    hostile = true,
    careful = true,
    neutral = false,
    friendly = false,
    allied = false,
}
local STANCE_LABELS = {
    allied = "Allied",
    friendly = "Friendly",
    neutral = "Neutral",
    careful = "Careful",
    hostile = "Hostile",
}
local STANCE_COLOURS = {
    allied = { 0.35, 0.72, 1 },
    friendly = { 0.35, 0.9, 0.35 },
    neutral = { 0.88, 0.88, 0.88 },
    careful = { 1, 0.62, 0.16 },
    hostile = { 1, 0.2, 0.16 },
}
local SHADOW_OFFSETS = { {-1, 0}, {1, 0}, {0, -1}, {0, 1} }
local DIRECTION_LABELS = {
    "AHEAD", "AHEAD-RIGHT", "RIGHT", "BEHIND-RIGHT",
    "BEHIND", "BEHIND-LEFT", "LEFT", "AHEAD-LEFT",
}
local directionTextureCache = {}
local typeIconTextureCache = {}
local neatPanelTextureCache = {}
local TYPE_ICON_TEXTURES = {
    alife = "media/ui/ThreatAlert/alife.png",
    zombie = "media/ui/Moodles/32/Mood_Zombified.png",
}
local NEAT_PANEL_HEADER_TEXTURE = "media/ui/NeatUI/DefaultPanel/MainTitle_BG.png"
local NEAT_PANEL_BODY_TEXTURE = "media/ui/NeatUI/DefaultPanel/MainPanelBG_FlatTop.png"

local modOptions
if PZAPI and PZAPI.ModOptions then
    modOptions = PZAPI.ModOptions:create(MOD_ID, "Viewpoint Threat Detector")
    modOptions:addTickBox("EnableHostileWarning", "Warn about nearby hostile NPCs", true)
    modOptions:addTickBox("WarnCarefulNPCs", "Warn about nearby careful NPCs", true)
    modOptions:addTickBox("WarnNeutralNPCs", "Warn about nearby neutral NPCs", false)
    modOptions:addTickBox("WarnFriendlyNPCs", "Warn about nearby friendly NPCs", false)
    modOptions:addTickBox("WarnAlliedNPCs", "Warn about nearby allied NPCs", false)
    modOptions:addSlider(
        "WarningDistance",
        "Maximum warning distance (tiles)",
        MIN_RANGE,
        MAX_RANGE,
        1,
        DEFAULT_RANGE,
        "Maximum horizontal distance at which A-Life NPCs trigger a warning."
    )
    modOptions:addTickBox("ShowDirectionArrow", "Show a direction arrow beside the warning", true)
    modOptions:addTickBox("ShowFirearmWarning", "Identify nearby NPCs carrying firearms", false)
    modOptions:addTickBox(
        "DisableInVehicle",
        "Disable alerts while inside a vehicle",
        true,
        "When enabled, threat detection, alerts, and alarm sounds are suppressed until you leave the vehicle."
    )
    modOptions:addTickBox("EnableRearZombieWarning", "Warn when zombies are behind you", true)
    modOptions:addTickBox(
        "RearZombieSameFloorOnly",
        "Detect rear zombies only on the same floor",
        true,
        "When enabled, zombies on other floors do not trigger rear warnings."
    )
    modOptions:addTickBox(
        "RearZombieRequireLineOfSight",
        "Require a clear path to rear zombies",
        true,
        "When enabled, walls and closed doors block rear zombie warnings."
    )
    modOptions:addTickBox(
        "IgnoreFallenZombies",
        "Ignore fallen zombies in rear warnings",
        false,
        "When enabled, zombies on the ground do not trigger the rear zombie warning."
    )
    modOptions:addTickBox(
        "UseBalancedRearZombieRange",
        "Use balanced rear zombie range (Keen Hearing-aware)",
        true,
        "Uses 3.5 tiles normally and 6.5 tiles with Keen Hearing. Disable this to use the custom distance below."
    )
    modOptions:addSlider(
        "RearZombieWarningDistance",
        "Custom rear zombie warning distance (tiles)",
        MIN_RANGE,
        MAX_RANGE,
        1,
        DEFAULT_REAR_ZOMBIE_RANGE,
        "Used only when the balanced rear zombie range is disabled."
    )
    modOptions:addSlider(
        "RearZombieWarningAngle",
        "Rear zombie detection angle (degrees)",
        MIN_REAR_ZOMBIE_ANGLE,
        MAX_REAR_ZOMBIE_ANGLE,
        REAR_ZOMBIE_ANGLE_STEP,
        DEFAULT_REAR_ZOMBIE_ANGLE,
        "Total angle centered behind you. 180 degrees detects the rear half; larger values widen the area."
    )
    modOptions:addTickBox(
        "EnableAlarmSound",
        "Play an alarm sound for new threats",
        true,
        "Enabled by default. Uses sounds bundled with Viewpoint Threat Detector."
    )
    modOptions:addSlider(
        "AlarmVolume",
        "Alarm volume (%)",
        0,
        MAX_ALARM_VOLUME,
        10,
        DEFAULT_ALARM_VOLUME,
        "Volume multiplier for this mod's alarm sounds. The default is louder than before."
    )
    modOptions:addTickBox(
        "ZombieAlarmOnly",
        "Play alarm only for zombie warnings",
        true,
        "When enabled, A-Life NPC alerts do not trigger alarm sounds."
    )
    local alarmSoundOption = modOptions:addComboBox(
        "AlarmSound",
        "Alarm sound",
        "Choose the alarm cue used when a new threat appears."
    )
    alarmSoundOption:addItem("Radar ping", false)
    alarmSoundOption:addItem("Siren", false)
    alarmSoundOption:addItem("Heartbeat", true)
    alarmSoundOption:addItem("Soft beep", false)
end

local alertPositionX
local alertPositionY
local alertDragHandle
local disableAlertsInVehicle = true
local playerInVehicle = false

local function loadAlertPosition()
    if not getFileReader then return end
    local ok, reader = pcall(getFileReader, ALERT_POSITION_FILE, false)
    if not ok or not reader then return end

    local readOk, x, y = pcall(function()
        local positionX = tonumber(reader:readLine())
        local positionY = tonumber(reader:readLine())
        reader:close()
        return positionX, positionY
    end)
    if not readOk then
        pcall(function() reader:close() end)
        return
    end
    if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
        alertPositionX = x
        alertPositionY = y
    end
end

local function saveAlertPosition()
    if not getFileWriter or not alertPositionX or not alertPositionY then return end
    local ok, writer = pcall(getFileWriter, ALERT_POSITION_FILE, true, false)
    if not ok or not writer then return end

    pcall(function() writer:write(string.format("%.6f\n%.6f\n", alertPositionX, alertPositionY)) end)
    pcall(function() writer:close() end)
end

loadAlertPosition()

local AlertDragHandle = ISUIElement:derive("ViewpointThreatDetectorAlertDragHandle")

function AlertDragHandle:new()
    return ISUIElement.new(self, 0, 0, 1, 1)
end

function AlertDragHandle:onMouseDown(x, y)
    self.dragging = true
    self.dragMoved = false
    return true
end

function AlertDragHandle:onMouseMove(dx, dy)
    if not self.dragging then return end
    local core = getCore()
    local screenWidth = core:getScreenWidth()
    local screenHeight = core:getScreenHeight()
    if screenWidth <= 0 or screenHeight <= 0 then return end

    local x = math.max(0, math.min(screenWidth - self.width, self.x + dx))
    local y = math.max(0, math.min(screenHeight - self.height, self.y + dy))
    self:setX(x)
    self:setY(y)
    alertPositionX = (x + self.width * 0.5) / screenWidth
    alertPositionY = y / screenHeight
    self.dragMoved = true
end

function AlertDragHandle:onMouseMoveOutside(dx, dy)
    self:onMouseMove(dx, dy)
end

function AlertDragHandle:onMouseUp(x, y)
    local wasDragging = self.dragging == true
    self.dragging = false
    if self.dragMoved then saveAlertPosition() end
    return wasDragging
end

function AlertDragHandle:onMouseUpOutside(x, y)
    self:onMouseUp(x, y)
end

local function ensureAlertDragHandle()
    if alertDragHandle then return alertDragHandle end
    local ok, handle = pcall(function()
        local instance = AlertDragHandle:new()
        instance:initialise()
        instance:addToUIManager()
        instance:setVisible(false)
        return instance
    end)
    if ok then alertDragHandle = handle end
    return alertDragHandle
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(ensureAlertDragHandle)
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

local function rearZombieWarningRange(player)
    if getOption("UseBalancedRearZombieRange", true) then
        local ok, hasKeenHearing = pcall(function()
            return player:hasTrait(CharacterTrait.KEEN_HEARING)
        end)
        if ok and hasKeenHearing then return 6.5 end
        return 3.5
    end

    local value = tonumber(getOption("RearZombieWarningDistance", DEFAULT_REAR_ZOMBIE_RANGE))
    if not value then return DEFAULT_REAR_ZOMBIE_RANGE end
    return math.max(MIN_RANGE, math.min(MAX_RANGE, math.floor(value + 0.5)))
end

local function rearZombieWarningAngle()
    local value = tonumber(getOption("RearZombieWarningAngle", DEFAULT_REAR_ZOMBIE_ANGLE))
    if not value then return DEFAULT_REAR_ZOMBIE_ANGLE end
    value = math.max(MIN_REAR_ZOMBIE_ANGLE, math.min(MAX_REAR_ZOMBIE_ANGLE, value))
    return math.floor(value / REAR_ZOMBIE_ANGLE_STEP + 0.5) * REAR_ZOMBIE_ANGLE_STEP
end

local function normalizeStance(value)
    if type(value) ~= "string" then return nil end
    value = string.lower(value)
    if value == "suspicious" then return "careful" end
    return STANCES[value] and value or nil
end

local function warningTitle(warning, uppercase)
    local title = (STANCE_LABELS[warning.stance] or "Hostile")
        .. " A-Life " .. (warning.count == 1 and "NPC nearby" or "NPCs nearby (" .. warning.count .. ")")
    return uppercase and string.upper(title) or title
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

local function carriesFirearm(project, shell)
    local relay = project.NPCHitRelay
    if type(relay) == "table" and type(relay.carriesFirearm) == "function" then
        local ok, result = pcall(relay.carriesFirearm, shell)
        if ok and result ~= nil then return result == true end
    end

    local ok, result = pcall(function()
        local inventory = shell:getInventory()
        local items = inventory and inventory:getItems() or nil
        for index = 0, (items and items:size() or 0) - 1 do
            local item = items:get(index)
            if item ~= nil and type(item.isAimedFirearm) == "function"
                    and item:isAimedFirearm() == true then
                return true
            end
        end
        return false
    end)
    return ok and result == true
end

local warnings = {}
local rearZombieWarning
local errorLogged = false

local function directionSector(dx, dy, forwardX, forwardY)
    local forward = dx * forwardX + dy * forwardY
    local right = dx * -forwardY + dy * forwardX
    local absForward, absRight = math.abs(forward), math.abs(right)
    local diagonalThreshold = 0.41421356

    if absRight <= absForward * diagonalThreshold then
        return forward >= 0 and 1 or 5
    end
    if absForward <= absRight * diagonalThreshold then
        return right >= 0 and 3 or 7
    end
    if forward >= 0 then return right >= 0 and 2 or 8 end
    return right >= 0 and 4 or 6
end

local function directionTextureFor(stance, sector)
    if not sector or not UIManager or not UIManager.DrawTexture then return nil end
    local arrowStance = stance == "hostile" and "hostile" or "careful"
    local texturePath = "media/ui/ThreatAlert/" .. arrowStance .. "_" .. tostring(sector) .. ".png"
    local texture = directionTextureCache[texturePath]
    if not texture and type(getTexture) == "function" then
        local ok, loaded = pcall(getTexture, texturePath)
        if ok and loaded then
            texture = loaded
            directionTextureCache[texturePath] = loaded
        end
    end
    return texture
end

local function typeIconTexture(kind)
    local texturePath = TYPE_ICON_TEXTURES[kind]
    if not texturePath or not UIManager or not UIManager.DrawTexture then return nil end

    local texture = typeIconTextureCache[texturePath]
    if texture ~= nil then return texture or nil end
    if type(getTexture) ~= "function" then
        typeIconTextureCache[texturePath] = false
        return nil
    end

    local ok, loaded = pcall(getTexture, texturePath)
    typeIconTextureCache[texturePath] = ok and loaded or false
    return typeIconTextureCache[texturePath] or nil
end

local function neatPanelTexture(path)
    local texture = neatPanelTextureCache[path]
    if texture ~= nil then return texture or nil end

    local ok, loaded = pcall(function()
        return NinePatchTexture.getSharedTexture(path)
    end)
    neatPanelTextureCache[path] = ok and loaded or false
    return neatPanelTextureCache[path] or nil
end

local function drawNeatAlertCard(headerTexture, bodyTexture, text, screenWidth, centerX, y,
        title, detail, extraDetail, stance, sector, showArrow, colour, iconKind)
    local arrow = showArrow and directionTextureFor(stance, sector) or nil
    local typeIcon = typeIconTexture(iconKind)
    if not arrow and sector then
        detail = detail .. " - " .. (DIRECTION_LABELS[sector] or DIRECTION_LABELS[1])
    end

    local padding = 10
    local smallHeight = text:getFontHeight(UIFont.Small)
    local mediumHeight = text:getFontHeight(UIFont.Medium)
    local titleWidth = text:MeasureStringX(UIFont.Medium, title)
    local detailWidth = text:MeasureStringX(UIFont.Small, detail)
    local extraDetailWidth = extraDetail and text:MeasureStringX(UIFont.Small, extraDetail) or 0
    local arrowSpace = arrow and 28 or 0
    local iconSize = typeIcon and (iconKind == "zombie" and 24 or 20) or 0
    local iconGap = typeIcon and 8 or 0
    local titleSpace = iconSize + iconGap
    local contentWidth = math.max(titleWidth + titleSpace, detailWidth, extraDetailWidth)
    local width = math.min(contentWidth + padding * 2 + arrowSpace, screenWidth - 24)
    local headerHeight = mediumHeight + 12
    local bodyHeight = padding + smallHeight + (extraDetail and smallHeight + 4 or 0) + 2
    local x = math.floor(math.max(12, math.min(screenWidth - width - 12, centerX - width * 0.5)))

    headerTexture:render(x, y, width, headerHeight, 0.08, 0.08, 0.08, 1)
    bodyTexture:render(x, y + headerHeight, width, bodyHeight, 0.15, 0.15, 0.15, 1)

    local titleY = y + math.floor((headerHeight - mediumHeight) * 0.5)
    text:DrawStringCentre(UIFont.Medium, x + padding + titleSpace + titleWidth * 0.5,
        titleY, title, colour[1], colour[2], colour[3], 1)
    if typeIcon then
        UIManager.DrawTexture(typeIcon, x + padding,
            y + math.floor((headerHeight - iconSize) * 0.5), iconSize, iconSize, 1)
    end
    if arrow then
        UIManager.DrawTexture(arrow, x + width - padding - 20,
            y + math.floor((headerHeight - 20) * 0.5), 20, 20, 1)
    end

    local detailY = y + headerHeight + math.floor(padding * 0.5)
    text:DrawStringCentre(UIFont.Small, x + padding + detailWidth * 0.5,
        detailY, detail, 0.9, 0.9, 0.9, 1)
    if extraDetail then
        local extraY = detailY + smallHeight + 4
        text:DrawStringCentre(UIFont.Small, x + padding + extraDetailWidth * 0.5,
            extraY, extraDetail, colour[1], colour[2], colour[3], 1)
    end

    return y + headerHeight + bodyHeight + 6, x, width, headerHeight + bodyHeight
end

local function mergeBounds(bounds, x, y, width, height)
    if not bounds then
        return { x = x, y = y, right = x + width, bottom = y + height }
    end
    bounds.x = math.min(bounds.x, x)
    bounds.y = math.min(bounds.y, y)
    bounds.right = math.max(bounds.right, x + width)
    bounds.bottom = math.max(bounds.bottom, y + height)
    return bounds
end

local function updateAlertDragHandle(bounds, screenWidth, screenHeight)
    if not bounds then
        if alertDragHandle and not alertDragHandle.dragging then
            alertDragHandle:setVisible(false)
        end
        return
    end

    local handle = ensureAlertDragHandle()
    if not handle then return end
    local width = bounds.right - bounds.x
    local height = bounds.bottom - bounds.y
    local x = math.max(0, math.min(math.max(0, screenWidth - width), bounds.x))
    local y = math.max(0, math.min(math.max(0, screenHeight - height), bounds.y))
    if x ~= bounds.x or y ~= bounds.y then
        alertPositionX = (x + width * 0.5) / math.max(screenWidth, 1)
        alertPositionY = y / math.max(screenHeight, 1)
    end
    handle:setX(x)
    handle:setY(y)
    handle:setWidth(math.max(1, width))
    handle:setHeight(math.max(1, height))
    handle:setVisible(true)
end

local function passesRearZombieVisibilityFilters(zombie, playerSquare, sameFloorOnly, requireLineOfSight)
    if not sameFloorOnly and not requireLineOfSight then return true end
    if playerSquare == nil then return false end

    local ok, passes = pcall(function()
        local zombieSquare = zombie:getCurrentSquare()
        if zombieSquare == nil then return false end
        if sameFloorOnly and zombieSquare:getZ() ~= playerSquare:getZ() then return false end
        if requireLineOfSight and zombieSquare:isBlockedTo(playerSquare) then return false end
        return true
    end)
    return ok and passes
end

local function scanNearbyThreats()
    warnings = {}
    rearZombieWarning = nil
    local stanceEnabled = {}
    local warnALifeNPCs = false
    for _, stance in ipairs(STANCE_PRIORITY) do
        local enabled = getOption(STANCE_OPTION_KEYS[stance], STANCE_OPTION_DEFAULTS[stance])
        stanceEnabled[stance] = enabled
        warnALifeNPCs = warnALifeNPCs or enabled
    end
    local warnRearZombies = getOption("EnableRearZombieWarning", true)
    if not warnALifeNPCs and not warnRearZombies then return end

    local project = ProjectALife
    if type(project) ~= "table" then
        project = nil
        warnALifeNPCs = false
    end
    if not warnALifeNPCs and not warnRearZombies then return end
    local player = getSpecificPlayer(0)
    if player == nil or player:isDead() then return end
    if disableAlertsInVehicle and playerInVehicle then return end
    local playerSquare = player:getCurrentSquare()
    local cell = getCell()
    local list = cell and cell:getZombieList() or nil
    if list == nil then return end

    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local forwardX, forwardY = player:getForwardDirectionX(), player:getForwardDirectionY()
    local forwardLength = math.sqrt(forwardX * forwardX + forwardY * forwardY)
    if forwardLength > 0.001 then
        forwardX, forwardY = forwardX / forwardLength, forwardY / forwardLength
    else
        forwardX, forwardY = 1, 0
    end
    local range = warnALifeNPCs and warningRange() or 0
    local rangeSquared = range * range
    local rearRange = warnRearZombies and rearZombieWarningRange(player) or 0
    local rearRangeSquared = rearRange * rearRange
    local rearAngleCos = math.cos(math.rad(rearZombieWarningAngle() * 0.5))
    local scanRangeSquared = math.max(rangeSquared, rearRangeSquared)
    local showDirectionArrow = getOption("ShowDirectionArrow", true)
    local showFirearmWarning = getOption("ShowFirearmWarning", false)
    local ignoreFallenZombies = getOption("IgnoreFallenZombies", false)
    local rearZombieSameFloorOnly = getOption("RearZombieSameFloorOnly", true)
    local rearZombieRequireLineOfSight = getOption("RearZombieRequireLineOfSight", true)
    local threatsByStance = {}
    for _, stance in ipairs(STANCE_PRIORITY) do
        threatsByStance[stance] = {
            count = 0,
            nearestDistance = rangeSquared,
            firearmCarriers = 0,
            nearestFirearmDistance = rangeSquared,
        }
    end
    local rearZombies = 0
    local nearestRearZombie = rearRangeSquared
    local nearestRearZombieDirection
    for index = 0, list:size() - 1 do
        local shell = list:get(index)
        if shell ~= nil and not shell:isDead() then
            local x, y, z = shell:getX(), shell:getY(), shell:getZ()
            local dx, dy = x - px, y - py
            local distanceSquared = dx * dx + dy * dy
            if math.abs(z - pz) <= 1 and distanceSquared <= scanRangeSquared then
                local rearCandidate = false
                if warnRearZombies and distanceSquared <= rearRangeSquared then
                    local fallen = false
                    if ignoreFallenZombies then
                        local ok, onFloor = pcall(function() return shell:isOnFloor() end)
                        fallen = ok and onFloor == true
                    end
                    if not fallen then
                        local forwardDot = dx * forwardX + dy * forwardY
                        rearCandidate = -forwardDot >= math.sqrt(distanceSquared) * rearAngleCos
                            and passesRearZombieVisibilityFilters(
                                shell,
                                playerSquare,
                                rearZombieSameFloorOnly,
                                rearZombieRequireLineOfSight
                            )
                    end
                end
                local alifeCandidate = warnALifeNPCs and distanceSquared <= rangeSquared
                local uid
                if project and (rearCandidate or alifeCandidate) then
                    uid = uidOf(project, shell)
                end

                if rearCandidate and uid == nil then
                    rearZombies = rearZombies + 1
                    if rearZombies == 1 or distanceSquared < nearestRearZombie then
                        nearestRearZombie = distanceSquared
                        nearestRearZombieDirection = directionSector(dx, dy, forwardX, forwardY)
                    end
                end

                if alifeCandidate and uid ~= nil then
                    local record = actorFor(project, uid)
                    if record then
                        local stance = stanceOf(project, record, player)
                        if stanceEnabled[stance] then
                            local threat = threatsByStance[stance]
                            if threat then
                                threat.count = threat.count + 1
                                if threat.nearestDirection == nil or distanceSquared < threat.nearestDistance then
                                    threat.nearestDistance = distanceSquared
                                    threat.nearestDirection = directionSector(dx, dy, forwardX, forwardY)
                                end
                                if showFirearmWarning and carriesFirearm(project, shell) then
                                    threat.firearmCarriers = threat.firearmCarriers + 1
                                    if threat.nearestFirearmDirection == nil
                                            or distanceSquared < threat.nearestFirearmDistance then
                                        threat.nearestFirearmDistance = distanceSquared
                                        threat.nearestFirearmDirection = directionSector(dx, dy, forwardX, forwardY)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    for _, stance in ipairs(STANCE_PRIORITY) do
        local threat = threatsByStance[stance]
        if threat.count > 0 then
            local usingFirearmDistance = threat.nearestFirearmDirection ~= nil
            warnings[#warnings + 1] = {
                stance = stance,
                count = threat.count,
                distance = math.sqrt(usingFirearmDistance
                    and threat.nearestFirearmDistance or threat.nearestDistance),
                direction = threat.nearestFirearmDirection or threat.nearestDirection,
                firearmCarriers = threat.firearmCarriers,
                showArrow = showDirectionArrow,
            }
        end
    end

    if rearZombies > 0 then
        rearZombieWarning = {
            count = rearZombies,
            distance = math.sqrt(nearestRearZombie),
            direction = nearestRearZombieDirection,
        }
    end
end

local lastAlarmSignature = ""
local activeAlarmSound

local function warningSignature()
    local parts = {}
    for _, warning in ipairs(warnings) do
        parts[#parts + 1] = warning.stance
    end
    if rearZombieWarning then parts[#parts + 1] = "rear-zombies" end
    return table.concat(parts, "|")
end

local function alarmSignature()
    if getOption("ZombieAlarmOnly", true) then
        return rearZombieWarning and "rear-zombies" or ""
    end
    return warningSignature()
end

local function playAlarmSound()
    local index = math.floor(tonumber(getOption("AlarmSound", 3)) or 3)
    local sound = ALARM_SOUND_IDS[index] or ALARM_SOUND_IDS[1]
    local volume = tonumber(getOption("AlarmVolume", DEFAULT_ALARM_VOLUME)) or DEFAULT_ALARM_VOLUME
    volume = math.max(0, math.min(MAX_ALARM_VOLUME, volume))
    if activeAlarmSound then
        pcall(function()
            getSoundManager():stopUISound(activeAlarmSound)
        end)
        activeAlarmSound = nil
    end

    local ok, soundInstance = pcall(function()
        return getSoundManager():playUISound(sound)
    end)
    if ok and soundInstance ~= nil and soundInstance ~= 0 then
        activeAlarmSound = soundInstance
        pcall(function()
            getSoundManager():getUIEmitter():setVolume(soundInstance, volume / 100)
        end)
    end
end

local function updateWarning()
    local ok, err = pcall(scanNearbyThreats)
    if not ok then
        warnings = {}
        rearZombieWarning = nil
        lastAlarmSignature = ""
        if not errorLogged then
            print("[Viewpoint Threat Detector] Detection failed: " .. tostring(err))
            errorLogged = true
        end
        return
    end

    local signature = alarmSignature()
    if signature ~= "" and signature ~= lastAlarmSignature
            and getOption("EnableAlarmSound", true) then
        playAlarmSound()
    end
    lastAlarmSignature = signature
end

local function drawWarning()
    if disableAlertsInVehicle and playerInVehicle then
        warnings = {}
        rearZombieWarning = nil
        lastAlarmSignature = ""
        updateAlertDragHandle(nil, 0, 0)
        return
    end
    if #warnings == 0 and rearZombieWarning == nil then
        updateAlertDragHandle(nil, 0, 0)
        return
    end
    local ok, err = pcall(function()
        local core = getCore()
        local screenWidth = core:getScreenWidth()
        local screenHeight = core:getScreenHeight()
        local text = getTextManager()
        local centerX = (alertPositionX or 0.5) * screenWidth
        local startY = alertPositionY and alertPositionY * screenHeight or 24

        local headerTexture = neatPanelTexture(NEAT_PANEL_HEADER_TEXTURE)
        local bodyTexture = neatPanelTexture(NEAT_PANEL_BODY_TEXTURE)
        if headerTexture and bodyTexture then
            local neatBounds
            local okNeat = pcall(function()
                local y = startY
                for _, currentWarning in ipairs(warnings) do
                    local extraDetail
                    if currentWarning.firearmCarriers and currentWarning.firearmCarriers > 0 then
                        extraDetail = tostring(currentWarning.firearmCarriers)
                            .. (currentWarning.firearmCarriers == 1 and " firearm carrier nearby"
                                or " firearm carriers nearby")
                    end
                    local cardY = y
                    local nextY, x, width, height = drawNeatAlertCard(
                        headerTexture, bodyTexture, text, screenWidth, centerX, y,
                        warningTitle(currentWarning, false),
                        "Distance: " .. tostring(math.floor(currentWarning.distance + 0.5)) .. " tiles",
                        extraDetail, currentWarning.stance, currentWarning.direction,
                        currentWarning.showArrow, STANCE_COLOURS[currentWarning.stance], "alife"
                    )
                    neatBounds = mergeBounds(neatBounds, x, cardY, width, height)
                    y = nextY
                end

                if rearZombieWarning then
                    local title = "Zombies out of sight (" .. tostring(rearZombieWarning.count) .. ")"
                    local _, x, width, height = drawNeatAlertCard(
                        headerTexture, bodyTexture, text, screenWidth, centerX, y,
                        title,
                        "Nearest zombie: " .. tostring(math.floor(rearZombieWarning.distance + 0.5)) .. " tiles",
                        nil, "hostile", rearZombieWarning.direction, true,
                        { 1, 0.2, 0.16 }, "zombie"
                    )
                    neatBounds = mergeBounds(neatBounds, x, y, width, height)
                end
            end)
            if okNeat then
                updateAlertDragHandle(neatBounds, screenWidth, screenHeight)
                return
            end
        end

        local bounds
        local nextWarningY = startY

        local function drawCenteredMessage(font, message, y, colour)
            local width = text:MeasureStringX(font, message)
            local height = text:getFontHeight(font)
            local left = math.max(12, math.min(screenWidth - width - 12, centerX - width * 0.5))
            local messageCenterX = left + width * 0.5
            for _, offset in ipairs(SHADOW_OFFSETS) do
                text:DrawStringCentre(font, messageCenterX + offset[1], y + offset[2], message, 0, 0, 0, 1)
            end
            text:DrawStringCentre(font, messageCenterX, y, message, colour[1], colour[2], colour[3], 1)
            bounds = mergeBounds(bounds, left, y, width, height)
        end

        for _, currentWarning in ipairs(warnings) do
            local message = warningTitle(currentWarning, true)
            local colour = STANCE_COLOURS[currentWarning.stance]
            local sector = currentWarning.direction
            local texture = currentWarning.showArrow and directionTextureFor(currentWarning.stance, sector) or nil
            local distanceText = tostring(math.floor(currentWarning.distance + 0.5)) .. " tiles"
            local arrowSize = 20
            local arrowGap = 8
            local icon = typeIconTexture("alife")
            local iconSize = icon and 20 or 0
            local iconGap = icon and 8 or 0
            local messageY = nextWarningY
            local arrowY = messageY + 6
            if not texture then
                local directionLabel = DIRECTION_LABELS[sector] or DIRECTION_LABELS[1]
                message = message .. "  " .. distanceText .. " - " .. directionLabel
            else
                message = message .. "  " .. distanceText
            end
            local messageWidth = text:MeasureStringX(UIFont.Large, message)

            local groupWidth = iconSize + iconGap + messageWidth
                + (texture and arrowGap + arrowSize or 0)
            local groupLeft = math.max(12, math.min(screenWidth - groupWidth - 12, centerX - groupWidth * 0.5))
            local messageLeft = groupLeft + iconSize + iconGap
            local messageX = messageLeft + messageWidth * 0.5
            local lineHeight = text:getFontHeight(UIFont.Large)
            local arrowHeight = texture and 6 + arrowSize or 0
            bounds = mergeBounds(bounds, groupLeft, messageY, groupWidth, math.max(lineHeight, arrowHeight))
            if icon then
                UIManager.DrawTexture(icon, groupLeft,
                    messageY + math.floor((lineHeight - iconSize) * 0.5),
                    iconSize, iconSize, 1)
            end
            for _, offset in ipairs(SHADOW_OFFSETS) do
                text:DrawStringCentre(UIFont.Large, messageX + offset[1], messageY + offset[2], message, 0, 0, 0, 1)
            end
            text:DrawStringCentre(UIFont.Large, messageX, messageY, message, colour[1], colour[2], colour[3], 1)

            if texture then
                UIManager.DrawTexture(texture, messageLeft + messageWidth + arrowGap,
                    arrowY, arrowSize, arrowSize, 1)
            end

            nextWarningY = messageY + lineHeight + 4
            if currentWarning.firearmCarriers and currentWarning.firearmCarriers > 0 then
                local firearmMessage = currentWarning.firearmCarriers == 1
                    and "1 FIREARM CARRIER NEARBY"
                    or tostring(currentWarning.firearmCarriers) .. " FIREARM CARRIERS NEARBY"
                drawCenteredMessage(UIFont.Small, firearmMessage, nextWarningY, colour)
                nextWarningY = nextWarningY + text:getFontHeight(UIFont.Small) + 4
            end
        end

        if rearZombieWarning then
            local message = "ZOMBIES OUT OF SIGHT (" .. tostring(rearZombieWarning.count) .. ") - "
                .. tostring(math.floor(rearZombieWarning.distance + 0.5)) .. " TILES"
            local y = nextWarningY
            local colour = { 1, 0.2, 0.08 }
            local sector = rearZombieWarning.direction
            local texture = directionTextureFor("hostile", sector)
            local icon = typeIconTexture("zombie")
            local messageWidth = text:MeasureStringX(UIFont.Large, message)
            if not texture then
                message = message .. " - " .. (DIRECTION_LABELS[sector] or DIRECTION_LABELS[1])
                messageWidth = text:MeasureStringX(UIFont.Large, message)
            end

            local arrowSize = 20
            local arrowGap = 8
            local iconSize = icon and 24 or 0
            local iconGap = icon and 8 or 0
            local groupWidth = iconSize + iconGap + messageWidth
                + (texture and arrowGap + arrowSize or 0)
            local groupLeft = math.max(12, math.min(screenWidth - groupWidth - 12, centerX - groupWidth * 0.5))
            local messageLeft = groupLeft + iconSize + iconGap
            local messageX = messageLeft + messageWidth * 0.5
            local lineHeight = text:getFontHeight(UIFont.Large)
            local arrowHeight = texture and 6 + arrowSize or 0
            bounds = mergeBounds(bounds, groupLeft, y, groupWidth, math.max(lineHeight, arrowHeight))
            if icon then
                UIManager.DrawTexture(icon, groupLeft,
                    y + math.floor((lineHeight - iconSize) * 0.5),
                    iconSize, iconSize, 1)
            end
            for _, offset in ipairs(SHADOW_OFFSETS) do
                text:DrawStringCentre(UIFont.Large, messageX + offset[1], y + offset[2], message, 0, 0, 0, 1)
            end
            text:DrawStringCentre(UIFont.Large, messageX, y, message, colour[1], colour[2], colour[3], 1)
            if texture then
                UIManager.DrawTexture(texture, messageLeft + messageWidth + arrowGap,
                    y + 6, arrowSize, arrowSize, 1)
            end
        end

        updateAlertDragHandle(bounds, screenWidth, screenHeight)
    end)
    if not ok and not errorLogged then
        print("[Viewpoint Threat Detector] Warning display failed: " .. tostring(err))
        errorLogged = true
    end
end

local ticks = 0
if Events and Events.OnTick then
    Events.OnTick.Add(function()
        ticks = ticks + 1
        disableAlertsInVehicle = getOption("DisableInVehicle", true)
        playerInVehicle = false
        if disableAlertsInVehicle then
            local player = getSpecificPlayer(0)
            if player then
                local ok, vehicle = pcall(function() return player:getVehicle() end)
                playerInVehicle = ok and vehicle ~= nil
            end
        end
        if ticks % SCAN_INTERVAL == 0 then updateWarning() end
    end)
end

if Events and Events.OnPreUIDraw then
    Events.OnPreUIDraw.Add(drawWarning)
end
