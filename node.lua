-- AeroShields Radar Node
-- bottom: player_detector | any side: ender modem

local PROTOCOL = "aeroshields_radar"
local RADIUS   = 100

local detector = peripheral.find("player_detector")
if not detector then error("No player_detector found") end

-- Open whichever modem is attached
local modemSide = nil
for _, side in ipairs({"top","bottom","left","right","front","back"}) do
    if peripheral.getType(side) == "modem" then
        modemSide = side
        break
    end
end
if not modemSide then error("No modem found") end
rednet.open(modemSide)

-- GPS
term.write("GPS... ")
local myX, myY, myZ = gps.locate(5)
if not myX then error("No GPS signal") end
print("OK")

local nodeId = string.format("%.0f,%.0f,%.0f", myX, myY, myZ)
print("Node online: " .. nodeId)

while true do
    local ok, names = pcall(detector.getPlayersInRange, RADIUS)
    local players = {}
    if ok and type(names) == "table" then
        for _, name in ipairs(names) do
            local info = detector.getPlayer(name)
            if info then
                players[name] = { x = info.x, y = info.y, z = info.z }
            end
        end
    end

    rednet.broadcast({
        type    = "radar_data",
        nodeId  = nodeId,
        players = players,
    }, PROTOCOL)

    sleep(1)
end
