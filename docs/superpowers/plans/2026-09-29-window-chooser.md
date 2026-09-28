# Hammerspoon Window Chooser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a searchable, MRU-ordered Hammerspoon window chooser backed by `hs.window.filter`, without thumbnails.

**Architecture:** Put deterministic transformation and trigger logic in a pure Lua module. Keep Hammerspoon objects, event subscriptions, icon caching, and focus actions in a thin integration module.

**Tech Stack:** Lua 5.4-compatible syntax, Hammerspoon 1.1.1 APIs, LuaJIT test runner.

---

### Task 1: Pure chooser model

**Files:**
- Create: `dockapps_core.lua`
- Create: `tests/dockapps_core_test.lua`

- [ ] **Step 1: Write failing tests** for modifier transitions, invalid-window rejection, current-app filtering, MRU preservation, duplicate IDs, and minimized/hidden labels.
- [ ] **Step 2: Run tests to verify RED:** `/opt/homebrew/bin/luajit tests/dockapps_core_test.lua`; expect module-not-found failure.
- [ ] **Step 3: Implement `flagsEqual`, `shouldOpen`, and `buildChoices`** with explicit input/output tables and no Hammerspoon dependency.
- [ ] **Step 4: Run tests to verify GREEN:** `/opt/homebrew/bin/luajit tests/dockapps_core_test.lua`; expect all assertions to pass.

### Task 2: Hammerspoon integration

**Files:**
- Modify: `dockapps.lua`
- Create: `tests/dockapps_integration_test.lua`

- [ ] **Step 1: Write a failing integration test** with a minimal fake `hs` API that requires `dockapps.lua`, opens both scopes, and verifies ID-based safe focus.
- [ ] **Step 2: Run test to verify RED:** `/opt/homebrew/bin/luajit tests/dockapps_integration_test.lua`; expect missing exported module behavior.
- [ ] **Step 3: Replace globals and `allWindows()`** with a local module, `hs.window.filter.new()`, MRU `getWindows`, application icon cache, safe property reads, and `hs.window.get(choice.windowID)`.
- [ ] **Step 4: Preserve the existing modifier gesture** and bind `Ctrl+Alt+Cmd+W` to current-app windows.
- [ ] **Step 5: Run both test files** and expect all assertions to pass.

### Task 3: Final verification and handoff

**Files:**
- Modify: `README.md` only if one already exists; otherwise document shortcuts in `dockapps.lua` comments.

- [ ] **Step 1: Run Lua syntax checks** over production and test files using `luajit -b` into a temporary directory.
- [ ] **Step 2: Run the complete test suite** and confirm clean output.
- [ ] **Step 3: Check the exact Git diff** to ensure unrelated `init.lua` and weather changes are untouched.
- [ ] **Step 4: If Hammerspoon IPC is available, reload the config and query module status; otherwise report that live GUI verification remains for the next Hammerspoon launch.**
