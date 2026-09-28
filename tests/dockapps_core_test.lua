package.path = "./?.lua;" .. package.path

local core = require("dockapps_core")

local function assertEqual(actual, expected, message)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
  end
end

local function testModifierTransition()
  assertEqual(core.shouldOpen({ cmd = true }, { cmd = true, ctrl = true }), true,
    "Cmd then Cmd+Ctrl opens")
  assertEqual(core.shouldOpen({ cmd = true, fn = true }, { cmd = true, ctrl = true, fn = true }), true,
    "irrelevant Fn flag is ignored")
  assertEqual(core.shouldOpen({ ctrl = true }, { cmd = true, ctrl = true }), false,
    "Ctrl then Cmd+Ctrl does not open")
  assertEqual(core.shouldOpen({ cmd = true }, { cmd = true, ctrl = true, alt = true }), false,
    "extra semantic modifiers do not open")
end

local function testChoiceBuilding()
  local icon = {}
  local records = {
    { id = 30, pid = 3, appName = "iTerm2", title = "logs", minimized = false, hidden = false, image = icon },
    { id = 20, pid = 2, appName = "Safari", title = "", minimized = true, hidden = false },
    { id = 10, pid = 3, appName = "iTerm2", title = "shell", minimized = false, hidden = true },
    { id = 30, pid = 3, appName = "iTerm2", title = "duplicate" },
    { id = nil, pid = 4, appName = "Broken", title = "missing id" },
    { id = 40, pid = 4, appName = "", title = "missing app" },
  }

  local choices = core.buildChoices(records)
  assertEqual(#choices, 3, "invalid and duplicate windows are rejected")
  assertEqual(choices[1].windowID, 30, "input MRU order is preserved")
  assertEqual(choices[1].text, "iTerm2", "application name is primary text")
  assertEqual(choices[1].subText, "logs", "window title is secondary text")
  assertEqual(choices[1].image, icon, "application icon passes through")
  assertEqual(choices[2].subText, "[Minimized] Untitled", "minimized untitled window is labelled")
  assertEqual(choices[3].subText, "[Hidden] shell", "hidden window is labelled")

  local currentApp = core.buildChoices(records, 3)
  assertEqual(#currentApp, 2, "current application scope filters by pid")
  assertEqual(currentApp[1].windowID, 30, "current application retains MRU order")
  assertEqual(currentApp[2].windowID, 10, "current application includes all matching windows")
end

testModifierTransition()
testChoiceBuilding()
print("dockapps_core_test: ok")
