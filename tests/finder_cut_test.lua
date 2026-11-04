local CMD = { cmd = true }

local function hasMods(event, mods)
  local want = {}
  for _, m in ipairs(mods) do want[m] = true end
  if #event.mods ~= #mods then return false end
  for _, m in ipairs(event.mods) do
    if not want[m] then return false end
  end
  return true
end

return function(T)
  local function finder()
    local mock = T.setup()
    mock.frontApp = mock.app("com.apple.finder", 100)
    local s = T.load("FinderCut"):start()
    return mock, s, mock.taps[1]
  end

  -- Presses Cmd+X and lets Finder "copy" the selection.
  local function cut(mock, tap)
    local consumed, events = tap.fn(mock.keyEvent("x", CMD))
    mock.pasteboardCount = mock.pasteboardCount + 1
    mock.advance(0.1)
    return consumed, events
  end

  T.test("Cmd+X in Finder is turned into Cmd+C", function()
    local mock, _, tap = finder()
    local consumed, events = tap.fn(mock.keyEvent("x", CMD))
    T.eq(consumed, true, "consumed")
    T.eq(events[1].key, "c", "key")
    T.ok(hasMods(events[1], { "cmd" }), "only Cmd held")
    T.eq(events[1].down, true, "key down")
    T.eq(events[2].down, false, "key up")
  end)

  T.test("Cmd+V after a cut becomes Move Item Here (Cmd+Option+V)", function()
    local mock, _, tap = finder()
    cut(mock, tap)
    local consumed, events = tap.fn(mock.keyEvent("v", CMD))
    T.eq(consumed, true, "consumed")
    T.eq(events[1].key, "v", "key")
    T.ok(hasMods(events[1], { "cmd", "alt" }), "Cmd+Option held")
  end)

  T.test("a cut is used up by one paste", function()
    local mock, _, tap = finder()
    cut(mock, tap)
    tap.fn(mock.keyEvent("v", CMD))
    T.eq(tap.fn(mock.keyEvent("v", CMD)), false, "second Cmd+V passes through")
  end)

  T.test("Cmd+X with nothing selected doesn't arm a cut", function()
    local mock, _, tap = finder()
    tap.fn(mock.keyEvent("x", CMD))
    mock.advance(1.5) -- clipboard never changes
    T.eq(tap.fn(mock.keyEvent("v", CMD)), false, "Cmd+V passes through")
  end)

  T.test("copying anything else cancels the cut", function()
    local mock, _, tap = finder()
    cut(mock, tap)
    mock.pasteboardCount = mock.pasteboardCount + 1 -- copied in another app
    T.eq(tap.fn(mock.keyEvent("v", CMD)), false, "Cmd+V passes through")
  end)

  T.test("plain Cmd+V without a cut passes through", function()
    local mock, _, tap = finder()
    T.eq(tap.fn(mock.keyEvent("v", CMD)), false, "Cmd+V passes through")
  end)

  T.test("other apps are left alone", function()
    local mock, _, tap = finder()
    mock.frontApp = mock.app("com.microsoft.VSCode", 200)
    T.eq(tap.fn(mock.keyEvent("x", CMD)), false, "Cmd+X passes through")
  end)

  T.test("text editing in Finder is left alone", function()
    local mock, _, tap = finder()
    mock.focusedElement = mock.element({ AXRole = "AXTextField" })
    T.eq(tap.fn(mock.keyEvent("x", CMD)), false, "Cmd+X passes through")
  end)

  T.test("only plain Cmd+X is handled", function()
    local mock, _, tap = finder()
    T.eq(tap.fn(mock.keyEvent("x", { cmd = true, shift = true })), false, "Cmd+Shift+X passes through")
    T.eq(tap.fn(mock.keyEvent("x", {})), false, "X passes through")
  end)

  T.test("the watchdog re-enables a tap macOS turned off", function()
    local mock, _, tap = finder()
    tap:stop()
    mock.advance(5)
    T.eq(tap:isEnabled(), true, "tap enabled")
  end)

  T.test("stop() turns the tap off", function()
    local _, s, tap = finder()
    T.eq(s:isRunning(), true, "running before stop")
    s:stop()
    T.eq(tap:isEnabled(), false, "tap enabled")
    T.eq(s:isRunning(), false, "running after stop")
  end)
end
