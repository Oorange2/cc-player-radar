-- AeroShields Drone Hover Controller
-- Plus-config quadcopter (one prop per cardinal side)
-- Follows TARGET_PLAYER from radar network
--
-- HARDWARE ON DRONE:
--   altitude_sensor       (any side)
--   gimbal_sensor         (any side)
--   4x rotation_speed_controller, one per prop
--   ender modem
--   wireless modem (for GPS)
--
-- Run 'peripherals' on the drone computer to confirm peripheral names
-- Adjust MOTOR_SIDES to match your wiring

-- ─── Config ─────────────────────────────────────────────────────────────────

local TARGET_PLAYER  = "GPIO"      -- player to follow from radar
local PROTOCOL       = "aeroshields_radar"
local HOVER_OFFSET   = 5           -- blocks above player to hover
local BASE_RPM       = 200         -- collective hover RPM (tune until it lifts)
local MAX_RPM        = 512         -- hard cap
local MIN_RPM        = 0
local MAX_TILT       = 20          -- max degrees of lean for horizontal movement
local LOOP_HZ        = 20          -- control loop rate

-- Which side of the computer each motor speed controller is on
-- Run 'peripherals' and adjust these
local MOTOR_SIDES = {
    F = "front",
    B = "back",
    L = "left",
    R = "right",
}

-- ─── PID factory ────────────────────────────────────────────────────────────

local function makePID(kP, kI, kD, maxI)
    local integral, lastErr = 0, 0
    return {
        update = function(err, dt)
            integral = math.max(-maxI, math.min(maxI, integral + err * dt))
            local deriv = dt > 0 and (err - lastErr) / dt or 0
            lastErr = err
            return kP * err + kI * integral + kD * deriv
        end,
        reset = function() integral = 0; lastErr = 0 end
    }
end

-- Outer loop: world position → desired tilt angle
local posX = makePID(1.5, 0.05, 1.2, 15)   -- X error → desired pitch
local posZ = makePID(1.5, 0.05, 1.2, 15)   -- Z error → desired roll
local posY = makePID(4.0, 0.20, 2.5, 60)   -- Y error → throttle delta

-- Inner loop: desired tilt vs actual tilt → motor differential
local attPitch = makePID(6.0, 0.1, 1.5, 40)
local attRoll  = makePID(6.0, 0.1, 1.5, 40)

-- ─── Peripherals ────────────────────────────────────────────────────────────

local alt    = peripheral.find("altitude_sensor")
local gimbal = peripheral.find("gimbal_sensor")

if not alt    then error("altitude_sensor not found - check it is attached") end
if not gimbal then error("gimbal_sensor not found - check it is attached") end

local motors = {}
for dir, side in pairs(MOTOR_SIDES) do
    motors[dir] = peripheral.wrap(side)
    if not motors[dir] then
        error("No peripheral on " .. side .. " for motor " .. dir)
    end
end

-- Open ender modem for rednet
local modemSide = nil
for _, side in ipairs({"top","bottom","left","right","front","back"}) do
    local t = peripheral.getType(side)
    if t == "modem" then
        modemSide = side
        break
    end
end
if not modemSide then error("No modem found") end
rednet.open(modemSide)

-- ─── Helpers ────────────────────────────────────────────────────────────────

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- Plus-config motor mixing
--        [F]
--    [L]  +  [R]
--        [B]
--
-- F/B control pitch, L/R control roll
-- For yaw: needs alternating spin directions on the physical props
local function setMotors(throttle, pitch, roll, yaw)
    local f = clamp(throttle + pitch - yaw, MIN_RPM, MAX_RPM)
    local b = clamp(throttle - pitch - yaw, MIN_RPM, MAX_RPM)
    local l = clamp(throttle + roll  + yaw, MIN_RPM, MAX_RPM)
    local r = clamp(throttle - roll  + yaw, MIN_RPM, MAX_RPM)
    motors.F.setTargetSpeed(f)
    motors.B.setTargetSpeed(b)
    motors.L.setTargetSpeed(l)
    motors.R.setTargetSpeed(r)
end

local function stopMotors()
    for _, m in pairs(motors) do pcall(m.setTargetSpeed, 0) end
end

-- ─── Shared state (written by network/GPS loops, read by flight loop) ───────

local droneX, droneY, droneZ = nil, nil, nil
local targetX, targetY, targetZ = nil, nil, nil
local running = true

-- ─── GPS loop (updates drone position every 0.5s) ────────────────────────────

local function gpsLoop()
    while running do
        local x, y, z = gps.locate(3)
        if x then droneX, droneY, droneZ = x, y, z end
        sleep(0.5)
    end
end

-- ─── Network loop (gets player position from radar hub) ──────────────────────

local function networkLoop()
    while running do
        local _, msg = rednet.receive(PROTOCOL, 2)
        if msg and type(msg) == "table" and msg.type == "radar_data" then
            local pos = msg.players and msg.players[TARGET_PLAYER]
            if pos then
                targetX = pos.x
                targetY = pos.y + HOVER_OFFSET
                targetZ = pos.z
            end
        end
    end
end

-- ─── Flight loop ─────────────────────────────────────────────────────────────

local function flightLoop()
    local lastT = os.clock()

    -- Spin up to base RPM
    print("Spinning up...")
    setMotors(BASE_RPM, 0, 0, 0)
    sleep(2)

    print("Control active. Following: " .. TARGET_PLAYER)

    while running do
        local now = os.clock()
        local dt  = math.max(0.001, now - lastT)
        lastT     = now

        -- ── Sensor readings ───────────────────────────────────────────────
        local height = alt.getHeight()
        local vspeed = alt.getVerticalSpeed()

        local angles = {gimbal.getAngles()}
        local pitch  = angles[1] or 0   -- nose up/down in degrees
        local roll   = angles[2] or 0   -- left/right tilt in degrees

        -- ── Altitude PID ─────────────────────────────────────────────────
        local targetH = targetY or (height + HOVER_OFFSET)
        local errY    = targetH - height
        -- Feed vspeed as damping to reduce bounce
        local throttle = BASE_RPM + posY.update(errY - vspeed * 0.3, dt)
        throttle = clamp(throttle, MIN_RPM, MAX_RPM)

        -- ── Position PID (outer loop) ─────────────────────────────────────
        local desiredPitch, desiredRoll = 0, 0
        if droneX and targetX then
            local errX = targetX - droneX
            local errZ = targetZ - droneZ
            desiredPitch = clamp(posX.update(errX, dt), -MAX_TILT, MAX_TILT)
            desiredRoll  = clamp(posZ.update(errZ, dt), -MAX_TILT, MAX_TILT)
        end

        -- ── Attitude PID (inner loop) ──────────────────────────────────────
        local pitchCmd = attPitch.update(desiredPitch - pitch, dt)
        local rollCmd  = attRoll.update(desiredRoll  - roll,  dt)

        -- ── Apply ──────────────────────────────────────────────────────────
        setMotors(throttle, pitchCmd, rollCmd, 0)

        sleep(1 / LOOP_HZ)
    end

    stopMotors()
end

-- ─── Entry point ─────────────────────────────────────────────────────────────

print("AeroShields Drone Controller")
print("Target: " .. TARGET_PLAYER .. " | Offset: +" .. HOVER_OFFSET .. "m")
print("Ctrl+T to terminate")

-- Initial GPS fix
term.write("GPS... ")
droneX, droneY, droneZ = gps.locate(5)
if droneX then
    print("OK (" .. math.floor(droneX) .. "," .. math.floor(droneY) .. "," .. math.floor(droneZ) .. ")")
    -- Default hover target is current position until player is found
    targetX, targetY, targetZ = droneX, droneY + HOVER_OFFSET, droneZ
else
    print("no signal - position hold disabled")
end

parallel.waitForAny(flightLoop, networkLoop, gpsLoop)
running = false
stopMotors()
print("Drone stopped.")
