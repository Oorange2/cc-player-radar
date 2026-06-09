-- Chunk loader turtle — sits still, keeps this chunk loaded.

local startTime = os.epoch("utc")

local function uptime()
    local s = math.floor((os.epoch("utc") - startTime) / 1000)
    return string.format("%02d:%02d:%02d", math.floor(s/3600), math.floor((s%3600)/60), s%60)
end

term.clear()
term.setCursorPos(1,1)
term.setTextColor(colors.yellow) term.write("=== Chunk Loader ===")

local x, y, z = gps.locate(3)
term.setCursorPos(1,2) term.setTextColor(colors.white)
if x then term.write(string.format("Pos: %d, %d, %d", x, y, z))
else term.write("Pos: no GPS") end

term.setCursorPos(1,3) term.setTextColor(colors.lime) term.write("Status: ACTIVE")
term.setCursorPos(1,5) term.setTextColor(colors.gray) term.write("Ctrl+T to stop")

while true do
    term.setCursorPos(1,4) term.setTextColor(colors.white)
    term.write("Uptime: " .. uptime() .. "   ")
    os.sleep(1)
end
