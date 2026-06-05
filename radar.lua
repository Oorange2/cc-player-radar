-- AeroShields Player Radar v3
-- bottom: player_detector | left: monitor | top: wireless modem

local detector = peripheral.wrap("bottom")
local monitor  = peripheral.wrap("left")

if not detector then error("No player_detector on bottom") end
if not monitor  then error("No monitor on left") end

monitor.setTextScale(0.5)
local W, H    = monitor.getSize()
local CX, CY  = math.floor(W / 2), math.floor(H / 2)
local RADIUS   = 100
local SCALE    = math.min(CX, CY) - 2

local LOG_FILE    = "player_log.txt"
local seenPlayers = {}
local sweepAngle  = 0
local SWEEP_STEP  = 0.12
local TRAIL_STEPS = 14

local cachedPlayers   = {}
local playerScreenPos = {}   -- name -> {sx, sy} used for touch hit detection
local popup           = nil  -- {name, info, expires} or nil

-- ─── Helpers ────────────────────────────────────────────────────────────────

local function log(msg)
    local t = os.date("%Y-%m-%d %H:%M:%S")
    local f = fs.open(LOG_FILE, "a")
    f.writeLine("[" .. t .. "] " .. msg)
    f.close()
end

local function put(x, y, col, char)
    if x < 1 or x > W or y < 1 or y > H then return end
    monitor.setTextColor(col)
    monitor.setCursorPos(x, y)
    monitor.write(char)
end

local function drawSweepLine(angle, col)
    for r = 1, SCALE do
        local px = CX + math.floor(math.cos(angle) * r)
        local py = CY + math.floor(math.sin(angle) * r * 0.5)
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
    elseif not hasGPS then
        table.insert(lines, "No GPS data")
    end

    -- Box sizing
    local bw = 2
    for _, l in ipairs(lines) do bw = math.max(bw, #l + 2) end
    local bh = #lines + 2
    local bx = math.max(1, math.min(W - bw, CX - math.floor(bw / 2)))
    local by = math.max(1, math.min(H - bh, CY - math.floor(bh / 2)))

    -- Background fill
    for row = by, by + bh - 1 do
        for col = bx, bx + bw - 1 do
            monitor.setBackgroundColor(colors.gray)
            monitor.setTextColor(colors.white)
            monitor.setCursorPos(col, row)
            monitor.write(" ")
        end
    end

    -- Border
    monitor.setBackgroundColor(colors.gray)
    monitor.setTextColor(colors.white)
    monitor.setCursorPos(bx, by)
    monitor.write("+" .. string.rep("-", bw - 2) .. "+")
    monitor.setCursorPos(bx, by + bh - 1)
    monitor.write("+" .. string.rep("-", bw - 2) .. "+")
    for row = by + 1, by + bh - 2 do
        monitor.setCursorPos(bx, row)             monitor.write("|")
        monitor.setCursorPos(bx + bw - 1, row)   monitor.write("|")
    end

    -- Text
    for i, line in ipairs(lines) do
        monitor.setBackgroundColor(colors.gray)
        monitor.setTextColor(i == 1 and colors.yellow or colors.white)
        monitor.setCursorPos(bx + 1, by + i)
        monitor.write(line)
    end
end

-- ─── GPS lock ───────────────────────────────────────────────────────────────

term.write("GPS... ")
local baseX, baseY, baseZ = gps.locate(5)
local hasGPS = baseX ~= nil
print(hasGPS and "OK" or "no signal")
if hasGPS then log("GPS locked " .. baseX .. "," .. baseY .. "," .. baseZ) end
log("=== Radar started ===")

-- ─── Event loop ─────────────────────────────────────────────────────────────

local animTimer = os.startTimer(0.05)
local pollTimer = os.startTimer(1)

while true do
    local event, p1, p2, p3 = os.pullEvent()

    -- ── Animation tick ───────────────────────────────────────────────────────
    if event == "timer" and p1 == animTimer then

        -- Expire popup
        if popup and os.clock() > popup.expires then popup = nil end

        monitor.setBackgroundColor(colors.black)
        monitor.clear()

        -- Sweep trail + leading edge
        for i = TRAIL_STEPS, 1, -1 do
            local col = (i <= 4) and colors.lime or colors.green
            drawSweepLine(sweepAngle - i * 0.07, col)
        end
        drawSweepLine(sweepAngle, colors.lime)

        -- Crosshair
        put(CX, CY, colors.lime, "+")

        -- Player dots
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
                local lx    = math.max(1, math.min(W - #label + 1, sx - math.floor(#label / 2)))
                local ly    = (sy > 2) and (sy - 1) or (sy + 1)
                monitor.setTextColor(colors.white)
                monitor.setCursorPos(lx, ly)
                monitor.write(label)
            end
        end

        -- Player list bottom-right
        local row = H
        for _, name in ipairs(playerList) do
            local lx = math.max(1, W - #name)
            monitor.setTextColor(colors.yellow)
            monitor.setCursorPos(lx, row)
            monitor.write(name)
            row = row - 1
            if row < 1 then break end
        end

        -- Popup overlay (drawn last so it's on top)
        if popup then drawPopup(popup.name, popup.info) end

        sweepAngle = (sweepAngle + SWEEP_STEP) % (math.pi * 2)
        animTimer  = os.startTimer(0.05)

    -- ── Player poll ──────────────────────────────────────────────────────────
    elseif event == "timer" and p1 == pollTimer then

        local ok, names = pcall(detector.getPlayersInRange, RADIUS)
        if ok and type(names) == "table" then
            local currentPlayers = {}
            local newCache       = {}
            for _, name in ipairs(names) do
                currentPlayers[name] = true
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
                if not currentPlayers[name] then log("LEFT: " .. name) end
            end
            seenPlayers   = currentPlayers
            cachedPlayers = newCache
        end
        pollTimer = os.startTimer(1)

    -- ── Touch ────────────────────────────────────────────────────────────────
    elseif event == "monitor_touch" then
        local tx, ty = p2, p3
        local hit    = nil

        for name, pos in pairs(playerScreenPos) do
            if math.abs(tx - pos.sx) <= 2 and math.abs(ty - pos.sy) <= 2 then
                hit = name
                break
            end
        end

        if hit then
            popup = { name = hit, info = cachedPlayers[hit], expires = os.clock() + 5 }
        else
            popup = nil   -- tap empty space to dismiss
        end
    end
end
