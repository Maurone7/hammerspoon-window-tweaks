local DISABLED_KEY = "windowTweaksMenu.disabled"

return function(T)
  local function setup(opts)
    opts = opts or {}
    local mock = T.setup()
    if opts.disabled then mock.settings[DISABLED_KEY] = opts.disabled end
    for _, name in ipairs(opts.spoons or { "FullscreenTrafficLights", "FinderCut", "ClickThrough" }) do
      spoon[name] = T.load(name):start()
    end
    local menu = T.load("WindowTweaksMenu"):start()
    return mock, menu, mock.menubars[1]
  end

  local function titles(items)
    local t = {}
    for _, item in ipairs(items) do table.insert(t, item.title) end
    return table.concat(t, " | ")
  end

  T.test("shows a template icon with every loaded feature checked", function()
    local _, _, mb = setup()
    T.ok(mb.icon, "icon set")
    T.eq(mb.template, true, "template image")
    local items = mb.menu()
    T.eq(titles(items), "Fullscreen Traffic Lights | Cut & Paste Files in Finder | Single-Click Activation"
      .. " | - | Reset Button Positions | Reload Config", "items")
    for i = 1, 3 do T.eq(items[i].checked, true, items[i].title .. " checked") end
  end)

  T.test("leaves out Spoons that aren't loaded", function()
    local _, _, mb = setup({ spoons = { "FinderCut" } })
    T.eq(titles(mb.menu()), "Cut & Paste Files in Finder | - | Reload Config", "items")
  end)

  T.test("unchecking a feature stops it and remembers that", function()
    local mock, _, mb = setup()
    mb.menu()[2].fn()
    T.eq(spoon.FinderCut:isRunning(), false, "FinderCut running")
    T.eq(mock.settings[DISABLED_KEY].FinderCut, true, "remembered")
    T.eq(mb.menu()[2].checked, false, "unchecked")
  end)

  T.test("checking it again starts it and forgets the setting", function()
    local mock, _, mb = setup()
    mb.menu()[2].fn()
    mb.menu()[2].fn()
    T.eq(spoon.FinderCut:isRunning(), true, "FinderCut running")
    T.eq(mock.settings[DISABLED_KEY].FinderCut, nil, "forgotten")
  end)

  T.test("features turned off stay off after a reload", function()
    setup({ disabled = { ClickThrough = true } })
    T.eq(spoon.ClickThrough:isRunning(), false, "ClickThrough running")
    T.eq(spoon.FinderCut:isRunning(), true, "FinderCut running")
  end)

  T.test("Reset Button Positions resets the traffic lights", function()
    local mock, _, mb = setup()
    mock.settings["fullscreenTrafficLights.offsets"] = { ["com.example.App"] = { x = 1, y = 1 } }
    mb.menu()[5].fn()
    T.eq(mock.settings["fullscreenTrafficLights.offsets"], nil, "positions cleared")
  end)

  T.test("Reset Button Positions is greyed out while the traffic lights are off", function()
    local _, _, mb = setup()
    mb.menu()[1].fn()
    T.eq(mb.menu()[5].disabled, true, "disabled")
  end)

  T.test("Reload Config reloads Hammerspoon", function()
    local mock, _, mb = setup()
    mb.menu()[6].fn()
    T.eq(mock.reloaded, true, "reloaded")
  end)

  T.test("Snap Window submenu snaps the focused window", function()
    local mock = T.setup()
    mock.screens = { mock.screen(1, { x = 0, y = 0, w = 1000, h = 800 }) }
    mock.frontApp = mock.app("com.example.App", 300, "Example")
    local win = mock.window({ id = 1, app = mock.frontApp, fullscreen = false, screen = mock.screens[1] })
    mock.focusedWindow = win
    spoon.WindowSnap = T.load("WindowSnap"):start()
    T.load("WindowTweaksMenu"):start()
    local items = mock.menubars[1].menu()
    T.eq(titles(items), "Window Snapping | - | Snap Window | Reload Config", "items")
    items[3].menu[1].fn()
    T.eq(win:frame().w, 500, "snapped to the left half")
    items[1].fn()
    T.eq(mock.menubars[1].menu()[3].disabled, true, "greyed out while snapping is off")
  end)

  T.test("stop() removes the icon", function()
    local _, menu, mb = setup()
    menu:stop()
    T.eq(mb.deleted, true, "deleted")
    T.eq(menu:isRunning(), false, "running")
  end)
end
