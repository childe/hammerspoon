-- Lists iTerm2 tabs, with tabs running claude/codex on top, grouped by the agent's directory
-- and newest first within one, and focuses a chosen session. menu() builds the tab menu that
-- iterm_agents_panel.lua shows on a right click of 🤖.
local core = require("iterm_agents_core")

local M = {}
local appName = "iTerm2"
M.maxTitleLength = 80

local listScript = [[
-- Inside the tell block `tab` means iTerm2's tab class, not the character.
set sep to character id 9
tell application "iTerm2"
  set out to ""
  repeat with w in windows
    set tabIndex to 0
    repeat with t in tabs of w
      set tabIndex to tabIndex + 1
      repeat with s in sessions of t
        set out to out & (id of w) & sep & tabIndex & sep & (id of s) & sep & (tty of s) & sep & (name of s) & linefeed
      end repeat
    end repeat
  end repeat
  return out
end tell
]]

local focusScript = [[
tell application "iTerm2"
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        if id of s is "%s" then
          select w
          tell t to select
          tell s to select
          activate
          return true
        end if
      end repeat
    end repeat
  end repeat
  return false
end tell
]]

-- Never launches iTerm2 just to list it.
local function isRunning()
  return hs.application.get(appName) ~= nil
end

local function cwdsFor(pids)
  return core.parseCwds(hs.execute("lsof -a -d cwd -Fn -p " .. table.concat(pids, ",")))
end

function M.sessions()
  if not isRunning() then return {} end
  local ok, output = hs.osascript.applescript(listScript)
  if not ok then return {} end
  local procs = core.parseProcesses(hs.execute("ps -A -o pid=,ppid=,etime=,tty=,comm="))
  return core.classify(core.parseSessions(output), procs, cwdsFor)
end

-- Tasks in flight; hs.task objects that nothing references can be collected before they finish.
local tasks = {}

-- Runs a program without blocking Hammerspoon and calls done(stdout, exitCode).
-- The program's stdout goes to a temp file, read after it exits: hs.task does not drain a
-- stdout pipe until the program exits, so output over the 64KB pipe buffer (ps -A is ~68KB
-- on a busy Mac) blocks the program forever.
local function run(path, args, done)
  local file = os.tmpname()
  local shArgs = { "-c", 'out="$1"; shift; "$@" > "$out"', "sh", file, path }
  for _, a in ipairs(args) do shArgs[#shArgs + 1] = a end
  local task
  task = hs.task.new("/bin/sh", function(code)
    tasks[task] = nil
    local f = io.open(file)
    local out = f and f:read("*a") or ""
    if f then f:close() end
    os.remove(file)
    done(out, code)
  end, shArgs)
  tasks[task] = true
  task:start()
end

-- Same result as sessions(), delivered to callback(sessions) without blocking the main thread:
-- the synchronous osascript + ps + lsof take about 0.4s, too long to run every 2 seconds.
function M.sessionsAsync(callback)
  if not isRunning() then return callback({}) end
  run("/usr/bin/osascript", { "-e", listScript }, function(listOut, code)
    if code ~= 0 then return callback({}) end
    run("/bin/ps", { "-A", "-o", "pid=,ppid=,etime=,tty=,comm=" }, function(psOut, psCode)
      if psCode ~= 0 then return callback({}) end
      local procs = core.parseProcesses(psOut)
      local pids
      core.classify(core.parseSessions(listOut), procs, function(p)
        pids = p
        return {}
      end)
      if not pids then return callback(core.classify(core.parseSessions(listOut), procs)) end
      -- lsof exits 1 when one of the pids is gone; the rest of its output is still good.
      run("/usr/sbin/lsof", { "-a", "-d", "cwd", "-Fn", "-p", table.concat(pids, ",") }, function(lsofOut)
        local cwds = core.parseCwds(lsofOut)
        callback(core.classify(core.parseSessions(listOut), procs, function() return cwds end))
      end)
    end)
  end)
end

function M.focus(sessionId)
  -- Session ids are UUIDs; reject anything that could break out of the string.
  if not sessionId:match("^[%w%-:]+$") then return false end
  local ok, found = hs.osascript.applescript(string.format(focusScript, sessionId))
  return ok and found == true
end

local function shorten(title)
  if utf8.len(title) == nil or utf8.len(title) <= M.maxTitleLength then return title end
  return title:sub(1, utf8.offset(title, M.maxTitleLength + 1) - 1) .. "…"
end

function M.menu()
  if not isRunning() then return { { title = "iTerm2 未运行", disabled = true } } end
  local sessions = M.sessions()
  if #sessions == 0 then return { { title = "没有 iTerm2 tab", disabled = true } } end

  local items, inOthers = {}, false
  for i, s in ipairs(sessions) do
    if not s.agent and not inOthers then
      inOthers = true
      if i > 1 then items[#items + 1] = { title = "-" } end
    end
    local prefix = s.agent and string.format("[%s] ", s.agent) or ""
    items[#items + 1] = {
      title = prefix .. shorten(s.title),
      fn = function()
        if not M.focus(s.id) then hs.alert.show("iTerm tab 已关闭") end
      end,
    }
  end
  return items
end

return M
