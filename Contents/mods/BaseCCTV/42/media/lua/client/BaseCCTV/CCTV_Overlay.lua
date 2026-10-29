-- Base CCTV: on-screen overlay while viewing (REC, camera name, timestamp, controls).

require "ISUI/ISUIElement"
require "BaseCCTV/CCTV_Client"

BaseCCTVOverlay = ISUIElement:derive("BaseCCTVOverlay")

local FONT = UIFont.Medium

function BaseCCTVOverlay:new()
    local o = ISUIElement.new(self, 0, 0, getCore():getScreenWidth(), getCore():getScreenHeight())
    o.anchorRight = true
    o.anchorBottom = true
    return o
end

function BaseCCTVOverlay:initialise()
    ISUIElement.initialise(self)
    if self.javaObject and self.javaObject.setConsumeMouseEvents then
        pcall(self.javaObject.setConsumeMouseEvents, self.javaObject, false)
    end
end

function BaseCCTVOverlay:isMouseOver() return false end
function BaseCCTVOverlay:onMouseDown() return false end
function BaseCCTVOverlay:onMouseUp() return false end
function BaseCCTVOverlay:onRightMouseDown() return false end
function BaseCCTVOverlay:onRightMouseUp() return false end
function BaseCCTVOverlay:onMouseWheel() return false end

local function pad2(n)
    n = math.floor(n)
    return n < 10 and ("0" .. n) or tostring(n)
end

local function timestamp()
    local gt = getGameTime()
    if not gt then return "" end
    return string.format("%d-%s-%s  %s:%s", gt:getYear(), pad2(gt:getMonth() + 1), pad2(gt:getDay() + 1),
        pad2(gt:getHour()), pad2(gt:getMinutes()))
end

function BaseCCTVOverlay:prerender() end

function BaseCCTVOverlay:render()
    local v = BaseCCTV.view
    if not v.active then return end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    if self.width ~= sw or self.height ~= sh then
        self:setWidth(sw); self:setHeight(sh)
    end
    local tm = getTextManager()
    local fh = tm:getFontHeight(FONT)
    local margin = 24
    local cam = BaseCCTV.cameras[v.index]

    if math.floor(getTimestampMs() / 600) % 2 == 0 then
        self:drawRect(margin, margin + fh / 2 - 6, 12, 12, 1, 0.9, 0.1, 0.1)
    end
    self:drawText("REC", margin + 20, margin, 1, 1, 1, 0.95, FONT)
    local label = string.format("%s  (%d/%d)", cam and cam.name or "?", v.index, #BaseCCTV.cameras)
    self:drawText(label, margin, margin + fh + 2, 1, 1, 1, 0.9, FONT)

    local ts = timestamp()
    self:drawText(ts, sw - margin - tm:MeasureStringX(FONT, ts), margin, 1, 1, 1, 0.95, FONT)

    local help = "Arrows: look    +/-: zoom    , . : switch camera    Backspace: exit"
    local hw = tm:MeasureStringX(UIFont.Small, help)
    self:drawText(help, (sw - hw) / 2, sh - margin - 16, 1, 1, 1, 0.7, UIFont.Small)
end

BaseCCTV.Overlay = {}

function BaseCCTV.Overlay.show()
    if not BaseCCTV.Overlay.instance then
        local o = BaseCCTVOverlay:new()
        o:initialise()
        o:addToUIManager()
        o:backMost()
        BaseCCTV.Overlay.instance = o
    end
    BaseCCTV.Overlay.instance:setVisible(true)
end

function BaseCCTV.Overlay.hide()
    if BaseCCTV.Overlay.instance then
        BaseCCTV.Overlay.instance:setVisible(false)
    end
end
