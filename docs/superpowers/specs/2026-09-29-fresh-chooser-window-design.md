# Fresh Chooser Window Design

## Problem

When the same `hs.chooser` is opened repeatedly on a horizontal monitor, a
second translucent frame can appear. Opening it first on a vertical monitor
temporarily avoids the artifact. Hammerspoon reuses one native chooser window
and resizes it before centering it, so stale window geometry or backing state
can survive a monitor transition.

## Decision

Create a new `hs.chooser` immediately before every opening and delete the
previous hidden chooser. Preserve the existing window collection, filtering,
search, focus behavior, shortcuts, and 15-row cap.

This intentionally changes only chooser ownership. It tests whether native
window reuse causes the artifact without mixing in sizing or layout changes.

## Verification

The integration test verifies that module loading creates no chooser, each
opening creates a fresh chooser, and the previously hidden chooser is deleted.
Automated tests also retain all existing behavior checks. Visual acceptance
uses the reported reproduction sequence: vertical once, then horizontal twice.
