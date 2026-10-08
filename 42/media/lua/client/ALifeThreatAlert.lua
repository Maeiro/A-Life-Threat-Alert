require "PZAPI/ModOptions"
require "ISUI/ISUIElement"

local MOD_ID = "ALifeThreatAlert"
local DEFAULT_RANGE = 40
local DEFAULT_CLOSE_HOSTILE_RANGE = 10
local DEFAULT_ALARM_SOUND = 3
local DEFAULT_CLOSE_HOSTILE_ALARM_SOUND = 2
local DEFAULT_SPRINTER_ALARM_SOUND = 2
local DEFAULT_REAR_ZOMBIE_RANGE = 20
local DEFAULT_SPRINTER_RANGE = 20
local DEFAULT_REAR_ZOMBIE_ANGLE = 180
local DEFAULT_ALARM_VOLUME = 150
local MAX_ALARM_VOLUME = 200
local MIN_RANGE = 5
local MAX_RANGE = 100
local MIN_CLOSE_HOSTILE_RANGE = 1
local MIN_REAR_ZOMBIE_ANGLE = 30
local MAX_REAR_ZOMBIE_ANGLE = 360
local REAR_ZOMBIE_ANGLE_STEP = 5
local ALERT_POSITION_FILE = "ViewpointThreatDetectorPosition.txt"
local ZOMBIE_ALERT_POSITION_FILE = "ViewpointThreatDetectorZombiePosition.txt"
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
    modOptions:addTitle("A-Life NPC Threats")
    modOptions:addTickBox("EnableHostileWarning", "Warn about nearby hostile NPCs", true)
    modOptions:addTickBox("WarnCarefulNPCs", "Warn about nearby careful NPCs", true)
    modOptions:addTickBox("WarnNeutralNPCs", "Warn about nearby neutral NPCs", false)
    modOptions:addTickBox("WarnFriendlyNPCs", "Warn about nearby friendly NPCs", false)
    modOptions:addTickBox("WarnAlliedNPCs", "Warn about nearby allied NPCs", false)
    modOptions:addTickBox("ShowFirearmWarning", "Identify nearby NPCs carrying firearms", false)
    modOptions:addSlider(
        "WarningDistance",
        "Maximum warning distance (tiles)",
        MIN_RANGE,
        MAX_RANGE,
        1,
        DEFAULT_RANGE,
        "Maximum horizontal distance at which A-Life NPCs trigger a warning."
    )
    modOptions:addTickBox(
        "EnableCloseHostileAlarm",
        "Play a separate alarm for close Hostile A-Life NPCs",
        true,
        "Triggers independently of the regular NPC warning when a Hostile NPC enters the configured distance."
    )
    modOptions:addSlider(
        "CloseHostileAlarmDistance",
        "Close Hostile A-Life alarm distance (tiles)",
        MIN_CLOSE_HOSTILE_RANGE,
        MAX_RANGE,
        1,
        DEFAULT_CLOSE_HOSTILE_RANGE,
        "Distance at which the separate Hostile A-Life alarm is triggered."
    )

    modOptions:addTitle("Rear Zombie Threats")
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

    modOptions:addTitle("Sprinter Threats")
    modOptions:addTickBox(
        "EnableSprinterWarning",
        "Warn about nearby sprinters",
        true,
        "Displays a separate warning and can play its own alarm when a sprinter enters range."
    )
    modOptions:addSlider(
        "SprinterWarningDistance",
        "Sprinter warning distance (tiles)",
        MIN_CLOSE_HOSTILE_RANGE,
        MAX_RANGE,
        1,
        DEFAULT_SPRINTER_RANGE,
        "Maximum distance for the sprinter warning and its dedicated alarm."
    )
    modOptions:addTickBox(
        "SprinterSameFloorOnly",
        "Detect sprinters only on the same floor",
        true,
        "When enabled, sprinters on other floors do not trigger this warning."
    )
    modOptions:addTickBox(
        "SprinterRequireLineOfSight",
        "Require a clear path to sprinters",
        true,
        "When enabled, walls and closed doors block sprinter warnings."
    )
    modOptions:addTickBox(
        "SprinterIgnoreFallen",
        "Ignore fallen sprinters",
        true,
        "When enabled, sprinters on the ground do not trigger the separate warning."
    )

    modOptions:addTitle("Alert Display")
    modOptions:addTickBox("ShowDirectionArrow", "Show a direction arrow beside the warning", true)
    modOptions:addTickBox(
        "MinimalAlertUI",
        "Use minimal alert UI",
        false,
        "Uses compact text and icons without the NeatUI alert cards."
    )
    modOptions:addTickBox(
        "SeparateAlertPositions",
        "Separate A-Life and zombie alert positions",
        false,
        "When enabled, drag A-Life and zombie alerts independently to place them anywhere on the screen."
    )
    modOptions:addTickBox(
        "EnableDragDiagnostics",
        "Log alert drag diagnostics",
        false,
        "Temporarily logs alert hitbox positions and mouse drag events to console.txt. Turn off after testing."
    )
    modOptions:addTickBox(
        "DisableInVehicle",
        "Disable alerts while inside a vehicle",
        true,
        "When enabled, threat detection, alerts, and alarm sounds are suppressed until you leave the vehicle."
    )

    modOptions:addTitle("Alarm Sounds")
    modOptions:addTickBox(
        "EnableAlarmSound",
        "Play an alarm sound for new threats",
        true,
        "Master switch for all alarm sounds, including the separate close Hostile A-Life and sprinter alarms."
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
        "Play the regular alarm only for zombie warnings",
        true,
        "When enabled, regular A-Life warnings do not trigger the regular alarm. Separate close Hostile A-Life and sprinter alarms are configured independently."
    )
    modOptions:addTickBox(
        "EnableSprinterAlarm",
        "Play a separate alarm for sprinters",
        true,
        "Uses the alarm sound and volume configured below when a sprinter enters range."
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
    local closeHostileAlarmSoundOption = modOptions:addComboBox(
        "CloseHostileAlarmSound",
        "Close Hostile A-Life alarm sound",
        "Choose a distinct sound cue for Hostile A-Life NPCs that enter the close range."
    )
    closeHostileAlarmSoundOption:addItem("Radar ping", false)
    closeHostileAlarmSoundOption:addItem("Siren", true)
    closeHostileAlarmSoundOption:addItem("Heartbeat", false)
    closeHostileAlarmSoundOption:addItem("Soft beep", false)
    local sprinterAlarmSoundOption = modOptions:addComboBox(
        "SprinterAlarmSound",
        "Sprinter alarm sound",
        "Choose a distinct sound cue for sprinters entering range."
    )
    sprinterAlarmSoundOption:addItem("Radar ping", false)
    sprinterAlarmSoundOption:addItem("Siren", true)
    sprinterAlarmSoundOption:addItem("Heartbeat", false)
    sprinterAlarmSoundOption:addItem("Soft beep", false)
    modOptions:addSlider(
        "CloseHostileAlarmVolume",
        "Close Hostile A-Life alarm volume (%)",
        0,
        MAX_ALARM_VOLUME,
        10,
        DEFAULT_ALARM_VOLUME,
        "Volume multiplier for the separate close Hostile A-Life alarm."
    )
    modOptions:addSlider(
        "SprinterAlarmVolume",
        "Sprinter alarm volume (%)",
        0,
        MAX_ALARM_VOLUME,
        10,
        DEFAULT_ALARM_VOLUME,
        "Volume multiplier for the separate sprinter alarm."
    )
end

local alertPositionX
local alertPositionY
local alertDragHandle
local zombieAlertPositionX
local zombieAlertPositionY
local zombieAlertDragHandle
local disableAlertsInVehicle = true
local playerInVehicle = false
local dragDiagnosticsEnabled = false
local activeGlobalDragHandle
local globalDragMouseX
local globalDragMouseY
local warnings = {}
local rearZombieWarning
local sprinterWarning

local function logDragDiagnostic(message)
    if dragDiagnosticsEnabled then
        print("[Viewpoint Threat Detector][Drag] " .. message)
    end
end

local function loadPosition(fileName)
    if not getFileReader then return end
    local ok, reader = pcall(getFileReader, fileName, false)
    if not ok or not reader then return end

    local readOk, x, y = pcall(function()
        local positionX = tonumber(reader:readLine())
        local positionY = tonumber(reader:readLine())
        reader:close()
        return positionX, positionY
    end)
    if not readOk then
        pcall(function() reader:close() end)
        return nil, nil
    end
    if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
        return x, y
    end
    return nil, nil
end

local function savePosition(fileName, x, y)
    if not getFileWriter or not x or not y then return end
    local ok, writer = pcall(getFileWriter, fileName, true, false)
    if not ok or not writer then return end

    pcall(function() writer:write(string.format("%.6f\n%.6f\n", x, y)) end)
    pcall(function() writer:close() end)
end

alertPositionX, alertPositionY = loadPosition(ALERT_POSITION_FILE)
zombieAlertPositionX, zombieAlertPositionY = loadPosition(ZOMBIE_ALERT_POSITION_FILE)

local function saveAlertPosition(kind)
    if kind == "zombie" then
        savePosition(ZOMBIE_ALERT_POSITION_FILE, zombieAlertPositionX, zombieAlertPositionY)
    else
        savePosition(ALERT_POSITION_FILE, alertPositionX, alertPositionY)
    end
end

local AlertDragHandle = ISUIElement:derive("ViewpointThreatDetectorAlertDragHandle")

function AlertDragHandle:new()
    return ISUIElement.new(self, 0, 0, 1, 1)
end

local function moveAlertDragHandle(handle, dx, dy, source)
    if not handle.dragging then return end
    local core = getCore()
    local screenWidth = core:getScreenWidth()
    local screenHeight = core:getScreenHeight()
    if screenWidth <= 0 or screenHeight <= 0 then return end

    local x = math.max(0, math.min(screenWidth - handle.width, handle.x + dx))
    local y = math.max(0, math.min(screenHeight - handle.height, handle.y + dy))
    handle:setX(x)
    handle:setY(y)
    handle:bringToTop()
    if handle.positionKind == "zombie" then
        zombieAlertPositionX = (x + handle.width * 0.5) / screenWidth
        zombieAlertPositionY = y / screenHeight
    else
        alertPositionX = (x + handle.width * 0.5) / screenWidth
        alertPositionY = y / screenHeight
    end
    handle.dragMoved = true
    handle.dragMoveLogCount = (handle.dragMoveLogCount or 0) + 1
    if handle.dragMoveLogCount == 1 or handle.dragMoveLogCount % 10 == 0 then
        local captureOk, captured = pcall(function() return handle:getIsCaptured() end)
        logDragDiagnostic(string.format(
            "handle-mouse-move source=%s kind=%s delta=(%.1f,%.1f) position=(%.1f,%.1f) captured=%s",
            source, tostring(handle.positionKind), dx, dy, x, y,
            tostring(captureOk and captured)
        ))
    end
end

local function finishAlertDrag(handle, source)
    local wasDragging = handle.dragging == true
    if not wasDragging then return false end
    local moved = handle.dragMoved == true
    handle.dragging = false
    handle.manualDrag = false
    pcall(function() handle:setCapture(false) end)
    if wasDragging and moved then saveAlertPosition(handle.positionKind) end
    if activeGlobalDragHandle == handle then activeGlobalDragHandle = nil end
    logDragDiagnostic(string.format(
        "handle-mouse-up source=%s kind=%s moved=%s position=(%.1f,%.1f) savedPosition=(%.4f,%.4f)",
        source, tostring(handle.positionKind), tostring(moved), handle.x, handle.y,
        handle.positionKind == "zombie" and (zombieAlertPositionX or 0) or (alertPositionX or 0),
        handle.positionKind == "zombie" and (zombieAlertPositionY or 0) or (alertPositionY or 0)
    ))
    handle.dragMoved = false
    return wasDragging
end

function AlertDragHandle:onMouseDown(x, y)
    if activeGlobalDragHandle == self then activeGlobalDragHandle = nil end
    self.manualDrag = false
    self.dragging = true
    self.dragMoved = false
    self.dragMoveLogCount = 0
    self.dragOutsideLogged = false
    self:setCapture(true)
    self:bringToTop()
    local captureOk, captured = pcall(function() return self:getIsCaptured() end)
    logDragDiagnostic(string.format(
        "handle-mouse-down kind=%s local=(%.1f,%.1f) bounds=(%.1f,%.1f %.1fx%.1f) captured=%s",
        tostring(self.positionKind), x, y, self.x, self.y, self.width, self.height,
        tostring(captureOk and captured)
    ))
    return true
end

function AlertDragHandle:onMouseMove(dx, dy)
    if self.manualDrag then return end
    moveAlertDragHandle(self, dx, dy, "ui")
end

function AlertDragHandle:onMouseMoveOutside(dx, dy)
    if not self.dragOutsideLogged then
        logDragDiagnostic("handle-mouse-move-outside kind=" .. tostring(self.positionKind))
        self.dragOutsideLogged = true
    end
    self:onMouseMove(dx, dy)
end

function AlertDragHandle:onMouseUp(x, y)
    if self.manualDrag then return false end
    return finishAlertDrag(self, "ui")
end

function AlertDragHandle:onMouseUpOutside(x, y)
    self:onMouseUp(x, y)
end

local function ensureAlertDragHandle(kind)
    kind = kind == "zombie" and "zombie" or "alife"
    local existingHandle
    if kind == "zombie" then
        existingHandle = zombieAlertDragHandle
    else
        existingHandle = alertDragHandle
    end
    if existingHandle then return existingHandle end
    local ok, handle = pcall(function()
        local instance = AlertDragHandle:new()
        instance.positionKind = kind
        instance:initialise()
        instance:addToUIManager()
        instance:setWantMouseEvents(true)
        instance:setAlwaysOnTop(true)
        instance:setVisible(false)
        return instance
    end)
    if ok then
        if kind == "zombie" then
            zombieAlertDragHandle = handle
        else
            alertDragHandle = handle
        end
        logDragDiagnostic("handle-created kind=" .. kind)
    end
    return handle
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(function()
        ensureAlertDragHandle("alife")
        ensureAlertDragHandle("zombie")
    end)
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

if Events and Events.OnMouseDown then
    Events.OnMouseDown.Add(function()
        local mouseX = getMouseX and getMouseX() or -1
        local mouseY = getMouseY and getMouseY() or -1
        local function describeHandle(kind, handle)
            if not handle then return kind .. "=missing" end
            local inside = mouseX >= handle.x and mouseX < handle.x + handle.width
                and mouseY >= handle.y and mouseY < handle.y + handle.height
            local capturedOk, captured = pcall(function() return handle:getIsCaptured() end)
            local visibleOk, visible = pcall(function() return handle:isVisible() end)
            local mouseEventsOk, mouseEvents = pcall(function() return handle:isWantMouseEvents() end)
            return string.format(
                "%s=(alertVisible:%s uiVisible:%s mouseEvents:%s inside:%s captured:%s bounds:%.1f,%.1f %.1fx%.1f)",
                kind, tostring(handle.alertVisible == true), tostring(visibleOk and visible),
                tostring(mouseEventsOk and mouseEvents),
                tostring(inside), tostring(capturedOk and captured),
                handle.x, handle.y, handle.width, handle.height
            )
        end
        if dragDiagnosticsEnabled then
            logDragDiagnostic(string.format(
                "global-mouse-down cursor=(%.1f,%.1f) leftDown=%s alifeWarnings=%d rearZombie=%s sprinters=%s %s %s",
                mouseX, mouseY,
                tostring(isMouseButtonDown and isMouseButtonDown(0) or false),
                #warnings, tostring(rearZombieWarning ~= nil), tostring(sprinterWarning ~= nil),
                describeHandle("alife", alertDragHandle),
                describeHandle("zombie", zombieAlertDragHandle)
            ))
        end

        if not isMouseButtonDown or not isMouseButtonDown(0) then return end
        local candidates = {}
        if zombieAlertDragHandle then candidates[#candidates + 1] = zombieAlertDragHandle end
        if alertDragHandle then candidates[#candidates + 1] = alertDragHandle end
        for _, handle in ipairs(candidates) do
            if handle and not handle.dragging then
                local inside = mouseX >= handle.x and mouseX < handle.x + handle.width
                    and mouseY >= handle.y and mouseY < handle.y + handle.height
                local hasActiveAlert
                if handle.positionKind == "zombie" then
                    hasActiveAlert = rearZombieWarning ~= nil or sprinterWarning ~= nil
                else
                    hasActiveAlert = #warnings > 0
                end
                logDragDiagnostic(string.format(
                    "global-drag-candidate kind=%s inside=%s active=%s bounds=(%.1f,%.1f %.1fx%.1f)",
                    tostring(handle.positionKind), tostring(inside), tostring(hasActiveAlert),
                    handle.x, handle.y, handle.width, handle.height
                ))
                if hasActiveAlert and inside then
                    activeGlobalDragHandle = handle
                    globalDragMouseX = mouseX
                    globalDragMouseY = mouseY
                    handle.dragging = true
                    handle.manualDrag = true
                    handle.dragMoved = false
                    handle.dragMoveLogCount = 0
                    handle.dragOutsideLogged = false
                    logDragDiagnostic("global-drag-start kind=" .. tostring(handle.positionKind))
                    return
                end
            end
        end
    end)
end

local function updateGlobalAlertDrag()
    local handle = activeGlobalDragHandle
    if not handle then return end
    if not handle.manualDrag then
        activeGlobalDragHandle = nil
        return
    end
    if not isMouseButtonDown or not isMouseButtonDown(0) then
        finishAlertDrag(handle, "global")
        return
    end

    local mouseX = getMouseX and getMouseX()
    local mouseY = getMouseY and getMouseY()
    if not mouseX or not mouseY then return end
    local deltaX = mouseX - globalDragMouseX
    local deltaY = mouseY - globalDragMouseY
    globalDragMouseX = mouseX
    globalDragMouseY = mouseY
    if deltaX ~= 0 or deltaY ~= 0 then
        moveAlertDragHandle(handle, deltaX, deltaY, "global")
    end
end

local function warningRange()
    local value = tonumber(getOption("WarningDistance", DEFAULT_RANGE))
    if not value then return DEFAULT_RANGE end
    return math.max(MIN_RANGE, math.min(MAX_RANGE, math.floor(value + 0.5)))
end

local function closeHostileAlarmRange()
    local value = tonumber(getOption("CloseHostileAlarmDistance", DEFAULT_CLOSE_HOSTILE_RANGE))
    if not value then return DEFAULT_CLOSE_HOSTILE_RANGE end
    return math.max(MIN_CLOSE_HOSTILE_RANGE, math.min(MAX_RANGE, math.floor(value + 0.5)))
end

local function sprinterWarningRange()
    local value = tonumber(getOption("SprinterWarningDistance", DEFAULT_SPRINTER_RANGE))
    if not value then return DEFAULT_SPRINTER_RANGE end
    return math.max(MIN_CLOSE_HOSTILE_RANGE, math.min(MAX_RANGE, math.floor(value + 0.5)))
end

local function isSprinter(zombie)
    local ok, speedType = pcall(function() return zombie:getSpeedType() end)
    if not ok then return false end
    local constantOk, sprinterType = pcall(function() return IsoZombie.SPEED_SPRINTER end)
    return constantOk and sprinterType ~= nil and speedType == sprinterType
end

local function zombieAlertId(zombie)
    local ok, id = pcall(function() return zombie:getID() end)
    if ok and id ~= nil then return tostring(id) end
    ok, id = pcall(function() return zombie:getOnlineID() end)
    if ok and id ~= nil then return tostring(id) end
    return tostring(zombie)
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

local sprinterZombieIDs = {}
local closeHostileNPCs = {}
local lastCloseHostileNPCs = {}
local lastSprinterZombieIDs = {}
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

local function updateAlertDragHandle(bounds, screenWidth, screenHeight, kind)
    kind = kind == "zombie" and "zombie" or "alife"
    local handle
    if kind == "zombie" then
        handle = zombieAlertDragHandle
    else
        handle = alertDragHandle
    end
    if not bounds then
        if handle and handle.alertVisible then
            handle.alertVisible = false
        end
        if handle and not handle.dragging then
            handle:setVisible(false)
        end
        return
    end

    handle = ensureAlertDragHandle(kind)
    if not handle then return end
    local width = bounds.right - bounds.x
    local height = bounds.bottom - bounds.y
    local x = math.max(0, math.min(math.max(0, screenWidth - width), bounds.x))
    local y = math.max(0, math.min(math.max(0, screenHeight - height), bounds.y))
    if x ~= bounds.x or y ~= bounds.y then
        if kind == "zombie" then
            zombieAlertPositionX = (x + width * 0.5) / math.max(screenWidth, 1)
            zombieAlertPositionY = y / math.max(screenHeight, 1)
        else
            alertPositionX = (x + width * 0.5) / math.max(screenWidth, 1)
            alertPositionY = y / math.max(screenHeight, 1)
        end
    end
    handle:setX(x)
    handle:setY(y)
    handle:setWidth(math.max(1, width))
    handle:setHeight(math.max(1, height))
    handle:setVisible(true)
    handle:bringToTop()
    handle.alertVisible = true
    local geometry = string.format("%.1f,%.1f %.1fx%.1f", x, y, width, height)
    if handle.diagnosticGeometry ~= geometry then
        local visibleOk, visible = pcall(function() return handle:isVisible() end)
        local mouseEventsOk, mouseEvents = pcall(function() return handle:isWantMouseEvents() end)
        logDragDiagnostic(string.format(
            "handle-bounds kind=%s bounds=%s screen=%dx%d alertVisible=%s uiVisible=%s mouseEvents=%s",
            kind, geometry, screenWidth, screenHeight,
            tostring(handle.alertVisible), tostring(visibleOk and visible),
            tostring(mouseEventsOk and mouseEvents)
        ))
        handle.diagnosticGeometry = geometry
    end
end

local function alertAnchor(kind, screenWidth, screenHeight, defaultY)
    if kind == "zombie" then
        return (zombieAlertPositionX or 0.5) * screenWidth,
            zombieAlertPositionY and zombieAlertPositionY * screenHeight
                or defaultY or screenHeight * 0.08
    end
    return (alertPositionX or 0.5) * screenWidth,
        alertPositionY and alertPositionY * screenHeight or defaultY or 24
end

local function drawCompactAlertLine(text, screenWidth, centerX, y, message, colour,
        iconKind, stance, sector, showArrow)
    local icon = typeIconTexture(iconKind)
    local arrow = showArrow and directionTextureFor(stance, sector) or nil
    if not arrow and sector then
        message = message .. " - " .. (DIRECTION_LABELS[sector] or DIRECTION_LABELS[1])
    end

    local font = UIFont.Small
    local lineHeight = text:getFontHeight(font)
    local iconSize = icon and 16 or 0
    local iconGap = icon and 5 or 0
    local arrowSize = arrow and 16 or 0
    local arrowGap = arrow and 5 or 0
    local messageWidth = text:MeasureStringX(font, message)
    local width = iconSize + iconGap + messageWidth + arrowGap + arrowSize
    local x = math.floor(math.max(8, math.min(screenWidth - width - 8, centerX - width * 0.5)))
    local textLeft = x + iconSize + iconGap
    local textCenter = textLeft + messageWidth * 0.5

    if icon then
        UIManager.DrawTexture(icon, x, y + math.floor((lineHeight - iconSize) * 0.5), iconSize, iconSize, 1)
    end
    for _, offset in ipairs(SHADOW_OFFSETS) do
        text:DrawStringCentre(font, textCenter + offset[1], y + offset[2], message, 0, 0, 0, 1)
    end
    text:DrawStringCentre(font, textCenter, y, message, colour[1], colour[2], colour[3], 1)
    if arrow then
        UIManager.DrawTexture(arrow, textLeft + messageWidth + arrowGap,
            y + math.floor((lineHeight - arrowSize) * 0.5), arrowSize, arrowSize, 1)
    end

    return mergeBounds(nil, x, y, width, lineHeight), y + lineHeight + 3
end

local function drawCompactAlertGroup(alertWarnings, zombieWarning, sprinterWarning,
        text, screenWidth, centerX, startY)
    local bounds
    local y = startY
    for _, warning in ipairs(alertWarnings) do
        local message = string.upper(STANCE_LABELS[warning.stance] or "Hostile")
            .. " A-LIFE (" .. tostring(warning.count) .. ") - "
            .. tostring(math.floor(warning.distance + 0.5)) .. " TILES"
        if warning.firearmCarriers and warning.firearmCarriers > 0 then
            message = message .. " - " .. tostring(warning.firearmCarriers) .. " ARMED"
        end
        local lineBounds, nextY = drawCompactAlertLine(
            text, screenWidth, centerX, y, message, STANCE_COLOURS[warning.stance],
            "alife", warning.stance, warning.direction, warning.showArrow
        )
        bounds = mergeBounds(bounds, lineBounds.x, lineBounds.y,
            lineBounds.right - lineBounds.x, lineBounds.bottom - lineBounds.y)
        y = nextY
    end

    if zombieWarning then
        local message = "ZOMBIES OUT OF SIGHT (" .. tostring(zombieWarning.count) .. ") - "
            .. tostring(math.floor(zombieWarning.distance + 0.5)) .. " TILES"
        local lineBounds, nextY = drawCompactAlertLine(
            text, screenWidth, centerX, y, message, { 1, 0.2, 0.08 }, "zombie",
            "hostile", zombieWarning.direction, true
        )
        bounds = mergeBounds(bounds, lineBounds.x, lineBounds.y,
            lineBounds.right - lineBounds.x, lineBounds.bottom - lineBounds.y)
        y = nextY
    end

    if sprinterWarning then
        local message = "SPRINTERS NEARBY (" .. tostring(sprinterWarning.count) .. ") - "
            .. tostring(math.floor(sprinterWarning.distance + 0.5)) .. " TILES"
        local lineBounds, nextY = drawCompactAlertLine(
            text, screenWidth, centerX, y, message, { 1, 0.28, 0.08 }, "zombie",
            "hostile", sprinterWarning.direction, true
        )
        bounds = mergeBounds(bounds, lineBounds.x, lineBounds.y,
            lineBounds.right - lineBounds.x, lineBounds.bottom - lineBounds.y)
        y = nextY
    end

    return bounds, y
end

local function drawNeatAlertGroup(alertWarnings, zombieWarning, sprinterWarning,
        headerTexture, bodyTexture,
        text, screenWidth, centerX, startY)
    local bounds
    local y = startY
    for _, warning in ipairs(alertWarnings) do
        local extraDetail
        if warning.firearmCarriers and warning.firearmCarriers > 0 then
            extraDetail = tostring(warning.firearmCarriers)
                .. (warning.firearmCarriers == 1 and " firearm carrier nearby"
                    or " firearm carriers nearby")
        end
        local nextY, x, width, height = drawNeatAlertCard(
            headerTexture, bodyTexture, text, screenWidth, centerX, y,
            warningTitle(warning, false),
            "Distance: " .. tostring(math.floor(warning.distance + 0.5)) .. " tiles",
            extraDetail, warning.stance, warning.direction,
            warning.showArrow, STANCE_COLOURS[warning.stance], "alife"
        )
        bounds = mergeBounds(bounds, x, y, width, height)
        y = nextY
    end

    if zombieWarning then
        local title = "Zombies out of sight (" .. tostring(zombieWarning.count) .. ")"
        local nextY, x, width, height = drawNeatAlertCard(
            headerTexture, bodyTexture, text, screenWidth, centerX, y,
            title,
            "Nearest zombie: " .. tostring(math.floor(zombieWarning.distance + 0.5)) .. " tiles",
            nil, "hostile", zombieWarning.direction, true,
            { 1, 0.2, 0.16 }, "zombie"
        )
        bounds = mergeBounds(bounds, x, y, width, height)
        y = nextY
    end

    if sprinterWarning then
        local title = "Sprinters nearby (" .. tostring(sprinterWarning.count) .. ")"
        local _, x, width, height = drawNeatAlertCard(
            headerTexture, bodyTexture, text, screenWidth, centerX, y,
            title,
            "Nearest sprinter: " .. tostring(math.floor(sprinterWarning.distance + 0.5)) .. " tiles",
            nil, "hostile", sprinterWarning.direction, true,
            { 1, 0.28, 0.08 }, "zombie"
        )
        bounds = mergeBounds(bounds, x, y, width, height)
    end

    return bounds
end

local function isBlockedBetweenSquares(firstSquare, secondSquare)
    return firstSquare:isBlockedTo(secondSquare) or secondSquare:isBlockedTo(firstSquare)
end

local function hasClearLineOnSameFloor(startSquare, targetSquare, cell)
    local startX, startY = startSquare:getX(), startSquare:getY()
    local targetX, targetY = targetSquare:getX(), targetSquare:getY()
    local deltaX, deltaY = targetX - startX, targetY - startY
    local stepX = deltaX < 0 and -1 or 1
    local stepY = deltaY < 0 and -1 or 1
    local absDeltaX, absDeltaY = math.abs(deltaX), math.abs(deltaY)
    local maxX = absDeltaX > 0 and 0.5 / absDeltaX or math.huge
    local maxY = absDeltaY > 0 and 0.5 / absDeltaY or math.huge
    local deltaMaxX = absDeltaX > 0 and 1 / absDeltaX or math.huge
    local deltaMaxY = absDeltaY > 0 and 1 / absDeltaY or math.huge
    local x, y = startX, startY
    local currentSquare = startSquare
    local z = startSquare:getZ()

    while x ~= targetX or y ~= targetY do
        if maxX < maxY then
            x = x + stepX
            maxX = maxX + deltaMaxX
            local nextSquare = cell:getGridSquare(x, y, z)
            if nextSquare == nil or isBlockedBetweenSquares(currentSquare, nextSquare) then return false end
            currentSquare = nextSquare
        elseif maxY < maxX then
            y = y + stepY
            maxY = maxY + deltaMaxY
            local nextSquare = cell:getGridSquare(x, y, z)
            if nextSquare == nil or isBlockedBetweenSquares(currentSquare, nextSquare) then return false end
            currentSquare = nextSquare
        else
            local sideX = cell:getGridSquare(x + stepX, y, z)
            local sideY = cell:getGridSquare(x, y + stepY, z)
            local nextSquare = cell:getGridSquare(x + stepX, y + stepY, z)
            if sideX == nil or sideY == nil or nextSquare == nil then return false end
            local pathXClear = not isBlockedBetweenSquares(currentSquare, sideX)
                and not isBlockedBetweenSquares(sideX, nextSquare)
            local pathYClear = not isBlockedBetweenSquares(currentSquare, sideY)
                and not isBlockedBetweenSquares(sideY, nextSquare)
            if not pathXClear and not pathYClear then return false end
            x, y = x + stepX, y + stepY
            maxX = maxX + deltaMaxX
            maxY = maxY + deltaMaxY
            currentSquare = nextSquare
        end
    end

    return true
end

local function passesRearZombieVisibilityFilters(zombie, playerSquare, cell, sameFloorOnly, requireLineOfSight)
    if not sameFloorOnly and not requireLineOfSight then return true end
    if playerSquare == nil then return false end

    local ok, passes = pcall(function()
        local zombieSquare = zombie:getCurrentSquare()
        if zombieSquare == nil then return false end
        if sameFloorOnly and zombieSquare:getZ() ~= playerSquare:getZ() then return false end
        if requireLineOfSight then
            if zombieSquare:getZ() == playerSquare:getZ() then
                if not hasClearLineOnSameFloor(zombieSquare, playerSquare, cell) then return false end
            elseif isBlockedBetweenSquares(zombieSquare, playerSquare) then
                return false
            end
        end
        return true
    end)
    return ok and passes
end

local function scanNearbyThreats()
    warnings = {}
    rearZombieWarning = nil
    sprinterWarning = nil
    sprinterZombieIDs = {}
    closeHostileNPCs = {}
    local stanceEnabled = {}
    local warnALifeNPCs = false
    for _, stance in ipairs(STANCE_PRIORITY) do
        local enabled = getOption(STANCE_OPTION_KEYS[stance], STANCE_OPTION_DEFAULTS[stance])
        stanceEnabled[stance] = enabled
        warnALifeNPCs = warnALifeNPCs or enabled
    end
    local warnRearZombies = getOption("EnableRearZombieWarning", true)
    local warnSprinters = getOption("EnableSprinterWarning", true)
    local warnCloseHostileAlarm = getOption("EnableCloseHostileAlarm", true)
    if not warnALifeNPCs and not warnRearZombies and not warnCloseHostileAlarm and not warnSprinters then return end

    local project = ProjectALife
    if type(project) ~= "table" then
        project = nil
        warnALifeNPCs = false
        warnCloseHostileAlarm = false
    end
    if not warnALifeNPCs and not warnRearZombies and not warnCloseHostileAlarm and not warnSprinters then return end
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
    local closeHostileRange = warnCloseHostileAlarm and closeHostileAlarmRange() or 0
    local closeHostileRangeSquared = closeHostileRange * closeHostileRange
    local rearRange = warnRearZombies and rearZombieWarningRange(player) or 0
    local rearRangeSquared = rearRange * rearRange
    local sprinterRange = warnSprinters and sprinterWarningRange() or 0
    local sprinterRangeSquared = sprinterRange * sprinterRange
    local rearAngleCos = math.cos(math.rad(rearZombieWarningAngle() * 0.5))
    local scanRangeSquared = math.max(rangeSquared, rearRangeSquared,
        closeHostileRangeSquared, sprinterRangeSquared)
    local showDirectionArrow = getOption("ShowDirectionArrow", true)
    local showFirearmWarning = getOption("ShowFirearmWarning", false)
    local ignoreFallenZombies = getOption("IgnoreFallenZombies", false)
    local rearZombieSameFloorOnly = getOption("RearZombieSameFloorOnly", true)
    local rearZombieRequireLineOfSight = getOption("RearZombieRequireLineOfSight", true)
    local sprinterSameFloorOnly = getOption("SprinterSameFloorOnly", true)
    local sprinterRequireLineOfSight = getOption("SprinterRequireLineOfSight", true)
    local sprinterIgnoreFallen = getOption("SprinterIgnoreFallen", true)
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
    local sprinters = 0
    local nearestSprinter = sprinterRangeSquared
    local nearestSprinterDirection
    for index = 0, list:size() - 1 do
        local shell = list:get(index)
        if shell ~= nil and not shell:isDead() then
            local x, y, z = shell:getX(), shell:getY(), shell:getZ()
            local dx, dy = x - px, y - py
            local distanceSquared = dx * dx + dy * dy
            local nearbyFloor = math.abs(z - pz) <= 1
                or (warnSprinters and not sprinterSameFloorOnly)
            if nearbyFloor and distanceSquared <= scanRangeSquared then
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
                                cell,
                                rearZombieSameFloorOnly,
                                rearZombieRequireLineOfSight
                            )
                    end
                end
                local closeHostileCandidate = warnCloseHostileAlarm
                    and distanceSquared <= closeHostileRangeSquared
                local sprinterCandidate = warnSprinters
                    and distanceSquared <= sprinterRangeSquared
                    and isSprinter(shell)
                if sprinterCandidate and sprinterIgnoreFallen then
                    local ok, onFloor = pcall(function() return shell:isOnFloor() end)
                    if ok and onFloor == true then sprinterCandidate = false end
                end
                if sprinterCandidate then
                    sprinterCandidate = passesRearZombieVisibilityFilters(
                        shell,
                        playerSquare,
                        cell,
                        sprinterSameFloorOnly,
                        sprinterRequireLineOfSight
                    )
                end
                local alifeCandidate = (warnALifeNPCs and distanceSquared <= rangeSquared)
                    or closeHostileCandidate
                local uid
                if project and (rearCandidate or alifeCandidate or sprinterCandidate) then
                    uid = uidOf(project, shell)
                end

                if rearCandidate and uid == nil then
                    rearZombies = rearZombies + 1
                    if rearZombies == 1 or distanceSquared < nearestRearZombie then
                        nearestRearZombie = distanceSquared
                        nearestRearZombieDirection = directionSector(dx, dy, forwardX, forwardY)
                    end
                end

                if sprinterCandidate and uid == nil then
                    sprinters = sprinters + 1
                    sprinterZombieIDs[zombieAlertId(shell)] = true
                    if sprinters == 1 or distanceSquared < nearestSprinter then
                        nearestSprinter = distanceSquared
                        nearestSprinterDirection = directionSector(dx, dy, forwardX, forwardY)
                    end
                end

                if alifeCandidate and uid ~= nil then
                    local record = actorFor(project, uid)
                    if record then
                        local stance = stanceOf(project, record, player)
                        if closeHostileCandidate and stance == "hostile" then
                            closeHostileNPCs[uid] = true
                        end
                        if warnALifeNPCs and distanceSquared <= rangeSquared and stanceEnabled[stance] then
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
    if sprinters > 0 then
        sprinterWarning = {
            count = sprinters,
            distance = math.sqrt(nearestSprinter),
            direction = nearestSprinterDirection,
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
    if sprinterWarning then parts[#parts + 1] = "sprinters" end
    return table.concat(parts, "|")
end

local function alarmSignature()
    if getOption("ZombieAlarmOnly", true) then
        local parts = {}
        if rearZombieWarning then parts[#parts + 1] = "rear-zombies" end
        if sprinterWarning then parts[#parts + 1] = "sprinters" end
        return table.concat(parts, "|")
    end
    return warningSignature()
end

local function playAlarmSound(soundOption, volumeOption)
    local defaultSound = DEFAULT_ALARM_SOUND
    if soundOption == "CloseHostileAlarmSound" then
        defaultSound = DEFAULT_CLOSE_HOSTILE_ALARM_SOUND
    elseif soundOption == "SprinterAlarmSound" then
        defaultSound = DEFAULT_SPRINTER_ALARM_SOUND
    end
    local index = math.floor(tonumber(getOption(soundOption or "AlarmSound", defaultSound)) or defaultSound)
    local sound = ALARM_SOUND_IDS[index] or ALARM_SOUND_IDS[1]
    local volume = tonumber(getOption(volumeOption or "AlarmVolume", DEFAULT_ALARM_VOLUME))
        or DEFAULT_ALARM_VOLUME
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
        sprinterWarning = nil
        sprinterZombieIDs = {}
        closeHostileNPCs = {}
        lastAlarmSignature = ""
        lastCloseHostileNPCs = {}
        lastSprinterZombieIDs = {}
        if not errorLogged then
            print("[Viewpoint Threat Detector] Detection failed: " .. tostring(err))
            errorLogged = true
        end
        return
    end

    local signature = alarmSignature()
    local alarmSoundsEnabled = getOption("EnableAlarmSound", true)
    local closeHostileAlarmEnabled = alarmSoundsEnabled
        and getOption("EnableCloseHostileAlarm", true)
    local sprinterAlarmEnabled = alarmSoundsEnabled
        and getOption("EnableSprinterWarning", true)
        and getOption("EnableSprinterAlarm", true)
    local closeHostileAlarmEntered = false
    if closeHostileAlarmEnabled then
        for uid in pairs(closeHostileNPCs) do
            if not lastCloseHostileNPCs[uid] then
                closeHostileAlarmEntered = true
                break
            end
        end
    end
    local sprinterAlarmEntered = false
    if sprinterAlarmEnabled then
        for id in pairs(sprinterZombieIDs) do
            if not lastSprinterZombieIDs[id] then
                sprinterAlarmEntered = true
                break
            end
        end
    end
    if signature ~= "" and signature ~= lastAlarmSignature
            and alarmSoundsEnabled and not closeHostileAlarmEntered and not sprinterAlarmEntered then
        playAlarmSound()
    end
    if sprinterAlarmEntered then
        playAlarmSound("SprinterAlarmSound", "SprinterAlarmVolume")
    elseif closeHostileAlarmEntered then
        playAlarmSound("CloseHostileAlarmSound", "CloseHostileAlarmVolume")
    end
    lastAlarmSignature = signature
    lastCloseHostileNPCs = closeHostileAlarmEnabled and closeHostileNPCs or {}
    lastSprinterZombieIDs = sprinterAlarmEnabled and sprinterZombieIDs or {}
end

local function drawWarning()
    if disableAlertsInVehicle and playerInVehicle then
        warnings = {}
        rearZombieWarning = nil
        sprinterWarning = nil
        sprinterZombieIDs = {}
        closeHostileNPCs = {}
        lastAlarmSignature = ""
        lastCloseHostileNPCs = {}
        lastSprinterZombieIDs = {}
        updateAlertDragHandle(nil, 0, 0)
        updateAlertDragHandle(nil, 0, 0, "zombie")
        return
    end
    if #warnings == 0 and rearZombieWarning == nil and sprinterWarning == nil then
        updateAlertDragHandle(nil, 0, 0)
        updateAlertDragHandle(nil, 0, 0, "zombie")
        return
    end

    local minimalUI = getOption("MinimalAlertUI", false)
    local separatePositions = getOption("SeparateAlertPositions", false)
    if minimalUI or separatePositions then
        local ok, err = pcall(function()
            local core = getCore()
            local screenWidth = core:getScreenWidth()
            local screenHeight = core:getScreenHeight()
            local text = getTextManager()
            local headerTexture = not minimalUI and neatPanelTexture(NEAT_PANEL_HEADER_TEXTURE) or nil
            local bodyTexture = not minimalUI and neatPanelTexture(NEAT_PANEL_BODY_TEXTURE) or nil
            local useNeat = headerTexture ~= nil and bodyTexture ~= nil

            local function drawGroup(alertWarnings, zombieWarning, sprinterAlert, kind, defaultY)
                local centerX, startY = alertAnchor(kind, screenWidth, screenHeight, defaultY)
                local bounds
                if useNeat then
                    bounds = drawNeatAlertGroup(
                        alertWarnings, zombieWarning, sprinterAlert, headerTexture, bodyTexture,
                        text, screenWidth, centerX, startY
                    )
                else
                    bounds = drawCompactAlertGroup(
                        alertWarnings, zombieWarning, sprinterAlert,
                        text, screenWidth, centerX, startY
                    )
                end
                updateAlertDragHandle(bounds, screenWidth, screenHeight, kind)
                return bounds
            end

            if separatePositions then
                local alifeBounds = drawGroup(warnings, nil, nil, "alife", 24)
                local zombieDefaultY = alifeBounds and alifeBounds.bottom + 12 or 24
                drawGroup({}, rearZombieWarning, sprinterWarning, "zombie", zombieDefaultY)
            else
                local centerX, startY = alertAnchor("alife", screenWidth, screenHeight)
                local bounds
                if useNeat then
                    bounds = drawNeatAlertGroup(
                        warnings, rearZombieWarning, sprinterWarning,
                        headerTexture, bodyTexture,
                        text, screenWidth, centerX, startY
                    )
                else
                    bounds = drawCompactAlertGroup(
                        warnings, rearZombieWarning, sprinterWarning,
                        text, screenWidth, centerX, startY
                    )
                end
                updateAlertDragHandle(bounds, screenWidth, screenHeight, "alife")
                updateAlertDragHandle(nil, screenWidth, screenHeight, "zombie")
            end
        end)
        if not ok then
            updateAlertDragHandle(nil, 0, 0)
            updateAlertDragHandle(nil, 0, 0, "zombie")
            if not errorLogged then
                print("[Viewpoint Threat Detector] Warning display failed: " .. tostring(err))
                errorLogged = true
            end
        end
        return
    end

    updateAlertDragHandle(nil, 0, 0, "zombie")
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
                    y = y + height + 6
                end
                if sprinterWarning then
                    local title = "Sprinters nearby (" .. tostring(sprinterWarning.count) .. ")"
                    local _, x, width, height = drawNeatAlertCard(
                        headerTexture, bodyTexture, text, screenWidth, centerX, y,
                        title,
                        "Nearest sprinter: " .. tostring(math.floor(sprinterWarning.distance + 0.5)) .. " tiles",
                        nil, "hostile", sprinterWarning.direction, true,
                        { 1, 0.28, 0.08 }, "zombie"
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

        if sprinterWarning then
            local message = "SPRINTERS NEARBY (" .. tostring(sprinterWarning.count) .. ") - "
                .. tostring(math.floor(sprinterWarning.distance + 0.5)) .. " TILES"
            local y = bounds and bounds.bottom + 4 or nextWarningY
            local lineBounds = drawCompactAlertLine(
                text, screenWidth, centerX, y, message, { 1, 0.28, 0.08 },
                "zombie", "hostile", sprinterWarning.direction, true
            )
            bounds = mergeBounds(bounds, lineBounds.x, lineBounds.y,
                lineBounds.right - lineBounds.x, lineBounds.bottom - lineBounds.y)
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
        dragDiagnosticsEnabled = getOption("EnableDragDiagnostics", false) == true
        updateGlobalAlertDrag()
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
