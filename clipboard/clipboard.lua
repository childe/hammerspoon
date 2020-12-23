local last_change = hs.pasteboard.changeCount()
local pasteboard = require("hs.pasteboard") -- http://www.hammerspoon.org/docs/hs.pasteboard.html

clipboard = hs.chooser.new(function (choice)
  if choice then
    pasteboard.setContents(choice.content)
    --hs.eventtap.keyStroke({ "cmd" }, "v")
  end
end)

local history = {}

function initHistory()
    for line in io.lines("/Users/liujia/.hammerspoon/clipboard/init.txt") do
        print(line)
        local item = {}
        item.text = line
        item.content = line
        table.insert(history, 1, item)
    end
end


function addHistoryFromPasteboard()
    now = pasteboard.changeCount()
    --print(last_change)
    --print(now)
    local item = {}
    if (now <= last_change) then
        return
    end

    current_clipboard = pasteboard.getContents()
    -- asmagill requested this feature. It prevents the history from keeping items removed by password managers
    --print(current_clipboard)
    if (current_clipboard == nil) then
        return
    end

    if string.len(current_clipboard) > 100 then
        return
    end

    item.text = current_clipboard
    item.content = current_clipboard
    last_change = now

    for i,v in pairs(history) do
        --print(item.text)
        --print(v.text)
        --print("==")
        if v.text == item.text then
            table.remove(history, i)
            break
        end
    end
    --print(exist)

    table.insert(history, 1, item)
end

initHistory()

watcher = hs.timer.new(1.0, function ()
     addHistoryFromPasteboard()
end)
watcher:start()

hs.hotkey.bind({ "cmd", "shift" }, "v", function ()
  print(#history)
  clipboard:choices(history)
  clipboard:query(nil)
  clipboard:show()
end)
