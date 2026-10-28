-- Body Cam: admin control window.
-- Open/close with the hotkey (default: Insert). Ctrl+Insert stops watching.

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISTickBox"
require "ISUI/ISScrollingListBox"
require "BodyCam/BodyCam_Client"

BodyCam.UI = BodyCam.UI or {}
BodyCam.UI.TOGGLE_KEY = Keyboard.KEY_INSERT

BodyCamWindow = ISPanel:derive("BodyCamWindow")

local FONT = UIFont.Small
local PAD = 10

local OPTIONS = {
    { key = "overlay",      label = "Show REC / timestamp overlay" },
    { key = "matchFacing",  label = "Match target's facing (vision cone)" },
    { key = "hideSelf",     label = "Hide my own character model" },
    { key = "autoZoom",     label = "Zoom in when starting" },
    { key = "returnOnStop", label = "Teleport back when stopping" },
    { key = "autoResume",   label = "Resume last target after login" },
}

function BodyCamWindow:new(x, y)
    local o = ISPanel.new(self, x, y, 340, 470)
    o.moveWithMouse = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.85 }
    o.borderColor = { r = 0.6, g = 0.1, b = 0.1, a = 1 }
    return o
end

function BodyCamWindow:createChildren()
    ISPanel.createChildren(self)
    local fh = getTextManager():getFontHeight(FONT)
    local y = PAD + fh + 6

    self.list = ISScrollingListBox:new(PAD, y, self.width - PAD * 2, 150)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = fh + 6
    self.list.font = FONT
    self.list.drawBorder = true
    self.list:setOnMouseDoubleClick(self, BodyCamWindow.onWatch)
    self:addChild(self.list)
    y = y + self.list.height + 6

    local bw = math.floor((self.width - PAD * 2 - 12) / 3)
    self.btnRefresh = ISButton:new(PAD, y, bw, 22, "Refresh", self, BodyCamWindow.onRefresh)
    self.btnWatch = ISButton:new(PAD + bw + 6, y, bw, 22, "Watch", self, BodyCamWindow.onWatch)
    self.btnStop = ISButton:new(PAD + (bw + 6) * 2, y, bw, 22, "Stop", self, BodyCamWindow.onStop)
    for _, b in ipairs({ self.btnRefresh, self.btnWatch, self.btnStop }) do
        b:initialise(); b:instantiate(); self:addChild(b)
    end
    y = y + 30

    self.tick = ISTickBox:new(PAD, y, self.width - PAD * 2, fh + 4, "", self, BodyCamWindow.onTick)
    self.tick:initialise()
    self.tick:instantiate()
    self:addChild(self.tick)
    for i, opt in ipairs(OPTIONS) do
        self.tick:addOption(opt.label)
        self.tick:setSelected(i, BodyCam.settings[opt.key] == true)
    end
    y = y + (fh + 6) * #OPTIONS + 8

    -- Forward offset: shifts the view ahead of the target, like a lens pointing forward.
    self.offsetY = y
    local sb = 26
    self.btnOffMinus = ISButton:new(self.width - PAD - sb * 2 - 4, y, sb, 20, "-", self, BodyCamWindow.onOffset)
    self.btnOffMinus.internal = -0.5
    self.btnOffPlus = ISButton:new(self.width - PAD - sb, y, sb, 20, "+", self, BodyCamWindow.onOffset)
    self.btnOffPlus.internal = 0.5
    y = y + 26
    self.zoomY = y
    self.btnZoomMinus = ISButton:new(self.width - PAD - sb * 2 - 4, y, sb, 20, "-", self, BodyCamWindow.onZoomSteps)
    self.btnZoomMinus.internal = -1
    self.btnZoomPlus = ISButton:new(self.width - PAD - sb, y, sb, 20, "+", self, BodyCamWindow.onZoomSteps)
    self.btnZoomPlus.internal = 1
    for _, b in ipairs({ self.btnOffMinus, self.btnOffPlus, self.btnZoomMinus, self.btnZoomPlus }) do
        b:initialise(); b:instantiate(); self:addChild(b)
    end
    y = y + 30

    self.statusY = y
    self.btnClose = ISButton:new(self.width - PAD - 70, self.height - PAD - 22, 70, 22, "Close", self, BodyCamWindow.close)
    self.btnClose:initialise(); self.btnClose:instantiate(); self:addChild(self.btnClose)
end

function BodyCamWindow:render()
    ISPanel.render(self)
    self:drawText("Body Cam - Admin Spectator", PAD, PAD, 1, 0.4, 0.4, 1, UIFont.Medium)
    self:drawText(string.format("Forward offset: %.1f tiles", BodyCam.settings.forwardOffset),
        PAD, self.offsetY + 2, 1, 1, 1, 0.9, FONT)
    self:drawText(string.format("Zoom-in steps on start: %d", BodyCam.settings.zoomSteps),
        PAD, self.zoomY + 2, 1, 1, 1, 0.9, FONT)

    local status
    if BodyCam.isActive() then
        status = "Watching: " .. tostring(BodyCam.state.targetName)
        if BodyCam.state.signalLost then status = status .. "  (locating...)" end
    else
        status = "Idle. Double-click a player or press Watch."
    end
    self:drawText(status, PAD, self.statusY, 0.8, 1, 0.8, 1, FONT)
    self:drawText("Insert: show/hide   Ctrl+Insert: stop", PAD, self.statusY + 18, 0.7, 0.7, 0.7, 1, FONT)
end

function BodyCamWindow:setPlayers(players)
    local selected = self.list.items[self.list.selected]
    local selectedName = selected and selected.item or nil
    self.list:clear()
    local me = getPlayer() and getPlayer():getUsername()
    table.sort(players, function(a, b) return tostring(a.username) < tostring(b.username) end)
    for _, p in ipairs(players) do
        if p.username ~= me then
            local label = p.username
            local fullName = p.fullName and p.fullName:gsub("^%s+", ""):gsub("%s+$", "") or ""
            if fullName ~= "" then label = label .. "  (" .. fullName .. ")" end
            if p.dead then label = label .. "  [dead]" end
            self.list:addItem(label, p.username)
        end
    end
    for i, item in ipairs(self.list.items) do
        if item.item == selectedName then self.list.selected = i end
    end
end

function BodyCamWindow:onRefresh()
    BodyCam.requestPlayerList()
end

function BodyCamWindow:onWatch()
    local item = self.list.items[self.list.selected]
    if item then BodyCam.start(item.item) end
end

function BodyCamWindow:onStop()
    BodyCam.stop()
end

function BodyCamWindow:onTick(index, selected)
    local opt = OPTIONS[index]
    if not opt then return end
    BodyCam.settings[opt.key] = selected
    BodyCam.saveSettings()
    if opt.key == "hideSelf" and not selected and getPlayer() then
        pcall(getPlayer().setAlphaAndTarget, getPlayer(), 0, 1)
    end
end

function BodyCamWindow:onOffset(button)
    local v = BodyCam.settings.forwardOffset + button.internal
    BodyCam.settings.forwardOffset = math.max(-3, math.min(5, v))
    BodyCam.saveSettings()
end

function BodyCamWindow:onZoomSteps(button)
    local v = BodyCam.settings.zoomSteps + button.internal
    BodyCam.settings.zoomSteps = math.max(0, math.min(6, v))
    BodyCam.saveSettings()
end

function BodyCamWindow:close()
    self:setVisible(false)
    self:removeFromUIManager()
    BodyCam.UI.instance = nil
end

----------------------------------------------------------------------------

function BodyCam.UI.toggle()
    if BodyCam.UI.instance then
        BodyCam.UI.instance:close()
        return
    end
    local player = getPlayer()
    if not player or not BodyCam.isAllowed(player) then return end
    local w = BodyCamWindow:new(100, 100)
    w:initialise()
    w:addToUIManager()
    w:bringToTop()
    BodyCam.UI.instance = w
    BodyCam.requestPlayerList()
end

function BodyCam.UI.onPlayerList(players)
    if BodyCam.UI.instance then
        BodyCam.UI.instance:setPlayers(players)
    end
end

local function onKeyPressed(key)
    if key ~= BodyCam.UI.TOGGLE_KEY then return end
    if isCtrlKeyDown() then
        BodyCam.stop()
    else
        BodyCam.UI.toggle()
    end
end

Events.OnKeyPressed.Add(onKeyPressed)
