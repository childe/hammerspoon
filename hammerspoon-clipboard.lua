clipboard = hs.chooser.new(function (choice)
  if choice then
    hs.pasteboard.setContents(choice.content)
    --hs.eventtap.keyStroke({ "cmd" }, "v")
  end
end)

local history = {}
function addHistoryFromPasteboard()
  local contentTypes = hs.pasteboard.contentTypes()

  local item = {}
  for index, uti in ipairs(contentTypes) do
    if uti == "public.utf8-plain-text" then
      local text = hs.pasteboard.readString()
      item.text = string.gsub(text, "[\r\n]+", " ")
      item.content = text;
      break
    end
  end

  local exist = false
  for _,v in pairs(history) do
      if v.text == item.text then
          exist = true
          break
      end
  end

  if exist then
  else
      table.insert(history, 1, item)
  end
end

local preChangeCount = hs.pasteboard.changeCount()
local watcher = hs.timer.new(1.0, function ()
     addHistoryFromPasteboard()
end)
watcher:start()

hs.hotkey.bind({ "cmd", "shift" }, "v", function ()
  clipboard:choices(history)
  clipboard:query(nil)
  clipboard:show()
end)
