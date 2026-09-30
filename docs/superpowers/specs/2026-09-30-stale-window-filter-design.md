# Stale Window Filter Design

## Problem

The chooser can display a window owned by an application that has already
terminated. Selecting that row then fails because `hs.window.get(windowID)` no
longer resolves it and shows `Window is no longer available`.

`hs.window.filter:getWindows()` checks its internal application cache, but an
application can terminate after that check and before `windowRecord()` builds
the chooser row. The current row validation checks only the cached name and PID,
not whether the application is still running.

## Decision

In `windowRecord()`, reject a record when
`application:isRunning()` explicitly returns `false`. Keep records when the
method is unavailable or errors so a transient API failure does not hide a
valid window.

This is preferred over validating every ID with `hs.window.get()`: that method
calls `hs.window.allWindows()` and re-enumerates every application's windows,
which would make chooser opening substantially more expensive. It is also
preferred over suppressing an ID only after a failed click because the stale
row should not be shown in the first place.

## Scope

The change filters windows whose owning process has terminated. It cannot
eliminate the unavoidable race where a valid window closes after the chooser
has already appeared; the existing selection-time error remains for that case.

## Verification

The integration fake will model a terminated application whose cached window is
still returned by the window filter. The test will verify that its row is absent
while rows from running applications remain unchanged. Existing core and
integration tests, LuaJIT bytecode compilation, and a Hammerspoon reload will
provide regression and runtime-load coverage.
