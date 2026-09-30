# Stale Window Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent windows owned by terminated applications from appearing in the chooser.

**Architecture:** Keep `hs.window.filter` as the cached source and add one cheap process-liveness guard while converting a cached window into a chooser record. Avoid `hs.window.get()` during list construction because it re-enumerates all application windows.

**Tech Stack:** Lua, Hammerspoon `hs.window.filter`, LuaJIT integration tests.

---

### Task 1: Restore the integration-test baseline

**Files:**
- Modify: `tests/dockapps_integration_test.lua:137`

- [ ] **Step 1: Match the test to the committed current-app shortcut**

Change the stale key assertion to:

```lua
assertEqual(hotkey.key, "o", "current-app hotkey is registered")
```

- [ ] **Step 2: Run the integration test**

Run:

```bash
/opt/homebrew/bin/luajit tests/dockapps_integration_test.lua
```

Expected: `dockapps_integration_test: ok`.

- [ ] **Step 3: Commit the baseline repair**

```bash
git add tests/dockapps_integration_test.lua
git commit -m "test: align current app shortcut assertion"
```

### Task 2: Filter terminated application records

**Files:**
- Modify: `tests/dockapps_integration_test.lua`
- Modify: `dockapps.lua:35-43`

- [ ] **Step 1: Model application liveness in the fake**

Extend the fake application with a mutable running state:

```lua
local function app(name, pid, hidden)
  local value = { activated = false, running = true }
  function value:name() return name end
  function value:pid() return pid end
  function value:path() return "/Applications/" .. name .. ".app" end
  function value:isHidden() return hidden end
  function value:isRunning() return self.running end
  function value:activate(allWindows)
    self.activated = true
    self.activatedAllWindows = allWindows
    return true
  end
  return value
end
```

- [ ] **Step 2: Add the failing regression case**

At the end of the integration test, append a cached window, terminate its fake
owner, reopen the chooser, and verify that the row is absent:

```lua
local closedApp = app("Closed App", 300, false)
windows[#windows + 1] = window(2001, closedApp, "stale", false)
closedApp.running = false
chooser.visible = false
dockapps.showAll()
assertEqual(#chooser.choiceList, 16, "terminated application windows are excluded")
```

- [ ] **Step 3: Run the test and verify RED**

Run:

```bash
/opt/homebrew/bin/luajit tests/dockapps_integration_test.lua
```

Expected: FAIL with `terminated application windows are excluded: expected 16, got 17`.

- [ ] **Step 4: Add the minimal liveness guard**

Immediately after resolving the owning application in `windowRecord()` add:

```lua
if safeCall(application, "isRunning") == false then return nil end
```

An unavailable or failing method produces `nil`, which intentionally keeps the
record rather than hiding a potentially valid window.

- [ ] **Step 5: Run the full Lua test suite and compile**

Run:

```bash
/opt/homebrew/bin/luajit tests/dockapps_core_test.lua
/opt/homebrew/bin/luajit tests/dockapps_integration_test.lua
/opt/homebrew/bin/luajit -b dockapps.lua /tmp/dockapps.luac
/opt/homebrew/bin/luajit -b dockapps_core.lua /tmp/dockapps_core.luac
git diff --check
```

Expected: both tests print `ok`; compilation and whitespace checks exit 0.

- [ ] **Step 6: Restart Hammerspoon and verify configuration load**

Quit and reopen Hammerspoon, then inspect the unified log. Expected: a new
`setup.lua completed` entry and no Lua configuration error.

- [ ] **Step 7: Commit the fix**

```bash
git add dockapps.lua tests/dockapps_integration_test.lua docs/superpowers/plans/2026-09-30-stale-window-filter.md
git commit -m "fix: hide windows from terminated apps"
```
