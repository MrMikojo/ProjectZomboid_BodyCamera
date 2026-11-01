-- Base CCTV (test build): view CCTV cameras through Project Viewpoint's 3D camera.
--
-- The Java add-on (BaseCCTV.jar, loaded by ZombieBuddy) exposes BaseCCTVJava, which
-- moves Viewpoint's camera to a position and angle. This file decides where:
-- test cameras are placed by right-click, and viewing starts from a computer.

BaseCCTV = BaseCCTV or {}

BaseCCTV.cameras = BaseCCTV.cameras or {}   -- { name, x, y, z, yaw } (test cameras, this session only)

BaseCCTV.view = {
    active = false,
    index = 1,
    yaw = 0, pitch = -25, fov = 70,
    startX = 0, startY = 0, startHealth = nil,
    startedAt = 0, startFrames = 0,
}

local PITCH_MIN, PITCH_MAX = -80, 15
local FOV_MIN, FOV_MAX = 30, 90
local TURN_SPEED = 60         -- degrees per second
local ZOOM_SPEED = 30         -- degrees of FOV per second
local MOVE_LIMIT = 1.5        -- tiles the viewer may drift from where they started
local CEILING_OFFSET = 0.8    -- camera height inside the level (0 = floor, 1 = next floor)

local lastTick = nil

local function now()
    return getTimestampMs()
end

function BaseCCTV.log(msg)
    print("[BaseCCTV] " .. tostring(msg))
end

function BaseCCTV.say(msg)
    local player = getPlayer()
    if player then pcall(player.setHaloNote, player, msg, 255, 200, 80, 300) end
    BaseCCTV.log(msg)
end

local function javaReady()
    return BaseCCTVJava ~= nil and BaseCCTVJava.setView ~= nil
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- Key constants are looked up by name so a missing one can't break the tick.
local function keyDown(...)
    for _, name in ipairs({ ... }) do
        local code = Keyboard[name]
        if code and isKeyDown(code) then return true end
    end
    return false
end

local function isKey(key, name)
    return Keyboard[name] ~= nil and key == Keyboard[name]
end

-- Keep yaw in 0..360 so it can spin all the way round without growing.
local function wrapYaw(a)
    return a % 360
end

----------------------------------------------------------------------------
-- Computers
----------------------------------------------------------------------------

-- Sprite and object names only: property lookups throw on some Build 42 objects,
-- and Viewpoint builds this menu in the background, so errors here add up fast.
function BaseCCTV.describe(obj)
    local spriteName, objectName = "?", "?"
    if obj and obj.getSprite then
        local sprite = obj:getSprite()
        if sprite and sprite.getName then spriteName = tostring(sprite:getName()) end
    end
    if obj and obj.getObjectName then objectName = tostring(obj:getObjectName()) end
    return spriteName, objectName
end

function BaseCCTV.isComputer(obj)
    if not obj then return false end
    local spriteName, objectName = BaseCCTV.describe(obj)
    spriteName, objectName = string.lower(spriteName), string.lower(objectName)
    return string.find(spriteName, "appliances_com_01", 1, true) ~= nil
        or string.find(spriteName, "computer", 1, true) ~= nil
        or string.find(objectName, "computer", 1, true) ~= nil
end

----------------------------------------------------------------------------
-- Viewing
----------------------------------------------------------------------------

local function currentCamera()
    return BaseCCTV.cameras[BaseCCTV.view.index]
end

local function aimAt(index)
    local v = BaseCCTV.view
    v.index = index
    local cam = currentCamera()
    if cam then
        -- Each camera remembers where it was last pointed.
        v.yaw = cam.lookYaw or cam.yaw
        v.pitch = cam.lookPitch or -25
    end
end

function BaseCCTV.start()
    local player = getPlayer()
    if not player then return end
    if not javaReady() then
        BaseCCTV.say("CCTV: Java add-on not loaded. Check ZombieBuddy approved BaseCCTV, then restart the game.")
        return
    end
    if #BaseCCTV.cameras == 0 then
        BaseCCTV.say("CCTV: no cameras yet. Right-click a floor tile > CCTV (test) > Add test camera here.")
        return
    end
    local status = BaseCCTVJava.getStatus()
    if status ~= "ok" then
        BaseCCTV.say("CCTV: Java add-on is off (" .. tostring(status) .. ")")
        return
    end
    local v = BaseCCTV.view
    v.active = true
    v.startX, v.startY = player:getX(), player:getY()
    local okHealth, health = pcall(player.getHealth, player)
    v.startHealth = okHealth and health or nil
    v.startedAt = now()
    v.startFrames = BaseCCTVJava.getFrames()
    lastTick = nil
    aimAt(clamp(v.index, 1, #BaseCCTV.cameras))
    if BaseCCTV.Overlay then BaseCCTV.Overlay.show() end
    BaseCCTV.log("Viewing started, " .. #BaseCCTV.cameras .. " camera(s), Java " .. tostring(BaseCCTVJava.getVersion()))
end

function BaseCCTV.stop(reason)
    local v = BaseCCTV.view
    if not v.active then return end
    v.active = false
    if javaReady() then BaseCCTVJava.clearView() end
    if BaseCCTV.Overlay then BaseCCTV.Overlay.hide() end
    BaseCCTV.say(reason and ("CCTV: " .. reason) or "CCTV: stopped viewing")
end

function BaseCCTV.switch(step)
    local n = #BaseCCTV.cameras
    if n == 0 then return end
    aimAt((BaseCCTV.view.index - 1 + step) % n + 1)
end

local function viewTick()
    local v = BaseCCTV.view
    if not v.active then return end
    local player = getPlayer()
    if not player or player:isDead() then
        BaseCCTV.stop("viewer died")
        return
    end
    local cam = currentCamera()
    if not cam then
        BaseCCTV.stop("camera missing")
        return
    end

    -- Leave the camera view if the viewer walks off or gets hurt.
    local dx, dy = player:getX() - v.startX, player:getY() - v.startY
    if dx * dx + dy * dy > MOVE_LIMIT * MOVE_LIMIT then
        BaseCCTV.stop("you moved away from the screen")
        return
    end
    if v.startHealth then
        local ok, health = pcall(player.getHealth, player)
        if ok and health and health < v.startHealth - 0.001 then
            BaseCCTV.stop("you were hurt")
            return
        end
    end

    -- Java health checks.
    local status = BaseCCTVJava.getStatus()
    if status ~= "ok" then
        BaseCCTV.stop("Java add-on switched off (" .. tostring(status) .. ")")
        return
    end
    if now() - v.startedAt > 1500 and BaseCCTVJava.getFrames() == v.startFrames then
        BaseCCTV.stop("Viewpoint's 3D view isn't running. Switch to first person (O) and try again")
        return
    end

    -- Look around with the arrow keys, zoom with +/-.
    local t = now()
    local dt = lastTick and math.min(0.1, (t - lastTick) / 1000) or 0
    lastTick = t
    if keyDown("KEY_LEFT") then v.yaw = v.yaw - TURN_SPEED * dt end
    if keyDown("KEY_RIGHT") then v.yaw = v.yaw + TURN_SPEED * dt end
    if keyDown("KEY_UP") then v.pitch = v.pitch + TURN_SPEED * dt end
    if keyDown("KEY_DOWN") then v.pitch = v.pitch - TURN_SPEED * dt end
    if keyDown("KEY_ADD", "KEY_EQUALS") then v.fov = v.fov - ZOOM_SPEED * dt end
    if keyDown("KEY_SUBTRACT", "KEY_MINUS") then v.fov = v.fov + ZOOM_SPEED * dt end
    v.yaw = wrapYaw(v.yaw)
    v.pitch = clamp(v.pitch, PITCH_MIN, PITCH_MAX)
    cam.lookYaw, cam.lookPitch = v.yaw, v.pitch
    v.fov = clamp(v.fov, FOV_MIN, FOV_MAX)

    BaseCCTVJava.setView(cam.x, cam.y, cam.z, v.yaw, v.pitch, v.fov)
end

-- An error here would otherwise repeat (and be logged) every tick.
local function onTick()
    if not BaseCCTV.view.active then return end
    local ok, err = pcall(viewTick)
    if not ok then
        BaseCCTV.log("view error: " .. tostring(err))
        BaseCCTV.stop("error, see console.txt")
    end
end

local function onKeyPressed(key)
    if not BaseCCTV.view.active then return end
    if isKey(key, "KEY_BACK") then
        BaseCCTV.stop()
    elseif isKey(key, "KEY_COMMA") then
        BaseCCTV.switch(-1)
    elseif isKey(key, "KEY_PERIOD") then
        BaseCCTV.switch(1)
    end
end

----------------------------------------------------------------------------
-- Test cameras
----------------------------------------------------------------------------

function BaseCCTV.addTestCamera(square)
    local player = getPlayer()
    if not square or not player then return end
    local x, y = square:getX() + 0.5, square:getY() + 0.5
    local yaw = math.deg(math.atan2(player:getY() - y, player:getX() - x))
    local cam = {
        name = "CAM " .. (#BaseCCTV.cameras + 1),
        x = x, y = y, z = square:getZ() + CEILING_OFFSET,
        yaw = yaw,
    }
    table.insert(BaseCCTV.cameras, cam)
    BaseCCTV.say(string.format("CCTV: %s added at %d,%d,%d facing %d deg", cam.name,
        square:getX(), square:getY(), square:getZ(), math.floor(yaw + 0.5)))
end

function BaseCCTV.clearTestCameras()
    BaseCCTV.stop()
    BaseCCTV.cameras = {}
    BaseCCTV.view.index = 1
    BaseCCTV.say("CCTV: test cameras removed")
end

----------------------------------------------------------------------------
-- Context menu
----------------------------------------------------------------------------

local function onFillWorldObjectContextMenu(playerNum, context, worldObjects, test)
    if test then return end
    local computer, square = nil, nil
    for _, obj in ipairs(worldObjects) do
        square = square or (obj.getSquare and obj:getSquare())
        if not computer and BaseCCTV.isComputer(obj) then computer = obj end
    end

    if BaseCCTV.view.active then
        context:addOption("CCTV: stop viewing", nil, BaseCCTV.stop)
    elseif computer then
        context:addOption("View Cameras", nil, BaseCCTV.start)
    end

    -- Test helpers (removed once cameras can be crafted and installed).
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(context:addOption("CCTV (test)"), sub)
    if square then
        sub:addOption("Add test camera here", square, BaseCCTV.addTestCamera)
    end
    sub:addOption("View cameras (without a computer)", nil, BaseCCTV.start)
    if #BaseCCTV.cameras > 0 then
        sub:addOption("Remove all test cameras", nil, BaseCCTV.clearTestCameras)
    end
    if javaReady() and BaseCCTVJava.setMoveCentre then
        local on = BaseCCTVJava.getMoveCentre()
        sub:addOption("Sound test: move world centre with camera (" .. (on and "ON" or "OFF") .. ")", nil, function()
            BaseCCTVJava.setMoveCentre(not on)
            BaseCCTV.say("CCTV: move world centre with camera " .. (on and "OFF" or "ON"))
        end)
    end
    sub:addOption("Log clicked objects", worldObjects, function(objs)
        for _, obj in ipairs(objs) do
            local spriteName, custom = BaseCCTV.describe(obj)
            BaseCCTV.log("object sprite=" .. spriteName .. " objectName=" .. custom
                .. " computer=" .. tostring(BaseCCTV.isComputer(obj)))
        end
        BaseCCTV.say("CCTV: object names written to console.txt")
    end)
end

local function onGameStart()
    BaseCCTV.log("client loaded; Java add-on " .. (javaReady()
        and ("found, version " .. tostring(BaseCCTVJava.getVersion()) .. ", status " .. tostring(BaseCCTVJava.getStatus()))
        or "NOT found"))
end

Events.OnTick.Add(onTick)
Events.OnKeyPressed.Add(onKeyPressed)
Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
Events.OnGameStart.Add(onGameStart)
