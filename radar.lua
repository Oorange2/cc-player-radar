-- AeroShields Player Radar v2
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
local SWEEP_STEP  = 0.12   -- radians per frame
local TRAIL_STEPS = 14     -- trail length behind sweep

local cachedPlayers = {}   -- updated every 1s, drawn every frame

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

-- ─── GPS lock ───────────────────────────────────────────────────────────────

term.write("GPS... ")
local baseX, baseY, baseZ = gps.locate(5)
local hasGPS = baseX ~= nil
print(hasGPS and "OK" or "no signal")
if hasGPS then log("GPS locked " .. baseX .. "," .. baseY .. "," .. baseZ) end
log("=== Radar started ===")

-- ─── Main loop ──────────────────────────────────────────────────────────────

local lastPoll = -999

while true do
    -- Poll player detector every 1 second
    local now = os.clock()
    if now - lastPoll >= 1 then
        lastPoll = now

        local ok, names = pcall(detector.getPlayersInRange, RADIUS)
        if ok and type(names) == "table" then
            local currentPlayers = {}
            local newCache = {}

            for _, name in ipairs(names) do
                currentPlayers[name] = true
                local info = detector.getPlayer(name)
                newCache[name] = info

                if not seenPlayers[name] then
                    if info and hasGPS then
                        local dx = info.x - baseX
                        local dy = info.y - baseY
                        local dz = info.z - baseZ
                        local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
                        log(string.format(
                            "SPOTTED: %s  %.1f blocks  (%.0f, %.0f, %.0f)",
                            name, dist, dx, dy, dz
                        ))
                    else
                        log("SPOTTED: " .. name)
                    end
                end
            end

            for name in pairs(seenPlayers) do
                if not currentPlayers[name] then
                    log("LEFT:    " .. name)
                end
            end

            seenPlayers   = currentPlayers
            cachedPlayers = newCache
        end
    end

    -- ── Draw frame ───────────────────────────────────────────────────────────

    monitor.setBackgroundColor(colors.black)
    monitor.clear()

    -- Sweep trail (darker further behind)
    for i = TRAIL_STEPS, 1, -1 do
        local a   = sweepAngle - (i * 0.07)
        local col = (i <= 4) and colors.lime or colors.green
        drawSweepLine(a, col)
    end
    -- Bright leading edge
    drawSweepLine(sweepAngle, colors.lime)

    -- Centre crosshair
    put(CX, CY, colors.lime, "+")

    -- Player dots + name labels
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

            -- Red dot
            put(sx, sy, colors.red, "O")

            -- Name above dot (shift below if at top edge)
            local label = name:sub(1, 6)
            local lx    = math.max(1, math.min(W - #label + 1, sx - math.floor(#label / 2)))
            local ly    = sy > 2 and (sy - 1) or (sy + 1)
            monitor.setTextColor(colors.white)
            monitor.setCursorPos(lx, ly)
            monitor.write(label)
        end
    end

    -- Player list at bottom right
    local row = H
    for _, name in ipairs(playerList) do
        monitor.setTextColor(colors.yellow)
        monitor.setCursorPos(W - #name + 1, row)
        monitor.write(name)
        row = row - 1
        if row < 1 then break end
    end

    sweepAngle = (sweepAngle + SWEEP_STEP) % (math.pi * 2)
    sleep(0.05)
end
