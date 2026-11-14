-- Pushes the iTerm2 agent session list to the Cardputer's AGENTS app and focuses the
-- session picked there. Talks line by line to agentbridge (stackm5 repo, tools/agentbridge)
-- over a Unix socket; agentbridge owns the Bluetooth link, since a process Hammerspoon
-- starts is killed by macOS as soon as it touches Bluetooth.
--
-- From agentbridge: "C\t1" / "C\t0" when the Cardputer connects / disconnects, "F\t<id>" to focus.
-- To agentbridge: "B", "S\t...", "E" — one full list every pushInterval seconds while connected.
local core = require("iterm_agents_core")
local agents = require("iterm_agents")

local M = {}
M.socketPath = os.getenv("HOME") .. "/.cache/agentbridge.sock"
M.pushInterval = 2
M.retryInterval = 5

local sock, pushTimer, busy

local function log(message)
  print("iterm_agents_ble: " .. message)
end

local function stopPushing()
  if pushTimer then pushTimer:stop() end
  pushTimer = nil
end

-- Skips a push while the previous one is still listing, unless that one has hung for 10 seconds.
local function push()
  if not sock or (busy and os.time() - busy < 10) then return end
  local started = os.time()
  busy = started
  agents.sessionsAsync(function(sessions)
    if busy == started then busy = nil end
    if not (sock and sock:connected()) then return end
    sock:write(table.concat(core.encodeList(sessions, os.getenv("HOME")), "\n") .. "\n")
  end)
end

local function onLine(line)
  line = line:gsub("[\r\n]+$", "")
  if line == "C\t1" then
    log("Cardputer connected")
    push()
    stopPushing()
    pushTimer = hs.timer.doEvery(M.pushInterval, push)
  elseif line == "C\t0" then
    log("Cardputer disconnected")
    stopPushing()
  else
    local id = line:match("^F\t(.+)$")
    if id and not agents.focus(id) then log("focus failed: " .. id) end
  end
end

local function connect()
  stopPushing()
  if sock then sock:disconnect() end
  sock = hs.socket.new(function(data)
    onLine(data)
    if sock then sock:read("\n") end
  end)
  sock:connect(M.socketPath, function()
    log("connected to agentbridge")
    sock:read("\n")
  end)
end

-- hs.socket has no disconnect callback, so check on a timer and reconnect.
M.watchdog = hs.timer.doEvery(M.retryInterval, function()
  if not (sock and sock:connected()) then connect() end
end)
connect()

M.push = push
_G.itermAgentsBle = M -- keep the socket and timers from being collected

return M
