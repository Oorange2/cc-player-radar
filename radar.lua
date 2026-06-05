-- AeroShields Player Radar
-- Requires: Advanced Peripherals (player_detector on bottom)
--           Advanced Monitor 2x2 (on left)
--           Wireless Modem (on top, for GPS)

local detector = peripheral.wrap("bottom")
local monitor  = peripheral.wrap("left")

if not detector then error("No player_detector found on bottom") end
if not monitor  then error("No monitor found on left") end

monitor.setTextScale(0.5)
local W, H   = monitor.getSize()
local CX, CY = math.floor(W / 2), math.floor(H / 2)
local RADIUS  = 100   -- match advancedperipherals.toml playerDetectorMaxRange
local SCALE   = math.min(CX, CY) - 2

local LOG_FILE    = "player_log.txt"
local seenPlayers = {}

-- ─── Helpers ────────────────────────────────────────────────────────────────

local function log(msg)
    local t = os.date("%Y-%m-%d %H:%M:%S")
    local line = "[" .. t .. "] " .. msg
    local f = fs.open(LOG_FILE, "a")
    f.writeLine(line)
    f.close()
end

local function put(x, y, col, char)
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(col)
    monitor.setCursorPos(x, y)
    monitor.write(char)
end

-- ─── GPS lock ───────────────────────────────────────────────────────────────

term.write("Locating via GPS... ")
local baseX, baseY, baseZ = gps.locate(5)
local hasGPS = baseX ~= nil

if hasGPS then
    print("OK (" .. baseX .. ", " .. baseY .. ", " .. baseZ .. ")")
    log("GPS locked at " .. baseX .. "," .. baseY .. "," .. baseZ)
else
    print("No signal. Dots disabled, names still show.")
    log("No GPS signal")
end

log("=== Radar started ===")

-- ─── Main loop ──────────────────────────────────────────────────────────────

while true do
    monitor.setBackgroundColor(colors.black)
    monitor.clear()

    -- Crosshair
    put(CX, CY, colors.lime, "+")

    local ok, names = pcall(detector.getPlayersInRange, RADIUS)
    if not ok or type(names) ~= "table" then names = {} end

    local currentPlayers = {}

    for i, name in ipairs(names) do
        currentPlayers[name] = true

        local info = detector.getPlayer(name)

        -- ── Logging ──────────────────────────────────────────────────────
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

        -- ── Radar dot ────────────────────────────────────────────────────
        if hasGPS and info then
            local dx = info.x - baseX
            local dz = info.z - baseZ
            local sx = CX + math.floor((dx / RADIUS) * SCALE)
            local sy = CY + math.floor((dz / RADIUS) * SCALE)
            sx = math.max(1, math.min(W, sx))
            sy = math.max(1, math.min(H, sy))
            put(sx, sy, colors.red, "P")
        end

        -- ── Name list (bottom of monitor) ────────────────────────────────
        local row = H - #names + i
        if row >= 1 and row <= H then
            monitor.setTextColor(colors.yellow)
            monitor.setCursorPos(1, row)
            monitor.write(name:sub(1, W))
        end
    end

    -- Log players who left range
    for name in pairs(seenPlayers) do
        if not currentPlayers[name] then
            log("LEFT:    " .. name)
        end
    end

    seenPlayers = currentPlayers
    sleep(1)
end
