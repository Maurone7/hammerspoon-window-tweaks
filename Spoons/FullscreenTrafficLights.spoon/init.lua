--- === FullscreenTrafficLights ===
---
--- Always-visible traffic-light buttons for fullscreen windows.
---
--- macOS hides the real close/minimize/fullscreen buttons in native fullscreen.
--- This Spoon draws working stand-ins on every fullscreen window currently on
--- screen, focused or not. Option-drag the buttons to move them; the position
--- is remembered per app.

local obj = {}
obj.__index = obj

obj.name = "FullscreenTrafficLights"
obj.version = "1.1"
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
--- Seconds between checks for fullscreen windows. Default 0.5.
obj.interval = 0.5

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
local timers = {}

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
      if overlay.dragMode and not self._dragTap then self:_startDrag(overlay) end
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

function obj:_update()
  if self._dragTap then return end
  local overlays, seen = self._overlays, {}
  for _, win in ipairs(hs.window.orderedWindows()) do
    if win:isFullScreen() then
      local id = win:id()
      local overlay = overlays[id] or self:_newOverlay(win)
      overlays[id], seen[id], overlay.win = overlay, true, win
      overlay.canvas:topLeft(self:_positionFor(win))
      overlay.canvas:show()
    end
  end
  for id, overlay in pairs(overlays) do
    if not seen[id] then
      overlay.canvas:delete()
      overlays[id] = nil
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
  self._timer = hs.timer.doEvery(self.interval, function() self:_update() end)
  self._spacesWatcher = hs.spaces.watcher.new(function()
    if self._spacesTimer then self._spacesTimer:stop() end
    self._spacesTimer = hs.timer.doAfter(0.05, function() self:_update() end)
  end):start()
  self:_update()
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
  for _, key in ipairs({ "_timer", "_spacesWatcher", "_spacesTimer", "_dragTap" }) do
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
  return self
end

return obj
