--- === ClickThrough ===
---
--- One click both activates an inactive app's window and clicks in it.
---
--- macOS normally spends the first click on an inactive app on activating it.
--- This Spoon holds the click, focuses the window under the mouse, then
--- replays the click. Cmd-click keeps its standard "click without activating"
--- behavior, and clicks on the Dock, menu bar and desktop are left alone.

local obj = {}
obj.__index = obj

obj.name = "ClickThrough"
obj.version = "1.0"
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

local function frontmostPid()
  local app = hs.application.frontmostApplication()
  return app and app:pid()
end

local function inactiveWindowAt(point)
  local el = hs.axuielement.systemElementAtPosition(point)
  if not el then return nil end
  local pid = el:pid()
  if not pid or pid == frontmostPid() or pid == hs.processInfo.processID then return nil end
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
  local pending -- clicks held while the target app activates

  local function replay()
    local events = pending
    pending = nil
    for _, e in ipairs(events) do
      e:setProperty(USER_DATA, REPLAY_MARK)
      e:post()
    end
  end

  self._tap = hs.eventtap.new({ types.leftMouseDown, types.leftMouseUp }, function(e)
    if e:getProperty(USER_DATA) == REPLAY_MARK then return false end
    if pending then
      table.insert(pending, e:copy())
      return true
    end
    if e:getType() ~= types.leftMouseDown or e:getFlags().cmd then return false end

    local win, pid = inactiveWindowAt(e:location())
    if not win then return false end

    pending = { e:copy() }
    win:focus()
    local started = hs.timer.secondsSinceEpoch()
    hs.timer.waitUntil(function()
      return frontmostPid() == pid
        or hs.timer.secondsSinceEpoch() - started > self.activationTimeout
    end, replay, 0.01)
    return true
  end):start()
  return self
end

--- ClickThrough:stop()
--- Method
--- Restores the normal macOS first-click behavior.
---
--- Returns:
---  * The ClickThrough object
function obj:stop()
  if self._tap then self._tap:stop() end
  self._tap = nil
  return self
end

return obj
