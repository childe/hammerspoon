-- Menubar list of iTerm2 tabs, with tabs running claude/codex on top, newest first.
-- The list is built when the menu opens; picking an item focuses that session.
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

function M.sessions()
  if not isRunning() then return {} end
  local ok, output = hs.osascript.applescript(listScript)
  if not ok then return {} end
  local procs = core.parseProcesses(hs.execute("ps -A -o pid=,ppid=,etime=,tty=,comm="))
  return core.classify(core.parseSessions(output), procs)
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

local menubar = hs.menubar.new()
if menubar then
  menubar:setTitle("🤖")
  menubar:setTooltip("iTerm2 tabs")
  menubar:setMenu(M.menu)
end

M.menubar = menubar

return M
