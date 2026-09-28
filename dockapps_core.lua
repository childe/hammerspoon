local M = {}

local semanticFlags = { "cmd", "ctrl", "alt", "shift" }

function M.flagsEqual(actual, expected)
  actual = actual or {}
  expected = expected or {}

  for _, name in ipairs(semanticFlags) do
    if not not actual[name] ~= not not expected[name] then
      return false
    end
  end

  return true
end

function M.shouldOpen(previousFlags, currentFlags)
  return M.flagsEqual(previousFlags, { cmd = true })
    and M.flagsEqual(currentFlags, { cmd = true, ctrl = true })
end

local function displayTitle(record)
  local title = record.title
  if type(title) ~= "string" or title == "" then
    title = "Untitled"
  end

  if record.minimized then
    return "[Minimized] " .. title
  end
  if record.hidden then
    return "[Hidden] " .. title
  end
  return title
end

function M.buildChoices(records, currentPid)
  local choices = {}
  local seen = {}

  for _, record in ipairs(records or {}) do
    local validID = type(record.id) == "number"
    local validApp = type(record.appName) == "string" and record.appName ~= ""
    local inScope = currentPid == nil or record.pid == currentPid

    if validID and validApp and inScope and not seen[record.id] then
      seen[record.id] = true
      choices[#choices + 1] = {
        text = record.appName,
        subText = displayTitle(record),
        image = record.image,
        windowID = record.id,
      }
    end
  end

  return choices
end

return M
