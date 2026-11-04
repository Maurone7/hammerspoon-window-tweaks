-- A fake `hs` API, just enough to run the Spoons outside Hammerspoon.
-- Timers run on a fake clock that tests move forward with `mock.advance()`.
local M = {}

local function newMock()
  local mock = {
    clock = 0,
    timers = {},
    taps = {},
    canvases = {},
    menubars = {},
    posted = {},
    settings = {},
    pasteboardCount = 0,
    modifiers = {},
    mouse = { x = 0, y = 0 },
    windows = {},
    frontApp = nil,
    elementAt = function() return nil end,
    focusedElement = nil,
    reloaded = false,
  }

  -- Timers ------------------------------------------------------------------

  local function newTimer(kind, interval, fn, predicate)
    local t = { kind = kind, interval = interval, fn = fn, predicate = predicate, active = true }
    t.due = mock.clock + interval
    function t:stop() self.active = false; return self end
    function t:start() self.active = true; return self end
    function t:running() return self.active end
    table.insert(mock.timers, t)
    return t
  end

  --- Moves the fake clock forward, firing every timer that comes due.
  function mock.advance(seconds)
    local target = mock.clock + seconds
    while true do
      local nextTimer
      for _, t in ipairs(mock.timers) do
        if t.active and t.due <= target and (not nextTimer or t.due < nextTimer.due) then nextTimer = t end
      end
      if not nextTimer then break end
      mock.clock = nextTimer.due
      if nextTimer.kind == "every" then
        nextTimer.due = nextTimer.due + nextTimer.interval
        nextTimer.fn(nextTimer)
      elseif nextTimer.kind == "after" then
        nextTimer.active = false
        nextTimer.fn(nextTimer)
      elseif nextTimer.predicate() then
        nextTimer.active = false
        nextTimer.fn(nextTimer)
      else
        nextTimer.due = nextTimer.due + nextTimer.interval
      end
    end
    mock.clock = target
  end

  -- Events --------------------------------------------------------------------

  local types = { leftMouseDown = 1, leftMouseUp = 2, leftMouseDragged = 6, keyDown = 10 }

  local function flagsObject(flags)
    local f = {}
    for k, v in pairs(flags or {}) do f[k] = v end
    return setmetatable(f, { __index = {
      containExactly = function(self, list)
        local want = {}
        for _, m in ipairs(list) do want[m] = true end
        for _, m in ipairs({ "cmd", "alt", "shift", "ctrl", "fn" }) do
          if (self[m] or false) ~= (want[m] or false) then return false end
        end
        return true
      end,
    } })
  end

  local function newEvent(fields)
    local e = { props = {} }
    for k, v in pairs(fields) do e[k] = v end
    function e:getType() return self.type end
    function e:getKeyCode() return self.keyCode end
    function e:getFlags() return flagsObject(self.flags) end
    function e:location() return self.point end
    function e:getProperty(p) return self.props[p] end
    function e:setProperty(p, v) self.props[p] = v; return self end
    function e:copy()
      local c = newEvent(fields)
      for k, v in pairs(self.props) do c.props[k] = v end
      return c
    end
    function e:post() table.insert(mock.posted, self); return self end
    return e
  end

  function mock.keyEvent(key, flags)
    return newEvent({ type = types.keyDown, keyCode = M.keycodes[key], key = key, flags = flags })
  end

  function mock.mouseEvent(kind, point, flags)
    return newEvent({ type = types[kind], kind = kind, point = point, flags = flags })
  end

  -- Windows, apps and accessibility elements ----------------------------------

  function mock.app(bundleID, pid, name)
    return {
      bundleID = function() return bundleID end,
      pid = function() return pid end,
      name = function() return name or bundleID end,
    }
  end

  function mock.window(opts)
    local w = {
      calls = {},
      fullscreen = opts.fullscreen ~= false,
      _id = opts.id,
      _frame = opts.frame or { x = 0, y = 0, w = 1920, h = 1080 },
      _screen = opts.screen or { x = 0, y = 0, w = 1920, h = 1080 },
      _app = opts.app,
    }
    function w:id() return self._id end
    function w:frame() return self._frame end
    function w:screen()
      local s = self._screen
      return { fullFrame = function() return s end }
    end
    function w:application() return self._app end
    function w:isFullScreen() return self.fullscreen end
    function w:setFullScreen(v) table.insert(self.calls, "setFullScreen:" .. tostring(v)) end
    function w:minimize() table.insert(self.calls, "minimize") end
    function w:close() table.insert(self.calls, "close") end
    function w:focus() table.insert(self.calls, "focus") end
    return w
  end

  function mock.element(attrs, pid, hsWindow)
    local el = { attrs = attrs }
    function el:attributeValue(name) return self.attrs[name] end
    function el:pid() return pid end
    function el:asHSWindow() return hsWindow end
    return el
  end

  -- Canvases ------------------------------------------------------------------

  local function newCanvas(frame)
    local c = { frame = { x = frame.x, y = frame.y }, elements = {}, showing = false, deleted = false }
    local methods = {}
    function methods:level() return self end
    function methods:behaviorAsLabels() return self end
    function methods:appendElements(...)
      for _, el in ipairs({ ... }) do
        table.insert(self.elements, el)
        if el.id then self.elements[el.id] = el end
      end
      return self
    end
    function methods:canvasMouseEvents() return self end
    function methods:mouseCallback(fn) self.callback = fn; return self end
    function methods:topLeft(p)
      if p == nil then return { x = self.frame.x, y = self.frame.y } end
      self.frame = { x = p.x, y = p.y }
      return self
    end
    function methods:show() self.showing = true; return self end
    function methods:hide() self.showing = false; return self end
    function methods:isShowing() return self.showing end
    function methods:delete() self.deleted = true; self.showing = false end
    function methods:imageFromCanvas() return { image = true } end
    --- Simulates a mouse event on the element with this id.
    function methods:fire(event, id) self.callback(self, event, id) end
    setmetatable(c, { __index = function(t, k)
      return methods[k] or rawget(t, "elements")[k]
    end })
    table.insert(mock.canvases, c)
    return c
  end

  -- The hs table --------------------------------------------------------------

  local tapNew = function(eventTypes, fn)
    local tap = { types = eventTypes, fn = fn, enabled = false }
    function tap:start() self.enabled = true; return self end
    function tap:stop() self.enabled = false; return self end
    function tap:isEnabled() return self.enabled end
    table.insert(mock.taps, tap)
    return tap
  end

  local function watcher()
    return { new = function()
      return { start = function(self) return self end, stop = function(self) return self end }
    end }
  end

  mock.hs = {
    timer = {
      doEvery = function(interval, fn) return newTimer("every", interval, fn) end,
      doAfter = function(delay, fn) return newTimer("after", delay, fn) end,
      waitUntil = function(predicate, fn, interval) return newTimer("until", interval or 1, fn, predicate) end,
      secondsSinceEpoch = function() return mock.clock end,
    },
    eventtap = {
      new = tapNew,
      event = {
        types = types,
        properties = { eventSourceUserData = 42 },
        newKeyEvent = function(mods, key, down) return { mods = mods, key = key, down = down } end,
      },
      checkKeyboardModifiers = function() return mock.modifiers end,
      doubleClickInterval = function() return 0.5 end,
    },
    keycodes = { map = M.keycodes },
    pasteboard = { changeCount = function() return mock.pasteboardCount end },
    application = { frontmostApplication = function() return mock.frontApp end },
    axuielement = {
      systemElementAtPosition = function(p) return mock.elementAt(p) end,
      systemWideElement = function()
        return mock.element({ AXFocusedUIElement = mock.focusedElement })
      end,
    },
    processInfo = { processID = 999 },
    settings = {
      get = function(k) return mock.settings[k] end,
      set = function(k, v) mock.settings[k] = v end,
      clear = function(k) mock.settings[k] = nil end,
    },
    canvas = { new = newCanvas, windowLevels = { overlay = 102 } },
    window = { orderedWindows = function() return mock.windows end },
    spaces = { watcher = watcher() },
    screen = { watcher = watcher() },
    mouse = { absolutePosition = function() return { x = mock.mouse.x, y = mock.mouse.y } end },
    menubar = {
      new = function()
        local mb = { deleted = false }
        function mb:setIcon(image, template) self.icon, self.template = image, template; return self end
        function mb:setTooltip(t) self.tooltip = t; return self end
        function mb:setMenu(m) self.menu = m; return self end
        function mb:delete() self.deleted = true end
        table.insert(mock.menubars, mb)
        return mb
      end,
    },
    reload = function() mock.reloaded = true end,
  }

  return mock
end

M.keycodes = { x = 7, c = 8, v = 9 }
M.new = newMock

return M
