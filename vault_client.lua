-- AeroShields Vault Client
-- Runs on pocket computer with ender modem attached
-- Up/Down to browse, Enter to send item to yourself, R to refresh, Q to quit

local PROTOCOL = "vault_ui"

-- Open ender modem
local modemSide = nil
for _, side in ipairs({"top","bottom","left","right","front","back"}) do
    if peripheral.getType(side) == "modem" then
        modemSide = side
        break
    end
end
if not modemSide then error("No ender modem found on pocket computer") end
rednet.open(modemSide)

local W, H     = term.getSize()
local items    = {}
local selected = 1
local scroll   = 0
local serverId = nil
local message  = ""
local msgTimer = 0

local function fetch()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.gray)
    term.setCursorPos(1, H)
    term.clearLine()
    term.write("Connecting...")
    rednet.broadcast({ type = "list_request" }, PROTOCOL)
    local id, msg = rednet.receive(PROTOCOL, 5)
    if msg and msg.type == "list_response" then
        serverId = id
        return msg.items
    end
    return nil
end

local function draw()
    term.setBackgroundColor(colors.black)
    term.clear()

    -- Header
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.setCursorPos(1, 1)
    term.clearLine()
    term.write(" Vault  [" .. #items .. " items]")

    -- List
    local listH = H - 2
    for row = 1, listH do
        local idx  = row + scroll
        local item = items[idx]
        term.setCursorPos(1, row + 1)
        term.clearLine()
        if item then
            if idx == selected then
                term.setBackgroundColor(colors.gray)
                term.setTextColor(colors.yellow)
            else
                term.setBackgroundColor(colors.black)
                term.setTextColor(colors.white)
            end
            local label = item.displayName or item.name
            local count = "x" .. item.count
            local pad   = W - #label - #count - 1
            if pad < 0 then
                label = label:sub(1, W - #count - 2)
                pad   = 1
            end
            term.write(label .. string.rep(" ", pad) .. count)
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
        term.write("Enter=Get  R=Refresh  Q=Quit")
    end
end

-- Initial fetch
items = fetch()
if not items then
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.red)
    term.setCursorPos(1,1)
    term.clear()
    print("Server not found.")
    print("Is vault_server running?")
    return
end

while true do
    draw()

    local event, key = os.pullEvent("key")

    if key == keys.up then
        if selected > 1 then
            selected = selected - 1
            if selected <= scroll then scroll = scroll - 1 end
        end

    elseif key == keys.down then
        if selected < #items then
            selected = selected + 1
            if selected > scroll + (H - 2) then scroll = scroll + 1 end
        end

    elseif key == keys.enter then
        local item = items[selected]
        if item and serverId then
            rednet.send(serverId, {
                type  = "send_item",
                name  = item.name,
                count = 1,
            }, PROTOCOL)
            local _, res = rednet.receive(PROTOCOL, 5)
            if res and res.count and res.count > 0 then
                message  = "Sent: " .. (item.displayName or item.name)
                msgTimer = os.clock() + 2
            else
                message  = "Failed - check vault/manager"
                msgTimer = os.clock() + 2
            end
        end

    elseif key == keys.r then
        local fresh = fetch()
        if fresh then
            items    = fresh
            selected = math.min(selected, #items)
            scroll   = math.max(0, selected - (H - 2))
            message  = "Refreshed"
            msgTimer = os.clock() + 1
        else
            message  = "Server not responding"
            msgTimer = os.clock() + 2
        end

    elseif key == keys.q then
        break
    end
end

term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
