-- Pure layout math for iterm_layout.lua; no hs.* dependencies so it runs under luajit.
--
-- Invariant: every slot owns a region (at least `margin` wide and tall) that no
-- other slot covers, so each window stays clickable whatever the z-order is.
local M = {}

local function rect(x, y, w, h)
  return { x = x, y = y, w = w, h = h }
end

-- Marks the slot's exclusive region: the sx by sy corner at `anchor` ("tl",
-- "tr", "bl" or "br"), which no other slot of the layout overlaps. A window
-- pinned to that corner covers the whole region however much it is shrunk.
local function anchored(slot, anchor, sx, sy)
  local right, bottom = anchor:sub(2, 2) == "r", anchor:sub(1, 1) == "b"
  slot.anchor = anchor
  slot.exclusive = rect(right and slot.x + slot.w - sx or slot.x,
    bottom and slot.y + slot.h - sy or slot.y, sx, sy)
  return slot
end

-- Diagonal cascade: slot i is offset (i*dx, i*dy). Its top-right dx by dy corner
-- falls outside every other slot. Steps shrink on small screens so each window
-- keeps at least half the screen; nil if even 1px steps don't fit.
local function cascade(frame, n, margin)
  local dx = math.min(margin, math.floor(frame.w / 2 / (n - 1)))
  local dy = math.min(margin, math.floor(frame.h / 2 / (n - 1)))
  if dx < 1 or dy < 1 then return nil end
  local w, h = frame.w - (n - 1) * dx, frame.h - (n - 1) * dy
  local slots = {}
  for i = 0, n - 1 do
    slots[#slots + 1] = anchored(rect(frame.x + i * dx, frame.y + i * dy, w, h), "tr", dx, dy)
  end
  return slots
end

-- Up to four windows, each one is the screen minus a single margin strip; the
-- exclusive areas sit on the screen corners. Consecutive counts reuse slots
-- (2 -> 3 keeps the left slot, 3 -> 4 keeps both right slots) so adding or
-- removing a window moves as few existing windows as possible.
-- Returns nil when the screen is too small to give every window a clickable area.
function M.slots(frame, n, margin)
  assert(margin >= 1, "margin must be at least 1")
  if n <= 0 then return {} end
  local x, y, w, h = frame.x, frame.y, frame.w, frame.h
  local m = math.min(margin, math.floor(w / 2), math.floor(h / 2))
  if m < 1 then return nil end
  if n == 1 then return { anchored(rect(x, y, w, h), "tl", m, m) } end
  if n > 4 then return cascade(frame, n, margin) end

  local left = anchored(rect(x, y, w - m, h), "tl", m, m)
  local right = anchored(rect(x + m, y, w - m, h), "tr", m, m)
  local topRight = anchored(rect(x + m, y, w - m, h - m), "tr", m, m)
  local bottomRight = anchored(rect(x + m, y + m, w - m, h - m), "br", m, m)
  if n == 2 then return { left, right } end
  if n == 3 then return { left, topRight, bottomRight } end
  local topLeft = anchored(rect(x, y, w - m, h - m), "tl", m, m)
  local bottomLeft = anchored(rect(x, y + m, w - m, h - m), "bl", m, m)
  return { topLeft, topRight, bottomLeft, bottomRight }
end

local function cost(a, b)
  return math.abs(a.x - b.x) + math.abs(a.y - b.y)
    + math.abs(a.x + a.w - b.x - b.w) + math.abs(a.y + a.h - b.y - b.h)
end

local function exactAssign(costs, n)
  local best, bestTotal = nil, math.huge
  local current, used = {}, {}
  local function search(i, total)
    if total >= bestTotal then return end
    if i > n then
      -- Copy by hand: Hammerspoon (Lua 5.4) has no global unpack.
      best, bestTotal = {}, total
      for k = 1, n do best[k] = current[k] end
      return
    end
    for s = 1, n do
      if not used[s] then
        used[s], current[i] = true, s
        search(i + 1, total + costs[i][s])
        used[s] = false
      end
    end
  end
  search(1, 0)
  return best
end

-- Greedily matches the cheapest (window, slot) pairs among `windows`, skipping
-- slots already in `mapping`.
local function greedyAssign(costs, n, windows, mapping)
  local takenSlot = {}
  for _, s in pairs(mapping) do takenSlot[s] = true end
  local candidates = {}
  for _, i in ipairs(windows) do
    for s = 1, n do
      if not takenSlot[s] then candidates[#candidates + 1] = { i = i, s = s, c = costs[i][s] } end
    end
  end
  table.sort(candidates, function(a, b)
    if a.c ~= b.c then return a.c < b.c end
    if a.i ~= b.i then return a.i < b.i end
    return a.s < b.s
  end)
  for _, p in ipairs(candidates) do
    if mapping[p.i] == nil and not takenSlot[p.s] then
      mapping[p.i], takenSlot[p.s] = p.s, true
    end
  end
end

-- Returns mapping[windowIndex] = slotIndex minimising edge movement, with
-- windows flagged in `existing` (already laid out before) taking strict priority
-- over newcomers: first their movement is minimised, then the newcomers'.
-- Exact for small counts (the common case); two-phase greedy beyond that.
function M.assign(frames, slots, existing)
  local n = #frames
  assert(n == #slots, "assign needs one slot per window")
  existing = existing or {}
  local costs = {}
  for i = 1, n do
    costs[i] = {}
    for s = 1, n do costs[i][s] = cost(frames[i], slots[s]) end
  end

  if n <= 8 then
    -- Scale existing windows' costs above any possible newcomer total so the
    -- single objective is lexicographic (existing first, then newcomers).
    local newcomerBound = 1
    for i = 1, n do
      if not existing[i] then
        for s = 1, n do newcomerBound = newcomerBound + costs[i][s] end
      end
    end
    local weighted = {}
    for i = 1, n do
      weighted[i] = {}
      for s = 1, n do
        weighted[i][s] = existing[i] and costs[i][s] * newcomerBound or costs[i][s]
      end
    end
    return exactAssign(weighted, n)
  end

  local olds, news = {}, {}
  for i = 1, n do
    if existing[i] then olds[#olds + 1] = i else news[#news + 1] = i end
  end
  local mapping = {}
  greedyAssign(costs, n, olds, mapping)
  greedyAssign(costs, n, news, mapping)
  return mapping
end

-- Where a w by h window goes inside `slot`: pinned to the slot's anchor corner,
-- so a window the app made smaller than requested (iTerm2 snaps to its
-- character grid) still covers the slot's whole exclusive region.
function M.place(slot, w, h)
  local right, bottom = slot.anchor:sub(2, 2) == "r", slot.anchor:sub(1, 1) == "b"
  return rect(right and slot.x + slot.w - w or slot.x, bottom and slot.y + slot.h - h or slot.y, w, h)
end

local function inside(inner, outer)
  return inner.x >= outer.x and inner.y >= outer.y
    and inner.x + inner.w <= outer.x + outer.w
    and inner.y + inner.h <= outer.y + outer.h
end

-- True when frame lies inside slot, covers its exclusive region, and is at most
-- `tolerance` smaller per axis. If every window fits its slot, each one owns its
-- slot's exclusive region (other windows stay inside their own slots, which do
-- not overlap it), so it stays clickable whatever the z-order is. `tolerance`
-- only decides how close to full size is good enough, not clickability.
function M.fits(frame, slot, tolerance)
  return inside(frame, slot) and inside(slot.exclusive, frame)
    and slot.w - frame.w <= tolerance and slot.h - frame.h <= tolerance
end

local function contains(r, x, y)
  return x > r.x and x < r.x + r.w and y > r.y and y < r.y + r.h
end

-- Indices of rects that every point of is covered by some other rect (checked
-- on the grid formed by all rect edges, so it is exact for axis-aligned rects).
function M.coveredWindows(rects)
  local xs, ys = {}, {}
  for _, r in ipairs(rects) do
    xs[#xs + 1], xs[#xs + 2] = r.x, r.x + r.w
    ys[#ys + 1], ys[#ys + 2] = r.y, r.y + r.h
  end
  table.sort(xs)
  table.sort(ys)
  local owns = {}
  for i = 1, #xs - 1 do
    for j = 1, #ys - 1 do
      if xs[i + 1] > xs[i] and ys[j + 1] > ys[j] then
        local cx, cy = (xs[i] + xs[i + 1]) / 2, (ys[j] + ys[j + 1]) / 2
        local owner, count = nil, 0
        for k, r in ipairs(rects) do
          if contains(r, cx, cy) then owner, count = k, count + 1 end
        end
        if count == 1 then owns[owner] = true end
      end
    end
  end
  local covered = {}
  for k = 1, #rects do
    if not owns[k] then covered[#covered + 1] = k end
  end
  return covered
end

return M
