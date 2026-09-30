package.path = "./?.lua;" .. package.path

local function assertEqual(actual, expected, message)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
  end
end

local state = {
  alerts = {},
  chooserDeletes = 0,
  chooserNewCalls = 0,
  iconCalls = 0,
  windowsByID = {},
}

local function app(name, pid, hidden)
  local value = { activated = false }
  function value:name() return name end
  function value:pid() return pid end
  function value:path() return "/Applications/" .. name .. ".app" end
  function value:isHidden() return hidden end
  function value:activate(allWindows)
    self.activated = true
    self.activatedAllWindows = allWindows
    return true
  end
  return value
end

local function window(id, owner, title, minimized)
  local value = { focused = false, unminimized = false }
  function value:id() return id end
  function value:application() return owner end
  function value:title() return title end
  function value:isMinimized() return minimized end
  function value:unminimize() self.unminimized = true return self end
  function value:focus() self.focused = true return self end
  state.windowsByID[id] = value
  return value
end

local iterm = app("iTerm2", 100, false)
local safari = app("Safari", 200, true)
local windows = {
  window(2, iterm, "server", false),
  window(1, iterm, "shell", true),
  window(3, safari, "Docs", false),
}

local chooser

local function newChooser(callback)
  local value = { visible = false, callback = callback }
  function value:choices(choices) self.choiceList = choices return self end
  function value:rows(rows) self.rowCount = rows return self end
  function value:query(query) self.queryValue = query return self end
  function value:show() self.visible = true return self end
  function value:isVisible() return self.visible end
  function value:searchSubText(enabled) self.searchesSubText = enabled return self end
  function value:delete()
    self.deleted = true
    state.chooserDeletes = state.chooserDeletes + 1
  end

  state.chooserNewCalls = state.chooserNewCalls + 1
  chooser = value
  return value
end

local filter = {}
function filter:setDefaultFilter(value) self.defaultFilter = value return self end
function filter:setSortOrder(value) self.sortOrder = value return self end
function filter:subscribe(events, callback)
  self.events = events
  self.callback = callback
  return self
end
function filter:getWindows(order)
  self.requestedOrder = order
  return windows
end

local eventTap = {}
function eventTap:start() self.started = true return self end

local hotkey = {}

_G.hs = {
  alert = { show = function(message) state.alerts[#state.alerts + 1] = message end },
  application = { frontmostApplication = function() return iterm end },
  chooser = { new = newChooser },
  eventtap = {
    event = { types = { flagsChanged = 1 } },
    new = function(_, callback) eventTap.callback = callback return eventTap end,
  },
  hotkey = {
    bind = function(modifiers, key, callback)
      hotkey.modifiers = modifiers
      hotkey.key = key
      hotkey.callback = callback
      return hotkey
    end,
  },
  image = {
    iconForFile = function(path)
      state.iconCalls = state.iconCalls + 1
      return "icon:" .. path
    end,
  },
  window = {
    filter = {
      new = function() return filter end,
      sortByFocusedLast = "focusedLast",
      windowFocused = "windowFocused",
      windowsChanged = "windowsChanged",
      windowTitleChanged = "windowTitleChanged",
      windowMinimized = "windowMinimized",
      windowUnminimized = "windowUnminimized",
      windowHidden = "windowHidden",
      windowUnhidden = "windowUnhidden",
    },
    get = function(id) return state.windowsByID[id] end,
  },
}

package.loaded.dockapps = nil
local dockapps = require("dockapps")

assertEqual(type(dockapps), "table", "module exports its controller")
assertEqual(type(dockapps.showAll), "function", "module exports all-window action")
assertEqual(type(dockapps.showCurrentApp), "function", "module exports current-app action")
assertEqual(filter.sortOrder, "focusedLast", "filter uses MRU ordering")
assertEqual(filter.defaultFilter.allowRoles[1], "AXStandardWindow", "standard windows are allowed")
assertEqual(state.chooserNewCalls, 0, "module loading does not allocate a chooser")
assertEqual(eventTap.started, true, "modifier event tap starts")
assertEqual(hotkey.key, "o", "current-app hotkey is registered")

dockapps.showAll()
assertEqual(state.chooserNewCalls, 1, "first opening allocates a chooser")
assertEqual(dockapps.chooser, chooser, "module exports the active chooser")
assertEqual(chooser.searchesSubText, true, "chooser searches window titles")
assertEqual(#chooser.choiceList, 3, "all scope contains every known window")
assertEqual(chooser.rowCount, 3, "all choices are shown without scrolling")
assertEqual(chooser.choiceList[1].windowID, 2, "filter MRU order is retained")
assertEqual(chooser.choiceList[2].subText, "[Minimized] shell", "minimized state is displayed")
assertEqual(chooser.choiceList[3].subText, "[Hidden] Docs", "hidden state is displayed")
assertEqual(state.iconCalls, 2, "icons are cached per application")

table.remove(windows, 3)
filter.callback()
assertEqual(chooser.rowCount, 2, "visible chooser resizes after a window-list refresh")

chooser.visible = false
local firstChooser = chooser
dockapps.showCurrentApp()
assertEqual(state.chooserNewCalls, 2, "second opening allocates a fresh chooser")
assertEqual(firstChooser.deleted, true, "second opening deletes the old chooser")
assertEqual(state.chooserDeletes, 1, "only the replaced chooser is deleted")
assertEqual(#chooser.choiceList, 2, "current-app scope only contains front app windows")
assertEqual(chooser.rowCount, 2, "current-app chooser shows every result")
assertEqual(chooser.choiceList[1].windowID, 2, "current-app scope retains MRU order")

chooser.callback({ windowID = 1 })
assertEqual(windows[2].unminimized, true, "selected minimized window is restored")
assertEqual(windows[2].focused, true, "selected window is focused")
assertEqual(iterm.activated, true, "selected application is activated")
assertEqual(iterm.activatedAllWindows, false, "unselected application windows are not raised")

chooser.callback({ windowID = 999 })
assertEqual(state.alerts[#state.alerts], "Window is no longer available", "stale selection is handled")

for id = 1001, 1014 do
  windows[#windows + 1] = window(id, iterm, "extra-" .. id, false)
end
chooser.visible = false
dockapps.showAll()
assertEqual(#chooser.choiceList, 16, "all choices remain available above the visible-row cap")
assertEqual(chooser.rowCount, 15, "chooser height uses the configured fifteen-row cap")

local function flagsEvent(flags)
  return { getFlags = function() return flags end }
end
chooser.visible = false
eventTap.callback(flagsEvent({ cmd = true }))
eventTap.callback(flagsEvent({ cmd = true, ctrl = true, fn = true }))
assertEqual(chooser.visible, true, "Cmd then Cmd+Ctrl opens the chooser")

print("dockapps_integration_test: ok")
