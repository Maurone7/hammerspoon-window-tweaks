local POINT = { x = 500, y = 400 }
local REPLAY_PROPERTY = 42 -- the mock's eventSourceUserData

return function(T)
  -- An inactive app (pid 300) with a standard window under the mouse, while
  -- Terminal (pid 200) is active. `attrs` describes the element clicked.
  local function setup(opts)
    opts = opts or {}
    local mock = T.setup()
    mock.frontApp = mock.app("com.apple.Terminal", 200)
    local target = mock.app("com.example.App", 300)
    local win = mock.window({ id = 1, app = target, fullscreen = false })
    local axWin = mock.element({ AXRole = "AXWindow", AXSubrole = opts.windowSubrole or "AXStandardWindow" }, 300, win)
    local attrs = opts.attrs or { AXRole = "AXButton" }
    attrs.AXWindow = axWin
    local el = mock.element(attrs, opts.pid or 300)
    mock.elementAt = function() return el end
    local s = T.load("ClickThrough"):start()
    return mock, s, mock.taps[1], win, target
  end

  local function down(mock, flags) return mock.mouseEvent("leftMouseDown", POINT, flags) end
  local function up(mock) return mock.mouseEvent("leftMouseUp", POINT) end

  T.test("a click on an inactive window focuses it and is replayed once it's active", function()
    local mock, _, tap, win, target = setup()
    T.eq(tap.fn(down(mock)), true, "mouse down held")
    T.eq(win.calls[1], "focus", "window focused")
    T.eq(tap.fn(up(mock)), true, "mouse up held")
    T.eq(#mock.posted, 0, "nothing replayed yet")
    mock.frontApp = target
    mock.advance(0.02)
    T.eq(#mock.posted, 2, "events replayed")
    T.eq(mock.posted[1].kind, "leftMouseDown", "first replayed")
    T.eq(mock.posted[2].kind, "leftMouseUp", "second replayed")
  end)

  T.test("replayed clicks pass through the tap", function()
    local mock, _, tap, _, target = setup()
    tap.fn(down(mock))
    mock.frontApp = target
    mock.advance(0.02)
    T.ok(mock.posted[1].props[REPLAY_PROPERTY], "replay marked")
    T.eq(tap.fn(mock.posted[1]), false, "replayed click passes")
  end)

  T.test("drags are held and replayed in order", function()
    local mock, _, tap, _, target = setup()
    tap.fn(down(mock))
    T.eq(tap.fn(mock.mouseEvent("leftMouseDragged", POINT)), true, "drag held")
    tap.fn(mock.mouseEvent("leftMouseDragged", POINT))
    tap.fn(up(mock))
    mock.frontApp = target
    mock.advance(0.02)
    local kinds = {}
    for _, e in ipairs(mock.posted) do table.insert(kinds, e.kind) end
    T.eq(table.concat(kinds, ","), "leftMouseDown,leftMouseDragged,leftMouseDragged,leftMouseUp", "order")
  end)

  T.test("the click is replayed after activationTimeout if the app never activates", function()
    local mock, _, tap = setup()
    tap.fn(down(mock))
    mock.advance(0.2)
    T.eq(#mock.posted, 0, "still waiting at 0.2 s")
    mock.advance(0.15)
    T.eq(#mock.posted, 1, "replayed after timeout")
  end)

  T.test("the failsafe releases held clicks if the wait never finishes", function()
    local mock, s, tap = setup()
    tap.fn(down(mock))
    s._waitTimer:stop() -- simulate a wait that never fires
    mock.advance(1.1)
    T.eq(tap.fn(up(mock)), false, "next event passes through")
    T.eq(#mock.posted, 1, "held click released")
  end)

  T.test("clicks in the active app pass through", function()
    local mock, _, tap, win, target = setup()
    mock.frontApp = target
    T.eq(tap.fn(down(mock)), false, "passes")
    T.eq(#win.calls, 0, "no focus call")
  end)

  T.test("Cmd-click passes through", function()
    local mock, _, tap = setup()
    T.eq(tap.fn(down(mock, { cmd = true })), false, "passes")
  end)

  T.test("title bars and empty window background pass through", function()
    local mock, _, tap = setup({ attrs = { AXRole = "AXWindow" } })
    T.eq(tap.fn(down(mock)), false, "passes")
  end)

  T.test("a window's title text passes through", function()
    local mock = T.setup()
    local parent = mock.element({ AXRole = "AXWindow" })
    local m, _, tap = setup({ attrs = { AXRole = "AXStaticText", AXParent = parent } })
    T.eq(tap.fn(down(m)), false, "passes")
  end)

  T.test("other static text inside a window is handled", function()
    local mock = T.setup()
    local parent = mock.element({ AXRole = "AXGroup" })
    local m, _, tap = setup({ attrs = { AXRole = "AXStaticText", AXParent = parent } })
    T.eq(tap.fn(down(m)), true, "held")
  end)

  T.test("a window's own traffic lights pass through", function()
    for _, subrole in ipairs({ "AXCloseButton", "AXMinimizeButton", "AXZoomButton", "AXFullScreenButton" }) do
      local mock, _, tap = setup({ attrs = { AXRole = "AXButton", AXSubrole = subrole } })
      T.eq(tap.fn(down(mock)), false, subrole .. " passes")
    end
  end)

  T.test("panels and other non-standard windows pass through", function()
    local mock, _, tap = setup({ windowSubrole = "AXFloatingWindow" })
    T.eq(tap.fn(down(mock)), false, "passes")
  end)

  T.test("Hammerspoon's own canvases pass through", function()
    local mock, _, tap = setup({ pid = 999 })
    T.eq(tap.fn(down(mock)), false, "passes")
  end)

  T.test("clicks with nothing under them pass through", function()
    local mock, _, tap = setup()
    mock.elementAt = function() return nil end
    T.eq(tap.fn(down(mock)), false, "passes")
  end)

  T.test("the watchdog re-enables a tap macOS turned off", function()
    local mock, _, tap = setup()
    tap:stop()
    mock.advance(5)
    T.eq(tap:isEnabled(), true, "tap enabled")
  end)

  T.test("stop() turns the tap off", function()
    local _, s, tap = setup()
    s:stop()
    T.eq(tap:isEnabled(), false, "tap enabled")
    T.eq(s:isRunning(), false, "running")
  end)
end
