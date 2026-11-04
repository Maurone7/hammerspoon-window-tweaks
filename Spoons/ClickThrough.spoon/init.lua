--- === ClickThrough ===
---
--- One click both activates an inactive app's window and clicks in it.
---
--- macOS normally spends the first click on an inactive app on activating it.
--- This Spoon holds the click, focuses the window under the mouse, then
--- replays the click. Cmd-click keeps its standard "click without activating"
--- behavior, and clicks on the Dock, menu bar, desktop, title bars and window
--- buttons are left alone.

local obj = {}
obj.__index = obj

obj.name = "ClickThrough"
obj.version = "1.1"
obj.author = "Maurone7"
obj.homepage = "https://github.com/Maurone7/hammerspoon-window-tweaks"
obj.license = "MIT - https://opensource.org/licenses/MIT"

--- ClickThrough.activationTimeout
--- Variable
--- Longest time, in seconds, to wait for the app to activate before replaying
--- the click anyway. Default 0.3.
obj.activationTimeout = 0.3

local types = hs.eventtap.event.types
local USER_DATA = hs.eventtap.event.properties.eventSourceUserData
local REPLAY_MARK = 0x7C11C4
-- Held clicks are released after this long even if the activation wait
-- never finishes, so a stuck wait can't swallow every click.
local FAILSAFE = 1
-- Elements whose first click already works natively.
local NATIVE_SUBROLES = {
  AXCloseButton = true,
  AXMinimizeButton = true,
  AXZoomButton = true,
  AXFullScreenButton = true,
}

local function now() return hs.timer.secondsSinceEpoch() end

-- The window itself (title bar, empty background), its title text and its
-- own buttons.
local function isWindowChrome(el)
  local role = el:attributeValue("AXRole")
  if role == "AXWindow" or NATIVE_SUBROLES[el:attributeValue("AXSubrole")] then return true end
  local parent = role == "AXStaticText" and el:attributeValue("AXParent")
  return parent and parent:attributeValue("AXRole") == "AXWindow" or false
end

local function frontmostPid()
  local app = hs.application.frontmostApplication()
  return app and app:pid()
end

local function inactiveWindowAt(point)
  local el = hs.axuielement.systemElementAtPosition(point)
  if not el then return nil end
  local pid = el:pid()
  if not pid or pid == frontmostPid() or pid == hs.processInfo.processID then return nil end
  -- Title bars and empty window background activate on the first click, and
  -- title-bar drags need the original event stream.
  if isWindowChrome(el) then return nil end
  local axWin = el:attributeValue("AXWindow")
  if not axWin or axWin:attributeValue("AXSubrole") ~= "AXStandardWindow" then return nil end
  return axWin:asHSWindow(), pid
end

--- ClickThrough:start()
--- Method
--- Starts making single clicks activate and click inactive windows.
---
--- Returns:
---  * The ClickThrough object
function obj:start()
  if self._tap then return self end
  local pending, pendingSince -- events held while the target app activates

  local function replay()
    if self._waitTimer then self._waitTimer:stop() end
    self._waitTimer = nil
    local events = pending or {}
    pending = nil
    for _, e in ipairs(events) do
      e:setProperty(USER_DATA, REPLAY_MARK)
      e:post()
    end
  end

  self._tap = hs.eventtap.new({ types.leftMouseDown, types.leftMouseDragged, types.leftMouseUp }, function(e)
    if e:getProperty(USER_DATA) == REPLAY_MARK then return false end
    if pending and now() - pendingSince > FAILSAFE then replay() end
    if pending then
      table.insert(pending, e:copy())
      return true
    end
    if e:getType() ~= types.leftMouseDown or e:getFlags().cmd then return false end

    local win, pid = inactiveWindowAt(e:location())
    if not win then return false end

    pending, pendingSince = { e:copy() }, now()
    win:focus()
    self._waitTimer = hs.timer.waitUntil(function()
      return frontmostPid() == pid or now() - pendingSince > self.activationTimeout
    end, replay, 0.01)
    return true
  end):start()

  -- macOS disables an event tap whose callback is too slow; turn it back on.
  self._watchdog = hs.timer.doEvery(5, function()
    if not self._tap:isEnabled() then self._tap:start() end
  end)
  return self
end

--- ClickThrough:stop()
--- Method
--- Restores the normal macOS first-click behavior.
---
--- Returns:
---  * The ClickThrough object
function obj:stop()
  for _, key in ipairs({ "_tap", "_watchdog", "_waitTimer" }) do
    if self[key] then self[key]:stop() end
    self[key] = nil
  end
  return self
end

return obj
