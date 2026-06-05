-- AeroShields Player Radar Hub v6
-- bottom: player_detector (local coverage) | left: 5x5 monitor | top: ender modem

local PROTOCOL       = "aeroshields_radar"
local DISPLAY_RADIUS = 500   -- blocks shown on radar map (covers all nodes)
local LOCAL_RADIUS   = 100   -- local detector range
local PLAYER_TIMEOUT = 3     -- seconds until a player is removed if nodes go quiet

local monitor = peripheral.wrap("left")
if not monitor then error("No monitor on left") end

local localDetector = peripheral.find("player_detector")

-- Open ender modem
local modemSide = nil
for _, side in ipairs({"top","bottom","left","right","front","back"}) do
    if peripheral.getType(side) == "modem" and side ~= "left" then
        modemSide = side
        break
    end
end
if not modemSide then error("No ender modem found") end
rednet.open(modemSide)

monitor.setTextScale(0.5)
local W, H   = monitor.getSize()
local CX, CY = math.floor(W / 2), math.floor(H / 2)
local SCALE  = math.min(CX, CY) - 2

local LOG_FILE    = "player_log.txt"
local sweepAngle  = 0
local SWEEP_STEP  = 0.28
local TRAIL_STEPS = 4

local baseX, baseY, baseZ
local hasGPS = false

-- allPlayers[name] = {x, y, z, lastSeen}
local allPlayers      = {}
local seenPlayers     = {}
local playerScreenPos = {}
local popup           = nil

local AUTHORIZED = {
    ["cypu001"]         = true,
    ["SirAlf1808"]      = true,
    ["ClothFisch"]      = true,
    ["OlsChan"]         = true,
    ["Ooranges"]        = true,
    ["Glikus"]          = true,
    ["Mechanoo"]        = true,
    ["Cedjy"]           = true,
    ["Quillowo"]        = true,
    ["Alecs0603"]       = true,
    ["Frigulus"]        = true,
    ["Hannah_Panda"]    = true,
    ["BeefBurgerrr"]    = true,
    ["ZwergNaseErik"]   = true,
    ["Vaedran"]         = true,
    ["ski11az"]         = true,
    ["Timmigamer06"]    = true,
    ["Lux_silver"]      = true,
    ["C0SMODEUS"]       = true,
    ["levitanbloop"]    = true,
    ["DrHarleySawyer_"] = true,
    ["That_Dang_Fox"]   = true,
}

-- ─── Helpers ────────────────────────────────────────────────────────────────

local function log(msg)
    local t = os.date("%Y-%m-%d %H:%M:%S")
    local f = fs.open(LOG_FILE, "a")
    f.writeLine("[" .. t .. "] " .. msg)
    f.close()
end

local function put(x, y, col, char)
    if x < 1 or x > W or y < 1 or y > H then return end
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(col)
    monitor.setCursorPos(x, y)
    monitor.write(char)
end

local function drawSweepLine(angle, col)
    for r = 1, math.max(W, H) do
        local px = CX + math.floor(math.cos(angle) * r)
        local py = CY + math.floor(math.sin(angle) * r * 0.5)
        if px < 1 or px > W or py < 1 or py > H then break end
        put(px, py, col, ".")
    end
end

local function drawPopup(name, data)
    local lines = { name }
    if data and hasGPS then
        local dx   = data.x - baseX
        local dy   = data.y - baseY
        local dz   = data.z - baseZ
        local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
        table.insert(lines, string.format("Dist: %.1f blk", dist))
        table.insert(lines, string.format("X: %.0f", data.x))
        table.insert(lines, string.format("Y: %.0f", data.y))
        table.insert(lines, string.format("Z: %.0f", data.z))
    else
        table.insert(lines, "No GPS data")
    end

    local bw = 2
    for _, l in ipairs(lines) do bw = math.max(bw, #l + 2) end
    local bh = #lines + 2
    local bx = math.max(1, math.min(W - bw, CX - math.floor(bw / 2)))
    local by = math.max(1, math.min(H - bh, CY - math.floor(bh / 2)))

    for row = by, by + bh - 1 do
        for col = bx, bx + bw - 1 do
            monitor.setBackgroundColor(colors.gray)
            monitor.setCursorPos(col, row)
            monitor.write(" ")
        end
    end
    monitor.setBackgroundColor(colors.gray)
    monitor.setTextColor(colors.white)
    monitor.setCursorPos(bx, by)
    monitor.write("+" .. string.rep("-", bw - 2) .. "+")
    monitor.setCursorPos(bx, by + bh - 1)
    monitor.write("+" .. string.rep("-", bw - 2) .. "+")
    for row = by + 1, by + bh - 2 do
        monitor.setCursorPos(bx, row)           monitor.write("|")
        monitor.setCursorPos(bx + bw - 1, row) monitor.write("|")
    end
    for i, line in ipairs(lines) do
        monitor.setBackgroundColor(colors.gray)
        monitor.setTextColor(i == 1 and colors.yellow or colors.white)
        monitor.setCursorPos(bx + 1, by + i)
        monitor.write(line)
    end
end

-- ─── GPS ────────────────────────────────────────────────────────────────────

term.write("GPS... ")
baseX, baseY, baseZ = gps.locate(5)
hasGPS = baseX ~= nil
print(hasGPS and "OK" or "no signal")
if hasGPS then log("GPS locked " .. baseX .. "," .. baseY .. "," .. baseZ) end
log("=== Radar Hub started ===")

-- ─── Radar loop ─────────────────────────────────────────────────────────────

local function radarLoop()
    local lastLocalPoll = -999

    while true do
        local now = os.clock()

        -- Local detector
        if localDetector and now - lastLocalPoll >= 1 then
            lastLocalPoll = now
            local ok, names = pcall(localDetector.getPlayersInRange, LOCAL_RADIUS)
            if ok and type(names) == "table" then
                for _, name in ipairs(names) do
                    local info = localDetector.getPlayer(name)
                    if info then
                        if not seenPlayers[name] then
                            log("SPOTTED (local): " .. name)
                        end
                        allPlayers[name] = { x = info.x, y = info.y, z = info.z, lastSeen = now }
                    end
                end
            end
        end

        -- Prune stale players
        for name, data in pairs(allPlayers) do
            if now - data.lastSeen > PLAYER_TIMEOUT then
                log("LEFT: " .. name)
                allPlayers[name] = nil
            end
        end

        -- Rebuild seenPlayers
        seenPlayers = {}
        for name in pairs(allPlayers) do seenPlayers[name] = true end

        -- Expire popup
        if popup and now > popup.expires then popup = nil end

        -- Draw frame
        monitor.setBackgroundColor(colors.black)
        monitor.clear()

        for i = TRAIL_STEPS, 1, -1 do
            drawSweepLine(sweepAngle - i * 0.1, i <= 2 and colors.lime or colors.green)
        end
        drawSweepLine(sweepAngle, colors.lime)
        put(CX, CY, colors.lime, "+")

        playerScreenPos = {}
        local playerList = {}
        for name, data in pairs(allPlayers) do
            table.insert(playerList, name)
            if hasGPS then
                local dx = data.x - baseX
                local dz = data.z - baseZ
                local sx = CX + math.floor((dx / DISPLAY_RADIUS) * SCALE)
                local sy = CY + math.floor((dz / DISPLAY_RADIUS) * SCALE)
                sx = math.max(1, math.min(W, sx))
                sy = math.max(1, math.min(H, sy))
                playerScreenPos[name] = { sx = sx, sy = sy }
                local dotColor = AUTHORIZED[name] and colors.green or colors.red
                put(sx, sy, dotColor, "O")
                local label = name:sub(1, 6)
                local lx = math.max(1, math.min(W - #label + 1, sx - math.floor(#label / 2)))
                local ly = (sy > 2) and (sy - 1) or (sy + 1)
                monitor.setBackgroundColor(colors.black)
                monitor.setTextColor(colors.white)
                monitor.setCursorPos(lx, math.max(1, math.min(H, ly)))
                monitor.write(label)
            end
        end

        -- Player list bottom-right, colored by auth
        local row = H
        for _, name in ipairs(playerList) do
            monitor.setBackgroundColor(colors.black)
            monitor.setTextColor(AUTHORIZED[name] and colors.green or colors.red)
            monitor.setCursorPos(math.max(1, W - #name), row)
            monitor.write(name)
            row = row - 1
            if row < 1 then break end
        end

        if popup then drawPopup(popup.name, allPlayers[popup.name]) end

        sweepAngle = (sweepAngle + SWEEP_STEP) % (math.pi * 2)
        sleep(0.05)
    end
end

-- ─── Network receiver loop ───────────────────────────────────────────────────

local function networkLoop()
    while true do
        local _, msg = rednet.receive(PROTOCOL, 5)
        if msg and type(msg) == "table" and msg.type == "radar_data" then
            local now = os.clock()
            for name, pos in pairs(msg.players) do
                if not seenPlayers[name] then
                    log("SPOTTED (node " .. msg.nodeId .. "): " .. name)
                end
                allPlayers[name] = { x = pos.x, y = pos.y, z = pos.z, lastSeen = now }
            end
        end
    end
end

-- ─── Touch loop ─────────────────────────────────────────────────────────────

local function touchLoop()
    while true do
        local _, _, tx, ty = os.pullEvent("monitor_touch")
        local hit = nil
        for name, pos in pairs(playerScreenPos) do
            if math.abs(tx - pos.sx) <= 2 and math.abs(ty - pos.sy) <= 2 then
                hit = name
                break
            end
        end
        if hit then
            popup = { name = hit, expires = os.clock() + 5 }
        else
            popup = nil
        end
    end
end

parallel.waitForAny(radarLoop, networkLoop, touchLoop)
