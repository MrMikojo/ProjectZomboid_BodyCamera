-- Body Cam: shared constants and helpers (loaded on client and server).

BodyCam = BodyCam or {}

BodyCam.MODULE = "BodyCam"

-- Access levels that may use the body cam. Compared lower-case.
BodyCam.ALLOWED_ACCESS = {
    admin = true,
    moderator = true,
    overseer = true,
    gm = true,
}

function BodyCam.isAllowed(player)
    if not player then return false end
    -- Single player: allow so the UI can be tested locally.
    if not isClient() and not isServer() then return true end
    local level = player:getAccessLevel()
    if not level then return false end
    return BodyCam.ALLOWED_ACCESS[string.lower(tostring(level))] == true
end

function BodyCam.log(msg)
    print("[BodyCam] " .. tostring(msg))
end
