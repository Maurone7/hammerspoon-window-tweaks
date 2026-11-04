local SETTINGS_KEY = "fullscreenTrafficLights.offsets"
local APP_ID = "com.example.App"

return function(T)
  local function setup(opts)
    opts = opts or {}
    local mock = T.setup()
    local app = mock.app(APP_ID, 300)
    local win = mock.window({ id = 1, app = app, frame = opts.frame })
    mock.windows = { win }
    if opts.offsets then mock.settings[SETTINGS_KEY] = opts.offsets end
    local s = T.load("FullscreenTrafficLights"):start()
    return mock, s, win, app
  end

  local function overlayCount(s)
    local n = 0
    for _ in pairs(s._overlays) do n = n + 1 end
    return n
  end

  local function canvasFor(s, win) return s._overlays[win:id()].canvas end

  local function click(canvas, id)
    canvas:fire("mouseDown", id)
    canvas:fire("mouseUp", id)
  end

  T.test("buttons appear on every fullscreen window, focused or not", function()
    local mock = T.setup()
    local app = mock.app(APP_ID, 300)
    mock.windows = {
      mock.window({ id = 1, app = app }),
      mock.window({ id = 2, app = app, frame = { x = 1920, y = 0, w = 1920, h = 1080 } }),
      mock.window({ id = 3, app = app, fullscreen = false }),
    }
    local s = T.load("FullscreenTrafficLights"):start()
    T.eq(overlayCount(s), 2, "overlays")
    T.eq(s._overlays[1].canvas:isShowing(), true, "first shown")
    T.eq(s._overlays[2].canvas:isShowing(), true, "second shown")
    T.eq(s._overlays[3], nil, "no overlay on a normal window")
  end)

  T.test("buttons sit at the window's top-left plus defaultOffset", function()
    local _, s, win = setup({ frame = { x = 0, y = 30, w = 1920, h = 1050 } })
    local pos = canvasFor(s, win):topLeft()
    T.eq(pos.x, 12, "x")
    T.eq(pos.y, 40, "y")
  end)

  T.test("buttons are removed when the window leaves fullscreen", function()
    local mock, s, win = setup()
    local canvas = canvasFor(s, win)
    win.fullscreen = false
    mock.advance(0.5)
    T.eq(overlayCount(s), 0, "overlays")
    T.eq(canvas.deleted, true, "canvas deleted")
  end)

  T.test("the fallback scan finds new fullscreen windows", function()
    local mock, s = setup()
    table.insert(mock.windows, mock.window({ id = 2, app = mock.app("com.other", 400) }))
    mock.advance(0.5)
    T.eq(overlayCount(s), 1, "cheap refresh doesn't scan")
    mock.advance(2.5)
    T.eq(overlayCount(s), 2, "scan after scanInterval")
  end)

  T.test("red closes the window", function()
    local _, s, win = setup()
    click(canvasFor(s, win), "close")
    T.eq(win.calls[1], "close", "call")
  end)

  T.test("green exits fullscreen", function()
    local _, s, win = setup()
    click(canvasFor(s, win), "fullscreen")
    T.eq(win.calls[1], "setFullScreen:false", "call")
  end)

  T.test("yellow exits fullscreen, then minimizes once it has", function()
    local mock, s, win = setup()
    click(canvasFor(s, win), "minimize")
    T.eq(win.calls[1], "setFullScreen:false", "first call")
    mock.advance(1)
    T.eq(#win.calls, 1, "no minimize while still fullscreen")
    win.fullscreen = false
    mock.advance(0.5)
    T.eq(win.calls[2], "minimize", "minimized")
  end)

  T.test("Option-drag moves the buttons and remembers the spot for the app", function()
    local mock, s, win = setup()
    local canvas = canvasFor(s, win)
    mock.modifiers = { alt = true }
    mock.mouse = { x = 20, y = 15 }
    canvas:fire("mouseDown", "close")
    local drag = mock.taps[#mock.taps]
    mock.mouse = { x = 120, y = 65 }
    drag.fn(mock.mouseEvent("leftMouseDragged", mock.mouse))
    T.eq(canvas:topLeft().x, 112, "x while dragging")
    drag.fn(mock.mouseEvent("leftMouseUp", mock.mouse))
    canvas:fire("mouseUp", "close")
    local saved = mock.settings[SETTINGS_KEY][APP_ID]
    T.eq(saved.x, 112, "saved x")
    T.eq(saved.y, 60, "saved y")
    T.eq(win.calls[1], "focus", "app refocused")
    T.eq(#win.calls, 1, "the button's action didn't run")
  end)

  T.test("a saved spot is used for the app's windows", function()
    local _, s, win = setup({ offsets = { [APP_ID] = { x = 300, y = 5 } } })
    local pos = canvasFor(s, win):topLeft()
    T.eq(pos.x, 300, "x")
    T.eq(pos.y, 5, "y")
  end)

  T.test("Option-double-click resets the app's spot", function()
    local mock, s, win = setup({ offsets = { [APP_ID] = { x = 300, y = 5 } } })
    local canvas = canvasFor(s, win)
    mock.modifiers = { alt = true }
    canvas:fire("mouseDown", "close")
    mock.taps[#mock.taps].fn(mock.mouseEvent("leftMouseUp", mock.mouse))
    canvas:fire("mouseUp", "close")
    mock.advance(0.2)
    click(canvas, "close")
    T.eq(mock.settings[SETTINGS_KEY][APP_ID], nil, "saved spot cleared")
    T.eq(canvas:topLeft().x, 12, "back at default x")
    T.eq(canvas:topLeft().y, 10, "back at default y")
    for _, call in ipairs(win.calls) do T.ok(call ~= "close", "window not closed") end
  end)

  T.test("two slow Option-clicks don't reset", function()
    local mock, s, win = setup({ offsets = { [APP_ID] = { x = 300, y = 5 } } })
    local canvas = canvasFor(s, win)
    mock.modifiers = { alt = true }
    mock.mouse = { x = 300, y = 5 }
    canvas:fire("mouseDown", "close")
    mock.taps[#mock.taps].fn(mock.mouseEvent("leftMouseUp", mock.mouse))
    canvas:fire("mouseUp", "close")
    mock.advance(1)
    canvas:fire("mouseDown", "close")
    T.ok(mock.settings[SETTINGS_KEY][APP_ID], "saved spot kept")
  end)

  T.test("buttons stay on screen when a saved spot would push them off", function()
    local _, s, win = setup({ offsets = { [APP_ID] = { x = 5000, y = -500 } } })
    local pos = canvasFor(s, win):topLeft()
    T.eq(pos.x, 1920 - (3 * 12 + 2 * 8), "x clamped to the right edge")
    T.eq(pos.y, 0, "y clamped to the top")
  end)

  T.test("resetPositions() moves every app back to the default", function()
    local mock, s, win = setup({ offsets = { [APP_ID] = { x = 300, y = 5 } } })
    s:resetPositions()
    T.eq(mock.settings[SETTINGS_KEY], nil, "settings cleared")
    T.eq(canvasFor(s, win):topLeft().x, 12, "moved back")
  end)

  T.test("stop() removes all buttons", function()
    local _, s, win = setup()
    local canvas = canvasFor(s, win)
    s:stop()
    T.eq(canvas.deleted, true, "canvas deleted")
    T.eq(s:isRunning(), false, "running")
  end)
end
