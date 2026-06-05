-- AeroShields Player Radar v5
-- bottom: player_detector | left: monitor | top: wireless modem

local detector = peripheral.wrap("bottom")
local monitor  = peripheral.wrap("left")

if not detector then error("No player_detector on bottom") end
if not monitor  then error("No monitor on left") end

monitor.setTextScale(0.5)
local W, H   = monitor.getSize()
local CX, CY = math.floor(W / 2), math.floor(H / 2)
local RADIUS  = 100
local SCALE   = math.min(CX, CY) - 2

local LOG_FILE    = "player_log.txt"
local seenPlayers = {}
local sweepAngle  = 0
local SWEEP_STEP  = 0.28
local TRAIL_STEPS = 4

-- Declared here so all functions below can close over them
local baseX, baseY, baseZ
local hasGPS = false

local cachedPlayers   = {}
local playerScreenPos = {}
local popup           = nil

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

local function drawPopup(name, info)
    local lines = { name }
    if info and hasGPS then
        local dx   = info.x - baseX
        local dy   = info.y - baseY
        local dz   = info.z - baseZ
        local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
        table.insert(lines, string.format("Dist: %.1f blk", dist))
        table.insert(lines, string.format("X: %.0f", info.x))
        table.insert(lines, string.format("Y: %.0f", info.y))
        table.insert(lines, string.format("Z: %.0f", info.z))
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

-- ─── GPS (runs before anything else) ────────────────────────────────────────

term.write("GPS... ")
baseX, baseY, baseZ = gps.locate(5)
hasGPS = baseX ~= nil
print(hasGPS and "OK" or "no signal")
if hasGPS then log("GPS locked " .. baseX .. "," .. baseY .. "," .. baseZ) end
log("=== Radar started ===")

-- ─── Radar loop (animation + polling) ───────────────────────────────────────

local function radarLoop()
    local lastPoll = -999

    while true do
        local now = os.clock()

        -- Poll player detector every 1 second
        if now - lastPoll >= 1 then
            lastPoll = now
            local ok, names = pcall(detector.getPlayersInRange, RADIUS)
            if ok and type(names) == "table" then
                local current = {}
                local newCache = {}
                for _, name in ipairs(names) do
                    current[name] = true
                    local info = detector.getPlayer(name)
                    newCache[name] = info
                    if not seenPlayers[name] then
                        if info and hasGPS then
                            local dx   = info.x - baseX
                            local dy   = info.y - baseY
                            local dz   = info.z - baseZ
                            local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
                            log(string.format("SPOTTED: %s  %.1f blk  (%.0f,%.0f,%.0f)", name, dist, dx, dy, dz))
                        else
                            log("SPOTTED: " .. name)
                        end
                    end
                end
                for name in pairs(seenPlayers) do
                    if not current[name] then log("LEFT: " .. name) end
                end
                seenPlayers   = current
                cachedPlayers = newCache
            end
        end

        -- Expire popup
        if popup and os.clock() > popup.expires then popup = nil end

        -- Draw frame
        monitor.setBackgroundColor(colors.black)
        monitor.clear()

        for i = TRAIL_STEPS, 1, -1 do
            drawSweepLine(sweepAngle - i * 0.1, i <= 2 and colors.lime or colors.green)
        end
        drawSweepLine(sweepAngle, colors.lime)
        put(CX, CY, colors.lime, "+")

        -- Players
        playerScreenPos = {}
        local playerList = {}
        for name, info in pairs(cachedPlayers) do
            table.insert(playerList, name)
            if hasGPS and info then
                local dx = info.x - baseX
                local dz = info.z - baseZ
                local sx = CX + math.floor((dx / RADIUS) * SCALE)
                local sy = CY + math.floor((dz / RADIUS) * SCALE)
                sx = math.max(1, math.min(W, sx))
                sy = math.max(1, math.min(H, sy))
                playerScreenPos[name] = { sx = sx, sy = sy }
                put(sx, sy, colors.red, "O")
                local label = name:sub(1, 6)
                local lx = math.max(1, math.min(W - #label + 1, sx - math.floor(#label / 2)))
                local ly = (sy > 2) and (sy - 1) or (sy + 1)
                monitor.setBackgroundColor(colors.black)
                monitor.setTextColor(colors.white)
                monitor.setCursorPos(lx, math.max(1, math.min(H, ly)))
                monitor.write(label)
            end
        end

        -- Name list bottom-right
        local row = H
        for _, name in ipairs(playerList) do
            monitor.setBackgroundColor(colors.black)
            monitor.setTextColor(colors.yellow)
            monitor.setCursorPos(math.max(1, W - #name), row)
            monitor.write(name)
            row = row - 1
            if row < 1 then break end
        end

        if popup then drawPopup(popup.name, popup.info) end

        sweepAngle = (sweepAngle + SWEEP_STEP) % (math.pi * 2)
        sleep(0.05)
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
            popup = { name = hit, info = cachedPlayers[hit], expires = os.clock() + 5 }
        else
            popup = nil
        end
    end
end

-- Run both loops concurrently
parallel.waitForAny(radarLoop, touchLoop)
