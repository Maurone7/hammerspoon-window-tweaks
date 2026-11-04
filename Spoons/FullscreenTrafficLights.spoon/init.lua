--- === FullscreenTrafficLights ===
---
--- Always-visible traffic-light buttons for fullscreen windows.
---
--- macOS hides the real close/minimize/fullscreen buttons in native fullscreen.
--- This Spoon draws working stand-ins on every fullscreen window currently on
--- screen, focused or not. Option-drag the buttons to move them; the position
--- is remembered per app. Option-double-click them to reset that app.

local obj = {}
obj.__index = obj

obj.name = "FullscreenTrafficLights"
obj.version = "1.3"
obj.author = "Maurone7"
obj.homepage = "https://github.com/Maurone7/hammerspoon-window-tweaks"
obj.license = "MIT - https://opensource.org/licenses/MIT"

--- FullscreenTrafficLights.size
--- Variable
--- Diameter of each button, in points. Default 12.
obj.size = 12

--- FullscreenTrafficLights.gap
--- Variable
--- Space between buttons, in points. Default 8.
obj.gap = 8

--- FullscreenTrafficLights.defaultOffset
--- Variable
--- Position of the buttons relative to the window's top-left corner, used
--- until they are Option-dragged elsewhere. Default { x = 12, y = 10 }.
obj.defaultOffset = { x = 12, y = 10 }

--- FullscreenTrafficLights.interval
--- Variable
--- Seconds between position updates of the buttons already shown. Default 0.5.
obj.interval = 0.5

--- FullscreenTrafficLights.scanInterval
--- Variable
--- Seconds between full scans for new fullscreen windows. Entering or leaving
--- fullscreen switches Spaces, which triggers a scan right away; this is only
--- a fallback. Default 3.
obj.scanInterval = 3

local SETTINGS_KEY = "fullscreenTrafficLights.offsets"
local ORDER = { "close", "minimize", "fullscreen" }
local COLORS = {
  close = { red = 1.00, green = 0.37, blue = 0.34 },
  minimize = { red = 1.00, green = 0.74, blue = 0.18 },
  fullscreen = { red = 0.16, green = 0.79, blue = 0.25 },
}
local GLYPHS = { close = "×", minimize = "−", fullscreen = "↙" }

-- One-shot timers are kept here so they can't be garbage-collected before
-- they fire.
local timers = {} -- luacheck: ignore 241

local function waitThen(predicate, action, timeout)
  local deadline = hs.timer.secondsSinceEpoch() + timeout
  local timer
  timer = hs.timer.waitUntil(function()
    return predicate() or hs.timer.secondsSinceEpoch() > deadline
  end, function()
    timers[timer] = nil
    action()
  end, 0.05)
  timers[timer] = true
end

local ACTIONS = {
  close = function(win) win:close() end,
  minimize = function(win)
    -- macOS can't minimize a fullscreen window, so leave fullscreen first and
    -- minimize once the exit animation has finished.
    win:setFullScreen(false)
    waitThen(function() return not win:isFullScreen() end, function()
      waitThen(function() return false end, function() win:minimize() end, 0.3)
    end, 3)
  end,
  fullscreen = function(win) win:setFullScreen(false) end,
}

local function appKey(win)
  local app = win:application()
  return app and (app:bundleID() or app:name()) or "?"
end

local function setGlyphAlpha(canvas, alpha)
  for _, name in ipairs(ORDER) do
    canvas[name .. "_glyph"].textColor = { white = 0, alpha = alpha }
  end
end

function obj:_offsetFor(win)
  return self._offsets[appKey(win)] or self.defaultOffset
end

-- Where the buttons go on `win`, kept inside its screen in case the saved
-- offset came from a larger display.
function obj:_positionFor(win)
  local f, off = win:frame(), self:_offsetFor(win)
  local s = win:screen():fullFrame()
  local w, h = 3 * self.size + 2 * self.gap, self.size
  return {
    x = math.max(s.x, math.min(f.x + off.x, s.x + s.w - w)),
    y = math.max(s.y, math.min(f.y + off.y, s.y + s.h - h)),
  }
end

function obj:_startDrag(overlay)
  local types = hs.eventtap.event.types
  local canvas, win = overlay.canvas, overlay.win
  local start, origin = hs.mouse.absolutePosition(), canvas:topLeft()
  self._dragTap = hs.eventtap.new({ types.leftMouseDragged, types.leftMouseUp }, function(e)
    local p = hs.mouse.absolutePosition()
    local pos = { x = origin.x + p.x - start.x, y = origin.y + p.y - start.y }
    canvas:topLeft(pos)
    if e:getType() == types.leftMouseUp then
      self._dragTap:stop()
      self._dragTap = nil
      local f = win:frame()
      self._offsets[appKey(win)] = { x = pos.x - f.x, y = pos.y - f.y }
      hs.settings.set(SETTINGS_KEY, self._offsets)
      win:focus()
    end
    return false
  end):start()
end

function obj:_newOverlay(win)
  local size, gap = self.size, self.gap
  local overlay = { win = win }
  local canvas = hs.canvas.new({ x = 0, y = 0, w = 3 * size + 2 * gap, h = size })
  canvas:level(hs.canvas.windowLevels.overlay)
  -- Not "canJoinAllSpaces": the canvas stays on its fullscreen window's Space
  -- and slides away with it when switching Spaces.
  canvas:behaviorAsLabels({ "fullScreenAuxiliary" })

  for i, name in ipairs(ORDER) do
    local x = (i - 1) * (size + gap)
    canvas:appendElements({
      id = name,
      type = "circle",
      center = { x = x + size / 2, y = size / 2 },
      radius = size / 2 - 0.5,
      action = "strokeAndFill",
      fillColor = COLORS[name],
      strokeColor = { white = 0, alpha = 0.15 },
      strokeWidth = 0.5,
      trackMouseDown = true,
      trackMouseUp = true,
    }, {
      id = name .. "_glyph",
      type = "text",
      frame = { x = x, y = -1.5, w = size, h = size + 2 },
      text = GLYPHS[name],
      textAlignment = "center",
      textSize = size * 5 / 6,
      textColor = { white = 0, alpha = 0 },
    })
  end

  canvas:canvasMouseEvents(true, true, true)
  canvas:mouseCallback(function(_, event, id)
    if event == "mouseEnter" then
      setGlyphAlpha(canvas, 0.6)
    elseif event == "mouseExit" then
      setGlyphAlpha(canvas, 0)
    elseif event == "mouseDown" then
      overlay.dragMode = hs.eventtap.checkKeyboardModifiers().alt
      if not overlay.dragMode then return end
      local now = hs.timer.secondsSinceEpoch()
      if now - (overlay.lastAltDown or -math.huge) < hs.eventtap.doubleClickInterval() then
        overlay.lastAltDown = nil
        self:resetPosition(overlay.win)
      elseif not self._dragTap then
        overlay.lastAltDown = now
        self:_startDrag(overlay)
      end
    elseif event == "mouseUp" then
      if overlay.dragMode then
        overlay.dragMode = false
      elseif ACTIONS[id] then
        ACTIONS[id](overlay.win)
      end
    end
  end)

  overlay.canvas = canvas
  return overlay
end

function obj:_place(overlay)
  overlay.canvas:topLeft(self:_positionFor(overlay.win))
  if not overlay.canvas:isShowing() then overlay.canvas:show() end
end

function obj:_remove(id)
  self._overlays[id].canvas:delete()
  self._overlays[id] = nil
end

-- Full scan: listing every on-screen window is the expensive part.
function obj:_scan()
  if self._dragTap then return end
  local overlays, seen = self._overlays, {}
  for _, win in ipairs(hs.window.orderedWindows()) do
    if win:isFullScreen() then
      local id = win:id()
      local overlay = overlays[id] or self:_newOverlay(win)
      overlays[id], seen[id], overlay.win = overlay, true, win
      self:_place(overlay)
    end
  end
  for id in pairs(overlays) do
    if not seen[id] then self:_remove(id) end
  end
end

-- Cheap refresh of the windows that already have buttons.
function obj:_refresh()
  if self._dragTap then return end
  for id, overlay in pairs(self._overlays) do
    if overlay.win:isFullScreen() then
      self:_place(overlay)
    else
      self:_remove(id)
    end
  end
end

--- FullscreenTrafficLights:start()
--- Method
--- Starts showing buttons on fullscreen windows.
---
--- Returns:
---  * The FullscreenTrafficLights object
function obj:start()
  if self._timer then return self end
  self._offsets = hs.settings.get(SETTINGS_KEY) or {}
  self._overlays = {}
  self._timer = hs.timer.doEvery(self.interval, function() self:_refresh() end)
  self._scanTimer = hs.timer.doEvery(self.scanInterval, function() self:_scan() end)
  local function scanSoon()
    if self._spacesTimer then self._spacesTimer:stop() end
    self._spacesTimer = hs.timer.doAfter(0.05, function() self:_scan() end)
  end
  self._spacesWatcher = hs.spaces.watcher.new(scanSoon):start()
  self._screenWatcher = hs.screen.watcher.new(scanSoon):start()
  self:_scan()
  return self
end

--- FullscreenTrafficLights:stop()
--- Method
--- Stops and removes all buttons.
---
--- Returns:
---  * The FullscreenTrafficLights object
function obj:stop()
  if not self._timer then return self end
  for _, key in ipairs({ "_timer", "_scanTimer", "_spacesWatcher", "_screenWatcher", "_spacesTimer", "_dragTap" }) do
    if self[key] then self[key]:stop() end
    self[key] = nil
  end
  for _, overlay in pairs(self._overlays) do overlay.canvas:delete() end
  self._overlays = nil
  return self
end

--- FullscreenTrafficLights:resetPositions()
--- Method
--- Forgets all Option-dragged positions, moving every app's buttons back to
--- `defaultOffset`.
---
--- Returns:
---  * The FullscreenTrafficLights object
function obj:resetPositions()
  self._offsets = {}
  hs.settings.clear(SETTINGS_KEY)
  self:_placeAll()
  return self
end

--- FullscreenTrafficLights:resetPosition(win)
--- Method
--- Forgets the Option-dragged position for the app that owns `win`, moving
--- its buttons back to `defaultOffset`. Option-double-clicking the buttons
--- does the same.
---
--- Parameters:
---  * win - an `hs.window` of the app to reset
---
--- Returns:
---  * The FullscreenTrafficLights object
function obj:resetPosition(win)
  self._offsets = self._offsets or hs.settings.get(SETTINGS_KEY) or {}
  self._offsets[appKey(win)] = nil
  hs.settings.set(SETTINGS_KEY, self._offsets)
  self:_placeAll()
  return self
end

--- FullscreenTrafficLights:isRunning()
--- Method
--- Whether the Spoon is started.
---
--- Returns:
---  * A boolean
function obj:isRunning()
  return self._timer ~= nil
end

function obj:_placeAll()
  for _, overlay in pairs(self._overlays or {}) do self:_place(overlay) end
end

return obj
