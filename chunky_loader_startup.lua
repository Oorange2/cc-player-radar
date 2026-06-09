-- Chunk loader auto-updater & launcher
local URL  = "https://raw.githubusercontent.com/Oorange2/cc-player-radar/main/chunky_loader.lua"
local FILE = "chunky_loader"

local function readLocal()
    if not fs.exists(FILE) then return nil end
    local f = fs.open(FILE, "r")
    local c = f.readAll() f.close() return c
end

local ok, res = pcall(http.get, URL)
if ok and res then
    local remote = res.readAll() res.close()
    if remote ~= readLocal() then
        local f = fs.open(FILE, "w") f.write(remote) f.close()
        print("Updated! Rebooting...") sleep(1) os.reboot()
    end
else
    print("No internet, using local copy")
end

shell.run(FILE)
