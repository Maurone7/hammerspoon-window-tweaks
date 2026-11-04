-- Unit tests for the Spoons, run against a fake `hs` API.
-- From the repo root: lua tests/run.lua
package.path = "./tests/?.lua;" .. package.path
local mockHs = require("mock_hs")

local T = {}
local tests = {}

--- Starts a test with a fresh fake `hs` and empty `spoon` table.
function T.setup()
  local mock = mockHs.new()
  _G.hs = mock.hs
  _G.spoon = {}
  return mock
end

--- Loads a fresh copy of a Spoon from Spoons/.
function T.load(name)
  return dofile("Spoons/" .. name .. ".spoon/init.lua")
end

function T.test(name, fn)
  table.insert(tests, { name = name, fn = fn })
end

function T.eq(actual, expected, what)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", what or "value", tostring(expected), tostring(actual)), 2)
  end
end

function T.ok(value, what)
  if not value then error((what or "condition") .. " was false", 2) end
end

for _, file in ipairs({
  "fullscreen_traffic_lights_test",
  "finder_cut_test",
  "click_through_test",
  "window_tweaks_menu_test",
}) do
  local group = #tests
  require(file)(T)
  for i = group + 1, #tests do tests[i].group = file end
end

local failed = 0
for _, t in ipairs(tests) do
  local ok, err = pcall(t.fn)
  if ok then
    print("  ok    " .. t.group .. ": " .. t.name)
  else
    failed = failed + 1
    print("  FAIL  " .. t.group .. ": " .. t.name .. "\n        " .. tostring(err))
  end
end

print(string.format("\n%d passed, %d failed", #tests - failed, failed))
os.exit(failed == 0 and 0 or 1)
