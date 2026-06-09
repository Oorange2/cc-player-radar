-- Chunk loader auto-updater & launcher
local URL  = "https://raw.githubusercontent.com/Oorange2/cc-player-radar/main/chunky_loader.lua"
local FILE = "chunky_loader"


local ok, res = pcall(http.get, URL)
if ok and res then
    local remote = res.readAll() res.close()
    local f = fs.open(FILE, "w") f.write(remote) f.close()
    print("Pulled from GitHub.")
else
    print("GitHub unavailable, using local copy.")
end

if fs.exists(FILE) then
    shell.run(FILE)
else
    -- Fallback: run inline if chunky_loader was never downloaded
    local startTime = os.epoch("utc")
    local function uptime()
        local s = math.floor((os.epoch("utc") - startTime) / 1000)
        return string.format("%02d:%02d:%02d", math.floor(s/3600), math.floor((s%3600)/60), s%60)
    end
    term.clear() term.setCursorPos(1,1)
    term.setTextColor(colors.yellow) term.write("=== Chunk Loader ===")
    term.setCursorPos(1,2) term.setTextColor(colors.orange) term.write("(offline fallback)")
    term.setCursorPos(1,3) term.setTextColor(colors.lime) term.write("Status: ACTIVE")
    term.setCursorPos(1,5) term.setTextColor(colors.gray) term.write("Ctrl+T to stop")
    while true do
        term.setCursorPos(1,4) term.setTextColor(colors.white)
        term.write("Uptime: " .. uptime() .. "   ")
        os.sleep(1)
    end
end
