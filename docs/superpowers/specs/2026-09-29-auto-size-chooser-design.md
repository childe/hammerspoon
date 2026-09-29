# Auto-sized Window Chooser Design

## Goal

Show every current chooser result at once so normal window lists do not require
mouse scrolling.

## Behavior

Before choices are displayed, set the chooser's row count to the number of
choices, capped at 11. Use one row for an empty result so Hammerspoon always
receives a valid positive row count. Recalculate the count when an open chooser
refreshes after window events.

The cap follows Hammerspoon 1.1.1's layout: about 107 points of fixed chrome and
82 points per row. Eleven rows require about 1009 points; twelve require about
1091 points and overflow a 1080-point display. Lists longer than 11 rows scroll;
no multi-column or custom UI is introduced.

## Verification

The integration test records calls to `chooser:rows()` and verifies both the
initial all-window list and a live refresh use the current number of choices,
while a 12-choice list is capped at 11 visible rows.
