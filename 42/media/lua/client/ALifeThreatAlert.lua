require "PZAPI/ModOptions"

local MOD_ID = "ALifeThreatAlert"
local DEFAULT_RANGE = 40
local DEFAULT_REAR_ZOMBIE_RANGE = 20
local DEFAULT_REAR_ZOMBIE_ANGLE = 180
local MIN_RANGE = 5
local MAX_RANGE = 100
local MIN_REAR_ZOMBIE_ANGLE = 30
local MAX_REAR_ZOMBIE_ANGLE = 360
local REAR_ZOMBIE_ANGLE_STEP = 5
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
    modOptions = PZAPI.ModOptions:create(MOD_ID, "A-Life Threat Alert")
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
    modOptions:addTickBox("EnableRearZombieWarning", "Warn when zombies are behind you", true)
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

local function drawNeatAlertCard(headerTexture, bodyTexture, text, screenWidth, y,
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
    local x = math.floor((screenWidth - width) * 0.5)

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

    return y + headerHeight + bodyHeight + 6
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
                    local forwardDot = dx * forwardX + dy * forwardY
                    rearCandidate = -forwardDot >= math.sqrt(distanceSquared) * rearAngleCos
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

local function updateWarning()
    local ok, err = pcall(scanNearbyThreats)
    if not ok then
        warnings = {}
        rearZombieWarning = nil
        if not errorLogged then
            print("[A-Life Threat Alert] Detection failed: " .. tostring(err))
            errorLogged = true
        end
    end
end

local function drawWarning()
    if #warnings == 0 and rearZombieWarning == nil then return end
    local ok, err = pcall(function()
        local core = getCore()
        local screenWidth = core:getScreenWidth()
        local text = getTextManager()

        local headerTexture = neatPanelTexture(NEAT_PANEL_HEADER_TEXTURE)
        local bodyTexture = neatPanelTexture(NEAT_PANEL_BODY_TEXTURE)
        if headerTexture and bodyTexture then
            local okNeat = pcall(function()
                local y = 24
                for _, currentWarning in ipairs(warnings) do
                    local extraDetail
                    if currentWarning.firearmCarriers and currentWarning.firearmCarriers > 0 then
                        extraDetail = tostring(currentWarning.firearmCarriers)
                            .. (currentWarning.firearmCarriers == 1 and " firearm carrier nearby"
                                or " firearm carriers nearby")
                    end
                    y = drawNeatAlertCard(
                        headerTexture, bodyTexture, text, screenWidth, y,
                        warningTitle(currentWarning, false),
                        "Distance: " .. tostring(math.floor(currentWarning.distance + 0.5)) .. " tiles",
                        extraDetail, currentWarning.stance, currentWarning.direction,
                        currentWarning.showArrow, STANCE_COLOURS[currentWarning.stance], "alife"
                    )
                end

                if rearZombieWarning then
                    local title = "Zombies out of sight (" .. tostring(rearZombieWarning.count) .. ")"
                    drawNeatAlertCard(
                        headerTexture, bodyTexture, text, screenWidth, y,
                        title,
                        "Nearest zombie: " .. tostring(math.floor(rearZombieWarning.distance + 0.5)) .. " tiles",
                        nil, "hostile", rearZombieWarning.direction, true,
                        { 1, 0.2, 0.16 }, "zombie"
                    )
                end
            end)
            if okNeat then return end
        end

        local nextWarningY = 24

        local function drawCenteredMessage(font, message, y, colour)
            for _, offset in ipairs(SHADOW_OFFSETS) do
                text:DrawStringCentre(font, screenWidth * 0.5 + offset[1], y + offset[2], message, 0, 0, 0, 1)
            end
            text:DrawStringCentre(font, screenWidth * 0.5, y, message, colour[1], colour[2], colour[3], 1)
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
            local groupLeft = (screenWidth - groupWidth) * 0.5
            local messageLeft = groupLeft + iconSize + iconGap
            local messageX = messageLeft + messageWidth * 0.5
            if icon then
                UIManager.DrawTexture(icon, groupLeft,
                    messageY + math.floor((text:getFontHeight(UIFont.Large) - iconSize) * 0.5),
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

            nextWarningY = messageY + text:getFontHeight(UIFont.Large) + 4
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
            local groupLeft = (screenWidth - groupWidth) * 0.5
            local messageLeft = groupLeft + iconSize + iconGap
            local messageX = messageLeft + messageWidth * 0.5
            if icon then
                UIManager.DrawTexture(icon, groupLeft,
                    y + math.floor((text:getFontHeight(UIFont.Large) - iconSize) * 0.5),
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
