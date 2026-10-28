-- Body Cam: shared constants and helpers (loaded on client and server).

BodyCam = BodyCam or {}

BodyCam.MODULE = "BodyCam"

-- Role / access level names that may use the body cam. Compared lower-case.
BodyCam.ALLOWED_ROLES = {
    admin = true,
    moderator = true,
    overseer = true,
    gm = true,
}

-- Build 42 uses roles, Build 41 used access levels; try both.
function BodyCam.getRoleName(player)
    local ok, role = pcall(function() return player:getRole() end)
    if ok and role then
        local okName, name = pcall(function() return role:getName() end)
        if okName and name then return string.lower(tostring(name)) end
        return string.lower(tostring(role))
    end
    local okLevel, level = pcall(function() return player:getAccessLevel() end)
    if okLevel and level then return string.lower(tostring(level)) end
    return nil
end

-- Usernames listed in the "BodyCam.AllowedUsers" sandbox option (comma separated).
-- Use this if your admin role has a custom name.
function BodyCam.isAllowListed(username)
    local vars = SandboxVars and SandboxVars.BodyCam
    local list = vars and vars.AllowedUsers
    if not list or list == "" or not username then return false end
    username = string.lower(username)
    for name in string.gmatch(list, "[^,;]+") do
        name = string.lower(string.gsub(string.gsub(name, "^%s+", ""), "%s+$", ""))
        if name == username then return true end
    end
    return false
end

function BodyCam.isAllowed(player)
    if not player then return false end
    -- Single player: allow so the UI can be tested locally.
    if not isClient() and not isServer() then return true end
    local role = BodyCam.getRoleName(player)
    if role and BodyCam.ALLOWED_ROLES[role] then return true end
    if BodyCam.isAllowListed(player:getUsername()) then return true end
    -- Client-side convenience check; the server still verifies every request.
    if isClient() and isAdmin then
        local ok, admin = pcall(isAdmin)
        if ok and admin then return true end
    end
    return false
end

function BodyCam.log(msg)
    print("[BodyCam] " .. tostring(msg))
end
