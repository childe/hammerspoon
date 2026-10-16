-- Keep iTerm2 windows as large as possible while every window keeps a region
-- no other window covers, so any window is always one click away.
-- Re-lays out on load, when windows appear/disappear, move to another screen, or
-- the screen setup changes; Cmd+Alt+Ctrl+T forces it.
local core = require("iterm_layout_core")

local M = {}
local appName = "iTerm2"
M.margin = 60
M.debounceSeconds = 0.3
-- How much smaller than its slot a window may be and still count as in place
-- (iTerm2 snaps windows to its character grid). Clickability never depends on it.
M.snapTolerance = 40
-- Window id -> screen id from the last layout; also the set of known windows.
local lastScreen = {}

local function safeCall(object, methodName, ...)
  if object == nil then return nil end
  local method = object[methodName]
  if type(method) ~= "function" then return nil end

  local ok, result = pcall(method, object, ...)
  if not ok then return nil end
  return result
end

-- Same stale-window guard as dockapps.lua: the filter can keep windows whose AX
-- element was destroyed without a notification.
local function isWindowAlive(window)
  local ok, element = pcall(hs.axuielement.windowElement, window)
  if not ok or element == nil then return true end
  return safeCall(element, "isValid") ~= false
end

local function frameRect(f)
  return { x = f.x, y = f.y, w = f.w, h = f.h }
end

-- Returns how many windows were moved.
local function layoutGroup(group, seen)
  -- Stable order so ties in the assignment always resolve the same way.
  table.sort(group.windows, function(a, b) return a:id() < b:id() end)
  local screenFrame = frameRect(group.screen:frame())
  local slots = core.slots(screenFrame, #group.windows, M.margin)
  if slots == nil then return 0 end

  -- Windows laid out before outrank newcomers when slots are assigned.
  local frames, existing = {}, {}
  for i, window in ipairs(group.windows) do
    frames[i] = frameRect(window:frame())
    existing[i] = lastScreen[window:id()] ~= nil
  end
  local mapping = core.assign(frames, slots, existing)
  local moved = 0
  for i, window in ipairs(group.windows) do
    local slot = slots[mapping[i]]
    if not core.fits(frames[i], slot, M.snapTolerance) then
      moved = moved + 1
      window:setFrame(hs.geometry.rect(slot.x, slot.y, slot.w, slot.h), 0)
      -- iTerm2 may snap to a smaller size, keeping the top-left; pin it back to
      -- the slot's anchor corner so it still covers its exclusive region.
      local actual = window:frame()
      local placed = core.place(slot, actual.w, actual.h)
      if placed.x ~= actual.x or placed.y ~= actual.y then
        window:setTopLeft(hs.geometry.point(placed.x, placed.y))
      end
    end
    seen[window:id()] = group.screen:id()
  end

  -- Pinned windows inside their slots always keep their exclusive region, so
  -- this should never fire; if it does, log what was asked for and what we got.
  local actuals = {}
  for i, window in ipairs(group.windows) do actuals[i] = frameRect(window:frame()) end
  for _, i in ipairs(core.coveredWindows(actuals)) do
    local slot, f = slots[mapping[i]], actuals[i]
    -- %g, not %d: Lua 5.4 rejects %d for non-integral coordinates.
    print(string.format("iterm_layout: window %d is fully covered (slot %g,%g %gx%g, actual %g,%g %gx%g)",
      group.windows[i]:id(), slot.x, slot.y, slot.w, slot.h, f.x, f.y, f.w, f.h))
  end
  return moved
end

-- Returns the number of windows laid out and how many of them were moved.
local function layoutWindows(windowFilter)
  local byScreen = {}
  for _, window in ipairs(windowFilter:getWindows()) do
    local screen = safeCall(window, "screen")
    if screen ~= nil and safeCall(window, "isStandard") and isWindowAlive(window) then
      local id = screen:id()
      byScreen[id] = byScreen[id] or { screen = screen, windows = {} }
      table.insert(byScreen[id].windows, window)
    end
  end

  local seen, total, moved = {}, 0, 0
  for _, group in pairs(byScreen) do
    total = total + #group.windows
    moved = moved + layoutGroup(group, seen)
  end
  lastScreen = seen
  return total, moved
end

local windowFilter = hs.window.filter.new(false):setAppFilter(appName, {
  visible = true,
  currentSpace = true,
  fullscreen = false,
})

local debounce = hs.timer.delayed.new(M.debounceSeconds, function()
  layoutWindows(windowFilter)
end)

function M.layout()
  return layoutWindows(windowFilter)
end

windowFilter:subscribe(hs.window.filter.windowsChanged, function()
  debounce:start()
end)

-- Moving a window to another screen keeps the filtered set unchanged, so watch
-- moves and only react to screen changes (our own setFrame never changes screen).
windowFilter:subscribe(hs.window.filter.windowMoved, function(window)
  local id = safeCall(window, "id")
  local screen = safeCall(window, "screen")
  if id == nil or screen == nil then return end
  if lastScreen[id] ~= nil and lastScreen[id] ~= screen:id() then
    debounce:start()
  end
end)

local screenWatcher = hs.screen.watcher.new(function() debounce:start() end):start()

-- Manual trigger always gives feedback: when the windows are already in place
-- nothing moves, which would otherwise look like the hotkey did nothing.
local hotkey = hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "T", function()
  local total, moved = M.layout()
  if total == 0 then
    hs.alert.show("iTerm 布局：没有可排列的 iTerm2 窗口")
  else
    hs.alert.show(string.format("iTerm 布局：%d 个窗口，移动 %d 个", total, moved))
  end
end)

-- Arrange windows that already exist when the config loads.
debounce:start()

M.windowFilter = windowFilter
M.debounce = debounce
M.screenWatcher = screenWatcher
M.hotkey = hotkey

return M
