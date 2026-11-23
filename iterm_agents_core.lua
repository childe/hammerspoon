-- Pure parsing for iterm_agents.lua; no hs.* dependencies so it runs under luajit.
local M = {}

-- Process basenames that count as a coding agent.
M.agents = { claude = true, codex = true }

local function lines(text)
  return (text or ""):gmatch("[^\n]+")
end

-- Converts ps etime, [[dd-]hh:]mm:ss, to seconds.
local function parseElapsed(etime)
  local days, rest = etime:match("^(%d+)-(.+)$")
  local seconds = 0
  for part in (rest or etime):gmatch("%d+") do seconds = seconds * 60 + tonumber(part) end
  return seconds + (tonumber(days) or 0) * 86400
end

-- Parses `ps -A -o pid=,ppid=,etime=,tty=,comm=` output into
-- {pid, ppid, elapsed, tty, comm}, elapsed being seconds since the process started.
function M.parseProcesses(text)
  local procs = {}
  for line in lines(text) do
    local pid, ppid, etime, tty, comm = line:match("^%s*(%d+)%s+(%d+)%s+([%d:-]+)%s+(%S+)%s+(.-)%s*$")
    if pid then
      procs[#procs + 1] = {
        pid = tonumber(pid), ppid = tonumber(ppid), elapsed = parseElapsed(etime), tty = tty, comm = comm,
      }
    end
  end
  return procs
end

-- Parses the AppleScript session dump: window id, tab index, session id, tty
-- and title, tab-separated, one session per line.
function M.parseSessions(text)
  local sessions = {}
  for line in lines(text) do
    local window, tab, id, tty, title = line:match("^([^\t]*)\t(%d+)\t([^\t]+)\t([^\t]*)\t(.*)$")
    if window then
      sessions[#sessions + 1] = { window = window, tab = tonumber(tab), id = id, tty = tty, title = title }
    end
  end
  return sessions
end

local function agentName(comm)
  local base = comm:match("([^/]+)$") or comm
  if M.agents[base] then return base end
  return nil
end

-- Returns the agent running under the session's tty and its process, or nil. Walks descendants
-- rather than matching the tty, since wrappers like kiro-cli-term run the real
-- programs on an inner pty.
function M.agentOnTty(procs, tty)
  tty = (tty or ""):gsub("^/dev/", "")
  local children, frontier = {}, {}
  for _, p in ipairs(procs) do
    children[p.ppid] = children[p.ppid] or {}
    table.insert(children[p.ppid], p)
    if p.tty == tty then frontier[#frontier + 1] = p end
  end

  local visited = {}
  while #frontier > 0 do
    local p = table.remove(frontier)
    if not visited[p.pid] then
      visited[p.pid] = true
      local agent = agentName(p.comm)
      if agent then return agent, p end
      for _, child in ipairs(children[p.pid] or {}) do frontier[#frontier + 1] = child end
    end
  end
  return nil
end

-- Parses `lsof -a -d cwd -p <pids> -Fn` output into {pid = cwd}.
function M.parseCwds(text)
  local cwds, pid = {}, nil
  for line in lines(text) do
    local field, value = line:sub(1, 1), line:sub(2)
    if field == "p" then
      pid = tonumber(value)
    elseif field == "n" and pid then
      cwds[pid] = value
    end
  end
  return cwds
end

-- Tags each session with its agent and returns agent sessions first, ordered by
-- the agent's working directory, then the most recently started agent on top;
-- agents with an unknown cwd follow. Other sessions keep iTerm2's window/tab order.
-- cwdsFor(pids) returns {pid = cwd} for the agent processes.
function M.classify(sessions, procs, cwdsFor)
  local agents, others, elapsed, order, pids = {}, {}, {}, {}, {}
  local procOf = {}
  for i, s in ipairs(sessions) do
    local agent, proc = M.agentOnTty(procs, s.tty)
    s.agent = agent
    elapsed[s], order[s], procOf[s] = proc and proc.elapsed, i, proc
    if proc then pids[#pids + 1] = proc.pid end
    table.insert(s.agent and agents or others, s)
  end
  local cwds = (cwdsFor and #pids > 0) and cwdsFor(pids) or {}
  for _, s in ipairs(agents) do s.cwd, s.elapsed = cwds[procOf[s].pid], elapsed[s] end
  -- table.sort is not stable, so ties fall back to iTerm2's order.
  table.sort(agents, function(a, b)
    if a.cwd ~= b.cwd then
      if a.cwd == nil or b.cwd == nil then return b.cwd == nil end
      return a.cwd < b.cwd
    end
    if elapsed[a] ~= elapsed[b] then return elapsed[a] < elapsed[b] end
    return order[a] < order[b]
  end)
  for _, s in ipairs(others) do agents[#agents + 1] = s end
  return agents
end

-- Returns "r" when the title starts with a spinner (the agent is running), "w" otherwise
-- (its turn is over: done, or waiting for input or a permission answer).
-- claude spins ◐◑◒◓ (U+25D0–25D3), codex spins braille dots (U+2800–28FF).
-- Matches bytes rather than using utf8, which luajit lacks.
function M.state(title)
  local b1, b2, b3 = (title or ""):byte(1, 3)
  if b1 ~= 0xE2 then return "w" end
  if b2 == 0x97 and b3 >= 0x90 and b3 <= 0x93 then return "r" end
  if b2 and b2 >= 0xA0 and b2 <= 0xA3 then return "r" end
  return "w"
end

-- Drops the leading status character and iTerm2's trailing " (job) — path"; iTerm2 puts
-- non-breaking spaces (U+00A0, bytes C2 A0) around the dash, so either kind of space matches.
function M.cleanTitle(title)
  title = title or ""
  local b1 = title:byte(1)
  if b1 == 0xE2 then
    local first = title:sub(1, 3)
    if M.state(first) == "r" or first == "✳" then title = title:sub(4):gsub("^ ", "") end
  end
  return (title:gsub(" %([^()]*%)[ \194\160]+—[ \194\160].*$", ""))
end

-- Longest S line the Cardputer is sent: macOS's usual 185-byte MTU minus the 3-byte ATT header,
-- with some slack.
M.maxLineBytes = 180

local agentCodes = { claude = "c", codex = "x" }

-- Replaces a leading home directory with "~".
local function shortDir(dir, home)
  dir = dir or ""
  if home and (dir == home or dir:sub(1, #home + 1) == home .. "/") then return "~" .. dir:sub(#home + 1) end
  return dir
end

local function field(s)
  return (s or ""):gsub("[\t\n\r]", " ")
end

-- Cuts s to at most n bytes without splitting a UTF-8 character.
local function cutUtf8(s, n)
  if #s <= n then return s end
  local i = n + 1
  while i > 1 and (s:byte(i) or 0) >= 0x80 and s:byte(i) < 0xC0 do i = i - 1 end
  return s:sub(1, i - 1)
end

-- Encodes agent sessions as the Cardputer's list messages, without trailing newlines:
-- "B", one "S\t<id>\t<agent>\t<state>\t<title>\t<dir>" per agent session in input order, "E".
function M.encodeList(sessions, home)
  local lines = { "B" }
  for _, s in ipairs(sessions) do
    if s.agent then
      local dir = shortDir(s.cwd, home)
      local head = table.concat({ "S", field(s.id), agentCodes[s.agent] or "c", M.state(s.title) }, "\t") .. "\t"
      local tail = "\t" .. field(dir)
      local title = cutUtf8(field(M.cleanTitle(s.title)), math.max(0, M.maxLineBytes - #head - #tail))
      lines[#lines + 1] = head .. title .. tail
    end
  end
  lines[#lines + 1] = "E"
  return lines
end

-- Formats seconds as the largest whole unit: "42s", "2m", "3h", "2d"; "" when unknown.
function M.age(seconds)
  if not seconds then return "" end
  if seconds < 60 then return seconds .. "s" end
  if seconds < 3600 then return math.floor(seconds / 60) .. "m" end
  if seconds < 86400 then return math.floor(seconds / 3600) .. "h" end
  return math.floor(seconds / 86400) .. "d"
end

-- Groups agent sessions for the panel: {{dir, rows = {{id, agent, state, title, age}}}}, one group
-- per run of sessions sharing a directory, in input order. dir is "" when the cwd is unknown.
function M.panelGroups(sessions, home)
  local groups = {}
  for _, s in ipairs(sessions) do
    if s.agent then
      local dir = shortDir(s.cwd, home)
      local group = groups[#groups]
      if not group or group.dir ~= dir then
        group = { dir = dir, rows = {} }
        groups[#groups + 1] = group
      end
      group.rows[#group.rows + 1] = {
        id = s.id, agent = s.agent, state = M.state(s.title), title = M.cleanTitle(s.title), age = M.age(s.elapsed),
      }
    end
  end
  return groups
end

local chordFlags = { "cmd", "ctrl", "alt", "shift" }

-- Detects a bare tap of a modifier chord such as {ctrl = true, alt = true}: flags(f) takes each
-- flagsChanged state and returns true when all keys are released after exactly the chord was held,
-- key() reports a key press. Any key or extra modifier during the hold cancels the tap, so
-- shortcuts that start with the chord, like ⌃⌥T or ⌃⌥⌘T, never fire it.
function M.chordTap(chord)
  local tap, held, spoiled, down = {}, false, false, false
  local function classify(f)
    local any, exact = false, true
    for _, name in ipairs(chordFlags) do
      local on = f[name] and true or false
      if on then any = true end
      if on and not chord[name] then return "extra", true end
      if on ~= (chord[name] and true or false) then exact = false end
    end
    return exact and "exact" or (any and "partial" or "none"), any
  end
  function tap:flags(f)
    local kind = classify(f or {})
    down = kind ~= "none"
    if kind == "extra" then
      spoiled = true
    elseif kind == "exact" then
      held = true
    elseif kind == "none" then
      local fire = held and not spoiled
      held, spoiled = false, false
      return fire
    end
    return false
  end
  function tap:key()
    if down then spoiled = true end
  end
  return tap
end

return M
