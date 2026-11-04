--- === WindowTweaksMenu ===
---
--- Menu-bar icon to turn the other window-tweaks Spoons on and off, reset
--- the fullscreen button positions and reload the Hammerspoon config.
---
--- Load and start it after the Spoons it controls. Features turned off from
--- the menu stay off after a reload or restart.

local obj = {}
obj.__index = obj

obj.name = "WindowTweaksMenu"
obj.version = "1.0"
obj.author = "Maurone7"
obj.homepage = "https://github.com/Maurone7/hammerspoon-window-tweaks"
obj.license = "MIT - https://opensource.org/licenses/MIT"

local SETTINGS_KEY = "windowTweaksMenu.disabled"

--- WindowTweaksMenu.features
--- Variable
--- The Spoons listed in the menu, in order, as { spoon = name, title = label }.
--- Spoons that aren't loaded are left out.
obj.features = {
  { spoon = "FullscreenTrafficLights", title = "Fullscreen Traffic Lights" },
  { spoon = "FinderCut", title = "Cut & Paste Files in Finder" },
  { spoon = "ClickThrough", title = "Single-Click Activation" },
}

-- Three dots, like the traffic lights, drawn as a template image so macOS
-- tints it for light and dark menu bars.
local function icon()
  local canvas = hs.canvas.new({ x = 0, y = 0, w = 18, h = 18 })
  for i = 0, 2 do
    canvas:appendElements({
      type = "circle",
      center = { x = 3 + i * 6, y = 9 },
      radius = 2.5,
      action = "fill",
      fillColor = { white = 0 },
    })
  end
  local image = canvas:imageFromCanvas()
  canvas:delete()
  return image
end

function obj:_setEnabled(name, enabled)
  local s = spoon[name]
  if not s then return end
  if enabled then s:start() else s:stop() end
  self._disabled[name] = (not enabled) or nil
  hs.settings.set(SETTINGS_KEY, self._disabled)
end

function obj:_menu()
  local items = {}
  for _, feature in ipairs(self.features) do
    local s = spoon[feature.spoon]
    if s then
      local running = s:isRunning()
      table.insert(items, {
        title = feature.title,
        checked = running,
        fn = function() self:_setEnabled(feature.spoon, not running) end,
      })
    end
  end
  table.insert(items, { title = "-" })
  local lights = spoon.FullscreenTrafficLights
  if lights then
    table.insert(items, {
      title = "Reset Button Positions",
      disabled = not lights:isRunning(),
      fn = function() lights:resetPositions() end,
    })
  end
  table.insert(items, { title = "Reload Config", fn = function() hs.reload() end })
  return items
end

--- WindowTweaksMenu:start()
--- Method
--- Shows the menu-bar icon and turns off the features that were turned off
--- from the menu before.
---
--- Returns:
---  * The WindowTweaksMenu object
function obj:start()
  if self._menubar then return self end
  self._disabled = hs.settings.get(SETTINGS_KEY) or {}
  for name in pairs(self._disabled) do
    if spoon[name] then spoon[name]:stop() end
  end
  self._menubar = hs.menubar.new()
  self._menubar:setIcon(icon(), true)
  self._menubar:setTooltip("Window Tweaks")
  self._menubar:setMenu(function() return self:_menu() end)
  return self
end

--- WindowTweaksMenu:stop()
--- Method
--- Removes the menu-bar icon. Features keep their current state.
---
--- Returns:
---  * The WindowTweaksMenu object
function obj:stop()
  if self._menubar then self._menubar:delete() end
  self._menubar = nil
  return self
end

--- WindowTweaksMenu:isRunning()
--- Method
--- Whether the menu-bar icon is shown.
---
--- Returns:
---  * A boolean
function obj:isRunning()
  return self._menubar ~= nil
end

return obj
