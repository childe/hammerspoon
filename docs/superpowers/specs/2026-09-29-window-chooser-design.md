# Hammerspoon Window Chooser Design

## Goal

Replace the per-invocation `hs.window.allWindows()` scan with a responsive,
searchable chooser backed by `hs.window.filter`, without window thumbnails.

## Scope

- Keep the existing Cmd then Cmd+Ctrl modifier gesture for all known windows.
- Add a conventional hotkey for the current application's windows.
- Show application icon, application name, window title, and minimized/hidden
  state.
- Order windows by most-recent focus, using `hs.window.filter`'s event-backed
  MRU ordering.
- Reject helper/transient windows through a private copy of Hammerspoon's
  default window filter.
- Resolve a selected window by stable window ID and validate it before focus.
- Keep all module state local so config reloads do not add global names.

## Architecture

`dockapps_core.lua` contains pure functions for modifier transition matching,
safe choice-model construction, and current-application filtering. It has no
dependency on Hammerspoon and is tested with LuaJIT.

`dockapps.lua` owns the Hammerspoon integration: a local window filter, chooser,
event subscriptions, application icon cache, modifier event tap, and hotkey.
At chooser-open time it asks the already-active filter for its current MRU
window list. The choice callback resolves the stored window ID again through
`hs.window.get` before focusing it.

## Error handling

Windows and applications may disappear during enumeration. Every property read
is protected, malformed entries are skipped, and a vanished selected window
produces a short alert rather than a Lua error. Missing icons are allowed.

## Known boundary

This improves speed and consistency for windows known to Hammerspoon, but the
public Hammerspoon API cannot guarantee discovery of every window on every
Mission Control Space or native full-screen Space.

## Verification

- Pure Lua tests cover ordering, filtering, labels, duplicate IDs, and modifier
  transitions.
- LuaJIT parses and runs the core tests.
- A stubbed `hs` integration smoke test loads `dockapps.lua` and exercises both
  chooser scopes and safe focus behavior.
- Live Hammerspoon reload is attempted only when its IPC endpoint is available.
