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

print("iterm_agents_core tests passed")
