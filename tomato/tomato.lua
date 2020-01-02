local msg = "take a break"
local duration = ""
local yesIsee = false
local breakTime = 25*60
local uuid = ''

function alertBreak()
    print(msg)
    uuid = hs.alert.show(msg, duration)
end


hs.hotkey.bind({"cmd", "alt", "ctrl"}, "0", function()
    print(string.format("close `%s`",uuid))
    hs.alert.closeSpecific(uuid)
    hs.timer.doAfter(breakTime, alertBreak)
end)

hs.timer.doAfter(breakTime, alertBreak)
