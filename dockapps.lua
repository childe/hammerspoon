local core = require("dockapps_core")

local M = {}
local wf = hs.window.filter
local maxVisibleRows = 11
local iconCache = {}
local activeScopePid = nil
local lastFlags = {}

local function safeCall(object, methodName, ...)
  if object == nil then return nil end
  local method = object[methodName]
  if type(method) ~= "function" then return nil end

  local ok, result = pcall(method, object, ...)
  if not ok then return nil end
  return result
end

local function appIcon(application)
  local path = safeCall(application, "path")
  if type(path) ~= "string" or path == "" then return nil end

  if iconCache[path] == nil then
    local ok, image = pcall(hs.image.iconForFile, path)
    iconCache[path] = ok and image or false
  end

  return iconCache[path] or nil
end

local function windowRecord(window)
  local id = safeCall(window, "id")
  local application = safeCall(window, "application")
  if type(id) ~= "number" or application == nil then return nil end

  local appName = safeCall(application, "name")
  local pid = safeCall(application, "pid")
  if type(appName) ~= "string" or appName == "" or type(pid) ~= "number" then
    return nil
  end

  return {
    id = id,
    pid = pid,
    appName = appName,
    title = safeCall(window, "title"),
    minimized = safeCall(window, "isMinimized") == true,
    hidden = safeCall(application, "isHidden") == true,
    image = appIcon(application),
  }
end

local windowFilter = wf.new()
  :setDefaultFilter({ allowRoles = { "AXStandardWindow", "AXDialog" } })
  :setSortOrder(wf.sortByFocusedLast)

local chooser

local function choicesFor(scopePid)
  local ok, windows = pcall(windowFilter.getWindows, windowFilter, wf.sortByFocusedLast)
  if not ok or type(windows) ~= "table" then
    hs.alert.show("Unable to read the window list")
    return {}
  end

  local records = {}
  for _, window in ipairs(windows) do
    local record = windowRecord(window)
    if record ~= nil then records[#records + 1] = record end
  end

  return core.buildChoices(records, scopePid)
end

local function applyChoices(scopePid)
  local choices = choicesFor(scopePid)
  chooser:rows(math.max(1, math.min(#choices, maxVisibleRows)))
  chooser:choices(choices)
end

local function focusChoice(choice)
  if choice == nil or type(choice.windowID) ~= "number" then return end

  local ok, window = pcall(hs.window.get, choice.windowID)
  if not ok or window == nil then
    hs.alert.show("Window is no longer available")
    return
  end

  local application = safeCall(window, "application")
  if safeCall(window, "isMinimized") == true then
    safeCall(window, "unminimize")
  end
  if safeCall(application, "isHidden") == true then
    safeCall(application, "unhide")
  end
  safeCall(application, "activate", false)

  if safeCall(window, "focus") == nil then
    hs.alert.show("Unable to focus the selected window")
  end
end

chooser = hs.chooser.new(focusChoice)
chooser:searchSubText(true)

local function show(scopePid)
  if safeCall(chooser, "isVisible") == true then return end

  activeScopePid = scopePid
  applyChoices(scopePid)
  chooser:query(nil)
  chooser:show()
end

function M.showAll()
  show(nil)
end

function M.showCurrentApp()
  local application = hs.application.frontmostApplication()
  local pid = safeCall(application, "pid")
  if type(pid) ~= "number" then
    hs.alert.show("No active application")
    return
  end
  show(pid)
end

local function refreshVisibleChooser()
  if safeCall(chooser, "isVisible") == true then
    applyChoices(activeScopePid)
  end
end

windowFilter:subscribe({
  wf.windowFocused,
  wf.windowsChanged,
  wf.windowTitleChanged,
  wf.windowMinimized,
  wf.windowUnminimized,
  wf.windowHidden,
  wf.windowUnhidden,
}, refreshVisibleChooser)

-- Keep the original gesture: press Cmd, then add Ctrl while still holding Cmd.
local modifierTap = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged }, function(event)
  local flags = event:getFlags()
  if core.shouldOpen(lastFlags, flags) then M.showAll() end
  lastFlags = flags
  return false
end):start()

-- A separate searchable list for windows belonging to the current application.
local currentAppHotkey = hs.hotkey.bind({ "ctrl", "alt", "cmd" }, "w", M.showCurrentApp)

-- Retain these Hammerspoon objects for the lifetime of the loaded module.
M.windowFilter = windowFilter
M.chooser = chooser
M.modifierTap = modifierTap
M.currentAppHotkey = currentAppHotkey

return M
