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

local state = { running = true, scripts = {}, alerts = {}, commands = {}, focusResult = true }

hs = {
  application = { get = function() return state.running and {} or nil end },
  osascript = {
    applescript = function(script)
      table.insert(state.scripts, script)
      if script:find("set out to") then return true, state.listOutput end
      return true, state.focusResult
    end,
  },
  execute = function(cmd)
    table.insert(state.commands, cmd)
    if cmd:find("^lsof") then return state.lsofOutput end
    return state.psOutput
  end,
  alert = { show = function(text) table.insert(state.alerts, text) end },
  -- Runs the command synchronously on start() with canned output picked by program path.
  -- Like the real hs.task, a task whose stdout pipe gets more than the 64KB pipe buffer never
  -- finishes: the program blocks writing because stdout is not drained until exit.
  -- `/bin/sh -c 'out="$1"; shift; "$@" > "$out"' sh <file> <program> <args...>` is understood:
  -- the canned output goes to <file> instead of the pipe.
  task = {
    new = function(path, callback, args)
      local t = { path = path, args = args }
      local program, file = path, nil
      if path == "/bin/sh" and args[1] == "-c" then
        file, program = args[4], args[5]
        t.program = program
        t.programArgs = {}
        for i = 6, #args do t.programArgs[#t.programArgs + 1] = args[i] end
      end
      table.insert(state.tasks, t)
      -- The real hs.task keeps its callback, and everything the callback captures, until it is
      -- replaced: collecting the task does not release it.
      function t:setCallback(fn)
        callback = fn
        t.callbackCleared = fn == nil
        return self
      end
      function t:start()
        local out = state.psOutput
        if program:find("osascript$") then out = state.listOutput end
        if program:find("lsof$") then out = state.lsofOutput end
        out = out or ""
        if file then
          local f = assert(io.open(file, "w"))
          f:write(out)
          f:close()
          callback(0, "", "")
        elseif #out <= 65536 then
          callback(0, out, "")
        end
        return self
      end
      return t
    end,
  },
}
state.tasks = {}

state.psOutput = table.concat({
  "100 1 01:00 ttys001 /usr/bin/login",
  "101 100 01:00 ttys001 -zsh",
  "102 101 00:30 ttys001 claude",
  "200 1 01:00 ttys002 /usr/bin/login",
  "201 200 01:00 ttys002 -zsh",
}, "\n")
local longTitle = string.rep("长", 100)
state.listOutput = table.concat({
  "1\t1\tAAA-1\t/dev/ttys002\t" .. longTitle,
  "1\t2\tAAA-2\t/dev/ttys001\t✳ fix bug (claude)",
}, "\n") .. "\n"

local agents = require("iterm_agents")

local items = agents.menu()
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

-- Agent tabs are grouped by directory, newest first within one.
state.psOutput = table.concat({
  "100 1 01:00 ttys001 claude",
  "200 1 02:00 ttys002 codex",
  "300 1 03:00 ttys003 claude",
}, "\n")
state.lsofOutput = "p100\nfcwd\nn/b\np200\nfcwd\nn/a\np300\nfcwd\nn/b\n"
state.listOutput = "1\t1\tX\t/dev/ttys001\tx\n1\t2\tY\t/dev/ttys002\ty\n1\t3\tZ\t/dev/ttys003\tz\n"
items = agents.menu()
assertEqual(state.commands[#state.commands], "lsof -a -d cwd -Fn -p 100,200,300", "asks lsof for agent cwds")
assertEqual(items[1].title, "[codex] y", "directory /a first")
assertEqual(items[2].title, "[claude] x", "newest agent in /b next")
assertEqual(items[3].title, "[claude] z", "older agent in /b last")

state.psOutput = "100 1 01:00 ttys001 claude\n"
state.listOutput = "1\t1\tB\t/dev/ttys001\tonly agent\n"
items = agents.menu()
assertEqual(#items, 1, "no separator without other tabs")

-- sessionsAsync runs osascript, ps and lsof as tasks and yields the same order as sessions().
state.psOutput = table.concat({
  "100 1 01:00 ttys001 claude",
  "200 1 02:00 ttys002 codex",
  "300 1 03:00 ttys003 claude",
  "400 1 03:00 ttys004 -zsh",
}, "\n")
state.lsofOutput = "p100\nfcwd\nn/b\np200\nfcwd\nn/a\np300\nfcwd\nn/b\n"
state.listOutput = "1\t1\tX\t/dev/ttys001\tx\n1\t2\tY\t/dev/ttys002\ty\n1\t3\tZ\t/dev/ttys003\tz\n1\t4\tW\t/dev/ttys004\tw\n"
local function ids(list)
  local out = {}
  for _, s in ipairs(list) do out[#out + 1] = s.id end
  return table.concat(out, ",")
end
local asyncResult
agents.sessionsAsync(function(list) asyncResult = list end)
assertEqual(ids(asyncResult), ids(agents.sessions()), "async order matches sync")
assertEqual(ids(asyncResult), "Y,X,Z,W", "async groups agents by directory, others last")
assertEqual(asyncResult[1].cwd, "/a", "async records cwd")
local lsofTask = state.tasks[#state.tasks]
assertEqual(lsofTask.program, "/usr/sbin/lsof", "lsof runs as a task")
assertEqual(table.concat(lsofTask.programArgs, " "), "-a -d cwd -Fn -p 100,200,300", "lsof asked for agent pids only")
for i, t in ipairs(state.tasks) do
  assert(t.callbackCleared, "task " .. i .. " released its callback after finishing")
end

-- ps output on a busy Mac is larger than the pipe buffer (68KB measured).
local psLines = { state.psOutput }
for i = 1, 2000 do psLines[#psLines + 1] = string.format("%d 1 01:00 ?? /usr/libexec/some-daemon", 10000 + i) end
state.psOutput = table.concat(psLines, "\n")
assert(#state.psOutput > 65536, "test ps output exceeds the pipe buffer")
asyncResult = nil
agents.sessionsAsync(function(list) asyncResult = list end)
assert(asyncResult, "async finishes when ps output exceeds the pipe buffer")
assertEqual(ids(asyncResult):sub(1, 7), "Y,X,Z,W", "large ps output parsed")

state.running = false
local tasksBefore = #state.tasks
asyncResult = nil
agents.sessionsAsync(function(list) asyncResult = list end)
assertEqual(#asyncResult, 0, "async yields nothing when iTerm2 is not running")
assertEqual(#state.tasks, tasksBefore, "async starts no task when iTerm2 is not running")
state.running = true

state.running = false
local scriptsBefore = #state.scripts
items = agents.menu()
assertEqual(items[1].title, "iTerm2 未运行", "reports iTerm2 not running")
assertEqual(#state.scripts, scriptsBefore, "does not launch iTerm2 via AppleScript")

print("iterm_agents integration tests passed")
