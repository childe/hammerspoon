package.path = "./?.lua;" .. package.path
-- Hammerspoon runs Lua 5.4: hide Lua 5.1-only globals that luajit still provides.
unpack, setfenv, getfenv, loadstring = nil, nil, nil, nil

local core = require("iterm_layout_core")

local function assertEqual(actual, expected, message)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
  end
end

local state = { alerts = {}, windows = {}, subscriptions = {}, hotkeys = {}, debounceStarts = 0, screenWatchers = 0 }

local function screen(id, frame)
  local value = {}
  function value:id() return id end
  function value:frame() return frame end
  return value
end

local function window(id, onScreen, frame)
  local value = { frameValue = frame, setCalls = 0, alive = true, standard = true, snap = 0, snapX = nil, snapY = nil, onScreen = onScreen }
  function value:id() return id end
  function value:screen() return self.onScreen end
  function value:isStandard() return self.standard end
  function value:frame() return self.frameValue end
  -- `snap` mimics iTerm2 shrinking the window to its character grid.
  function value:setFrame(f, duration)
    self.setCalls = self.setCalls + 1
    self.lastDuration = duration
    self.frameValue = { x = f.x, y = f.y, w = f.w - (self.snapX or self.snap), h = f.h - (self.snapY or self.snap) }
  end
  function value:setTopLeft(p)
    self.frameValue = { x = p.x, y = p.y, w = self.frameValue.w, h = self.frameValue.h }
  end
  return value
end

local filter = {}
function filter:setAppFilter(name, options)
  self.appName, self.options = name, options
  return self
end
function filter:getWindows() return state.windows end
function filter:subscribe(event, fn) state.subscriptions[event] = fn return self end

hs = {
  window = {
    filter = { new = function() return filter end, windowsChanged = "windowsChanged", windowMoved = "windowMoved" },
  },
  axuielement = {
    windowElement = function(w)
      return { isValid = function() return w.alive end }
    end,
  },
  geometry = {
    rect = function(x, y, w, h) return { x = x, y = y, w = w, h = h } end,
    point = function(x, y) return { x = x, y = y } end,
  },
  screen = {
    watcher = {
      new = function(fn)
        state.screenWatcher = fn
        return { start = function(self) state.screenWatchers = state.screenWatchers + 1 return self end }
      end,
    },
  },
  timer = {
    delayed = {
      new = function(seconds, fn)
        return { seconds = seconds, start = function() state.debounceStarts = state.debounceStarts + 1 fn() end }
      end,
    },
  },
  alert = { show = function(message) state.alerts[#state.alerts + 1] = message end },
  hotkey = {
    bind = function(mods, key, fn)
      state.hotkeys[#state.hotkeys + 1] = { mods = mods, key = key, fn = fn }
      return {}
    end,
  },
}

local main = screen(1, { x = 0, y = 25, w = 1728, h = 1080 })
local side = screen(2, { x = 1728, y = 0, w = 1920, h = 1200 })

-- Windows that exist before the config loads are arranged right away.
local pre1 = window(11, main, { x = 0, y = 25, w = 1728, h = 1080 })
local pre2 = window(12, main, { x = 0, y = 25, w = 1728, h = 1080 })
state.windows = { pre1, pre2 }

local layout = require("iterm_layout")
assertEqual(state.debounceStarts, 1, "layout is scheduled on load")
assertEqual(state.screenWatchers, 1, "screen changes are watched")
assertEqual(pre1:frame().w, 1728 - layout.margin, "pre-existing window resized on load")
assertEqual(pre1:frame().x ~= pre2:frame().x, true, "pre-existing windows no longer overlap fully")
assertEqual(filter.appName, "iTerm2", "filter targets iTerm2")
assertEqual(filter.options.visible, true, "only visible windows are laid out")
assertEqual(filter.options.fullscreen, false, "fullscreen windows are ignored")
assertEqual(#state.hotkeys, 1, "one manual hotkey")
assertEqual(state.hotkeys[1].key, "T", "manual hotkey is T")

local function frameEquals(w, slot)
  return core.fits(w:frame(), slot, layout.snapTolerance)
end

local function assertLaidOut(windows, onScreen, message)
  local slots = core.slots(onScreen:frame(), #windows, layout.margin)
  local used = {}
  for _, w in ipairs(windows) do
    local hit
    for s, slot in ipairs(slots) do
      if not used[s] and frameEquals(w, slot) then hit = s break end
    end
    assertEqual(hit ~= nil, true, message .. ": window " .. w:id() .. " sits in a free slot")
    used[hit] = true
  end
end

-- Three windows appear on the main screen.
local a = window(1, main, { x = 100, y = 100, w = 800, h = 600 })
local b = window(2, main, { x = 900, y = 100, w = 800, h = 600 })
local c = window(3, main, { x = 500, y = 500, w = 800, h = 600 })
state.windows = { a, b, c }
state.subscriptions.windowsChanged()
assertEqual(state.debounceStarts, 2, "windowsChanged goes through the debounce timer")
assertLaidOut({ a, b, c }, main, "three windows")
assertEqual(a.lastDuration, 0, "frames are set without animation")

-- Re-applying is a no-op: nothing moves.
local before = { a.setCalls, b.setCalls, c.setCalls }
layout.layout()
assertEqual(a.setCalls + b.setCalls + c.setCalls, before[1] + before[2] + before[3],
  "already laid-out windows are not touched")

-- A fourth window: the two windows in shared 3/4 slots stay put.
local placed = {}
for _, w in ipairs({ a, b, c }) do placed[w] = w.setCalls end
local d = window(4, main, { x = 10, y = 10, w = 300, h = 300 })
state.windows = { a, b, c, d }
state.subscriptions.windowsChanged()
assertLaidOut({ a, b, c, d }, main, "four windows")
local untouched = 0
for _, w in ipairs({ a, b, c }) do
  if w.setCalls == placed[w] then untouched = untouched + 1 end
end
assertEqual(untouched, 2, "adding a fourth window keeps two windows in place")

-- A destroyed window and a non-standard one are ignored; another screen is independent.
d.alive = false
local panel = window(5, main, { x = 0, y = 0, w = 100, h = 100 })
panel.standard = false
local e = window(6, side, { x = 1800, y = 50, w = 700, h = 500 })
state.windows = { a, b, c, d, panel, e }
state.subscriptions.windowsChanged()
assertLaidOut({ a, b, c }, main, "stale window dropped")
assertLaidOut({ e }, side, "second screen laid out on its own")
assertEqual(panel.setCalls, 0, "non-standard window untouched")

-- A newcomer opening exactly on an existing window's slot does not displace it.
local bFrame, cFrame = b:frame(), c:frame()
local f = window(7, main, { x = bFrame.x, y = bFrame.y, w = bFrame.w, h = bFrame.h })
state.windows = { a, b, c, f, e }
state.subscriptions.windowsChanged()
assertEqual(b:frame().x == bFrame.x and b:frame().y == bFrame.y, true, "existing window b keeps its place")
assertEqual(c:frame().x == cFrame.x and c:frame().y == cFrame.y, true, "existing window c keeps its place")
assertLaidOut({ a, b, c, f }, main, "newcomer squeezed in")

-- Dragging a window to the other screen re-lays out both screens.
local starts = state.debounceStarts
state.subscriptions.windowMoved(a)
assertEqual(state.debounceStarts, starts, "moving within a screen does nothing")
a.onScreen = side
state.subscriptions.windowMoved(a)
assertEqual(state.debounceStarts, starts + 1, "moving to another screen re-lays out")
assertLaidOut({ b, c, f }, main, "main screen after move")
assertLaidOut({ a, e }, side, "side screen after move")

-- iTerm2 snapping: a right-edge window stays flush with the screen edge.
local g = window(8, side, { x = 1800, y = 50, w = 300, h = 300 })
g.snap = 7
state.windows = { a, b, c, f, e, g }
state.subscriptions.windowsChanged()
assertLaidOut({ a, e, g }, side, "snapped window still fits its slot")
local sf = side:frame()
local flush = 0
for _, w in ipairs({ a, e, g }) do
  if w:frame().x + w:frame().w == sf.x + sf.w then flush = flush + 1 end
end
assertEqual(flush >= 2, true, "right-anchored slots stay flush right")
local before4 = g.setCalls
state.subscriptions.windowsChanged()
assertEqual(g.setCalls, before4, "snapped window is not resized again")

-- Screen setup change triggers a layout.
starts = state.debounceStarts
state.screenWatcher()
assertEqual(state.debounceStarts, starts + 1, "screen change re-lays out")

-- Reviewer regression: a small screen with clamped cascade steps (25x18) and a
-- window that snaps by exactly one step. It must still be clickable.
local warnings = 0
local realPrint = print
print = function(...) warnings = warnings + 1 end
local tiny = screen(3, { x = 5000, y = 0, w = 400, h = 300 })
local crowd = {}
for i = 1, 9 do crowd[i] = window(100 + i, tiny, { x = 5000, y = 0, w = 400, h = 300 }) end
crowd[2].snapX, crowd[2].snapY = 25, 18
state.windows = crowd
state.subscriptions.windowsChanged()
print = realPrint
local actual = {}
for i, w in ipairs(crowd) do actual[i] = w:frame() end
assertEqual(#core.coveredWindows(actual), 0, "every crowded window stays clickable")
assertEqual(warnings, 0, "no window reported as covered")
assertLaidOut(crowd, tiny, "crowded small screen")
assertEqual(crowd[2]:frame().x + crowd[2]:frame().w, 5000 + 25 + 200, "snapped window pinned to its slot's right edge")

-- The manual hotkey always gives feedback, even when nothing has to move.
assertEqual(#state.alerts, 0, "automatic layouts stay silent")
state.hotkeys[1].fn()
assertEqual(state.alerts[1], "iTerm 布局：9 个窗口，移动 0 个", "hotkey reports a no-op layout")
crowd[5].frameValue = { x = 5000, y = 0, w = 100, h = 100 }
state.hotkeys[1].fn()
assertEqual(state.alerts[2], "iTerm 布局：9 个窗口，移动 1 个", "hotkey reports moved windows")
state.windows = {}
state.hotkeys[1].fn()
assertEqual(state.alerts[3], "iTerm 布局：没有可排列的 iTerm2 窗口", "hotkey reports no windows")
print("iterm_layout integration tests passed")
