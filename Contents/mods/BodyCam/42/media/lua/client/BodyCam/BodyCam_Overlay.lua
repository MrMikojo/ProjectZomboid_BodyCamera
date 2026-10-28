-- Body Cam: on-screen overlay (REC indicator, unit label, in-game timestamp).
-- Drawn as small corner text only, so it never blocks mouse input.

require "ISUI/ISUIElement"
require "BodyCam/BodyCam_Client"

BodyCamOverlay = ISUIElement:derive("BodyCamOverlay")

local FONT = UIFont.Medium

function BodyCamOverlay:new()
    local w, h = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = ISUIElement.new(self, 0, 0, w, h)
    o.anchorRight = true
    o.anchorBottom = true
    return o
end

function BodyCamOverlay:initialise()
    ISUIElement.initialise(self)
    if self.javaObject and self.javaObject.setConsumeMouseEvents then
        pcall(self.javaObject.setConsumeMouseEvents, self.javaObject, false)
    end
end

-- Never claim the mouse, even though the element spans the screen.
function BodyCamOverlay:isMouseOver() return false end
function BodyCamOverlay:onMouseDown() return false end
function BodyCamOverlay:onMouseUp() return false end
function BodyCamOverlay:onRightMouseDown() return false end
function BodyCamOverlay:onRightMouseUp() return false end
function BodyCamOverlay:onMouseWheel() return false end

local function pad2(n)
    n = math.floor(n)
    if n < 10 then return "0" .. n end
    return tostring(n)
end

local function timestamp()
    local gt = getGameTime()
    if not gt then return "" end
    return string.format("%d-%s-%s  %s:%s",
        gt:getYear(), pad2(gt:getMonth() + 1), pad2(gt:getDay() + 1),
        pad2(gt:getHour()), pad2(gt:getMinutes()))
end

function BodyCamOverlay:prerender() end

function BodyCamOverlay:render()
    if not BodyCam.settings.overlay or not BodyCam.isActive() then return end

    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    if self.width ~= sw or self.height ~= sh then
        self:setWidth(sw); self:setHeight(sh)
    end

    local tm = getTextManager()
    local fh = tm:getFontHeight(FONT)
    local margin = 24

    -- Blinking REC dot, top-left.
    local blinkOn = math.floor(getTimestampMs() / 600) % 2 == 0
    if blinkOn then
        self:drawRect(margin, margin + fh / 2 - 6, 12, 12, 1, 0.9, 0.1, 0.1)
    end
    self:drawText("REC", margin + 20, margin, 1, 1, 1, 0.95, FONT)
    self:drawText(BodyCam.settings.unitLabel or "", margin, margin + fh + 2, 1, 1, 1, 0.85, FONT)

    -- Timestamp, top-right.
    local ts = timestamp()
    local tw = tm:MeasureStringX(FONT, ts)
    self:drawText(ts, sw - margin - tw, margin, 1, 1, 1, 0.95, FONT)

    if BodyCam.state.signalLost then
        local msg = "SIGNAL LOST"
        local mw = tm:MeasureStringX(UIFont.Large, msg)
        self:drawText(msg, (sw - mw) / 2, sh / 2 - 40, 1, 0.3, 0.3, 0.9, UIFont.Large)
    end
end

BodyCam.Overlay = {}

function BodyCam.Overlay.show()
    if not BodyCam.Overlay.instance then
        local o = BodyCamOverlay:new()
        o:initialise()
        o:addToUIManager()
        o:backMost()
        BodyCam.Overlay.instance = o
    end
    BodyCam.Overlay.instance:setVisible(true)
end

function BodyCam.Overlay.hide()
    if BodyCam.Overlay.instance then
        BodyCam.Overlay.instance:setVisible(false)
    end
end
