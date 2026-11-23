package.path = "./?.lua;" .. package.path
-- Hammerspoon runs Lua 5.4: hide Lua 5.1-only globals that luajit still provides.
unpack, setfenv, getfenv, loadstring = nil, nil, nil, nil

local core = require("iterm_agents_core")

local function assertEqual(actual, expected, message)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
  end
end

-- parseProcesses: `ps -A -o pid=,ppid=,etime=,tty=,comm=` output, comm may contain spaces.
local procs = core.parseProcesses(table.concat({
  "    1     0 148-01:55:22 ??       /sbin/launchd",
  "55210 43788  1-02:03:10 ttys013  /usr/bin/login",
  "55211 55210  1-02:03:09 ttys013  zsh (kiro-cli-term)",
  "55226 55211  1-02:03:08 ttys014  /bin/zsh",
  "55632 55226  1-02:03:04 ttys014  claude",
  "55700 55632       00:10 ttys014  caffeinate",
  "60000 43788    03:00:00 ttys006  /usr/bin/login",
  "60001 60000    03:00:00 ttys006  -zsh",
  "70000 43788       10:00 ttys020  /usr/bin/login",
  "70001 70000       10:00 ttys020  -zsh",
  "70002 70001       05:00 ttys020  /opt/homebrew/bin/codex",
  "80000 43788       01:00 ttys030  /usr/bin/login",
  "80001 80000       01:00 ttys030  -zsh",
  "80002 80001       00:30 ttys030  nvim",
  "90000 43788       02:00 ttys040  /usr/bin/login",
  "90001 90000       02:00 ttys040  -zsh",
  "90002 90001       01:00 ttys040  claude",
  "",
}, "\n"))
assertEqual(#procs, 17, "every process line is parsed")
assertEqual(procs[3].comm, "zsh (kiro-cli-term)", "comm keeps embedded spaces")
assertEqual(procs[3].pid, 55211, "pid is numeric")
assertEqual(procs[3].ppid, 55210, "ppid is numeric")
assertEqual(procs[5].elapsed, 93784, "dd-hh:mm:ss elapsed in seconds")
assertEqual(procs[7].elapsed, 10800, "hh:mm:ss elapsed in seconds")
assertEqual(procs[11].elapsed, 300, "mm:ss elapsed in seconds")
assertEqual(procs[3].tty, "ttys013", "tty is kept")

-- agentOnTty walks descendants, so agents behind a wrapper pty are still found.
assertEqual(core.agentOnTty(procs, "/dev/ttys013"), "claude", "claude behind kiro-cli-term wrapper")
assertEqual(core.agentOnTty(procs, "ttys006"), nil, "idle shell has no agent")
assertEqual(core.agentOnTty(procs, "/dev/ttys020"), "codex", "codex matched by basename of full path")
assertEqual(core.agentOnTty(procs, "/dev/ttys030"), nil, "other programs are not agents")
assertEqual(core.agentOnTty(procs, "/dev/ttys099"), nil, "unknown tty has no agent")

-- A process cycle in a racy ps snapshot must not loop forever.
local cyclic = core.parseProcesses("10 11 01:00 ttys001 -zsh\n11 10 01:00 ttys001 bash\n")
assertEqual(core.agentOnTty(cyclic, "ttys001"), nil, "cyclic parents terminate")

-- parseSessions: AppleScript output, one tab-separated line per session.
local sessions = core.parseSessions(table.concat({
  "w1\t1\tS-A\t/dev/ttys013\t✳ Judge (claude) — ~/p",
  "w1\t2\tS-B\t/dev/ttys006\tzsh — ~/p",
  "w2\t1\tS-C\t/dev/ttys020\tcodex — ~/q",
  "w2\t2\tS-D\t/dev/ttys040\tclaude — ~/p",
  "",
}, "\n"))
assertEqual(#sessions, 4, "every session line is parsed")
assertEqual(sessions[1].id, "S-A", "session id")
assertEqual(sessions[1].tty, "/dev/ttys013", "session tty")
assertEqual(sessions[1].title, "✳ Judge (claude) — ~/p", "title keeps unicode")
assertEqual(sessions[3].window, "w2", "window id")
assertEqual(sessions[2].tab, 2, "tab index is numeric")

-- parseCwds: `lsof -a -d cwd -p <pids> -Fn` output.
local cwds = core.parseCwds(table.concat({
  "p55632", "fcwd", "n/Users/me/p",
  "p70002", "fcwd", "n/Users/me/a dir",
  "p90002", "fcwd", "n/Users/me/p",
  "",
}, "\n"))
assertEqual(cwds[55632], "/Users/me/p", "cwd keyed by pid")
assertEqual(cwds[70002], "/Users/me/a dir", "cwd keeps spaces")

-- classify tags each session and puts agent sessions first, ordered by the
-- agent's directory, newest agent process first within a directory, keeping
-- iTerm2's order for the rest.
local asked
local classified = core.classify(sessions, procs, function(pids)
  asked = pids
  return cwds
end)
assertEqual(#asked, 3, "cwds looked up for agent processes only")
assertEqual(classified[1].id, "S-C", "alphabetically first directory first")
assertEqual(classified[1].agent, "codex", "codex tagged")
assertEqual(classified[1].cwd, "/Users/me/a dir", "cwd recorded")
assertEqual(classified[2].id, "S-D", "newest agent first within a directory")
assertEqual(classified[2].agent, "claude", "agent tagged")
assertEqual(classified[3].id, "S-A", "older agent in the same directory next")
assertEqual(classified[4].id, "S-B", "non-agent sessions last")
assertEqual(classified[4].agent, nil, "non-agent untagged")

-- Agents whose cwd is unknown go after those with one.
classified = core.classify(sessions, procs, function() return { [55632] = "/Users/me/p" } end)
assertEqual(classified[1].id, "S-A", "known cwd first")
assertEqual(classified[2].id, "S-D", "unknown cwd ordered by start time")
assertEqual(classified[3].id, "S-C", "oldest unknown cwd last")

-- state: a spinner as the title's first character means the agent is running.
-- claude spins ◐◑◒◓ (U+25D0–25D3), codex spins braille dots (U+2800–28FF).
for _, title in ipairs({ "◐ x", "◓ x", "⠸ x", "⣿ x" }) do
  assertEqual(core.state(title), "r", "running: " .. title)
end
for _, title in ipairs({ "✳ x", "Respond to greeting | stackm5", "" }) do
  assertEqual(core.state(title), "w", "waiting: " .. title)
end

-- cleanTitle drops the status character and iTerm2's " (job) — path" suffix.
assertEqual(core.cleanTitle("✳ 电路图项目增加题目 (claude) — ~/Projects/saisai.me"), "电路图项目增加题目",
  "claude title cleaned")
assertEqual(core.cleanTitle("⠸ 提供项目卡供选择 | stackm5 (codex) — ~/Projects/stackm5"),
  "提供项目卡供选择 | stackm5", "codex running title cleaned")
assertEqual(core.cleanTitle("Respond to greeting | stackm5 (codex) — ~/Projects/stackm5"),
  "Respond to greeting | stackm5", "codex idle title has no status character")
assertEqual(core.cleanTitle("◑ a (b) c (caffeinate) — ~/x"), "a (b) c", "only the last (job) suffix is dropped")
-- Real iTerm2 titles put non-breaking spaces (U+00A0) around the em dash.
assertEqual(core.cleanTitle("✳ 使用场景 (claude)\194\160—\194\160~/Projects/osg"), "使用场景",
  "suffix with non-breaking spaces dropped")

-- encodeList: one B, an S line per agent session in input order, one E.
local lines = core.encodeList({
  { id = "id1", agent = "claude", title = "◐ T1 (claude) — ~/p", cwd = "/Users/u/p" },
  { id = "id9", agent = nil, title = "zsh" },
  { id = "id2", agent = "codex", title = "T2\tx\ny (codex) — /tmp", cwd = nil },
}, "/Users/u")
assertEqual(#lines, 4, "B + two agents + E")
assertEqual(lines[1], "B", "list starts with B")
assertEqual(lines[2], "S\tid1\tc\tr\tT1\t~/p", "claude session encoded")
assertEqual(lines[3], "S\tid2\tx\tw\tT2 x y\t", "tab and newline become spaces, unknown cwd empty")
assertEqual(lines[4], "E", "list ends with E")

-- encodeList truncates long titles on a UTF-8 character boundary.
local long = core.encodeList({ { id = "id1", agent = "claude", title = string.rep("汉", 100), cwd = "/Users/u" } },
  "/Users/u")[2]
assert(#long <= 180, "S line is at most 180 bytes, got " .. #long)
local title = long:match("^S\tid1\tc\tw\t(.-)\t~$")
assert(title, "S line keeps its trailing dir field")
assertEqual(#title % 3, 0, "title cut between whole 3-byte characters")
assertEqual(title:sub(1, 3), "汉", "title keeps leading characters")

-- classify records how long each agent process has run.
classified = core.classify(core.parseSessions("w\t1\tS-A\t/dev/ttys013\tx\n"), procs)
assertEqual(classified[1].elapsed, 93784, "agent elapsed recorded")

-- age: compact elapsed time for the panel.
assertEqual(core.age(nil), "", "unknown age")
assertEqual(core.age(42), "42s", "seconds")
assertEqual(core.age(125), "2m", "minutes")
assertEqual(core.age(3 * 3600 + 59), "3h", "hours")
assertEqual(core.age(2 * 86400 + 5), "2d", "days")

-- panelGroups: agent sessions only, one group per directory in input order.
local groups = core.panelGroups({
  { id = "a", agent = "codex", title = "⠸ T1 (codex) — /x", cwd = "/Users/u/p", elapsed = 120 },
  { id = "b", agent = "claude", title = "✳ T2 (claude) — /x", cwd = "/Users/u/p", elapsed = 7200 },
  { id = "c", agent = "claude", title = "◐ T3", cwd = "/opt/q", elapsed = 5 },
  { id = "d", agent = "claude", title = "T4", cwd = nil },
  { id = "e", agent = nil, title = "zsh" },
}, "/Users/u")
assertEqual(#groups, 3, "one group per directory, other tabs dropped")
assertEqual(groups[1].dir, "~/p", "home shortened to ~")
assertEqual(#groups[1].rows, 2, "same-directory agents share a group")
local row = groups[1].rows[1]
assertEqual(row.id, "a", "row id")
assertEqual(row.agent, "codex", "row agent")
assertEqual(row.state, "r", "row state")
assertEqual(row.title, "T1", "row title cleaned")
assertEqual(row.age, "2m", "row age")
assertEqual(groups[1].rows[2].state, "w", "waiting row")
assertEqual(groups[2].dir, "/opt/q", "path outside home kept")
assertEqual(groups[3].dir, "", "unknown cwd has empty dir")
assertEqual(#core.panelGroups({}, "/Users/u"), 0, "no agents, no groups")
-- A home prefix that is not a whole path component is not shortened.
assertEqual(core.panelGroups({ { id = "x", agent = "claude", title = "t", cwd = "/Users/u2" } }, "/Users/u")[1].dir,
  "/Users/u2", "home prefix must end at a path boundary")

-- chordTap fires when exactly ctrl+alt were held together and all released, with no other key
-- or modifier in between.
local function run(events)
  local tap, fired = core.chordTap({ ctrl = true, alt = true }), 0
  for _, e in ipairs(events) do
    if e == "key" then tap:key() elseif tap:flags(e) then fired = fired + 1 end
  end
  return fired
end
local none, ctrl, alt, both = {}, { ctrl = true }, { alt = true }, { ctrl = true, alt = true }
local withCmd = { ctrl = true, alt = true, cmd = true }
assertEqual(run({ ctrl, both, alt, none }), 1, "ctrl then alt, released")
assertEqual(run({ alt, both, ctrl, none }), 1, "alt then ctrl, released")
assertEqual(run({ ctrl, both, none }), 1, "both released at once")
assertEqual(run({ ctrl, both, "key", none }), 0, "a key pressed while held cancels (⌃⌥T)")
assertEqual(run({ ctrl, both, withCmd, both, none }), 0, "an extra modifier cancels (⌃⌥⌘T)")
assertEqual(run({ ctrl, both, withCmd, "key", none }), 0, "⌃⌥⌘ shortcut does not fire")
assertEqual(run({ ctrl, none }), 0, "ctrl alone does not fire")
assertEqual(run({ ctrl, "key", both, none }), 0, "a key before the chord completes cancels")
assertEqual(run({ ctrl, both, "key", none, ctrl, both, none }), 1, "state resets after release")
assertEqual(run({ { ctrl = true, alt = true, fn = true }, none }), 1, "fn and other flags are ignored")
assertEqual(run({ both, alt, both, none }), 1, "re-pressing within the hold still one tap")
assertEqual(run({ "key", ctrl, both, none }), 1, "typing with no modifier held does not cancel the next tap")

print("iterm_agents_core tests passed")
