# Fifteen-row Chooser Design

## Decision

Raise the chooser's visible-row cap from 11 to 15. Lists with 15 or fewer
choices display fully; longer lists retain every choice but scroll after row 15.

The user confirmed that 11 rows occupy only about half of the actual target
screen. The separate transparent-frame artifact persists at 11 rows, so it is
not treated as an overflow symptom and is outside this sizing change.

## Verification

The integration test creates 16 choices and verifies that all 16 remain in the
model while the chooser requests exactly 15 visible rows.
