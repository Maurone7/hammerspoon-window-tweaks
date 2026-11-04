--- === FinderCut ===
---
--- Cmd+X / Cmd+V to cut and move files in Finder.
---
--- Finder has no file cut: Cmd+X copies the selection, and the next Cmd+V
--- becomes Cmd+Option+V ("Move Item Here"), but only while the clipboard still
--- holds what that Cmd+X copied. Copying anything else cancels the cut.
--- While editing text (renaming, the search field) the keys behave normally.

local obj = {}
obj.__index = obj

obj.name = "FinderCut"
obj.version = "1.2"
obj.author = "Maurone7"
obj.homepage = "https://github.com/Maurone7/hammerspoon-window-tweaks"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- How long to wait for Finder to finish the copy behind a Cmd+X.
local COPY_TIMEOUT = 1
local TEXT_ROLES = { AXTextField = true, AXTextArea = true, AXComboBox = true }

local function finderFocused()
  local app = hs.application.frontmostApplication()
  return app and app:bundleID() == "com.apple.finder"
end

local function editingText()
  local el = hs.axuielement.systemWideElement():attributeValue("AXFocusedUIElement")
  return el and TEXT_ROLES[el:attributeValue("AXRole")] or false
end

local function keyPress(mods, key)
  return {
    hs.eventtap.event.newKeyEvent(mods, key, true),
    hs.eventtap.event.newKeyEvent(mods, key, false),
  }
end

--- FinderCut:start()
--- Method
--- Starts handling Cmd+X / Cmd+V in Finder.
---
--- Returns:
---  * The FinderCut object
function obj:start()
  if self._tap then return self end
  local X, V = hs.keycodes.map.x, hs.keycodes.map.v
  local cutCount -- clipboard changeCount right after a Cmd+X copy

  local function awaitCopy()
    local before, started = hs.pasteboard.changeCount(), hs.timer.secondsSinceEpoch()
    cutCount = nil
    if self._copyTimer then self._copyTimer:stop() end
    self._copyTimer = hs.timer.waitUntil(function()
      return hs.pasteboard.changeCount() ~= before
        or hs.timer.secondsSinceEpoch() - started > COPY_TIMEOUT
    end, function()
      local count = hs.pasteboard.changeCount()
      if count ~= before then cutCount = count end
      self._copyTimer = nil
    end, 0.02)
  end

  self._tap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
    if not event:getFlags():containExactly({ "cmd" }) then return false end
    local code = event:getKeyCode()
    if code ~= X and code ~= V then return false end
    if not finderFocused() or editingText() then return false end

    if code == X then
      awaitCopy()
      return true, keyPress({ "cmd" }, "c")
    elseif cutCount and hs.pasteboard.changeCount() == cutCount then
      cutCount = nil
      return true, keyPress({ "cmd", "alt" }, "v")
    end
    return false
  end):start()

  -- macOS disables an event tap whose callback is too slow; turn it back on.
  self._watchdog = hs.timer.doEvery(5, function()
    if not self._tap:isEnabled() then self._tap:start() end
  end)
  return self
end

--- FinderCut:stop()
--- Method
--- Stops handling Cmd+X / Cmd+V in Finder.
---
--- Returns:
---  * The FinderCut object
function obj:stop()
  for _, key in ipairs({ "_tap", "_watchdog", "_copyTimer" }) do
    if self[key] then self[key]:stop() end
    self[key] = nil
  end
  return self
end

--- FinderCut:isRunning()
--- Method
--- Whether the Spoon is started.
---
--- Returns:
---  * A boolean
function obj:isRunning()
  return self._tap ~= nil
end

return obj
