# Fresh Chooser Window Implementation Plan

**Goal:** Avoid the repeated-horizontal-monitor translucent frame by preventing
reuse of the native `hs.chooser` window.

**Architecture:** Keep a reference only to the currently displayed chooser.
Before each opening, delete the prior hidden chooser and construct/configure a
new one. Keep the existing callback and refresh paths pointed at that instance.

**Tech Stack:** Lua, Hammerspoon `hs.chooser`, LuaJIT tests.

---

### Task 1: Specify chooser lifecycle

**Files:**
- Modify: `tests/dockapps_integration_test.lua`

- [ ] Make the chooser fake produce distinct instances and track deletion.
- [ ] Verify module loading does not allocate a native chooser.
- [ ] Verify consecutive openings allocate distinct choosers and delete the old one.
- [ ] Run the integration test and observe failure under the reused-chooser implementation.

### Task 2: Recreate chooser on every opening

**Files:**
- Modify: `dockapps.lua`

- [ ] Extract construction and configuration into a helper.
- [ ] Delete a prior hidden chooser before constructing the next one.
- [ ] Update the exported chooser reference for diagnostics.
- [ ] Run core and integration tests and compile both Lua modules.

### Task 3: Runtime verification

- [ ] Restart Hammerspoon.
- [ ] Verify the Lua setup completes without an error.
- [ ] Ask the user to run the vertical-once, horizontal-twice visual check.
