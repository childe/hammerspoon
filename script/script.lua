local scriptsPath = "/Users/liujia/.hammerspoon/scripts/enabled/"

function runScripts()
  local iterFn, dirObj = hs.fs.dir(scriptsPath)
  if iterFn then
    for file in iterFn, dirObj do
      if string.match(file, ".*sh$") then
          print(file)
          local fullPath = scriptsPath .. file
          local output, status, typ, rc = hs.execute(scriptsPath .. file)
          print(output)
          print(status)
          print(typ)
          print(rc)

          if rc == 0 then
              hs.alert.show(output)
          end
      end
    end
  else
    print(string.format("The following error occurred: %s", dirObj))
  end
end

hs.timer.doEvery(60, runScripts)
