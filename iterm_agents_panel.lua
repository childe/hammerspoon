-- Menubar 🤖 that shows a panel of the iTerm2 agent sessions at the top right of the screen under
-- the mouse. The panel floats above other windows until closed: left click 🤖 or tap ⌃⌥
-- (press both, release, nothing else) to toggle it. Right click or ctrl-click 🤖 opens the old tab menu instead.
-- Clicking a row focuses that session and leaves the panel open.
-- The list refreshes every refreshInterval seconds while the panel is open, never otherwise.
local core = require("iterm_agents_core")
local agents = require("iterm_agents")

local M = {}
M.width = 360
M.margin = 8
M.refreshInterval = 2
M.chord = { ctrl = true, alt = true }

local html = [[
<!doctype html>
<html><head><meta charset="utf-8">
<style>
:root {
  --bg: rgba(246, 244, 239, 0.94); --fg: #1d1d1f; --dim: #86868b; --line: rgba(0, 0, 0, 0.08);
  --hover: rgba(0, 0, 0, 0.06); --run: #30b158; --wait: #ff9500; --wait-bg: rgba(255, 149, 0, 0.10);
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: rgba(38, 38, 40, 0.94); --fg: #f5f5f7; --dim: #98989d; --line: rgba(255, 255, 255, 0.10);
    --hover: rgba(255, 255, 255, 0.08); --run: #32d74b; --wait: #ff9f0a; --wait-bg: rgba(255, 159, 10, 0.14);
  }
}
html, body { margin: 0; padding: 0; background: transparent; overflow: hidden; }
body { font: 13px -apple-system, "PingFang SC", sans-serif; color: var(--fg); -webkit-user-select: none; cursor: default; }
#card { background: var(--bg); border-radius: 14px; border: 0.5px solid var(--line); padding: 10px 8px 8px; }
header { display: flex; align-items: baseline; justify-content: space-between; padding: 0 8px 8px; }
h1 { font-size: 14px; font-weight: 600; margin: 0; }
#summary { color: var(--dim); font-size: 12px; }
.dir { color: var(--dim); font-size: 11px; padding: 8px 8px 3px; border-top: 0.5px solid var(--line);
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis; direction: rtl; text-align: left; }
.row { display: flex; align-items: center; gap: 8px; padding: 6px 8px; border-radius: 8px; }
.row:hover { background: var(--hover); }
.row.w { background: var(--wait-bg); }
.row.w:hover { background: var(--hover); }
.dot { flex: none; width: 8px; height: 8px; border-radius: 50%; box-sizing: border-box; }
.r .dot { background: var(--run); animation: pulse 1.2s ease-in-out infinite; }
.w .dot { border: 1.5px solid var(--wait); }
@keyframes pulse { 50% { opacity: 0.35; } }
.agent { flex: none; width: 44px; color: var(--dim); font-size: 12px; }
.title { flex: 1; min-width: 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.w .title { font-weight: 500; }
.age { flex: none; color: var(--dim); font-size: 12px; font-variant-numeric: tabular-nums; }
.empty { color: var(--dim); padding: 12px 8px 6px; text-align: center; }
</style></head>
<body><div id="card">
<header><h1>Agents</h1><span id="summary"></span></header>
<div id="list"></div>
</div>
<script>
function post(msg) { window.webkit.messageHandlers.agents.postMessage(msg); }
function el(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined) e.textContent = text;
  return e;
}
function render(data) {
  const list = document.getElementById("list");
  list.replaceChildren();
  let running = 0, waiting = 0;
  for (const g of data.groups || []) {
    const dir = el("div", "dir");
    // direction: rtl ellipsizes the start of long paths; the bdi keeps the path itself left to right.
    dir.appendChild(el("bdi", null, g.dir || "(未知目录)"));
    list.appendChild(dir);
    for (const r of g.rows) {
      if (r.state === "r") running++; else waiting++;
      const row = el("div", "row " + r.state);
      row.title = r.title;
      row.append(el("span", "dot"), el("span", "agent", r.agent), el("span", "title", r.title), el("span", "age", r.age));
      row.addEventListener("click", () => post({ action: "focus", id: r.id }));
      list.appendChild(row);
    }
  }
  if (data.message) list.appendChild(el("div", "empty", data.message));
  document.getElementById("summary").textContent = data.message ? "" : running + " 在跑 · " + waiting + " 在等";
  post({ action: "height", height: document.getElementById("card").offsetHeight });
}
</script>
</body></html>
]]

local panel, menubar, popup, chordWatcher, clickWatcher, refreshTimer
local ready, pendingData, busy, screen
-- Work deferred out of an event tap callback; a timer nothing references can be collected before it fires.
local deferred

local function defer(fn)
  deferred = hs.timer.doAfter(0, fn)
end

-- The screen picked when the panel opened; the panel stays there while the mouse moves on.
local function screenFrame()
  return (screen or hs.mouse.getCurrentScreen() or hs.screen.mainScreen()):frame()
end

local function place(height)
  local f = screenFrame()
  height = math.min(height, f.h - 2 * M.margin)
  panel:frame({ x = f.x + f.w - M.width - M.margin, y = f.y + M.margin, w = M.width, h = height })
end

local function render(data)
  if not ready then
    pendingData = data
    return
  end
  panel:evaluateJavaScript("render(" .. hs.json.encode(data) .. ")")
end

function M.isShown()
  return panel ~= nil and panel:isVisible()
end

-- Skips a refresh while the previous one is still listing, unless that one has hung for 10 seconds.
local function refresh()
  if busy and os.time() - busy < 10 then return end
  if not hs.application.get("iTerm2") then return render({ message = "iTerm2 未运行" }) end
  local started = os.time()
  busy = started
  agents.sessionsAsync(function(sessions)
    if busy == started then busy = nil end
    if not M.isShown() then return end
    local groups = core.panelGroups(sessions, os.getenv("HOME"))
    render({ groups = groups, message = #groups == 0 and "没有 agent" or nil })
  end)
end

function M.hide()
  if refreshTimer then refreshTimer:stop() end
  refreshTimer = nil
  if panel then panel:hide() end
end

local function onMessage(msg)
  local body = msg.body or {}
  if body.action == "height" then
    place(tonumber(body.height) or 100)
  elseif body.action == "focus" then
    if not agents.focus(tostring(body.id)) then hs.alert.show("iTerm tab 已关闭") end
  end
end

local function create()
  local content = hs.webview.usercontent.new("agents")
  content:setCallback(onMessage)
  local f = screenFrame()
  panel = hs.webview.new({ x = f.x + f.w - M.width - M.margin, y = f.y + M.margin, w = M.width, h = 100 },
    { developerExtrasEnabled = false }, content)
  panel:windowStyle({ "borderless", "nonactivating" })
  panel:transparent(true)
  panel:shadow(true)
  panel:level(hs.drawing.windowLevels.floating)
  local b = hs.drawing.windowBehaviors
  panel:behavior(b.canJoinAllSpaces + b.stationary + b.fullScreenAuxiliary)
  panel:allowTextEntry(false)
  panel:navigationCallback(function(action)
    if action == "didFinishNavigation" then
      ready = true
      if pendingData then
        render(pendingData)
        pendingData = nil
      end
    end
  end)
  panel:html(html)
end

function M.show()
  screen = hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
  if not panel then create() end
  place(panel:frame().h)
  panel:show()
  refresh()
  if refreshTimer then refreshTimer:stop() end
  refreshTimer = hs.timer.doEvery(M.refreshInterval, refresh)
end

function M.toggle()
  if M.isShown() then M.hide() else M.show() end
end

local function showMenu(point)
  popup:setMenu(agents.menu())
  popup:popupMenu(point or hs.mouse.absolutePosition())
end

local function inside(point, frame)
  return frame ~= nil and point.x >= frame.x and point.x <= frame.x + frame.w
    and point.y >= frame.y and point.y <= frame.y + frame.h
end

local function screenAt(point)
  for _, s in ipairs(hs.screen.allScreens()) do
    if inside(point, s:fullFrame()) then return s end
  end
end

-- With several displays every menu bar shows 🤖, but menubar:frame() reports only the one it last
-- drew on, sometimes off every screen. Items keep the same distance from each screen's right edge,
-- so compare that distance on the clicked screen.
local function onIcon(point)
  local f = menubar:frame()
  local home = screenAt({ x = f.x + f.w / 2, y = f.y + f.h / 2 })
  local here = screenAt(point)
  if not (home and here) then return inside(point, f) end
  local hf, pf = home:fullFrame(), here:fullFrame()
  local x = pf.x + pf.w - (hf.x + hf.w - f.x)
  return inside(point, { x = x, y = pf.y + (f.y - hf.y), w = f.w, h = f.h })
end

menubar = hs.menubar.new()
if menubar then
  menubar:setTitle("🤖")
  menubar:setTooltip("iTerm2 agents（单按 ⌃⌥ 开关，右键：所有 tab）")
  menubar:setClickCallback(function(mods)
    if mods.ctrl then showMenu() else M.toggle() end
  end)
  popup = hs.menubar.new(false)

  -- A status item with a click callback never sees right clicks, so catch them here.
  clickWatcher = hs.eventtap.new({ hs.eventtap.event.types.rightMouseDown }, function(event)
    local point = event:location()
    if not onIcon(point) then return false end
    defer(function() showMenu(point) end)
    return true
  end)
  clickWatcher:start()
end

-- A key press or mouse click while ⌃⌥ is held belongs to another shortcut and cancels the tap.
local chord = core.chordTap(M.chord)
local types = hs.eventtap.event.types
chordWatcher = hs.eventtap.new({ types.flagsChanged, types.keyDown, types.leftMouseDown, types.rightMouseDown },
  function(event)
    if event:getType() ~= types.flagsChanged then
      chord:key()
    elseif chord:flags(event:getFlags()) then
      defer(M.toggle)
    end
    return false
  end)
chordWatcher:start()

M.menubar = menubar
M.clickWatcher = clickWatcher
M.chordWatcher = chordWatcher
_G.itermAgentsPanel = M -- keep the webview, menubar and event taps from being collected

return M
