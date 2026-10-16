-- API key 存在 macOS Keychain，不进 git。首次设置：
--   security add-generic-password -a "$USER" -s hammerspoon-weather -w '<your key>'
local function loadApiKey()
   local out, ok = hs.execute('security find-generic-password -s hammerspoon-weather -w')
   if not ok then return nil end
   return (out:gsub('%s+$', ''))
end

local apiKey = loadApiKey()
local urlApi = apiKey and ('https://api.weatherapi.com/v1/current.json?key=' .. apiKey .. '&q=Shanghai&aqi=no&lang=zh')
local menubar = hs.menubar.new()
local menuData = {}

-- weatherapi.com condition code -> emoji
local emojiByCode = {}
local function mark(emoji, codes) for _, c in ipairs(codes) do emojiByCode[c] = emoji end end
mark('☀️', {1000})
mark('⛅️', {1003})
mark('☁️', {1006, 1009})
mark('🌫', {1030, 1135, 1147})
mark('⚡️', {1087, 1273, 1276, 1279, 1282})
mark('❄️', {1066, 1114, 1117, 1210, 1213, 1216, 1219, 1222, 1225, 1255, 1258})
mark('🌨', {1069, 1072, 1168, 1171, 1198, 1201, 1204, 1207, 1237, 1249, 1252, 1261, 1264})

local function weaEmoji(code)
   return emojiByCode[code] or '🌧' -- 其余都是各类雨
end

function updateMenubar()
	menubar:setTooltip("Weather Info")
    menubar:setMenu(menuData)
end

function getWeather()
   if not urlApi then
      print('weather: API key not found in Keychain (service hammerspoon-weather)')
      menubar:setTitle('🔑')
      return
   end
   code, body, htable = hs.http.get(urlApi, nil)
   if code ~= 200 then
      print('get weather error:'..code)
      return
   end
   rawjson = hs.json.decode(body)
   local city = rawjson.location.name
   local cur = rawjson.current
   local emoji = weaEmoji(cur.condition.code)
   menubar:setTitle(emoji)
   titlestr = string.format("%s %s %s 🌡️%s°C (体感%s°C) 💧%s%% 🌬%s %skm/h",
      city, emoji, cur.condition.text, cur.temp_c, cur.feelslike_c, cur.humidity, cur.wind_dir, cur.wind_kph)
   print(titlestr)
   menuData = {
      { title = titlestr, fn = function() getWeather() end },
      { title = '-' },
      { title = '更新于 ' .. cur.last_updated },
   }
   updateMenubar()
end

menubar:setTitle('⌛')
getWeather()
updateMenubar()
hs.timer.doEvery(3600, getWeather)
