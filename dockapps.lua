appChooser = hs.chooser.new(function (choice)
  if choice then
    choice.win:focus()
  end
end)

local function getWindows()
  local windows = {}

  for i, win in ipairs(hs.window.allWindows()) do
    local item = {}
    item.text = win:title()
    item.win = win
    table.insert(windows, 1, item)
  end
  return windows
end

function showWindowList()
  local windows = getWindows()
  print(#windows, 'windows')
  appChooser:choices(windows)
  appChooser:query(nil)
  appChooser:show()
end

-- thanks to philsnow @ https://stackoverflow.com/questions/77378977/hammerspoon-bind-cmd-shift-without-any-other-key
function same_keys(t1, t2)
   return _same_keys_oneway(t1, t2) and _same_keys_oneway(t2, t1)
end

function _same_keys_oneway(t1, t2)
   for k, _ in pairs(t1) do
      local found = false
      for j, _ in pairs(t2) do
         if k == j then found = true end
      end
      if found == false then return false end
   end
   return true
end

etap_last_flags = {}
etap = hs.eventtap.new(
   {
      hs.eventtap.event.types.flagsChanged,
   },
   function(ev)
      local flags = ev:getFlags()

      if same_keys(flags, {cmd = true, ctrl = true}) then
         if (same_keys(etap_last_flags, {cmd = true}) or
             same_keys(etap_last_flags, {ctrl = true})) then
              showWindowList()
         end
      end

      etap_last_flags = flags
   end
):start()
