--- === WindowSnap ===
---
--- Rectangle-style window snapping: keyboard shortcuts move the focused
--- window to halves, thirds, quarters, fourths, sixths and more, and dragging
--- a window to a screen edge or corner snaps it there, with a preview.
---
--- Pressing a half shortcut again cycles its size through 1/2, 2/3 and 1/3.
--- Holding two half shortcuts at once, like ⌃⌥↑ and ⌃⌥→, snaps to that corner,
--- and ⌃⌥↑ with ⌃⌥↓ toggles native fullscreen.
--- Restore puts a window back where it was before it was snapped, and
--- dragging a snapped window away gives it back its old size.

local obj = {}
obj.__index = obj

obj.name = "WindowSnap"
obj.version = "1.8"
obj.author = "Maurone7"
obj.homepage = "https://github.com/Maurone7/hammerspoon-window-tweaks"
obj.license = "MIT - https://opensource.org/licenses/MIT"

--- WindowSnap.gap
--- Variable
--- Space, in points, between snapped windows and around the screen edges.
--- Default 0.
obj.gap = 0

--- WindowSnap.cycleSizes
--- Variable
--- Sizes, as fractions of the screen, that a half shortcut cycles through
--- when pressed again. Default { 1/2, 2/3, 1/3 }.
obj.cycleSizes = { 1 / 2, 2 / 3, 1 / 3 }

--- WindowSnap.sizeStep
--- Variable
--- Points that Make Larger and Make Smaller move each free edge. Default 30.
obj.sizeStep = 30

--- WindowSnap.dragToSnap
--- Variable
--- Whether dragging a window to a screen edge or corner snaps it. Default true.
obj.dragToSnap = true

--- WindowSnap.snapMargin
--- Variable
--- How close, in points, the mouse must get to a screen edge to snap.
--- Default 5.
obj.snapMargin = 5

--- WindowSnap.cornerSize
--- Variable
--- How far, in points, the corner snap areas reach along each edge. Default 30.
obj.cornerSize = 30

--- WindowSnap.ignoredApps
--- Variable
--- Bundle IDs of apps whose windows are never snapped. Their shortcuts go to
--- the app instead. Apps ignored from the menu are remembered separately.
--- Default {}.
obj.ignoredApps = {}

--- WindowSnap.fullscreenExitWait
--- Variable
--- Seconds to wait after a window leaves fullscreen before moving it to
--- another display, when macOS doesn't say the exit is over. Moving it too
--- soon can cancel the exit. Default 0.1.
obj.fullscreenExitWait = 0.1

--- WindowSnap.arrowCorners
--- Variable
--- Whether holding two half shortcuts at once snaps to the corner between
--- them: ⌃⌥↑ with ⌃⌥→ is Top Right, ⌃⌥↓ with ⌃⌥← is Bottom Left, in either
--- order. ⌃⌥↑ with ⌃⌥↓ toggles fullscreen. Default true.
obj.arrowCorners = true

--- WindowSnap.hotkeys
--- Variable
--- Shortcut for each action, as { mods, key }. Defaults to Rectangle's,
--- except the corners, which are two half shortcuts held together (see
--- WindowSnap.arrowCorners).
--- Change it with WindowSnap:bindHotkeys(). Actions without a shortcut are
--- still in the menu and can be run with WindowSnap:doAction(name).
obj.hotkeys = {
  leftHalf = { { "ctrl", "alt" }, "left" },
  rightHalf = { { "ctrl", "alt" }, "right" },
  topHalf = { { "ctrl", "alt" }, "up" },
  bottomHalf = { { "ctrl", "alt" }, "down" },
  firstThird = { { "ctrl", "alt" }, "d" },
  centerThird = { { "ctrl", "alt" }, "f" },
  lastThird = { { "ctrl", "alt" }, "g" },
  firstTwoThirds = { { "ctrl", "alt" }, "e" },
  lastTwoThirds = { { "ctrl", "alt" }, "t" },
  maximize = { { "ctrl", "alt" }, "return" },
  maximizeHeight = { { "ctrl", "alt", "shift" }, "up" },
  smaller = { { "ctrl", "alt" }, "-" },
  larger = { { "ctrl", "alt" }, "=" },
  center = { { "ctrl", "alt" }, "c" },
  restore = { { "ctrl", "alt" }, "delete" },
  nextDisplay = { { "ctrl", "alt", "cmd" }, "right" },
  previousDisplay = { { "ctrl", "alt", "cmd" }, "left" },
}

local IGNORED_KEY = "windowSnap.ignoredApps"
-- Options changed from the menu, which win over the ones in init.lua.
local OPTIONS_KEY = "windowSnap.options"
local GAP_CHOICES = { 0, 5, 10, 20 }
-- Actions run by holding two half shortcuts together, and the halves that
-- make each one.
local CHORD_HALVES = {
  topLeft = { "topHalf", "leftHalf" },
  topRight = { "topHalf", "rightHalf" },
  bottomLeft = { "bottomHalf", "leftHalf" },
  bottomRight = { "bottomHalf", "rightHalf" },
  fullscreen = { "topHalf", "bottomHalf" },
}
local CHORDS = {}
for chord, pair in pairs(CHORD_HALVES) do
  CHORDS[pair[1] .. "+" .. pair[2]] = chord
  CHORDS[pair[2] .. "+" .. pair[1]] = chord
end
local MIN_SIZE = 100
-- Frames within this many points count as the same, since some apps round
-- their size (Terminal snaps to whole characters, for example).
local TOLERANCE = 2
-- How far the mouse can drag before a window that hasn't moved is taken to
-- be a text selection or similar, not a window move.
local DRAG_GIVE_UP = 50
-- Longest time, in seconds, to move a fullscreen window to another display.
local FULLSCREEN_TIMEOUT = 4
-- macOS ignores requests to go fullscreen for about a second after a window
-- leaves fullscreen. Ask this often, in seconds, until one takes, for at most
-- REFULLSCREEN_TIMEOUT seconds.
local REFULLSCREEN_RETRY = 0.1
local REFULLSCREEN_TIMEOUT = 3

-- Unit rects are { x, y, w, h } as fractions of the screen. Functions get
-- the cycle size and whether the screen is taller than wide.
local function half(side)
  return function(size)
    if side == "left" then return { 0, 0, size, 1 } end
    if side == "right" then return { 1 - size, 0, size, 1 } end
    if side == "top" then return { 0, 0, 1, size } end
    return { 0, 1 - size, 1, size }
  end
end

-- Columns on a landscape screen, rows on a portrait one.
local function strip(parts, first, span)
  return function(_, portrait)
    if portrait then return { 0, first / parts, 1, span / parts } end
    return { first / parts, 0, span / parts, 1 }
  end
end

local function sixth(i)
  return function(_, portrait)
    local cols = portrait and 2 or 3
    local rows = 6 / cols
    return { (i % cols) / cols, (i // cols) / rows, 1 / cols, 1 / rows }
  end
end

local function clampAxis(pos, len, lo, size)
  len = math.min(len, size)
  return math.max(lo, math.min(pos, lo + size - len)), len
end

-- Moves each edge of one axis by `d`, except edges against the screen edge,
-- so a left-half window grows and shrinks on its right side only.
local function resizeAxis(pos, len, lo, size, d)
  local hi, max = pos + len, lo + size
  local loFixed, hiFixed = pos <= lo + TOLERANCE, hi >= max - TOLERANCE
  if loFixed and hiFixed then loFixed, hiFixed = false, false end
  local newLo = loFixed and pos or math.max(lo, pos - d)
  local newHi = hiFixed and hi or math.min(max, hi + d)
  if newHi - newLo < MIN_SIZE then return pos, len end
  return newLo, newHi - newLo
end

local function spans(pos, len, lo, size)
  return pos <= lo + TOLERANCE and pos + len >= lo + size - TOLERANCE
end

-- An axis that already spans the screen, like the height of a half, is left
-- alone unless the window is maximized.
local function resize(f, b, d)
  local fullW, fullH = spans(f.x, f.w, b.x, b.w), spans(f.y, f.h, b.y, b.h)
  local x, y, w, h = f.x, f.y, f.w, f.h
  if fullH or not fullW then x, w = resizeAxis(f.x, f.w, b.x, b.w, d) end
  if fullW or not fullH then y, h = resizeAxis(f.y, f.h, b.y, b.h, d) end
  return { x = x, y = y, w = w, h = h }
end

local function move(dx, dy)
  return function(f, b)
    local x, w = clampAxis(f.x, f.w, b.x, b.w)
    local y, h = clampAxis(f.y, f.h, b.y, b.h)
    if dx < 0 then x = b.x elseif dx > 0 then x = b.x + b.w - w end
    if dy < 0 then y = b.y elseif dy > 0 then y = b.y + b.h - h end
    return { x = x, y = y, w = w, h = h }
  end
end

-- `unit` places the window on its screen, `frame` computes a new frame from
-- the current one and the usable screen area, `display` moves it to another
-- screen.
local ACTIONS = {
  leftHalf = { title = "Left Half", unit = half("left"), cycles = true },
  rightHalf = { title = "Right Half", unit = half("right"), cycles = true },
  centerHalf = { title = "Center Half", unit = { 1 / 4, 0, 1 / 2, 1 } },
  topHalf = { title = "Top Half", unit = half("top"), cycles = true },
  bottomHalf = { title = "Bottom Half", unit = half("bottom"), cycles = true },
  topLeft = { title = "Top Left", unit = { 0, 0, 1 / 2, 1 / 2 } },
  topRight = { title = "Top Right", unit = { 1 / 2, 0, 1 / 2, 1 / 2 } },
  bottomLeft = { title = "Bottom Left", unit = { 0, 1 / 2, 1 / 2, 1 / 2 } },
  bottomRight = { title = "Bottom Right", unit = { 1 / 2, 1 / 2, 1 / 2, 1 / 2 } },
  firstThird = { title = "First Third", unit = strip(3, 0, 1) },
  centerThird = { title = "Center Third", unit = strip(3, 1, 1) },
  lastThird = { title = "Last Third", unit = strip(3, 2, 1) },
  firstTwoThirds = { title = "First Two Thirds", unit = strip(3, 0, 2) },
  lastTwoThirds = { title = "Last Two Thirds", unit = strip(3, 1, 2) },
  firstFourth = { title = "First Fourth", unit = strip(4, 0, 1) },
  secondFourth = { title = "Second Fourth", unit = strip(4, 1, 1) },
  thirdFourth = { title = "Third Fourth", unit = strip(4, 2, 1) },
  lastFourth = { title = "Last Fourth", unit = strip(4, 3, 1) },
  firstThreeFourths = { title = "First Three Fourths", unit = strip(4, 0, 3) },
  lastThreeFourths = { title = "Last Three Fourths", unit = strip(4, 1, 3) },
  topLeftSixth = { title = "Top Left Sixth", unit = sixth(0) },
  topCenterSixth = { title = "Top Center Sixth", unit = sixth(1) },
  topRightSixth = { title = "Top Right Sixth", unit = sixth(2) },
  bottomLeftSixth = { title = "Bottom Left Sixth", unit = sixth(3) },
  bottomCenterSixth = { title = "Bottom Center Sixth", unit = sixth(4) },
  bottomRightSixth = { title = "Bottom Right Sixth", unit = sixth(5) },
  maximize = { title = "Maximize", unit = { 0, 0, 1, 1 } },
  fullscreen = { title = "Toggle Fullscreen", fullscreen = true },
  almostMaximize = { title = "Almost Maximize", unit = { 0.05, 0.05, 0.9, 0.9 } },
  maximizeHeight = {
    title = "Maximize Height",
    frame = function(f, b)
      local x, w = clampAxis(f.x, f.w, b.x, b.w)
      return { x = x, y = b.y, w = w, h = b.h }
    end,
  },
  smaller = { title = "Make Smaller", frame = function(f, b, step) return resize(f, b, -step) end, repeats = true },
  larger = { title = "Make Larger", frame = function(f, b, step) return resize(f, b, step) end, repeats = true },
  center = {
    title = "Center",
    frame = function(f, b)
      local w, h = math.min(f.w, b.w), math.min(f.h, b.h)
      return { x = b.x + (b.w - w) / 2, y = b.y + (b.h - h) / 2, w = w, h = h }
    end,
  },
  restore = { title = "Restore", restore = true },
  moveLeft = { title = "Move Left", frame = move(-1, 0) },
  moveRight = { title = "Move Right", frame = move(1, 0) },
  moveUp = { title = "Move Up", frame = move(0, -1) },
  moveDown = { title = "Move Down", frame = move(0, 1) },
  nextDisplay = { title = "Next Display", display = "next" },
  previousDisplay = { title = "Previous Display", display = "previous" },
}

-- Menu layout: groups are separated by lines, tables become submenus.
local MENU = {
  { "leftHalf", "rightHalf", "centerHalf", "topHalf", "bottomHalf" },
  { "topLeft", "topRight", "bottomLeft", "bottomRight" },
  { "firstThird", "centerThird", "lastThird", "firstTwoThirds", "lastTwoThirds" },
  {
    { title = "Fourths", "firstFourth", "secondFourth", "thirdFourth", "lastFourth",
      "firstThreeFourths", "lastThreeFourths" },
    { title = "Sixths", "topLeftSixth", "topCenterSixth", "topRightSixth",
      "bottomLeftSixth", "bottomCenterSixth", "bottomRightSixth" },
    { title = "Move to Edge", "moveLeft", "moveRight", "moveUp", "moveDown" },
  },
  { "maximize", "fullscreen", "almostMaximize", "maximizeHeight", "smaller", "larger", "center", "restore" },
  { "nextDisplay", "previousDisplay" },
}

local SYMBOLS = {
  ctrl = "⌃", alt = "⌥", shift = "⇧", cmd = "⌘",
  left = "←", right = "→", up = "↑", down = "↓", ["return"] = "↩", delete = "⌫",
}
local MOD_ORDER = { "ctrl", "alt", "shift", "cmd" }

-- Whether exactly `mods` are held. Ignores fn, which macOS sets on every
-- arrow key press.
local function holdsExactly(flags, mods)
  local want = {}
  for _, m in ipairs(mods) do want[m] = true end
  for _, m in ipairs(MOD_ORDER) do
    if (flags[m] or false) ~= (want[m] or false) then return false end
  end
  return true
end

local function inset(r, d)
  return { x = r.x + d, y = r.y + d, w = r.w - 2 * d, h = r.h - 2 * d }
end

-- Rounds the edges rather than the size, so neighbours meet exactly.
local function round(r)
  local function n(v) return math.floor(v + 0.5) end
  local x, y = n(r.x), n(r.y)
  return { x = x, y = y, w = n(r.x + r.w) - x, h = n(r.y + r.h) - y }
end

local function near(a, b)
  return math.abs(a.x - b.x) <= TOLERANCE and math.abs(a.y - b.y) <= TOLERANCE
    and math.abs(a.w - b.w) <= TOLERANCE and math.abs(a.h - b.h) <= TOLERANCE
end

local function contains(r, p)
  return p.x >= r.x and p.x < r.x + r.w and p.y >= r.y and p.y < r.y + r.h
end

local function shortcutText(mods, ...)
  local text = ""
  for _, m in ipairs(MOD_ORDER) do
    for _, held in ipairs(mods) do
      if held == m then text = text .. SYMBOLS[m] end
    end
  end
  for _, key in ipairs({ ... }) do text = text .. (SYMBOLS[key] or key:upper()) end
  return text
end

local function windowAt(point)
  local el = hs.axuielement.systemElementAtPosition(point)
  if not el then return nil end
  local axWin = el:attributeValue("AXRole") == "AXWindow" and el or el:attributeValue("AXWindow")
  return axWin and axWin:asHSWindow()
end

-- The same place and size relative to another screen's usable area.
local function translate(frame, from, to)
  return round({
    x = to.x + (frame.x - from.x) / from.w * to.w,
    y = to.y + (frame.y - from.y) / from.h * to.h,
    w = frame.w / from.w * to.w,
    h = frame.h / from.h * to.h,
  })
end

-- Whether a screen is showing a fullscreen app. Normal windows can't go
-- there: macOS puts them on that display's desktop Space, out of sight.
local function showsFullscreenApp(screen)
  local ok, space = pcall(hs.spaces.activeSpaceOnScreen, screen)
  return ok and space ~= nil and hs.spaces.spaceType(space) == "fullscreen"
end

-- The next screen in `direction` ("next" or "previous") that a window can
-- move to, skipping screens showing a fullscreen app unless `anyScreen`.
local function screenToward(screen, direction, anyScreen)
  local to = screen
  for _ = 1, #hs.screen.allScreens() do
    to = to[direction](to)
    if to:id() == screen:id() then return nil end
    if anyScreen or not showsFullscreenApp(to) then return to end
  end
  return nil
end

local function screenAt(point)
  for _, screen in ipairs(hs.screen.allScreens()) do
    if contains(screen:fullFrame(), point) then return screen end
  end
  return nil
end

function obj:_ignored(app)
  local bundleID = app and app:bundleID()
  if not bundleID then return false end
  if self._ignoredFromMenu[bundleID] then return true end
  for _, id in ipairs(self.ignoredApps) do
    if id == bundleID then return true end
  end
  return false
end

-- Some apps, mostly games, draw a window that Accessibility can't see or
-- move, so there's no focused window even though one is on screen. Say so,
-- rather than have the shortcut silently do nothing.
local lastExplained = -math.huge
local function explainNoWindow()
  -- Once is enough when a chord's two keys both land here.
  if hs.timer.secondsSinceEpoch() - lastExplained < 2 then return end
  local app = hs.application.frontmostApplication()
  if not app or app:bundleID() == "com.apple.finder" then return end
  local pid, onScreen = app:pid(), false
  for _, info in ipairs(hs.window.list(true) or {}) do
    if info.kCGWindowOwnerPID == pid and info.kCGWindowLayer == 0 and info.kCGWindowIsOnscreen then
      onScreen = true
      break
    end
  end
  if not onScreen then return end
  local name = app:name()
  if not name or name == "" then name = (app:path() or ""):match("([^/]+)%.app$") or "This app" end
  lastExplained = hs.timer.secondsSinceEpoch()
  hs.alert.show(name .. " doesn't let other apps move or resize its window. Use its own display settings.")
end

function obj:_canFullscreen(win)
  return win:isStandard() and not self:_ignored(win:application())
end

function obj:_snappable(win)
  return win:isStandard() and not win:isFullScreen() and not self:_ignored(win:application())
end

-- The frame for a unit rect on a screen's usable area, with `gap` points
-- around the screen edges and between neighbouring windows.
function obj:_unitFrame(action, screenFrame, size)
  local u = action.unit
  if type(u) == "function" then u = u(size or self.cycleSizes[1], screenFrame.h > screenFrame.w) end
  local area = inset(screenFrame, self.gap / 2)
  return round(inset({
    x = area.x + u[1] * area.w,
    y = area.y + u[2] * area.h,
    w = u[3] * area.w,
    h = u[4] * area.h,
  }, self.gap / 2))
end

-- Sets the frame and remembers where the window was before, for Restore.
-- A window moved by hand since its last snap starts a new history.
function obj:_place(win, frame, name, cycle, before)
  local id = win:id()
  local state = self._state[id]
  if not (state and near(win:frame(), state.frame)) then
    state = { restore = before or win:frame() }
    self._state[id] = state
  end
  win:setFrame(frame, 0)
  -- An app with a minimum size can end up larger than asked and hang off
  -- the screen, like a Last Third that's too wide. Pull it back on.
  local actual = win:frame()
  if actual.w > frame.w + TOLERANCE or actual.h > frame.h + TOLERANCE then
    local b = inset(win:screen():frame(), self.gap)
    local x = clampAxis(actual.x, actual.w, b.x, b.w)
    local y = clampAxis(actual.y, actual.h, b.y, b.h)
    if x ~= actual.x or y ~= actual.y then
      win:setFrame({ x = x, y = y, w = actual.w, h = actual.h }, 0)
      actual = win:frame()
    end
  end
  state.action, state.cycle, state.frame = name, cycle, actual
end

--- WindowSnap:doAction(name[, win])
--- Method
--- Runs a snapping action, such as "leftHalf" or "nextDisplay".
---
--- Parameters:
---  * name - The action's name, as in WindowSnap.hotkeys or the menu
---  * win - Optional hs.window to move. Defaults to the focused window
---
--- Returns:
---  * true if the window was moved, false if there was no window to move
function obj:doAction(name, win)
  local action = ACTIONS[name]
  assert(action, "unknown WindowSnap action: " .. tostring(name))
  if not win then
    win = hs.window.focusedWindow()
    if not win then
      explainNoWindow()
      return false
    end
  end
  if action.fullscreen then
    if not self:_canFullscreen(win) then return false end
    if self._fullscreenTimer then
      -- The first key of ⌃⌥↑↓ already started leaving fullscreen: that's
      -- the toggle, so just don't snap afterwards.
      self:_stopFullscreenTimer()
      return true
    end
    win:setFullScreen(not win:isFullScreen())
    return true
  end
  -- On a fullscreen window, leave fullscreen first, then do the action. One
  -- that's still leaving does the newest action instead, like the corner of
  -- a chord whose first key was the half.
  local leaving = self._leavingWin and self._leavingWin:id() == win:id()
  if (win:isFullScreen() or leaving) and self:_canFullscreen(win) and not action.restore then
    if action.display then return self:_moveFullscreen(win, action.display) end
    self:_afterLeavingFullscreen(win, function() self:doAction(name, win) end)
    return true
  end
  if not win or not self:_snappable(win) then return false end
  local id, frame = win:id(), win:frame()
  local state = self._state[id]

  if action.restore then
    if not state then return false end
    self._state[id] = nil
    win:setFrame(state.restore, 0)
    return true
  end

  local screen = win:screen()
  local s = screen:frame()
  local cycle = 1
  if action.cycles and state and state.action == name and near(frame, state.frame) then
    cycle = state.cycle % #self.cycleSizes + 1
  end

  local target
  if action.display then
    local to = screenToward(screen, action.display)
    if not to then
      if #hs.screen.allScreens() > 1 then hs.alert.show("The other display is showing a fullscreen app") end
      return false
    end
    target = translate(frame, s, to:frame())
  elseif action.frame then
    target = round(action.frame(frame, inset(s, self.gap), self.sizeStep))
  else
    target = self:_unitFrame(action, s, self.cycleSizes[cycle])
  end
  self:_place(win, target, name, cycle)
  return true
end

-- Whether a window is back on a desktop Space: false while it's still on
-- its fullscreen Space, nil when macOS doesn't say (during the transition
-- it's on no Space at all).
local function onDesktopSpace(win)
  local ok, spaces = pcall(hs.spaces.windowSpaces, win)
  if not ok or not spaces or #spaces == 0 then return nil end
  for _, id in ipairs(spaces) do
    if hs.spaces.spaceType(id) == "fullscreen" then return false end
  end
  return true
end

function obj:_stopFullscreenTimer()
  if self._fullscreenTimer then self._fullscreenTimer:stop() end
  self._fullscreenTimer, self._leavingWin = nil, nil
end

-- Takes a window out of fullscreen and calls `after` once the exit animation
-- has finished. macOS reports the window as not fullscreen, at its final
-- frame, while the animation is still running, and moving it then cancels
-- the exit, so wait for it to be back on a desktop Space.
function obj:_afterLeavingFullscreen(win, after)
  self:_stopFullscreenTimer()
  self._leavingWin = win
  local started = hs.timer.secondsSinceEpoch()
  local last, stable = nil, 0
  win:setFullScreen(false)
  self._fullscreenTimer = hs.timer.doEvery(0.05, function()
    local elapsed = hs.timer.secondsSinceEpoch() - started
    if elapsed > FULLSCREEN_TIMEOUT then
      self:_stopFullscreenTimer() -- it never left fullscreen; leave it be
      return
    end
    if win:isFullScreen() then return end
    local f = win:frame()
    stable = (last and near(f, last)) and stable + 1 or 0
    last = f
    if stable < 1 then return end
    local desktop = onDesktopSpace(win)
    if desktop == false and elapsed < FULLSCREEN_TIMEOUT then return end
    if desktop == nil and elapsed < self.fullscreenExitWait then return end
    self:_stopFullscreenTimer()
    after()
  end)
end

-- A fullscreen window can't be moved directly, so leave fullscreen, move
-- it, and go fullscreen again there; macOS gives it a new fullscreen Space
-- on that display.
function obj:_moveFullscreen(win, direction)
  local from = win:screen()
  local to = screenToward(from, direction, true)
  if not to then return false end
  self:_afterLeavingFullscreen(win, function()
    local target = translate(win:frame(), from:frame(), to:frame())
    local deadline = hs.timer.secondsSinceEpoch() + 2
    local landedAt
    win:setFrame(target, 0)
    -- Ask right away; if macOS isn't ready yet, the timer asks again.
    win:setFullScreen(true)
    local lastAsk = hs.timer.secondsSinceEpoch()
    self._fullscreenTimer = hs.timer.doEvery(0.05, function()
      local now = hs.timer.secondsSinceEpoch()
      if not landedAt then
        if win:screen():id() ~= to:id() and now < deadline then
          win:setFrame(target, 0)
          return
        end
        -- Even if the move didn't take, don't leave the window out of fullscreen.
        landedAt = now
      end
      if win:isFullScreen() or now - landedAt > REFULLSCREEN_TIMEOUT then
        self:_stopFullscreenTimer()
        return
      end
      if lastAsk and now - lastAsk < REFULLSCREEN_RETRY - 0.01 then return end
      lastAsk = now
      win:setFullScreen(true)
    end)
  end)
  return true
end

--- WindowSnap:bindHotkeys(mapping)
--- Method
--- Sets the shortcuts, replacing WindowSnap.hotkeys.
---
--- Parameters:
---  * mapping - A table of action name to { mods, key }. Leave an action out
---    to give it no shortcut
---
--- Returns:
---  * The WindowSnap object
function obj:bindHotkeys(mapping)
  for name in pairs(mapping) do
    assert(ACTIONS[name], "unknown WindowSnap action: " .. tostring(name))
  end
  self.hotkeys = mapping
  if self:isRunning() then
    self:_unbindHotkeys()
    self:_bindHotkeys()
  end
  return self
end

-- The half shortcuts are read from an event tap instead of hs.hotkey, which
-- can't tell that another key is still held down.
function obj:_startHalfKeys()
  local types = hs.eventtap.event.types
  local AUTOREPEAT = hs.eventtap.event.properties.keyboardEventAutorepeat
  local halves = {} -- keycode -> { name, mods }
  self._tapHalves = {}
  for _, pair in pairs(CHORD_HALVES) do
    for _, name in ipairs(pair) do
      local hotkey = self.hotkeys[name]
      if hotkey and not self._tapHalves[name] then
        halves[hs.keycodes.map[hotkey[2]]] = { name = name, mods = hotkey[1] }
        self._tapHalves[name] = true
      end
    end
  end
  -- Halves whose key is down, so a second one makes a chord, with the
  -- focused window's frame from before the half moved it.
  local held = {}

  self._keyTap = hs.eventtap.new({ types.keyDown, types.keyUp, types.flagsChanged }, function(e)
    local t = e:getType()
    if t == types.flagsChanged then
      -- All modifiers released: forget held keys, in case a key-up was missed.
      local f = e:getFlags()
      if not (f.cmd or f.alt or f.ctrl or f.shift) then held = {} end
      return false
    end
    local pressed = halves[e:getKeyCode()]
    if not pressed then return false end
    if t == types.keyUp then
      local was = held[pressed.name] ~= nil
      held[pressed.name] = nil
      return was
    end
    if not holdsExactly(e:getFlags(), pressed.mods) then return false end
    if self:_ignored(hs.application.frontmostApplication()) then return false end
    if e:getProperty(AUTOREPEAT) == 1 then return true end
    local win = hs.window.focusedWindow()
    held[pressed.name] = { win = win, frame = win and win:frame(), fullscreen = win and win:isFullScreen() }
    for other, first in pairs(held) do
      local chord = CHORDS[pressed.name .. "+" .. other]
      if chord then
        -- Fullscreen shouldn't keep the half the first key snapped to, or
        -- the window comes out of fullscreen at that half.
        if chord == "fullscreen" and first.win and first.win == win and not first.fullscreen then
          win:setFrame(first.frame, 0)
        end
        self:doAction(chord)
        return true
      end
    end
    self:doAction(pressed.name)
    return true
  end):start()
end

function obj:_bindHotkeys()
  self._hotkeys = {}
  if self.arrowCorners then self:_startHalfKeys() end
  for name, hotkey in pairs(self.hotkeys) do
    if not (self._tapHalves and self._tapHalves[name]) then
      local mods, key = hotkey[1], hotkey[2]
      local hk
      local function run()
        -- Ignored apps get their own shortcut back.
        if self:_ignored(hs.application.frontmostApplication()) then
          hk:disable()
          hs.eventtap.keyStroke(mods, key, 0)
          hk:enable()
          return
        end
        self:doAction(name)
      end
      hk = hs.hotkey.new(mods, key, run, nil, ACTIONS[name].repeats and run or nil):enable()
      table.insert(self._hotkeys, hk)
    end
  end
end

function obj:_unbindHotkeys()
  for _, hk in ipairs(self._hotkeys or {}) do hk:delete() end
  if self._keyTap then self._keyTap:stop() end
  self._hotkeys, self._keyTap, self._tapHalves = nil, nil, nil
end

--- WindowSnap:setIgnored(bundleID, ignored)
--- Method
--- Ignores or stops ignoring an app, and remembers that across reloads.
---
--- Parameters:
---  * bundleID - The app's bundle ID
---  * ignored - A boolean
---
--- Returns:
---  * The WindowSnap object
function obj:setIgnored(bundleID, ignored)
  self._ignoredFromMenu[bundleID] = ignored or nil
  hs.settings.set(IGNORED_KEY, self._ignoredFromMenu)
  return self
end

-- Drag to snap ----------------------------------------------------------------

-- `blocked` caches, for one drag, which screens show a fullscreen app.
function obj:_zoneAt(p, blocked)
  local screen = screenAt(p)
  if not screen then return nil end
  if blocked[screen:id()] == nil then blocked[screen:id()] = showsFullscreenApp(screen) end
  if blocked[screen:id()] then return nil end
  local s, m, c = screen:fullFrame(), self.snapMargin, self.cornerSize
  local left, right = p.x <= s.x + m, p.x >= s.x + s.w - 1 - m
  local top, bottom = p.y <= s.y + m, p.y >= s.y + s.h - 1 - m
  local nearLeft, nearRight = p.x <= s.x + c, p.x >= s.x + s.w - 1 - c
  local nearTop, nearBottom = p.y <= s.y + c, p.y >= s.y + s.h - 1 - c
  local name
  if (left and nearTop) or (top and nearLeft) then name = "topLeft"
  elseif (right and nearTop) or (top and nearRight) then name = "topRight"
  elseif (left and nearBottom) or (bottom and nearLeft) then name = "bottomLeft"
  elseif (right and nearBottom) or (bottom and nearRight) then name = "bottomRight"
  elseif left then name = "leftHalf"
  elseif right then name = "rightHalf"
  elseif top then name = "maximize"
  elseif bottom then
    local third = math.min(2, math.floor((p.x - s.x) / s.w * 3))
    name = ({ "firstThird", "centerThird", "lastThird" })[third + 1]
  end
  return name and { name = name, screen = screen, key = name .. ":" .. screen:id() }
end

function obj:_zoneFrame(zone)
  return self:_unitFrame(ACTIONS[zone.name], zone.screen:frame())
end

function obj:_showPreview(zone)
  if not zone then
    if self._preview then self._preview:hide() end
    return
  end
  local frame = self:_zoneFrame(zone)
  if not self._preview then
    self._preview = hs.canvas.new(frame)
      :level(hs.canvas.windowLevels.overlay)
      :behaviorAsLabels({ "canJoinAllSpaces", "transient" })
    self._preview:appendElements({
      type = "rectangle",
      action = "strokeAndFill",
      fillColor = { red = 0.2, green = 0.5, blue = 1, alpha = 0.2 },
      strokeColor = { red = 0.2, green = 0.5, blue = 1, alpha = 0.7 },
      strokeWidth = 3,
      roundedRectRadii = { xRadius = 10, yRadius = 10 },
    })
  end
  self._preview:frame(frame):show()
end

-- A snapped window dragged away gets its pre-snap size back, with the mouse
-- at the same relative spot across its width.
function obj:_unsnapForDrag(drag, frame, p)
  local id = drag.win:id()
  local state = self._state[id]
  if not (state and near(drag.frame, state.frame)) then return end
  self._state[id] = nil
  local r = state.restore
  local restored = round({ x = p.x - (p.x - frame.x) * r.w / frame.w, y = frame.y, w = r.w, h = r.h })
  drag.win:setFrame(restored, 0)
  drag.frame = restored
end

function obj:_dragged(drag, p)
  if drag.done then return end
  if not drag.win then
    -- Only look the window up once a drag starts, so plain clicks cost nothing.
    local win = windowAt(drag.start)
    if not win or not self:_snappable(win) then drag.done = true; return end
    drag.win, drag.frame = win, win:frame()
    return
  end
  if not drag.moving then
    -- Reading a window's frame is slow, so check at most every 50ms.
    local now = hs.timer.secondsSinceEpoch()
    if drag.checked and now - drag.checked < 0.05 then return end
    drag.checked = now
    local f = drag.win:frame()
    if f.w ~= drag.frame.w or f.h ~= drag.frame.h then drag.done = true; return end -- a resize
    if f.x == drag.frame.x and f.y == drag.frame.y then
      if math.abs(p.x - drag.start.x) + math.abs(p.y - drag.start.y) > DRAG_GIVE_UP then drag.done = true end
      return
    end
    drag.moving = true
    self:_unsnapForDrag(drag, f, p)
  end
  drag.blocked = drag.blocked or {}
  local zone = self:_zoneAt(p, drag.blocked)
  if (zone and zone.key) ~= (drag.zone and drag.zone.key) then
    drag.zone = zone
    self:_showPreview(zone)
  end
end

function obj:_dropped(drag)
  self:_showPreview(nil)
  local zone = drag.moving and drag.zone
  if not zone then return end
  local win, before = drag.win, drag.frame
  -- Let the window server finish the move before setting the frame.
  self._dropTimer = hs.timer.doAfter(0.05, function()
    self._dropTimer = nil
    self:_place(win, self:_zoneFrame(zone), zone.name, 1, before)
  end)
end

function obj:_startDragToSnap()
  local types = hs.eventtap.event.types
  local drag
  self._tap = hs.eventtap.new({ types.leftMouseDown, types.leftMouseDragged, types.leftMouseUp }, function(e)
    local t = e:getType()
    if t == types.leftMouseDown then
      drag = { start = e:location() }
    elseif drag and t == types.leftMouseDragged then
      self:_dragged(drag, e:location())
    elseif drag and t == types.leftMouseUp then
      self:_dropped(drag)
      drag = nil
    end
    return false
  end):start()
end

-- Menu ------------------------------------------------------------------------

function obj:_shortcutFor(name)
  local hotkey = self.hotkeys[name]
  if hotkey then return shortcutText(hotkey[1], hotkey[2]) end
  local pair = CHORD_HALVES[name]
  if not (pair and self._tapHalves and self._tapHalves[pair[1]] and self._tapHalves[pair[2]]) then return nil end
  local a, b = self.hotkeys[pair[1]], self.hotkeys[pair[2]]
  if shortcutText(a[1]) ~= shortcutText(b[1]) then return nil end
  return shortcutText(a[1], a[2], b[2])
end

local function menuTitle(title, shortcut)
  if not shortcut then return title end
  return hs.styledtext.new(title .. "\t" .. shortcut, {
    font = hs.styledtext.defaultFonts.menu,
    paragraphStyle = { tabStops = { { location = 210, tabStopType = "right" } } },
  })
end

--- WindowSnap:menuItems()
--- Method
--- Menu items for every action, applied to the focused window, followed by
--- an item to ignore the frontmost app. Used by WindowTweaksMenu.
---
--- Returns:
---  * A table of hs.menubar menu items
function obj:menuItems()
  local win = hs.window.focusedWindow()
  local usable = win ~= nil and self:_snappable(win)
  local canFullscreen = win ~= nil and self:_canFullscreen(win)
  local function item(name)
    return {
      title = menuTitle(ACTIONS[name].title, self:_shortcutFor(name)),
      disabled = not (usable or ((ACTIONS[name].fullscreen or ACTIONS[name].display) and canFullscreen)),
      fn = function() self:doAction(name, win) end,
    }
  end

  local items = {}
  for _, group in ipairs(MENU) do
    if #items > 0 then table.insert(items, { title = "-" }) end
    for _, entry in ipairs(group) do
      if type(entry) == "table" then
        local sub = {}
        for _, name in ipairs(entry) do table.insert(sub, item(name)) end
        table.insert(items, { title = entry.title, disabled = not usable, menu = sub })
      else
        table.insert(items, item(entry))
      end
    end
  end

  table.insert(items, { title = "-" })
  table.insert(items, {
    title = "Drag to Snap",
    checked = self.dragToSnap,
    fn = function() self:setOption("dragToSnap", not self.dragToSnap) end,
  })
  local gaps = {}
  for _, gap in ipairs(GAP_CHOICES) do
    table.insert(gaps, {
      title = gap == 0 and "None" or (gap .. " pt"),
      checked = self.gap == gap,
      fn = function() self:setOption("gap", gap) end,
    })
  end
  table.insert(items, { title = "Gaps Between Windows", menu = gaps })

  local app = hs.application.frontmostApplication()
  local bundleID = app and app:bundleID()
  if bundleID then
    local ignored = self:_ignored(app)
    table.insert(items, { title = "-" })
    table.insert(items, {
      title = "Ignore " .. app:name(),
      checked = ignored,
      -- Apps listed in WindowSnap.ignoredApps can only be changed in init.lua.
      disabled = ignored and not self._ignoredFromMenu[bundleID],
      fn = function() self:setIgnored(bundleID, not ignored) end,
    })
  end
  return items
end

--- WindowSnap:setOption(name, value)
--- Method
--- Changes "gap" or "dragToSnap" right away and remembers it across reloads,
--- over what init.lua sets. Used by the menu.
---
--- Parameters:
---  * name - "gap" or "dragToSnap"
---  * value - The new value
---
--- Returns:
---  * The WindowSnap object
function obj:setOption(name, value)
  assert(name == "gap" or name == "dragToSnap", "unknown WindowSnap option: " .. tostring(name))
  self[name] = value
  local saved = hs.settings.get(OPTIONS_KEY) or {}
  saved[name] = value
  hs.settings.set(OPTIONS_KEY, saved)
  if name == "dragToSnap" and self:isRunning() then
    if value and not self._tap then self:_startDragToSnap() end
    if not value and self._tap then
      self._tap:stop()
      self._tap = nil
    end
  end
  return self
end

--- WindowSnap:start()
--- Method
--- Turns on the shortcuts and drag to snap.
---
--- Returns:
---  * The WindowSnap object
function obj:start()
  if self._hotkeys then return self end
  self._state = self._state or {}
  self._ignoredFromMenu = hs.settings.get(IGNORED_KEY) or {}
  for name, value in pairs(hs.settings.get(OPTIONS_KEY) or {}) do self[name] = value end
  self:_bindHotkeys()
  if self.dragToSnap then self:_startDragToSnap() end
  -- macOS disables an event tap whose callback is too slow; turn it back on.
  self._watchdog = hs.timer.doEvery(5, function()
    for _, key in ipairs({ "_tap", "_keyTap" }) do
      local tap = self[key]
      if tap and not tap:isEnabled() then tap:start() end
    end
  end)
  return self
end

--- WindowSnap:stop()
--- Method
--- Turns off the shortcuts and drag to snap. Windows stay where they are.
---
--- Returns:
---  * The WindowSnap object
function obj:stop()
  self:_unbindHotkeys()
  self:_stopFullscreenTimer()
  for _, key in ipairs({ "_tap", "_watchdog", "_dropTimer" }) do
    if self[key] then self[key]:stop() end
    self[key] = nil
  end
  if self._preview then self._preview:delete() end
  self._preview = nil
  return self
end

--- WindowSnap:isRunning()
--- Method
--- Whether the Spoon is started.
---
--- Returns:
---  * A boolean
function obj:isRunning()
  return self._hotkeys ~= nil
end

return obj
