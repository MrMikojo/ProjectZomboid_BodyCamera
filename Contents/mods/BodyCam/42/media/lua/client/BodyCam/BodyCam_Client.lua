-- Body Cam: client side follow logic.
--
-- Project Zomboid's camera always follows the local player and the client only
-- loads/streams the world around that player. So instead of moving the camera,
-- the (invisible, ghosted, no-clipping) admin character is pinned onto the
-- target's position, giving a spectator-style overhead camera held close above
-- the target. With "see everyone" on, zombies and players behind the target
-- stay visible, so viewers can see what the target can't. Optionally the view
-- can also turn with the target's body (the original chest-cam behaviour).
--
-- The target is sampled every tick into a short buffer, and the view is moved
-- `updateFps` times a second to where the target was `delayMs` ago. The delay
-- smooths out network jitter; the fixed rate gives a camera-like cadence.

require "BodyCam/BodyCam_Shared"

BodyCam.settings = {
    overlay = true,         -- REC / timestamp overlay
    seeAll = true,          -- admin "see/hear everyone": show what's behind the target
    turnWithBody = false,   -- copy target's body facing (chest-cam style vision cone)
    hideSelf = true,        -- try to hide the admin's own model
    autoZoom = true,        -- zoom in when starting
    zoomSteps = 5,          -- how many zoom-in steps to apply (game caps at its closest level)
    returnOnStop = true,    -- teleport back to where you started
    autoResume = false,     -- resume watching the last target after login
    forwardOffset = 0,      -- tiles ahead of the target to center the view
    updateFps = 24,         -- how often the view moves (body cam frame rate)
    delayMs = 250,          -- how far behind the target the view runs
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
local STALE_MS = 3000       -- local copy must be frozen this long before we call it stale
local LOST_GRACE_MS = 1500  -- hide brief hiccups from the SIGNAL LOST overlay
local MAX_TICK_ERRORS = 30  -- stop instead of spamming the log every tick

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
        seeAll = tryCall(player, "isCanSeeAll"),
        hearAll = tryCall(player, "isCanHearAll"),
    }
    tryCall(player, "setInvisible", true)
    tryCall(player, "setGhostMode", true)
    tryCall(player, "setGodMod", true)
    tryCall(player, "setNoClip", true)
    if BodyCam.settings.seeAll then
        tryCall(player, "setCanSeeAll", true)
        tryCall(player, "setCanHearAll", true)
    end
    syncAdminFlags(player)
end

-- Called when the "see everyone" option is toggled while watching.
function BodyCam.applySeeAll()
    local player = getPlayer()
    local f = BodyCam.state.savedFlags
    if not player or not BodyCam.state.active or not f then return end
    local on = BodyCam.settings.seeAll
    tryCall(player, "setCanSeeAll", on or f.seeAll == true)
    tryCall(player, "setCanHearAll", on or f.hearAll == true)
    syncAdminFlags(player)
end

local function restoreSpectatorFlags(player)
    local f = BodyCam.state.savedFlags
    if not f then return end
    if f.invisible ~= nil then tryCall(player, "setInvisible", f.invisible) end
    if f.ghost ~= nil then tryCall(player, "setGhostMode", f.ghost) end
    if f.god ~= nil then tryCall(player, "setGodMod", f.god) end
    if f.noclip ~= nil then tryCall(player, "setNoClip", f.noclip) end
    if f.seeAll ~= nil then tryCall(player, "setCanSeeAll", f.seeAll) end
    if f.hearAll ~= nil then tryCall(player, "setCanHearAll", f.hearAll) end
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

    BodyCam.clearSamples()
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
    s.lostSince = nil
    s.lastTargetPos = nil
    BodyCam.clearSamples()

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

local samples = {}          -- { t, x, y, z, angle, dir }, oldest first
local lastApply = 0
local lastApplied = nil     -- last sample the view was moved to
local JUMP_DISTANCE = 5     -- tiles between samples that count as a teleport, not movement

function BodyCam.clearSamples()
    samples = {}
    lastApplied = nil
end

local function recordSample(target)
    local angle = tryCall(target, "getDirectionAngle")
    if angle == nil then
        local fwd = tryCall(target, "getForwardDirection")
        if fwd and math.atan2 then angle = math.deg(math.atan2(fwd:getY(), fwd:getX())) end
    end
    table.insert(samples, {
        t = now(),
        x = target:getX(), y = target:getY(), z = target:getZ(),
        angle = angle,
        dir = tryCall(target, "getDir"),
    })
    local keepAfter = now() - (BodyCam.settings.delayMs or 0) - 1000
    while #samples > 2 and samples[2].t < keepAfter do
        table.remove(samples, 1)
    end
end

local function lerpAngle(a, b, f)
    local d = (b - a + 540) % 360 - 180
    return a + d * f
end

-- Where the target was at time t, interpolated between buffered samples.
local function sampleAt(t)
    local n = #samples
    if n == 0 then return nil end
    if t <= samples[1].t then return samples[1] end
    for i = n, 2, -1 do
        local a, b = samples[i - 1], samples[i]
        if a.t <= t then
            if t >= b.t then return b end
            local dx, dy = b.x - a.x, b.y - a.y
            if dx * dx + dy * dy > JUMP_DISTANCE * JUMP_DISTANCE or math.floor(a.z) ~= math.floor(b.z) then
                return b
            end
            local f = (t - a.t) / math.max(1, b.t - a.t)
            local angle = b.angle
            if a.angle and b.angle then angle = lerpAngle(a.angle, b.angle, f) end
            return {
                x = a.x + dx * f, y = a.y + dy * f, z = b.z,
                angle = angle,
                dir = f < 0.5 and a.dir or b.dir,
            }
        end
    end
    return samples[n]
end

-- Optional: facing comes only from the wearer's body, never from the admin's own mouse.
local function applyFacing(player, sample)
    if not BodyCam.settings.turnWithBody or not sample.angle then return end
    if sample.dir then tryCall(player, "setDir", sample.dir) end
    tryCall(player, "setDirectionAngle", sample.angle)
    tryCall(player, "setForwardDirection", math.cos(math.rad(sample.angle)), math.sin(math.rad(sample.angle)))
end

local function pinTo(player, sample)
    local fx, fy = 0, 0
    if sample.angle then
        fx, fy = math.cos(math.rad(sample.angle)), math.sin(math.rad(sample.angle))
    end
    local offset = BodyCam.settings.forwardOffset or 0
    local x, y, z = sample.x + fx * offset, sample.y + fy * offset, sample.z

    player:setX(x); player:setY(y); player:setZ(z)
    -- Previous-position setters: setLastX in Build 42, setLx in Build 41.
    if player.setLastX then
        tryCall(player, "setLastX", x); tryCall(player, "setLastY", y); tryCall(player, "setLastZ", z)
    elseif player.setLx then
        tryCall(player, "setLx", x); tryCall(player, "setLy", y); tryCall(player, "setLz", z)
    end

    applyFacing(player, sample)
    lastApplied = sample
end

-- Move the view at most updateFps times a second, to where the target was delayMs ago.
local function applyDelayed(player)
    local fps = math.max(1, BodyCam.settings.updateFps or 24)
    if now() - lastApply < 1000 / fps then
        -- Between updates, hold the last facing so local mouse input can't turn the view.
        if lastApplied then applyFacing(player, lastApplied) end
        return
    end
    lastApply = now()
    local sample = sampleAt(now() - (BodyCam.settings.delayMs or 0))
    if sample then pinTo(player, sample) end
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

-- Remote players are interpolated, and the server position we compare against is
-- up to a couple of seconds old, so a moving target always "drifts" from it.
-- Only treat the local copy as stale if it has stopped updating.
local function isLocalCopyStale(s, target)
    local tx, ty = target:getX(), target:getY()
    local last = s.lastTargetPos
    if not last or last.name ~= s.targetName or math.abs(last.x - tx) > 0.01 or math.abs(last.y - ty) > 0.01 then
        s.lastTargetPos = { name = s.targetName, x = tx, y = ty, time = now() }
        return false
    end
    if now() - last.time < STALE_MS or not s.serverPos then return false end
    local dx = s.serverPos.x - tx
    local dy = s.serverPos.y - ty
    return math.sqrt(dx * dx + dy * dy) > DRIFT_DISTANCE
end

local lastReason = nil
local function setLost(s, lost, reason)
    if lost then
        s.lostSince = s.lostSince or now()
        if reason ~= lastReason then
            BodyCam.log("Signal lost: " .. reason)
            lastReason = reason
        end
    else
        if s.lostSince and lastReason then BodyCam.log("Signal recovered") end
        s.lostSince = nil
        lastReason = nil
    end
    s.signalLost = s.lostSince ~= nil and now() - s.lostSince > LOST_GRACE_MS
end

local function followTick()
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
    local reason = nil
    if not target then
        reason = "target not synced to this client"
    elseif not target:getCurrentSquare() then
        reason = "target's area not loaded"
    elseif player:DistTo(target) >= NEAR_DISTANCE then
        reason = string.format("target %.0f tiles away", player:DistTo(target))
    elseif isLocalCopyStale(s, target) then
        reason = "local copy of target stopped updating"
    end

    if not reason then
        if target:isDead() then
            setLost(s, true, "target is dead")
        else
            setLost(s, false)
        end
        recordSample(target)
        applyDelayed(player)
    elseif s.serverPos then
        setLost(s, true, reason)
        local dx = s.serverPos.x - player:getX()
        local dy = s.serverPos.y - player:getY()
        if math.sqrt(dx * dx + dy * dy) > 2 or math.floor(player:getZ()) ~= math.floor(s.serverPos.z) then
            BodyCam.clearSamples()
            teleportTo(s.serverPos.x, s.serverPos.y, s.serverPos.z)
        end
    else
        setLost(s, true, reason .. ", waiting for server position")
    end
end

-- Any error in the follow loop would otherwise repeat (and be logged) every tick.
local tickErrors = 0
local function onTick()
    if not BodyCam.state.active then return end
    local ok, err = pcall(followTick)
    if ok then
        tickErrors = 0
        return
    end
    tickErrors = tickErrors + 1
    if tickErrors == 1 then BodyCam.log("Follow error: " .. tostring(err)) end
    if tickErrors >= MAX_TICK_ERRORS then
        tickErrors = 0
        BodyCam.stop()
        BodyCam.say("Body Cam stopped after repeated errors - please send console.txt")
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
