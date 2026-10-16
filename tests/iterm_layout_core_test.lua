package.path = "./?.lua;" .. package.path
-- Hammerspoon runs Lua 5.4: hide Lua 5.1-only globals that luajit still provides.
unpack, setfenv, getfenv, loadstring = nil, nil, nil, nil

local core = require("iterm_layout_core")

local function assertEqual(actual, expected, message)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
  end
end

local function assertTrue(value, message)
  if not value then error(message, 2) end
end

local function contains(rect, x, y)
  return x > rect.x and x < rect.x + rect.w and y > rect.y and y < rect.y + rect.h
end

-- Independent of the implementation: compress all rectangle edges into a grid
-- and look for a cell owned by rect `index` alone, at least minSize on each side.
local function exclusiveArea(rects, index)
  local xs, ys = {}, {}
  for _, r in ipairs(rects) do
    xs[#xs + 1] = r.x; xs[#xs + 1] = r.x + r.w
    ys[#ys + 1] = r.y; ys[#ys + 1] = r.y + r.h
  end
  table.sort(xs); table.sort(ys)
  local best = 0
  for i = 1, #xs - 1 do
    for j = 1, #ys - 1 do
      local w, h = xs[i + 1] - xs[i], ys[j + 1] - ys[j]
      if w > 0 and h > 0 then
        local cx, cy = xs[i] + w / 2, ys[j] + h / 2
        if contains(rects[index], cx, cy) then
          local owned = true
          for k, other in ipairs(rects) do
            if k ~= index and contains(other, cx, cy) then owned = false break end
          end
          if owned then best = math.max(best, math.min(w, h)) end
        end
      end
    end
  end
  return best
end

local screen = { x = 0, y = 25, w = 1728, h = 1080 }
local margin = 60

local function insideScreen(rect)
  return rect.x >= screen.x and rect.y >= screen.y
    and rect.x + rect.w <= screen.x + screen.w
    and rect.y + rect.h <= screen.y + screen.h
end

local function testEveryWindowKeepsClickableArea()
  for n = 1, 9 do
    local slots = core.slots(screen, n, margin)
    assertEqual(#slots, n, n .. " windows get " .. n .. " slots")
    for i, slot in ipairs(slots) do
      assertTrue(insideScreen(slot), string.format("n=%d slot %d stays on screen", n, i))
      if n > 1 then
        assertTrue(exclusiveArea(slots, i) >= margin,
          string.format("n=%d slot %d has an exclusive %dpx area", n, i, margin))
      end
    end
  end
end

local function testWindowsAreAsLargeAsPossible()
  local one = core.slots(screen, 1, margin)
  assertEqual(one[1].w * one[1].h, screen.w * screen.h, "single window fills the screen")

  for _, slot in ipairs(core.slots(screen, 2, margin)) do
    assertEqual(slot.w, screen.w - margin, "two windows lose only one margin of width")
    assertEqual(slot.h, screen.h, "two windows keep full height")
  end

  for n = 3, 4 do
    for _, slot in ipairs(core.slots(screen, n, margin)) do
      assertTrue(slot.w >= screen.w - margin and slot.h >= screen.h - margin,
        n .. " windows lose at most one margin per axis")
    end
  end
end

local function testLayoutsShareSlotsAcrossCounts()
  local function key(r) return string.format("%d,%d,%d,%d", r.x, r.y, r.w, r.h) end
  local function shared(a, b)
    local set, count = {}, 0
    for _, r in ipairs(a) do set[key(r)] = true end
    for _, r in ipairs(b) do if set[key(r)] then count = count + 1 end end
    return count
  end
  assertEqual(shared(core.slots(screen, 2, margin), core.slots(screen, 3, margin)), 1,
    "2 -> 3 keeps one window untouched")
  assertEqual(shared(core.slots(screen, 3, margin), core.slots(screen, 4, margin)), 2,
    "3 -> 4 keeps two windows untouched")
end

local function testCascadeShrinksStepOnSmallScreens()
  local small = { x = 0, y = 0, w = 400, h = 300 }
  local slots = core.slots(small, 9, margin)
  for i, slot in ipairs(slots) do
    assertTrue(slot.w >= small.w / 2 and slot.h >= small.h / 2,
      "slot " .. i .. " keeps at least half the screen")
    assertTrue(exclusiveArea(slots, i) > 0, "slot " .. i .. " stays clickable")
  end
end

local function testAssignmentMinimisesMovement()
  local three = core.slots(screen, 3, margin)
  local four = core.slots(screen, 4, margin)

  local current = { three[3], three[1], three[2] }
  local mapping = core.assign(current, three)
  assertEqual(mapping[1], 3, "window already in slot 3 stays")
  assertEqual(mapping[2], 1, "window already in slot 1 stays")
  assertEqual(mapping[3], 2, "window already in slot 2 stays")

  -- Removing a window: the two survivors pick the nearest 2-window slots.
  local two = core.slots(screen, 2, margin)
  mapping = core.assign({ three[1], three[2] }, two)
  assertEqual(mapping[1], 1, "left window stays left")
  assertEqual(mapping[2], 2, "right window stays right")

  -- Adding a window: existing ones keep their slots, newcomer gets the free one.
  local newcomer = { x = 300, y = 300, w = 500, h = 400 }
  mapping = core.assign({ four[1], four[2], four[3], newcomer }, four)
  assertEqual(mapping[1], 1, "slot 1 untouched")
  assertEqual(mapping[2], 2, "slot 2 untouched")
  assertEqual(mapping[3], 3, "slot 3 untouched")
  assertEqual(mapping[4], 4, "newcomer takes remaining slot")

  local seen = {}
  local many = core.slots(screen, 10, margin)
  local frames = {}
  for i = #many, 1, -1 do frames[#frames + 1] = many[i] end
  mapping = core.assign(frames, many)
  for i, slotIndex in ipairs(mapping) do
    assertTrue(not seen[slotIndex], "large assignment never reuses a slot")
    seen[slotIndex] = true
    assertEqual(slotIndex, #many - i + 1, "large assignment keeps exact matches")
  end
end

local function testExistingWindowsOutrankNewcomers()
  local three = core.slots(screen, 3, margin)
  local four = core.slots(screen, 4, margin)
  -- The newcomer opens exactly on top of an existing window's reusable slot.
  local frames = { three[1], three[2], three[3], three[2] }
  local mapping = core.assign(frames, four, { true, true, true, false })
  assertEqual(mapping[2], 2, "existing top-right window keeps its slot")
  assertEqual(mapping[3], 4, "existing bottom-right window keeps its slot")
  assertEqual(mapping[4] == 1 or mapping[4] == 3, true, "newcomer takes a left slot")
end

local function testDegenerateInputsAreRejected()
  assertEqual(core.slots({ x = 0, y = 0, w = 8, h = 8 }, 9, margin), nil, "tiny screen with many windows")
  assertEqual(core.slots({ x = 0, y = 0, w = 400, h = 300 }, 302, margin), nil, "too many windows")
  assertEqual(core.slots({ x = 0, y = 0, w = 1, h = 1 }, 2, margin), nil, "screen too small for a margin")
  assertEqual(#core.slots(screen, 0, margin), 0, "no windows, no slots")
  assertEqual(pcall(core.slots, screen, 3, 0), false, "margin must be positive")
end

local tolerance = 40

-- Every slot's exclusive region lies inside it and outside every other slot.
local function testExclusiveRegionsAreDisjoint()
  for n = 1, 9 do
    local slots = core.slots(screen, n, margin)
    for i, slot in ipairs(slots) do
      local e = slot.exclusive
      assertTrue(e.w >= 1 and e.h >= 1, "exclusive region is not empty")
      assertTrue(e.x >= slot.x and e.y >= slot.y and e.x + e.w <= slot.x + slot.w
        and e.y + e.h <= slot.y + slot.h, "exclusive region lies inside its slot")
      for k, other in ipairs(slots) do
        if k ~= i then
          local overlap = e.x < other.x + other.w and other.x < e.x + e.w
            and e.y < other.y + other.h and other.y < e.y + e.h
          assertTrue(not overlap, string.format("n=%d exclusive %d avoids slot %d", n, i, k))
        end
      end
    end
  end
end

-- iTerm2 may snap a window smaller than requested, by more than the cascade step
-- on small screens. Pinned to its anchor, every window must stay clickable, and
-- any frames `fits` accepts (wherever they sit in the slot) must too.
local function testFittingFramesStayClickable()
  local seed = 12345
  local function rand(k)
    seed = (seed * 1103515245 + 12345) % 2147483648
    return seed % k
  end
  local screens = { screen, { x = 0, y = 0, w = 400, h = 300 }, { x = 0, y = 0, w = 120, h = 90 } }
  for _, frame in ipairs(screens) do
    for n = 2, 9 do
      local slots = core.slots(frame, n, margin)
      if slots then
        for _ = 1, 200 do
          local pinned, loose = {}, {}
          for i, slot in ipairs(slots) do
            -- Never smaller than the exclusive region itself.
            local maxX = math.min(tolerance, slot.w - slot.exclusive.w)
            local maxY = math.min(tolerance, slot.h - slot.exclusive.h)
            local w, h = slot.w - rand(maxX + 1), slot.h - rand(maxY + 1)
            pinned[i] = core.place(slot, w, h)
            assertTrue(core.fits(pinned[i], slot, tolerance), "pinned snapped window fits")
            local candidate = { x = slot.x + rand(slot.w - w + 1), y = slot.y + rand(slot.h - h + 1), w = w, h = h }
            loose[i] = core.fits(candidate, slot, tolerance) and candidate or pinned[i]
          end
          local label = string.format("%dx%d n=%d", frame.w, frame.h, n)
          assertEqual(#core.coveredWindows(pinned), 0, label .. ": pinned windows all clickable")
          assertEqual(#core.coveredWindows(loose), 0, label .. ": fitting windows all clickable")
          for i = 1, n do
            assertTrue(exclusiveArea(loose, i) >= 1, label .. " window " .. i .. " has an exclusive area (independent check)")
          end
        end
      end
    end
  end

  -- Reviewer counterexample: clamped cascade steps (25x18) with a 25x18 shrink.
  local small = core.slots({ x = 0, y = 0, w = 400, h = 300 }, 9, margin)
  assertEqual(core.fits({ x = 25, y = 18, w = 175, h = 138 }, small[2], tolerance), false,
    "top-left pinned snapped window leaves the exclusive corner")
  local p = core.place(small[2], 175, 138)
  assertEqual(p.x, 50, "snapped cascade window pinned to its top-right corner")
  assertTrue(core.fits(p, small[2], tolerance), "pinned snapped window fits")

  local right = core.slots(screen, 2, margin)[2]
  p = core.place(right, right.w - 13, right.h)
  assertEqual(p.x + p.w, screen.x + screen.w, "slot on the right edge stays flush right")
  assertEqual(core.fits({ x = 0, y = 0, w = 10, h = 10 }, right, tolerance), false, "far frame does not fit")
  assertEqual(core.fits(core.place(right, right.w - 100, right.h), right, tolerance), false,
    "much smaller window is not good enough")

  local covered = core.coveredWindows({ { x = 0, y = 0, w = 100, h = 100 }, { x = 10, y = 10, w = 50, h = 50 } })
  assertEqual(#covered == 1 and covered[1] == 2, true, "coveredWindows finds the hidden window")
end

-- Greedy branch (n > 8): existing windows are matched before newcomers.
local function testGreedyKeepsExistingWindows()
  local eight = core.slots(screen, 8, margin)
  local nine = core.slots(screen, 9, margin)
  local frames, existing = {}, {}
  for i, slot in ipairs(eight) do
    frames[i] = { x = slot.x, y = slot.y, w = slot.w - 7, h = slot.h - 7 }
    existing[i] = true
  end
  frames[9] = nine[1]
  local mapping = core.assign(frames, nine, existing)
  for i = 1, 8 do assertEqual(mapping[i], i, "existing window " .. i .. " keeps its slot index") end
  assertEqual(mapping[9], 9, "newcomer takes the free slot")
end

testEveryWindowKeepsClickableArea()
testExistingWindowsOutrankNewcomers()
testDegenerateInputsAreRejected()
testExclusiveRegionsAreDisjoint()
testFittingFramesStayClickable()
testGreedyKeepsExistingWindows()
testWindowsAreAsLargeAsPossible()
testLayoutsShareSlotsAcrossCounts()
testCascadeShrinksStepOnSmallScreens()
testAssignmentMinimisesMovement()
print("iterm_layout_core tests passed")
