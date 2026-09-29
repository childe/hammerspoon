# Cap Chooser Rows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent the chooser panel from overflowing a 1080-point display.

**Architecture:** Keep dynamic sizing for short lists but clamp the requested row count to a fixed 11-row maximum. The existing `applyChoices` helper remains the single sizing point.

**Tech Stack:** Lua, Hammerspoon `hs.chooser`, LuaJIT tests.

---

### Task 1: Enforce the 11-row maximum

**Files:**
- Modify: `tests/dockapps_integration_test.lua`
- Modify: `dockapps.lua`

- [x] **Step 1: Add a failing test**

Append enough fake windows to produce 12 choices, call `showAll`, and assert
that all 12 choices remain searchable while `chooser.rowCount` is 11.

- [x] **Step 2: Verify RED**

Run: `/opt/homebrew/bin/luajit tests/dockapps_integration_test.lua`

Expected: failure showing the row count is 12 rather than 11.

- [x] **Step 3: Add the cap**

Define `local maxVisibleRows = 11` and change the sizing expression to:

```lua
chooser:rows(math.max(1, math.min(#choices, maxVisibleRows)))
```

- [x] **Step 4: Verify GREEN**

Run both Lua tests and compile `dockapps.lua` with `luajit -b`. Expect all
commands to exit zero.

- [x] **Step 5: Reload Hammerspoon**

Restart Hammerspoon and confirm `setup.lua completed` appears without a Lua
configuration error.
