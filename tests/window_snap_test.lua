local IGNORED_KEY = "windowSnap.ignoredApps"
local OPTIONS_KEY = "windowSnap.options"
local APP_ID = "com.example.App"
-- A 1920x1080 screen with a 25pt menu bar and no Dock: usable area 1920x1055.
local FULL = { x = 0, y = 0, w = 1920, h = 1080 }
local VISIBLE = { x = 0, y = 25, w = 1920, h = 1055 }
local START = { x = 300, y = 200, w = 800, h = 600 }

return function(T)
  local function setup(opts)
    opts = opts or {}
    local mock = T.setup()
    mock.screens = { mock.screen(1, FULL, VISIBLE) }
    for _, s in ipairs(opts.screens or {}) do table.insert(mock.screens, mock.screen(#mock.screens + 1, s, s)) end
    local app = mock.app(APP_ID, 300, "Example")
    mock.frontApp = app
    local win = mock.window({
      id = 1, app = app, fullscreen = false, frame = opts.frame or START, screen = mock.screens[1],
      minSize = opts.minSize,
    })
    mock.focusedWindow = win
    if opts.ignored then mock.settings[IGNORED_KEY] = opts.ignored end
    if opts.options then mock.settings[OPTIONS_KEY] = opts.options end
    local s = T.load("WindowSnap")
    if opts.configure then opts.configure(s) end
    s:start()
    return mock, s, win
  end

  local CTRL_ALT = { ctrl = true, alt = true }
  local ARROWS = { left = true, right = true, up = true, down = true }

  local function tapFor(mock, eventType)
    for _, tap in ipairs(mock.taps) do
      for _, t in ipairs(tap.types) do
        if t == eventType and tap.enabled then return tap end
      end
    end
    return nil
  end
  local function keyTap(mock) return tapFor(mock, 10) end
  local function dragTap(mock) return tapFor(mock, 1) end

  local function keyDown(mock, key, flags, repeated)
    return keyTap(mock).fn(mock.keyEvent(key, flags or CTRL_ALT, "keyDown", repeated))
  end
  local function keyUp(mock, key, flags)
    return keyTap(mock).fn(mock.keyEvent(key, flags or CTRL_ALT, "keyUp"))
  end

  -- ⌃⌥ + an arrow goes through the event tap, everything else is a hotkey.
  local function press(mock, mods, key)
    if mods == "ctrl+alt" and ARROWS[key] then
      T.eq(keyDown(mock, key), true, mods .. "+" .. key .. " consumed")
      keyUp(mock, key)
      return
    end
    local hk = mock.hotkey(mods, key)
    T.ok(hk and hk.enabled, mods .. "+" .. key .. " bound")
    hk.pressed()
  end

  local function frameIs(win, x, y, w, h)
    local f = win:frame()
    T.eq(string.format("%d,%d %dx%d", f.x, f.y, f.w, f.h), string.format("%d,%d %dx%d", x, y, w, h), "frame")
  end

  -- Drags from `from` through each point, `between` moving the window as
  -- the window server would.
  local function drag(mock, tap, from, points, between)
    tap.fn(mock.mouseEvent("leftMouseDown", from))
    for i, p in ipairs(points) do
      if between then between(i, p) end
      mock.advance(0.06)
      tap.fn(mock.mouseEvent("leftMouseDragged", p))
    end
  end

  local function release(mock, tap, p)
    tap.fn(mock.mouseEvent("leftMouseUp", p))
    mock.advance(0.1)
  end

  -- The window under the mouse is `win`, grabbed by its title bar.
  local function grab(mock, win)
    mock.elementAt = function() return mock.element({ AXRole = "AXWindow" }, 300, win) end
  end

  local function moveBy(win, dx, dy)
    return function()
      local f = win:frame()
      win._frame = { x = f.x + dx, y = f.y + dy, w = f.w, h = f.h }
    end
  end

  T.test("binds Rectangle's default shortcuts", function()
    local mock = setup()
    for _, k in ipairs({ "d", "f", "g", "e", "t", "return", "-", "=", "c", "delete" }) do
      T.ok(mock.hotkey("ctrl+alt", k), "ctrl+alt+" .. k)
    end
    T.ok(keyTap(mock), "arrow keys read from an event tap")
    T.eq(mock.hotkey("ctrl+alt", "u"), nil, "no ⌃⌥U for Top Left")
    T.ok(mock.hotkey("ctrl+alt+shift", "up"), "maximize height")
    T.ok(mock.hotkey("ctrl+alt+cmd", "right"), "next display")
    T.ok(mock.hotkey("ctrl+alt", "=").repeated, "Make Larger repeats while held")
  end)

  T.test("halves, quarters and maximize fill the usable screen area", function()
    local mock, _, win = setup()
    press(mock, "ctrl+alt", "left"); frameIs(win, 0, 25, 960, 1055)
    press(mock, "ctrl+alt", "right"); frameIs(win, 960, 25, 960, 1055)
    press(mock, "ctrl+alt", "down"); frameIs(win, 0, 553, 1920, 527)
    press(mock, "ctrl+alt", "return"); frameIs(win, 0, 25, 1920, 1055)
  end)

  T.test("pressing a half again cycles through 1/2, 2/3 and 1/3", function()
    local mock, _, win = setup()
    press(mock, "ctrl+alt", "left"); frameIs(win, 0, 25, 960, 1055)
    press(mock, "ctrl+alt", "left"); frameIs(win, 0, 25, 1280, 1055)
    press(mock, "ctrl+alt", "left"); frameIs(win, 0, 25, 640, 1055)
    press(mock, "ctrl+alt", "left"); frameIs(win, 0, 25, 960, 1055)
  end)

  T.test("a window moved by hand starts the cycle over", function()
    local mock, _, win = setup()
    press(mock, "ctrl+alt", "left")
    moveBy(win, 50, 0)()
    press(mock, "ctrl+alt", "left"); frameIs(win, 0, 25, 960, 1055)
  end)

  T.test("holding two arrows snaps to the corner between them", function()
    local mock, _, win = setup()
    keyDown(mock, "up"); frameIs(win, 0, 25, 1920, 528)
    keyDown(mock, "right"); frameIs(win, 960, 25, 960, 528)
    keyUp(mock, "right"); keyUp(mock, "up")
    keyDown(mock, "left"); keyDown(mock, "down"); frameIs(win, 0, 553, 960, 527)
    keyUp(mock, "left"); keyUp(mock, "down")
    keyDown(mock, "down"); keyDown(mock, "right"); frameIs(win, 960, 553, 960, 527)
  end)

  T.test("holding up and down enters fullscreen at the original size", function()
    local mock, _, win = setup()
    keyDown(mock, "up"); frameIs(win, 0, 25, 1920, 528)
    T.eq(keyDown(mock, "down"), true, "consumed")
    T.eq(win.calls[#win.calls], "setFullScreen:true", "entered fullscreen")
    frameIs(win, 300, 200, 800, 600) -- not left at the top half
  end)

  T.test("down then up works too", function()
    local mock, _, win = setup()
    keyDown(mock, "down"); keyDown(mock, "up")
    T.eq(win.calls[#win.calls], "setFullScreen:true", "entered fullscreen")
  end)

  T.test("up and down on a fullscreen window leaves fullscreen", function()
    local mock, _, win = setup()
    win.fullscreen = true
    keyDown(mock, "up"); keyDown(mock, "down")
    win.fullscreen = false
    mock.advance(1)
    T.eq(table.concat(win.calls, ","), "setFullScreen:false", "only left fullscreen, no half")
  end)

  T.test("Toggle Fullscreen in the menu works on a fullscreen window", function()
    local _, s, win = setup()
    win.fullscreen = true
    for _, item in ipairs(s:menuItems()) do
      if item.title == "Toggle Fullscreen\t⌃⌥↑↓" then
        T.eq(item.disabled, false, "enabled")
        item.fn()
      elseif item.title == "Maximize\t⌃⌥↩" then
        T.eq(item.disabled, true, "snapping greyed out")
      end
    end
    T.eq(win.calls[#win.calls], "setFullScreen:false", "left fullscreen")
  end)

  T.test("restore after a corner goes back to before the half", function()
    local mock, _, win = setup()
    keyDown(mock, "up"); keyDown(mock, "left")
    keyUp(mock, "left"); keyUp(mock, "up")
    press(mock, "ctrl+alt", "delete")
    frameIs(win, 300, 200, 800, 600)
  end)

  T.test("the fn flag macOS puts on arrow keys is ignored", function()
    local mock, _, win = setup()
    T.eq(keyDown(mock, "left", { ctrl = true, alt = true, fn = true }), true, "consumed")
    frameIs(win, 0, 25, 960, 1055)
  end)

  T.test("arrows on the same axis don't make a corner", function()
    local mock, _, win = setup()
    keyDown(mock, "left"); keyDown(mock, "right")
    frameIs(win, 960, 25, 960, 1055)
  end)

  T.test("an arrow already let go doesn't make a corner", function()
    local mock, _, win = setup()
    keyDown(mock, "up"); keyUp(mock, "up")
    keyDown(mock, "right")
    frameIs(win, 960, 25, 960, 1055)
  end)

  T.test("letting go of the modifiers forgets held arrows", function()
    local mock, _, win = setup()
    keyDown(mock, "up") -- its key-up never arrives
    keyTap(mock).fn(mock.keyEvent(nil, {}, "flagsChanged"))
    keyDown(mock, "right")
    frameIs(win, 960, 25, 960, 1055)
  end)

  T.test("holding an arrow doesn't keep cycling", function()
    local mock, _, win = setup()
    keyDown(mock, "left")
    T.eq(keyDown(mock, "left", nil, true), true, "repeat consumed")
    frameIs(win, 0, 25, 960, 1055)
  end)

  T.test("arrows with other modifiers pass through", function()
    local mock, _, win = setup()
    T.eq(keyDown(mock, "up", { ctrl = true, alt = true, shift = true }), false, "passed through")
    T.eq(keyDown(mock, "up", {}), false, "plain arrow passed through")
    frameIs(win, 300, 200, 800, 600)
  end)

  T.test("arrowCorners = false binds the arrows as plain hotkeys", function()
    local mock, _, win = setup({ configure = function(s) s.arrowCorners = false end })
    T.eq(keyTap(mock), nil, "no key tap")
    mock.hotkey("ctrl+alt", "up").pressed()
    frameIs(win, 0, 25, 1920, 528)
  end)

  T.test("thirds are columns on a landscape screen", function()
    local mock, _, win = setup()
    press(mock, "ctrl+alt", "d"); frameIs(win, 0, 25, 640, 1055)
    press(mock, "ctrl+alt", "f"); frameIs(win, 640, 25, 640, 1055)
    press(mock, "ctrl+alt", "g"); frameIs(win, 1280, 25, 640, 1055)
    press(mock, "ctrl+alt", "e"); frameIs(win, 0, 25, 1280, 1055)
    press(mock, "ctrl+alt", "t"); frameIs(win, 640, 25, 1280, 1055)
  end)

  T.test("thirds are rows on a portrait screen", function()
    local mock, _, win = setup()
    local portrait = { x = 0, y = 0, w = 1080, h = 1920 }
    win._screen = mock.screen(9, portrait, portrait)
    press(mock, "ctrl+alt", "f"); frameIs(win, 0, 640, 1080, 640)
  end)

  T.test("fourths and sixths are available as actions", function()
    local _, s, win = setup()
    s:doAction("secondFourth"); frameIs(win, 480, 25, 480, 1055)
    s:doAction("bottomRightSixth"); frameIs(win, 1280, 553, 640, 527)
  end)

  T.test("gap leaves space around and between windows", function()
    local mock, _, win = setup({ configure = function(s) s.gap = 10 end })
    press(mock, "ctrl+alt", "left"); frameIs(win, 10, 35, 945, 1035)
    press(mock, "ctrl+alt", "right"); frameIs(win, 965, 35, 945, 1035)
  end)

  T.test("a window too wide for the last third is kept on screen", function()
    local mock, _, win = setup({ minSize = { w = 900, h = 0 } })
    press(mock, "ctrl+alt", "g")
    frameIs(win, 1020, 25, 900, 1055)
  end)

  T.test("a window too wide for the left half stays at the left edge", function()
    local mock, _, win = setup({ minSize = { w = 1200, h = 0 } })
    press(mock, "ctrl+alt", "left")
    frameIs(win, 0, 25, 1200, 1055)
  end)

  T.test("cycling still works for an app with a minimum size", function()
    local mock, _, win = setup({ minSize = { w = 700, h = 0 } })
    press(mock, "ctrl+alt", "right"); frameIs(win, 960, 25, 960, 1055)
    press(mock, "ctrl+alt", "right"); frameIs(win, 640, 25, 1280, 1055)
    press(mock, "ctrl+alt", "right"); frameIs(win, 1220, 25, 700, 1055)
  end)

  T.test("restore goes back to the frame from before the first snap", function()
    local mock, _, win = setup()
    press(mock, "ctrl+alt", "left")
    press(mock, "ctrl+alt", "f")
    press(mock, "ctrl+alt", "delete")
    frameIs(win, 300, 200, 800, 600)
  end)

  T.test("restore after moving by hand goes back to where it was moved", function()
    local mock, _, win = setup()
    press(mock, "ctrl+alt", "left")
    win._frame = { x = 100, y = 100, w = 500, h = 500 }
    press(mock, "ctrl+alt", "right")
    press(mock, "ctrl+alt", "delete")
    frameIs(win, 100, 100, 500, 500)
  end)

  T.test("center keeps the size", function()
    local mock, _, win = setup()
    press(mock, "ctrl+alt", "c"); frameIs(win, 560, 253, 800, 600)
  end)

  T.test("Make Larger and Smaller keep edges that touch the screen", function()
    local mock, _, win = setup()
    press(mock, "ctrl+alt", "left")
    press(mock, "ctrl+alt", "="); frameIs(win, 0, 25, 990, 1055)
    press(mock, "ctrl+alt", "-"); frameIs(win, 0, 25, 960, 1055)
    press(mock, "ctrl+alt", "c")
    press(mock, "ctrl+alt", "-"); frameIs(win, 510, 25, 900, 1055)
  end)

  T.test("maximize height keeps the width", function()
    local mock, _, win = setup()
    press(mock, "ctrl+alt+shift", "up"); frameIs(win, 300, 25, 800, 1055)
  end)

  T.test("next display keeps the window's relative place and size", function()
    local mock, _, win = setup({ screens = { { x = 1920, y = 0, w = 1280, h = 1024 } } })
    press(mock, "ctrl+alt", "left")
    press(mock, "ctrl+alt+cmd", "right")
    frameIs(win, 1920, 0, 640, 1024)
  end)

  T.test("next display skips a display showing a fullscreen app", function()
    local mock, _, win = setup({ screens = { { x = 1920, y = 0, w = 1920, h = 1080 },
      { x = 3840, y = 0, w = 1920, h = 1080 } } })
    mock.fullscreenScreens[2] = true
    press(mock, "ctrl+alt+cmd", "right")
    T.eq(win:frame().x, 3840 + 300, "moved past the fullscreen display")
  end)

  T.test("next display won't put a window behind a fullscreen app", function()
    local mock, _, win = setup({ screens = { { x = 1920, y = 0, w = 1920, h = 1080 } } })
    mock.fullscreenScreens[2] = true
    press(mock, "ctrl+alt+cmd", "right")
    frameIs(win, 300, 200, 800, 600)
    T.eq(mock.alerts[1], "The other display is showing a fullscreen app", "explained")
  end)

  T.test("a fullscreen window moves to the next display and stays fullscreen", function()
    local mock, _, win = setup({ screens = { { x = 1920, y = 0, w = 1920, h = 1080 } } })
    win.fullscreen = true
    press(mock, "ctrl+alt+cmd", "right")
    T.eq(table.concat(win.calls, ","), "setFullScreen:false", "left fullscreen first")
    win.fullscreen = false -- the exit animation finishes
    mock.advance(0.06)
    T.eq(win:frame().x, 300, "not moved before fullscreenExitWait")
    mock.advance(0.1)
    T.eq(win:frame().x, 1920 + 300, "moved right after")
    T.eq(win.calls[#win.calls], "setFullScreen:true", "asked to go fullscreen again in the same step")
  end)

  T.test("fullscreenExitWait can be made longer", function()
    local mock, _, win = setup({ screens = { { x = 1920, y = 0, w = 1920, h = 1080 } },
      configure = function(s) s.fullscreenExitWait = 0.5 end })
    win.fullscreen = true
    press(mock, "ctrl+alt+cmd", "right")
    win.fullscreen = false
    mock.advance(0.4)
    T.eq(win:frame().x, 300, "not moved yet")
    mock.advance(0.2)
    T.eq(win:frame().x, 1920 + 300, "moved")
  end)

  T.test("a fullscreen window moves as soon as it's back on a desktop Space", function()
    local mock, _, win = setup({ screens = { { x = 1920, y = 0, w = 1920, h = 1080 } } })
    win.fullscreen = true
    press(mock, "ctrl+alt+cmd", "right")
    win.fullscreen, win.spaces = false, { 1 }
    mock.advance(0.2)
    T.eq(win:frame().x, 1920 + 300, "moved before the 0.5s fallback")
  end)

  T.test("going fullscreen again is retried if macOS drops the request", function()
    local mock, _, win = setup({ screens = { { x = 1920, y = 0, w = 1920, h = 1080 } } })
    win.fullscreen = true
    press(mock, "ctrl+alt+cmd", "right")
    win.fullscreen = false
    mock.advance(1.5)
    local function asks()
      local n = 0
      for _, c in ipairs(win.calls) do if c == "setFullScreen:true" then n = n + 1 end end
      return n
    end
    local soFar = asks()
    T.ok(soFar >= 5, "asked about every 0.1s, " .. soFar .. " times")
    win.fullscreen = true -- this time it took
    mock.advance(3)
    T.eq(asks(), soFar, "stopped asking once fullscreen")
  end)

  T.test("going fullscreen again gives up after a while", function()
    local mock, _, win = setup({ screens = { { x = 1920, y = 0, w = 1920, h = 1080 } } })
    win.fullscreen = true
    press(mock, "ctrl+alt+cmd", "right")
    win.fullscreen = false
    mock.advance(10)
    local n = #win.calls
    mock.advance(10)
    T.eq(#win.calls, n, "stopped asking")
    T.ok(n < 40, "gave up after about 3 seconds")
  end)

  T.test("a fullscreen window isn't moved while still on its fullscreen Space", function()
    local mock, _, win = setup({ screens = { { x = 1920, y = 0, w = 1920, h = 1080 } } })
    mock.fullscreenSpaces[500] = true
    win.fullscreen, win.spaces = true, { 500 }
    press(mock, "ctrl+alt+cmd", "right")
    win.fullscreen = false -- reported early, while the animation still runs
    mock.advance(1)
    T.eq(win:frame().x, 300, "not moved yet")
    win.spaces = { 1 } -- the transition is over
    mock.advance(0.1)
    T.eq(win:frame().x, 1920 + 300, "moved")
  end)

  T.test("a fullscreen window isn't moved while it's still animating", function()
    local mock, _, win = setup({ screens = { { x = 1920, y = 0, w = 1920, h = 1080 } } })
    win.fullscreen = true
    press(mock, "ctrl+alt+cmd", "right")
    win.fullscreen = false
    for i = 1, 14 do
      win._frame = { x = 300 - i * 10, y = 200, w = 800, h = 600 } -- still shrinking out of fullscreen
      mock.advance(0.05)
    end
    T.eq(win:frame().x, 160, "not moved yet")
    mock.advance(0.15)
    T.eq(win:frame().x, 1920 + 160, "moved once it stopped")
  end)

  T.test("a fullscreen window that won't leave fullscreen is given up on", function()
    local mock, _, win = setup({ screens = { { x = 1920, y = 0, w = 1920, h = 1080 } } })
    win.fullscreen = true
    press(mock, "ctrl+alt+cmd", "right")
    mock.advance(5)
    T.eq(table.concat(win.calls, ","), "setFullScreen:false", "nothing else tried")
    mock.advance(5)
    T.eq(#win.calls, 1, "timer stopped")
  end)

  T.test("a move that doesn't land in time still goes back to fullscreen", function()
    local mock, _, win = setup({ screens = { { x = 1920, y = 0, w = 1920, h = 1080 } } })
    win.fullscreen = true
    win.setFrame = function(self) table.insert(self.calls, "setFrame") end -- the app refuses to move
    press(mock, "ctrl+alt+cmd", "right")
    win.fullscreen = false
    mock.advance(5)
    T.eq(win.calls[#win.calls], "setFullScreen:true", "back to fullscreen")
  end)

  T.test("a fullscreen window can move onto a display with another fullscreen app", function()
    local mock, _, win = setup({ screens = { { x = 1920, y = 0, w = 1920, h = 1080 } } })
    mock.fullscreenScreens[2] = true
    win.fullscreen = true
    press(mock, "ctrl+alt+cmd", "right")
    win.fullscreen = false
    mock.advance(2)
    T.eq(win:frame().x, 1920 + 300, "moved")
    T.eq(win.calls[#win.calls], "setFullScreen:true", "fullscreen again")
  end)

  T.test("next display with one screen does nothing", function()
    local mock, _, win = setup()
    press(mock, "ctrl+alt+cmd", "right")
    frameIs(win, 300, 200, 800, 600)
  end)

  T.test("an app whose window Accessibility can't see gets an explanation", function()
    local mock = setup()
    mock.focusedWindow = nil
    mock.frontApp = mock.app(nil, 400, "", "/Games/steamapps/common/Victoria 3/binaries/victoria3.app")
    mock.cgWindows = { { kCGWindowOwnerPID = 400, kCGWindowLayer = 0, kCGWindowIsOnscreen = true } }
    press(mock, "ctrl+alt", "left")
    T.eq(mock.alerts[1], "victoria3 doesn't let other apps move or resize its window. Use its own display settings.",
      "alert")
    keyDown(mock, "up"); keyDown(mock, "down")
    T.eq(#mock.alerts, 1, "not repeated right away")
    mock.advance(3)
    keyDown(mock, "up"); keyUp(mock, "up")
    T.eq(#mock.alerts, 2, "shown again later")
  end)

  T.test("no explanation when the app just has no window open", function()
    local mock = setup()
    mock.focusedWindow = nil
    mock.cgWindows = { { kCGWindowOwnerPID = 300, kCGWindowLayer = 25, kCGWindowIsOnscreen = true } } -- a menu-bar item
    press(mock, "ctrl+alt", "left")
    mock.frontApp = mock.app("com.apple.finder", 100, "Finder")
    mock.cgWindows = { { kCGWindowOwnerPID = 100, kCGWindowLayer = 0, kCGWindowIsOnscreen = true } } -- the desktop
    press(mock, "ctrl+alt", "left")
    T.eq(#mock.alerts, 0, "alerts")
  end)

  T.test("non-standard windows are left alone", function()
    local mock, _, win = setup()
    win.standard = false
    press(mock, "ctrl+alt", "left")
    press(mock, "ctrl+alt", "d")
    frameIs(win, 300, 200, 800, 600)
    T.eq(#win.calls, 0, "untouched")
  end)

  T.test("a shortcut on a fullscreen window leaves fullscreen, then snaps", function()
    local mock, _, win = setup()
    win.fullscreen = true
    press(mock, "ctrl+alt", "left")
    T.eq(table.concat(win.calls, ","), "setFullScreen:false", "left fullscreen")
    win.fullscreen = false
    mock.advance(0.7)
    frameIs(win, 0, 25, 960, 1055)
    T.eq(win.calls[#win.calls], "setFrame", "not fullscreen again")
    press(mock, "ctrl+alt", "delete")
    frameIs(win, 300, 200, 800, 600) -- its size from before fullscreen
  end)

  T.test("a corner chord on a fullscreen window snaps to the corner", function()
    local mock, _, win = setup()
    win.fullscreen = true
    keyDown(mock, "up")
    win.fullscreen = false
    keyDown(mock, "right")
    mock.advance(0.7)
    frameIs(win, 960, 25, 960, 528)
  end)

  T.test("restore on a fullscreen window does nothing", function()
    local mock, _, win = setup()
    win.fullscreen = true
    press(mock, "ctrl+alt", "delete")
    T.eq(#win.calls, 0, "untouched")
  end)

  T.test("an ignored app gets the shortcut instead", function()
    local mock, _, win = setup({ ignored = { [APP_ID] = true } })
    press(mock, "ctrl+alt", "d")
    frameIs(win, 300, 200, 800, 600)
    T.eq(#mock.keystrokes, 1, "keystroke passed on")
    T.eq(mock.keystrokes[1].key, "d", "key")
    T.eq(mock.hotkey("ctrl+alt", "d").enabled, true, "hotkey back on")
    T.eq(keyDown(mock, "left"), false, "arrow passed through")
    frameIs(win, 300, 200, 800, 600)
  end)

  T.test("bindHotkeys replaces the shortcuts", function()
    local mock, s, win = setup()
    s:bindHotkeys({ maximize = { { "cmd", "alt" }, "f" } })
    T.eq(mock.hotkey("ctrl+alt", "d"), nil, "old shortcut gone")
    T.eq(keyTap(mock).fn(mock.keyEvent("left", CTRL_ALT)), false, "old arrow passes through")
    press(mock, "cmd+alt", "f")
    frameIs(win, 0, 25, 1920, 1055)
  end)

  T.test("dragging to the left edge previews and snaps to the left half", function()
    local mock, s, win = setup()
    grab(mock, win)
    local tap = dragTap(mock)
    drag(mock, tap, { x = 500, y = 210 }, { { x = 490, y = 210 }, { x = 2, y = 500 } }, function(i)
      if i == 2 then moveBy(win, -488, 290)() end
    end)
    T.ok(s._preview and s._preview:isShowing(), "preview shown")
    local p = s._preview:frame()
    T.eq(p.w, 960, "preview width")
    release(mock, tap, { x = 2, y = 500 })
    T.eq(s._preview:isShowing(), false, "preview hidden")
    frameIs(win, 0, 25, 960, 1055)
    s:doAction("restore")
    frameIs(win, 300, 200, 800, 600)
  end)

  T.test("dragging to corners, the top and the bottom edge", function()
    local cases = {
      { { x = 1, y = 1 }, { 0, 25, 960, 528 } },
      { { x = 1919, y = 1079 }, { 960, 553, 960, 527 } },
      { { x = 900, y = 0 }, { 0, 25, 1920, 1055 } },
      { { x = 900, y = 1079 }, { 640, 25, 640, 1055 } },
    }
    for _, case in ipairs(cases) do
      local mock, _, win = setup()
      grab(mock, win)
      local tap = dragTap(mock)
      drag(mock, tap, { x = 500, y = 210 }, { { x = 495, y = 210 }, case[1] }, function(i)
        if i == 2 then moveBy(win, 10, 10)() end
      end)
      release(mock, tap, case[1])
      frameIs(win, table.unpack(case[2]))
    end
  end)

  T.test("no snapping onto a display showing a fullscreen app", function()
    local mock, s, win = setup({ screens = { { x = 1920, y = 0, w = 1920, h = 1080 } } })
    mock.fullscreenScreens[2] = true
    grab(mock, win)
    local tap = dragTap(mock)
    drag(mock, tap, { x = 500, y = 210 }, { { x = 495, y = 210 }, { x = 3838, y = 500 } }, function(i)
      if i == 2 then moveBy(win, 100, 0)() end
    end)
    T.eq(s._preview, nil, "no preview")
    release(mock, tap, { x = 3838, y = 500 })
    frameIs(win, 400, 200, 800, 600)
  end)

  T.test("resizing a window at the edge doesn't snap it", function()
    local mock, s, win = setup()
    grab(mock, win)
    local tap = dragTap(mock)
    drag(mock, tap, { x = 300, y = 400 }, { { x = 299, y = 400 }, { x = 2, y = 400 } }, function(i)
      if i == 2 then win._frame = { x = 2, y = 200, w = 1098, h = 600 } end
    end)
    release(mock, tap, { x = 2, y = 400 })
    T.eq(s._preview, nil, "no preview")
    frameIs(win, 2, 200, 1098, 600)
  end)

  T.test("a drag that doesn't move the window stops being watched", function()
    local mock, _, win = setup()
    grab(mock, win)
    local tap = dragTap(mock)
    local reads = 0
    local frame = win.frame
    win.frame = function(self) reads = reads + 1; return frame(self) end
    drag(mock, tap, { x = 500, y = 500 }, { { x = 510, y = 500 }, { x = 600, y = 500 }, { x = 700, y = 500 },
      { x = 2, y = 500 } })
    T.eq(reads, 2, "frame reads") -- once to start, once to see the window hasn't moved
    release(mock, tap, { x = 2, y = 500 })
    frameIs(win, 300, 200, 800, 600)
  end)

  T.test("dragging a snapped window away gives back its old size", function()
    local mock, s, win = setup()
    s:doAction("leftHalf")
    grab(mock, win)
    local tap = dragTap(mock)
    drag(mock, tap, { x = 480, y = 30 }, { { x = 485, y = 30 }, { x = 600, y = 300 } }, function(i)
      if i == 2 then moveBy(win, 120, 270)() end
    end)
    -- The mouse was halfway across the window, so it still is.
    frameIs(win, 200, 295, 800, 600)
    release(mock, tap, { x = 600, y = 300 })
    frameIs(win, 200, 295, 800, 600)
  end)

  T.test("dragToSnap = false leaves the mouse alone", function()
    local mock = setup({ configure = function(s) s.dragToSnap = false end })
    T.eq(dragTap(mock), nil, "mouse event tap")
  end)

  T.test("menu items snap the focused window and show shortcuts", function()
    local _, s, win = setup()
    local items = s:menuItems()
    T.eq(items[1].title, "Left Half\t⌃⌥←", "first item")
    T.eq(items[7].title, "Top Left\t⌃⌥↑←", "corner shows both arrows")
    items[1].fn()
    frameIs(win, 0, 25, 960, 1055)
  end)

  T.test("menu items are greyed out without a window to snap", function()
    local mock, s = setup()
    mock.focusedWindow = nil
    T.eq(s:menuItems()[1].disabled, true, "disabled")
  end)

  T.test("Ignore <app> in the menu is remembered", function()
    local mock, s, win = setup()
    local items = s:menuItems()
    local ignore = items[#items]
    T.eq(ignore.title, "Ignore Example", "title")
    T.eq(ignore.checked, false, "unchecked")
    ignore.fn()
    T.eq(mock.settings[IGNORED_KEY][APP_ID], true, "remembered")
    T.eq(s:doAction("leftHalf"), false, "ignored")
    frameIs(win, 300, 200, 800, 600)
    items = s:menuItems()
    items[#items].fn()
    T.eq(s:doAction("leftHalf"), true, "snaps again")
  end)

  local function find(items, title)
    for _, item in ipairs(items) do
      if item.title == title then return item end
    end
    error("no menu item " .. title)
  end

  T.test("gaps set from the menu apply right away and are remembered", function()
    local mock, s, win = setup()
    local gaps = find(s:menuItems(), "Gaps Between Windows").menu
    T.eq(gaps[1].checked, true, "None checked")
    find(gaps, "10 pt").fn()
    press(mock, "ctrl+alt", "left"); frameIs(win, 10, 35, 945, 1035)
    T.eq(mock.settings[OPTIONS_KEY].gap, 10, "remembered")
    T.eq(find(find(s:menuItems(), "Gaps Between Windows").menu, "10 pt").checked, true, "10 pt checked")
  end)

  T.test("options from the menu win over init.lua after a reload", function()
    local mock, _, win = setup({ options = { gap = 20, dragToSnap = false },
      configure = function(s) s.gap = 5 end })
    T.eq(dragTap(mock), nil, "drag to snap off")
    press(mock, "ctrl+alt", "left"); frameIs(win, 20, 45, 930, 1015)
  end)

  T.test("Drag to Snap can be turned off and on from the menu", function()
    local mock, s = setup()
    find(s:menuItems(), "Drag to Snap").fn()
    T.eq(dragTap(mock), nil, "off")
    T.eq(find(s:menuItems(), "Drag to Snap").checked, false, "unchecked")
    find(s:menuItems(), "Drag to Snap").fn()
    T.ok(dragTap(mock), "back on")
    T.eq(mock.settings[OPTIONS_KEY].dragToSnap, true, "remembered")
  end)

  T.test("stop() removes the shortcuts and the event tap", function()
    local mock, s = setup()
    s:stop()
    T.eq(mock.hotkey("ctrl+alt", "d"), nil, "hotkey")
    for _, tap in ipairs(mock.taps) do T.eq(tap.enabled, false, "tap") end
    T.eq(s:isRunning(), false, "running")
  end)
end
