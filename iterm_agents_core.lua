-- Pure parsing for iterm_agents.lua; no hs.* dependencies so it runs under luajit.
local M = {}

-- Process basenames that count as a coding agent.
M.agents = { claude = true, codex = true }

local function lines(text)
  return (text or ""):gmatch("[^\n]+")
end

-- Parses `ps -A -o pid=,ppid=,tty=,comm=` output into {pid, ppid, tty, comm}.
function M.parseProcesses(text)
  local procs = {}
  for line in lines(text) do
    local pid, ppid, tty, comm = line:match("^%s*(%d+)%s+(%d+)%s+(%S+)%s+(.-)%s*$")
    if pid then
      procs[#procs + 1] = { pid = tonumber(pid), ppid = tonumber(ppid), tty = tty, comm = comm }
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

-- Returns the agent running under the session's tty, or nil. Walks descendants
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
      if agent then return agent end
      for _, child in ipairs(children[p.pid] or {}) do frontier[#frontier + 1] = child end
    end
  end
  return nil
end

-- Tags each session with its agent and returns agent sessions first, otherwise
-- keeping iTerm2's window/tab order.
function M.classify(sessions, procs)
  local agents, others = {}, {}
  for _, s in ipairs(sessions) do
    s.agent = M.agentOnTty(procs, s.tty)
    table.insert(s.agent and agents or others, s)
  end
  for _, s in ipairs(others) do agents[#agents + 1] = s end
  return agents
end

return M
