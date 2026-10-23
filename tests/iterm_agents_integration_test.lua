package.path = "./?.lua;" .. package.path
-- Hammerspoon runs Lua 5.4: hide Lua 5.1-only globals that luajit still provides.
unpack, setfenv, getfenv, loadstring = nil, nil, nil, nil

local function assertEqual(actual, expected, message)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
  end
end

-- luajit lacks Lua 5.4's utf8 library; provide the two functions the module uses.
utf8 = utf8 or {
  len = function(s)
    local _, n = s:gsub("[^\128-\191]", "")
    return n
  end,
  offset = function(s, n)
    local count = 0
    for i = 1, #s do
      if s:byte(i) < 128 or s:byte(i) >= 192 then
        count = count + 1
        if count == n then return i end
      end
    end
    return #s + 1
  end,
}

local state = { running = true, scripts = {}, alerts = {}, focusResult = true }

local menubar = {}
function menubar:setTitle(t) self.title = t end
function menubar:setTooltip(t) self.tooltip = t end
function menubar:setMenu(fn) self.menuFn = fn end

hs = {
  application = { get = function() return state.running and {} or nil end },
  osascript = {
    applescript = function(script)
      table.insert(state.scripts, script)
      if script:find("set out to") then return true, state.listOutput end
      return true, state.focusResult
    end,
  },
  execute = function() return state.psOutput end,
  menubar = { new = function() return menubar end },
  alert = { show = function(text) table.insert(state.alerts, text) end },
}

state.psOutput = table.concat({
  "100 1 ttys001 /usr/bin/login",
  "101 100 ttys001 -zsh",
  "102 101 ttys001 claude",
  "200 1 ttys002 /usr/bin/login",
  "201 200 ttys002 -zsh",
}, "\n")
local longTitle = string.rep("长", 100)
state.listOutput = table.concat({
  "1\t1\tAAA-1\t/dev/ttys002\t" .. longTitle,
  "1\t2\tAAA-2\t/dev/ttys001\t✳ fix bug (claude)",
}, "\n") .. "\n"

local agents = require("iterm_agents")
assertEqual(menubar.title, "🤖", "menubar icon set")
assertEqual(menubar.menuFn, agents.menu, "menu built on click")

local items = menubar.menuFn()
assertEqual(#items, 3, "agent item, separator, other item")
assertEqual(items[1].title, "[claude] ✳ fix bug (claude)", "agent tab listed first with tag")
assertEqual(items[2].title, "-", "separator between agent and other tabs")
assertEqual(utf8.len(items[3].title), 81, "long titles are shortened")

items[1].fn()
assertEqual(state.scripts[#state.scripts]:find('id of s is "AAA-2"', 1, true) ~= nil, true, "focuses the chosen session")
assertEqual(#state.alerts, 0, "no alert when focus succeeds")

state.focusResult = false
items[1].fn()
assertEqual(state.alerts[1], "iTerm tab 已关闭", "alert when the session is gone")

assertEqual(agents.focus('x" & do shell script "rm'), false, "rejects unsafe session ids")

state.listOutput = "1\t1\tB\t/dev/ttys001\tonly agent\n"
items = menubar.menuFn()
assertEqual(#items, 1, "no separator without other tabs")

state.running = false
local scriptsBefore = #state.scripts
items = menubar.menuFn()
assertEqual(items[1].title, "iTerm2 未运行", "reports iTerm2 not running")
assertEqual(#state.scripts, scriptsBefore, "does not launch iTerm2 via AppleScript")

print("iterm_agents integration tests passed")
