-- Vault Client v5
-- Up/Down or scroll to browse  |  Shift+Scroll = adjust send amount
-- Enter = send  |  R = refresh  |  Q = quit

local PROTOCOL      = "vault_ui"
local REFRESH_EVERY = 30  -- seconds

local modemSide = nil
for _, side in ipairs({"top","bottom","left","right","front","back"}) do
    if peripheral.getType(side) == "modem" then modemSide = side break end
end
if not modemSide then error("No ender modem on pocket computer") end
rednet.open(modemSide)

-- ─── Login ───────────────────────────────────────────────────────────────────

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
term.setBackgroundColor(colors.blue)
term.setTextColor(colors.white)
term.clearLine()
term.write(" Vault Login")
term.setBackgroundColor(colors.black)
term.setCursorPos(1, 3)
term.write("Username: ")
local localPlayer = read()
if localPlayer == "" then localPlayer = "Player" end

-- ─── State ───────────────────────────────────────────────────────────────────

local W, H      = term.getSize()
local items     = {}
local selected  = 1
local scroll    = 0
local serverId  = nil
local message   = ""
local msgTimer  = 0
local shiftHeld = false
local sendCount = 1
local refreshTimer = nil

-- ─── Item icon colors ────────────────────────────────────────────────────────

local iconColors = {
    colors.orange, colors.magenta, colors.lightBlue, colors.yellow,
    colors.lime,   colors.pink,    colors.cyan,      colors.purple,
    colors.blue,   colors.brown,   colors.green,     colors.red,
}

local function itemColor(name)
    local h = 0
    for i = 1, #name do h = (h * 31 + string.byte(name, i)) % #iconColors end
    return iconColors[h + 1]
end

-- ─── Network ─────────────────────────────────────────────────────────────────

local function fetch()
    rednet.broadcast({ type="list_request", player=localPlayer }, PROTOCOL)
    local id, msg = rednet.receive(PROTOCOL, 5)
    if msg and msg.type == "list_response" then
        serverId = id
        return msg.items
    end
    return nil
end

local function doRefresh()
    local fresh = fetch()
    if fresh then
        items    = fresh
        selected = math.min(selected, math.max(1, #items))
    end
    refreshTimer = os.startTimer(REFRESH_EVERY)
end

local function sendItem()
    local item = items[selected]
    if not item or not serverId then return end
    rednet.send(serverId, { type="send_item", name=item.name, count=sendCount, player=localPlayer }, PROTOCOL)
    local _, res = rednet.receive(PROTOCOL, 10)
    local label  = item.displayName or item.name
    if res and res.ok then
        message  = "Sent x" .. sendCount .. ": " .. label
        msgTimer = os.clock() + 3
    else
        message  = (res and res.err) or "Failed"
        msgTimer = os.clock() + 3
    end
    doRefresh()
end

-- ─── Draw ────────────────────────────────────────────────────────────────────

local function draw()
    term.setBackgroundColor(colors.black)
    term.clear()

    -- Header
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.setCursorPos(1, 1)
    term.clearLine()
    local header = " " .. localPlayer .. " [" .. #items .. "]"
    local countLabel = " x" .. sendCount
    local pad = W - #header - #countLabel
    term.write(header .. string.rep(" ", math.max(0, pad)) .. countLabel)

    -- Item list
    local listH = H - 2
    for row = 1, listH do
        local idx  = row + scroll
        local item = items[idx]
        term.setCursorPos(1, row + 1)

        if item then
            local isSel  = idx == selected
            local nameBg = isSel and colors.gray  or colors.black
            local nameFg = isSel and colors.yellow or colors.white

            term.setBackgroundColor(itemColor(item.name))
            term.setTextColor(colors.black)
            term.write("  ")

            local countStr = "x" .. item.count
            local maxName  = W - 3 - #countStr
            local label    = (item.displayName or item.name):sub(1, maxName)
            term.setBackgroundColor(nameBg)
            term.setTextColor(nameFg)
            term.write(" " .. label)

            local filled = 2 + 1 + #label
            local rpad   = math.max(0, W - filled - #countStr)
            term.setTextColor(colors.cyan)
            term.write(string.rep(" ", rpad) .. countStr)
        else
            term.setBackgroundColor(colors.black)
            term.write(string.rep(" ", W))
        end
    end

    -- Footer
    term.setCursorPos(1, H)
    term.setBackgroundColor(colors.black)
    if message ~= "" and os.clock() < msgTimer then
        term.setTextColor(colors.lime)
        term.write(message:sub(1, W))
    else
        message = ""
        term.setTextColor(colors.gray)
        term.write("Entr=snd Shft+Scrl=amt R=rfsh Q=quit")
    end
end

-- ─── Main ────────────────────────────────────────────────────────────────────

term.clear()
term.setCursorPos(1, 1)
print("Connecting...")
items = fetch()
if not items then
    print("Server not found!")
    return
end
refreshTimer = os.startTimer(REFRESH_EVERY)

while true do
    draw()

    local event, p1, p2, p3 = os.pullEvent()

    if event == "key" then
        if p1 == keys.leftShift or p1 == keys.rightShift then
            shiftHeld = true
        elseif p1 == keys.up then
            if selected > 1 then
                selected = selected - 1
                if selected <= scroll then scroll = scroll - 1 end
            end
        elseif p1 == keys.down then
            if selected < #items then
                selected = selected + 1
                if selected > scroll + (H - 2) then scroll = scroll + 1 end
            end
        elseif p1 == keys.enter then
            sendItem()
        elseif p1 == keys.r then
            doRefresh()
            message  = "Refreshed"
            msgTimer = os.clock() + 1
        elseif p1 == keys.q then
            break
        end

    elseif event == "key_up" then
        if p1 == keys.leftShift or p1 == keys.rightShift then
            shiftHeld = false
        end

    elseif event == "mouse_scroll" then
        if shiftHeld then
            -- adjust send count
            sendCount = math.max(1, sendCount + p1)
        else
            if p1 == -1 and selected > 1 then
                selected = selected - 1
                if selected <= scroll then scroll = scroll - 1 end
            elseif p1 == 1 and selected < #items then
                selected = selected + 1
                if selected > scroll + (H - 2) then scroll = scroll + 1 end
            end
        end

    elseif event == "timer" and p1 == refreshTimer then
        doRefresh()
    end
end

term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)