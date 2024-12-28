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

hs.hotkey.bind({"cmd"}, "0", function()
  local windows = getWindows()
  print(#windows, 'windows')
  appChooser:choices(windows)
  appChooser:query(nil)
  appChooser:show()
end)
