appChooser = hs.chooser.new(function (choice)
  if choice then
    --print(choice.text)
    choice.win:focus()
  end
end)

-- 获取 Dock 中的应用程序列表
local function getWindows()
  local windows = hs.window.allWindows()

  local apps = {}
  for i, win in ipairs(windows) do
    local item = {}
    item.text = win:title()
    item.win = win
    table.insert(apps, 1, item)
  end
  return apps
end

-- 长按 opt 键时显示应用程序列表
hs.hotkey.bind({"cmd"}, "0", function()
  local windows = getWindows()
  print(#windows, 'windows')
  appChooser:choices(windows)
  appChooser:query(nil)
  appChooser:show()
end)
