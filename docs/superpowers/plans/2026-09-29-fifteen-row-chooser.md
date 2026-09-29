# Fifteen-row Chooser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Increase the Hammerspoon chooser cap from 11 to 15 visible rows.

**Architecture:** Change the existing cap constant only; preserve dynamic sizing and all choices.

**Tech Stack:** Lua, Hammerspoon `hs.chooser`, LuaJIT tests.

---

### Task 1: Increase row cap

**Files:**
- Modify: `tests/dockapps_integration_test.lua`
- Modify: `dockapps.lua`

- [x] Add 14 extra fake windows so the test contains 16 choices, then expect 15 visible rows.
- [x] Run the integration test and observe the current implementation returning 11 rows.
- [x] Change `maxVisibleRows` from 11 to 15.
- [x] Run both tests and LuaJIT bytecode compilation.
- [ ] Restart Hammerspoon and verify its Lua setup completes.
