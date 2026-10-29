-- Body Cam: client side follow logic.
--
-- Project Zomboid's camera always follows the local player and the client only
-- loads/streams the world around that player. So instead of moving the camera,
-- the (invisible, ghosted, no-clipping) admin character is pinned onto the
-- target's position and facing every tick. The camera, line of sight and vision
-- cone then match what the target sees, like a chest-mounted camera.

require "BodyCam/BodyCam_Shared"

BodyCam.settings = {
    overlay = true,         -- REC / timestamp overlay
    matchFacing = true,     -- copy target's facing (vision cone)
    hideSelf = true,        -- try to hide the admin's own model
    autoZoom = true,        -- zoom in when starting
    zoomSteps = 3,          -- how many zoom-in steps to apply
    returnOnStop = true,    -- teleport back to where you started
    autoResume = false,     -- resume watching the last target after login
    forwardOffset = 0,      -- tiles ahead of the target to center the view
    unitLabel = "UNIT 01",  -- text shown in the overlay
    lastTarget = "",
}

BodyCam.state = {
    active = false,
    targetName = nil,
    savedFlags = nil,
    startPos = nil,
    zoomApplied = 0,
    lastLocateRequest = 0,
    lastTeleport = 0,
    serverPos = nil,
    signalLost = false,
}

local SETTINGS_FILE = "BodyCam_settings.txt"
local LOCATE_INTERVAL_MS = 2000
local TELEPORT_COOLDOWN_MS = 3000
local NEAR_DISTANCE = 40    -- tiles; closer than this we track the local copy of the target
local DRIFT_DISTANCE = 10   -- server vs local position mismatch that means local copy is stale

----------------------------------------------------------------------------
-- Settings persistence (client-side file in Zomboid/Lua/)
----------------------------------------------------------------------------

function BodyCam.saveSettings()
    local writer = getFileWriter(SETTINGS_FILE, true, false)
    if not writer then return end
    for k, v in pairs(BodyCam.settings) do
        writer:write(k .. "=" .. tostring(v) .. "\n")
    end
    writer:close()
end

function BodyCam.loadSettings()
    local reader = getFileReader(SETTINGS_FILE, false)
    if not reader then return end
    local line = reader:readLine()
    while line do
        local k, v = string.match(line, "^([^=]+)=(.*)$")
        if k and BodyCam.settings[k] ~= nil then
            local current = BodyCam.settings[k]
            if type(current) == "boolean" then
                BodyCam.settings[k] = (v == "true")
            elseif type(current) == "number" then
                BodyCam.settings[k] = tonumber(v) or current
            else
                BodyCam.settings[k] = v
            end
        end
        line = reader:readLine()
    end
    reader:close()
end

----------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------

local say

local function now()
    return getTimestampMs()
end

function BodyCam.say(msg)
    local player = getPlayer()
    if player then
        pcall(player.setHaloNote, player, msg, 255, 200, 80, 300)
    end
    BodyCam.log(msg)
end

say = BodyCam.say

local function tryCall(obj, method, ...)
    if obj and obj[method] then
        local ok, res = pcall(obj[method], obj, ...)
        if ok then return res end
    end
    return nil
end

function BodyCam.findLocalTarget(username)
    local players = getOnlinePlayers()
    if not players then return nil end
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p and p:getUsername() == username then
            return p
        end
    end
    return nil
end

local function syncAdminFlags(player)
    if sendPlayerExtraInfo then
        pcall(sendPlayerExtraInfo, player)
    end
end

local function applySpectatorFlags(player)
    local s = BodyCam.state
    s.savedFlags = {
        invisible = tryCall(player, "isInvisible"),
        ghost = tryCall(player, "isGhostMode"),
        god = tryCall(player, "isGodMod"),
        noclip = tryCall(player, "isNoClip"),
    }
    tryCall(player, "setInvisible", true)
    tryCall(player, "setGhostMode", true)
    tryCall(player, "setGodMod", true)
    tryCall(player, "setNoClip", true)
    syncAdminFlags(player)
end

local function restoreSpectatorFlags(player)
    local f = BodyCam.state.savedFlags
    if not f then return end
    if f.invisible ~= nil then tryCall(player, "setInvisible", f.invisible) end
    if f.ghost ~= nil then tryCall(player, "setGhostMode", f.ghost) end
    if f.god ~= nil then tryCall(player, "setGodMod", f.god) end
    if f.noclip ~= nil then tryCall(player, "setNoClip", f.noclip) end
    syncAdminFlags(player)
    BodyCam.state.savedFlags = nil
end

local function setSelfAlpha(player, alpha)
    -- Signatures differ between builds; try them all.
    tryCall(player, "setAlphaAndTarget", 0, alpha)
    tryCall(player, "setAlphaAndTarget", alpha)
    tryCall(player, "setAlpha", 0, alpha)
    tryCall(player, "setTargetAlpha", 0, alpha)
end

local function zoom(steps)
    -- negative = zoom in, positive = zoom out
    local core = getCore()
    if not core or steps == 0 then return end
    local dir = steps < 0 and -1 or 1
    for _ = 1, math.abs(steps) do
        pcall(core.doZoomScroll, core, 0, dir)
    end
end

local function teleportTo(x, y, z)
    local s = BodyCam.state
    if now() - s.lastTeleport < TELEPORT_COOLDOWN_MS then return end
    s.lastTeleport = now()
    local cmd = string.format("/teleportto %d,%d,%d", math.floor(x), math.floor(y), math.floor(z))
    if isClient() then
        SendCommandToServer(cmd)
    else
        local p = getPlayer()
        p:setX(x); p:setY(y); p:setZ(z)
        p:setLx(x); p:setLy(y); p:setLz(z)
    end
end

local function requestLocate()
    local s = BodyCam.state
    if now() - s.lastLocateRequest < LOCATE_INTERVAL_MS then return end
    s.lastLocateRequest = now()
    sendClientCommand(getPlayer(), BodyCam.MODULE, "locate", { username = s.targetName })
end

function BodyCam.requestPlayerList()
    local player = getPlayer()
    if player then
        sendClientCommand(player, BodyCam.MODULE, "list", {})
    end
end

----------------------------------------------------------------------------
-- Start / stop
----------------------------------------------------------------------------

function BodyCam.start(username)
    local player = getPlayer()
    if not player or not username or username == "" then return end
    if not BodyCam.isAllowed(player) then
        say("Body Cam: admin or moderator access required")
        return
    end
    if username == player:getUsername() then
        say("Body Cam: you can't watch yourself")
        return
    end
    if player:getVehicle() then
        say("Body Cam: leave the vehicle first")
        return
    end

    local s = BodyCam.state
    if s.active then
        -- Switching target: keep flags, zoom and start position.
        s.targetName = username
        s.serverPos = nil
        s.lastLocateRequest = 0
        s.lastTeleport = 0
    else
        s.active = true
        s.targetName = username
        s.serverPos = nil
        s.lastLocateRequest = 0
        s.lastTeleport = 0
        s.startPos = { x = player:getX(), y = player:getY(), z = player:getZ() }
        applySpectatorFlags(player)
        if BodyCam.settings.autoZoom then
            local steps = math.max(0, math.floor(BodyCam.settings.zoomSteps))
            zoom(-steps)
            s.zoomApplied = steps
        end
    end

    BodyCam.settings.lastTarget = username
    BodyCam.saveSettings()
    requestLocate()
    if BodyCam.Overlay then BodyCam.Overlay.show() end
    say("Body Cam: watching " .. username)
end

function BodyCam.stop()
    local s = BodyCam.state
    if not s.active then return end
    local player = getPlayer()
    s.active = false
    s.targetName = nil
    s.serverPos = nil
    s.signalLost = false

    if player then
        setSelfAlpha(player, 1)
        restoreSpectatorFlags(player)
        if BodyCam.settings.returnOnStop and s.startPos then
            s.lastTeleport = 0
            teleportTo(s.startPos.x, s.startPos.y, s.startPos.z)
        end
    end
    if s.zoomApplied > 0 then
        zoom(s.zoomApplied)
        s.zoomApplied = 0
    end
    s.startPos = nil
    if BodyCam.Overlay then BodyCam.Overlay.hide() end
    say("Body Cam: stopped")
end

function BodyCam.isActive()
    return BodyCam.state.active
end

----------------------------------------------------------------------------
-- Per-tick follow
----------------------------------------------------------------------------

local function pinTo(player, target)
    local tx, ty, tz = target:getX(), target:getY(), target:getZ()
    local fwd = tryCall(target, "getForwardDirection")
    local fx, fy = 0, 0
    if fwd then fx, fy = fwd:getX(), fwd:getY() end

    local offset = BodyCam.settings.forwardOffset or 0
    local x, y = tx + fx * offset, ty + fy * offset

    player:setX(x); player:setY(y); player:setZ(tz)
    player:setLx(x); player:setLy(y); player:setLz(tz)

    if BodyCam.settings.matchFacing then
        local dir = tryCall(target, "getDir")
        if dir then tryCall(player, "setDir", dir) end
        if fwd then
            -- (x, y) in some builds, (Vector2) in others; the wrong one fails silently.
            tryCall(player, "setForwardDirection", fx, fy)
            tryCall(player, "setForwardDirection", fwd)
        end
    end
end

-- Re-apply flags (throttled) without overwriting the originally saved values.
local lastFlagCheck = 0
local function ensureSpectatorFlags(player)
    if now() - lastFlagCheck < 2000 then return end
    lastFlagCheck = now()
    if tryCall(player, "isInvisible") and tryCall(player, "isGhostMode") then return end
    local saved = BodyCam.state.savedFlags
    applySpectatorFlags(player)
    if saved then BodyCam.state.savedFlags = saved end
end

local function onTick()
    local s = BodyCam.state
    if not s.active then return end
    local player = getPlayer()
    if not player or player:isDead() then
        BodyCam.stop()
        return
    end

    -- Keep flags on in case something (admin panel, respawn) toggled them.
    ensureSpectatorFlags(player)
    if BodyCam.settings.hideSelf then setSelfAlpha(player, 0) end

    requestLocate()

    local target = BodyCam.findLocalTarget(s.targetName)
    local useLocal = false
    if target and target:getCurrentSquare() then
        local dist = player:DistTo(target)
        useLocal = dist < NEAR_DISTANCE
        -- Local copy can be stale if the target isn't being synced to us.
        if useLocal and s.serverPos then
            local dx = s.serverPos.x - target:getX()
            local dy = s.serverPos.y - target:getY()
            if math.sqrt(dx * dx + dy * dy) > DRIFT_DISTANCE then
                useLocal = false
            end
        end
    end

    if useLocal then
        s.signalLost = target:isDead()
        pinTo(player, target)
    elseif s.serverPos then
        s.signalLost = true
        local dx = s.serverPos.x - player:getX()
        local dy = s.serverPos.y - player:getY()
        if math.sqrt(dx * dx + dy * dy) > 2 or math.floor(player:getZ()) ~= math.floor(s.serverPos.z) then
            teleportTo(s.serverPos.x, s.serverPos.y, s.serverPos.z)
        end
    else
        s.signalLost = true
    end
end

----------------------------------------------------------------------------
-- Server responses
----------------------------------------------------------------------------

local function onServerCommand(module, command, args)
    if module ~= BodyCam.MODULE then return end
    if command == "locate" then
        local s = BodyCam.state
        if not s.active or args.username ~= s.targetName then return end
        if args.found then
            s.serverPos = { x = args.x, y = args.y, z = args.z }
        else
            s.serverPos = nil
        end
    elseif command == "denied" then
        local wasActive = BodyCam.state.active
        BodyCam.stop()
        if wasActive or (BodyCam.UI and BodyCam.UI.instance) then
            say("Body Cam: server refused (role '" .. tostring(args.role) .. "'). Add your username to the BodyCam.AllowedUsers sandbox option.")
        end
    elseif command == "list" then
        if BodyCam.UI and BodyCam.UI.onPlayerList then
            BodyCam.UI.onPlayerList(args.players or {})
        end
    end
end

----------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------

local resumeAt = nil

local function onGameStart()
    BodyCam.loadSettings()
    local player = getPlayer()
    if player then
        BodyCam.log("Game started as " .. tostring(player:getUsername()) .. ", role: " ..
            tostring(BodyCam.getRoleName(player)) .. ", allowed: " .. tostring(BodyCam.isAllowed(player)))
    end
    if BodyCam.settings.autoResume and BodyCam.settings.lastTarget ~= "" then
        -- Give the world and player list a few seconds to settle.
        resumeAt = now() + 5000
    end
end

local function onResumeTick()
    if resumeAt and now() >= resumeAt then
        resumeAt = nil
        local player = getPlayer()
        if player and BodyCam.isAllowed(player) and not BodyCam.state.active then
            BodyCam.start(BodyCam.settings.lastTarget)
        end
    end
end

Events.OnGameStart.Add(onGameStart)
Events.OnTick.Add(onTick)
Events.OnTick.Add(onResumeTick)
Events.OnServerCommand.Add(onServerCommand)
