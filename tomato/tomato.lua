local msg = "have a break"
local duration = 2
local yesIsee = false
local breakTime = 30*60

function alertBreak(i, total)
    print(msg)

    if i >= total then
        return
    end

    if yesIsee then
        yesIsee = false
        return
    end

    hs.alert.show(msg, duration)
    hs.timer.doAfter(duration+1, function() alertBreak(i+1, total) end)
end

function sparkBreak()
    alertBreak(1, breakTime/(duration+1))
end

hs.timer.doEvery(breakTime, sparkBreak)

hs.hotkey.bind({"cmd", "alt", "ctrl"}, "0", function()
    if yesIsee then
        yesIsee = false
        print("tomato show")
    else
        yesIsee = true
        print("tomato hide")
    end
end)
