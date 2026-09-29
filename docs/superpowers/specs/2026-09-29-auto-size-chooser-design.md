# Auto-sized Window Chooser Design

## Goal

Show every current chooser result at once so normal window lists do not require
mouse scrolling.

## Behavior

Before choices are displayed, set the chooser's row count to the number of
choices. Use one row for an empty result so Hammerspoon always receives a valid
positive row count. Recalculate the count when an open chooser refreshes after
window events.

Hammerspoon and the physical display may still constrain a list taller than the
available screen; no multi-column or custom UI is introduced.

## Verification

The integration test records calls to `chooser:rows()` and verifies both the
initial all-window list and a live refresh use the current number of choices.
