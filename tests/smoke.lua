-- Checks the running Hammerspoon after a reload. Run by tests/smoke.sh;
-- reads state only, so it never clicks, types or moves windows.
local NAMES = { "FullscreenTrafficLights", "FinderCut", "ClickThrough", "WindowTweaksMenu" }
local MARK = "window-tweaks-smoke-reload"
local failures = 0

local function check(ok, what, detail)
  if ok then
    print("  ok    " .. what)
  else
    failures = failures + 1
    print("  FAIL  " .. what .. (detail and (" (" .. detail .. ")") or ""))
  end
end

local function installedVersion(name)
  local path = hs.configdir .. "/Spoons/" .. name .. ".spoon/init.lua"
  local f = io.open(path)
  if not f then return nil end
  local text = f:read("a")
  f:close()
  return text:match('obj%.version = "([^"]+)"')
end

local disabled = hs.settings.get("windowTweaksMenu.disabled") or {}

for _, name in ipairs(NAMES) do
  local s = spoon[name]
  local installed = installedVersion(name)
  if not installed then
    print("  skip  " .. name .. " is not installed")
  elseif not s then
    print("  skip  " .. name .. " is installed but not loaded in init.lua")
  else
    check(s.version == installed, name .. " loaded at the installed version " .. installed, "loaded " .. s.version)
    if disabled[name] then
      check(not s:isRunning(), name .. " is off, as set in the menu")
    else
      check(s:isRunning(), name .. " is running")
    end
  end
end

local lights = spoon.FullscreenTrafficLights
if lights and lights:isRunning() then
  lights:_scan()
  local fullscreen, overlays, showing = 0, 0, 0
  for _, win in ipairs(hs.window.orderedWindows()) do
    if win:isFullScreen() then fullscreen = fullscreen + 1 end
  end
  for _, overlay in pairs(lights._overlays) do
    overlays = overlays + 1
    if overlay.canvas:isShowing() then showing = showing + 1 end
  end
  check(overlays == fullscreen and showing == fullscreen,
    string.format("buttons shown on all %d fullscreen window(s)", fullscreen),
    string.format("%d overlays, %d showing", overlays, showing))
end

for _, name in ipairs({ "FinderCut", "ClickThrough" }) do
  local s = spoon[name]
  if s and s:isRunning() then check(s._tap:isEnabled(), name .. " event tap is enabled") end
end

local menu = spoon.WindowTweaksMenu
if menu and menu:isRunning() then
  check(menu._menubar:isInMenuBar(), "menu-bar icon is in the menu bar")
end

-- Only look at the console after the latest reload marker, and only for
-- Hammerspoon's own error formats ("*** ERROR:", "LuaSkin ... ERROR:").
local console = hs.console.getConsole()
local markEnd, from = nil, 1
while true do
  local _, e = console:find(MARK, from, true)
  if not e then break end
  markEnd, from = e, e + 1
end
local sinceReload = markEnd and console:sub(markEnd + 1) or console
local errorLine = sinceReload:match("[^\n]*ERROR[^\n]*") or sinceReload:match("[^\n]*stack traceback[^\n]*")
check(errorLine == nil, "no errors in the console since the reload", errorLine)

print(string.format("\n%s", failures == 0 and "smoke test passed" or (failures .. " check(s) failed")))
