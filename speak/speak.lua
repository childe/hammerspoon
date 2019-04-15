local s = hs.speech.new("samantha.premium")

hs.hotkey.bind({"cmd", "alt", "ctrl"}, "SPACE", function()
  local c = hs.pasteboard.getContents()
  if not s:isSpeaking() then
    s:speak(c)
  else
    s:stop()
  end
end)
