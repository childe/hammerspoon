# Auto-sized Window Chooser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resize the Hammerspoon chooser to show every current result row.

**Architecture:** Centralize choice application in one helper that sets both row count and choices. Reuse it for initial display and event-driven refresh.

**Tech Stack:** Lua, Hammerspoon `hs.chooser`, LuaJIT tests.

---

### Task 1: Dynamic chooser rows

**Files:**
- Modify: `tests/dockapps_integration_test.lua`
- Modify: `dockapps.lua`

- [x] **Step 1: Add a failing assertion**

Add a `chooser:rows(value)` fake and assert `chooser.rowCount == 3` after
`dockapps.showAll()`.

- [x] **Step 2: Verify RED**

Run: `/opt/homebrew/bin/luajit tests/dockapps_integration_test.lua`

Expected: failure reporting that the expected row count is `3` but the actual
value is `nil`.

- [x] **Step 3: Apply choices and rows together**

Add this helper to `dockapps.lua` and use it from `show` and
`refreshVisibleChooser`:

```lua
local function applyChoices(scopePid)
  local choices = choicesFor(scopePid)
  chooser:rows(math.max(1, #choices))
  chooser:choices(choices)
end
```

- [x] **Step 4: Verify GREEN and regression tests**

Run:

```text
/opt/homebrew/bin/luajit tests/dockapps_core_test.lua
/opt/homebrew/bin/luajit tests/dockapps_integration_test.lua
```

Expected: both print `ok` and exit zero.

- [ ] **Step 5: Reload Hammerspoon**

Restart Hammerspoon, confirm its process is running, and inspect startup logs
for Lua errors.
