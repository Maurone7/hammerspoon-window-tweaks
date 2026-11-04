--- === FinderCut ===
---
--- Cmd+X / Cmd+V to cut and move files in Finder.
---
--- Finder has no file cut: Cmd+X copies the selection, and the next Cmd+V
--- becomes Cmd+Option+V ("Move Item Here"). Cmd+C cancels a pending cut.
--- While editing text (renaming, the search field) the keys behave normally.

local obj = {}
obj.__index = obj

obj.name = "FinderCut"
obj.version = "1.0"
obj.author = "Maurone7"
obj.homepage = "https://github.com/Maurone7/hammerspoon-window-tweaks"
obj.license = "MIT - https://opensource.org/licenses/MIT"

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
  local X, C, V = hs.keycodes.map.x, hs.keycodes.map.c, hs.keycodes.map.v
  local cutPending = false

  self._tap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
    if not event:getFlags():containExactly({ "cmd" }) then return false end
    local code = event:getKeyCode()
    if code ~= X and code ~= C and code ~= V then return false end
    if not finderFocused() or editingText() then return false end

    if code == X then
      cutPending = true
      return true, keyPress({ "cmd" }, "c")
    elseif code == C then
      cutPending = false
    elseif code == V and cutPending then
      cutPending = false
      return true, keyPress({ "cmd", "alt" }, "v")
    end
    return false
  end):start()
  return self
end

--- FinderCut:stop()
--- Method
--- Stops handling Cmd+X / Cmd+V in Finder.
---
--- Returns:
---  * The FinderCut object
function obj:stop()
  if self._tap then self._tap:stop() end
  self._tap = nil
  return self
end

return obj
