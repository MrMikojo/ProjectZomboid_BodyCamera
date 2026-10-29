-- Body Cam: server side.
-- Remote players far away from a client are not synced to that client, so the
-- server (which knows everyone's position) answers "where is X?" requests.

if isClient() then return end

require "BodyCam/BodyCam_Shared"

local function findPlayer(username)
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

local function describe(p)
    local fullName = ""
    local desc = p:getDescriptor()
    if desc then
        fullName = (desc:getForename() or "") .. " " .. (desc:getSurname() or "")
    end
    return {
        username = p:getUsername(),
        fullName = fullName,
        x = p:getX(),
        y = p:getY(),
        z = p:getZ(),
        dead = p:isDead(),
    }
end

local Commands = {}

function Commands.list(player, args)
    local result = {}
    local players = getOnlinePlayers()
    if players then
        for i = 0, players:size() - 1 do
            local p = players:get(i)
            if p then
                table.insert(result, describe(p))
            end
        end
    end
    sendServerCommand(player, BodyCam.MODULE, "list", { players = result })
end

function Commands.locate(player, args)
    local username = args and args.username
    if not username then return end
    local target = findPlayer(username)
    if target then
        local info = describe(target)
        info.found = true
        sendServerCommand(player, BodyCam.MODULE, "locate", info)
    else
        sendServerCommand(player, BodyCam.MODULE, "locate", { username = username, found = false })
    end
end

local function onClientCommand(module, command, player, args)
    if module ~= BodyCam.MODULE then return end
    if not BodyCam.isAllowed(player) then
        BodyCam.log("Rejected '" .. tostring(command) .. "' from " .. tostring(player and player:getUsername()) .. " (role: " .. tostring(player and BodyCam.getRoleName(player)) .. ")")
        if player then
            sendServerCommand(player, BodyCam.MODULE, "denied", { role = tostring(BodyCam.getRoleName(player)) })
        end
        return
    end
    local handler = Commands[command]
    if handler then
        handler(player, args)
    end
end

Events.OnClientCommand.Add(onClientCommand)

BodyCam.log("Server module loaded")
