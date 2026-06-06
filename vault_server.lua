-- Vault Server v7
-- Multi-player with per-player send queue, batched packaging (max 64 per package)

local PROTOCOL           = "vault_ui"
local DELIVERY_VAULT_DIR = "back"

local SOURCES = {
    { vault="create:item_vault_9",  buffer="minecraft:barrel_7",  packager="Create_Packager_1" },
    { vault="create:item_vault_10", buffer="minecraft:barrel_8",  packager="Create_Packager_0" },
    { vault="create:item_vault_11", buffer="minecraft:barrel_9",  packager="Create_Packager_2" },
    { vault="create:item_vault_12", buffer="minecraft:barrel_10", packager="Create_Packager_3" },
}

local inv = peripheral.find("inventory_manager")
if not inv then error("No inventory_manager found on network") end

local modemSide = nil
for _, side in ipairs({"top","bottom","left","right","front","back"}) do
    if peripheral.getType(side) == "modem" then modemSide = side break end
end
if not modemSide then error("No modem found") end
rednet.open(modemSide)

local pendingItems = {}
local sendQueue    = {}

local function listAllItems()
    local merged = {}
    for _, station in ipairs(SOURCES) do
        local vault = peripheral.wrap(station.vault)
        if vault then
            local ok, items = pcall(vault.list)
            if ok and type(items) == "table" then
                for slot, item in pairs(items) do
                    if not merged[item.name] then
                        local detail = nil
                        pcall(function() detail = vault.getItemDetail(slot) end)
                        merged[item.name] = {
                            name        = item.name,
                            displayName = (detail and detail.displayName) or item.name,
                            count       = 0,
                        }
                    end
                    merged[item.name].count = merged[item.name].count + item.count
                end
            end
        end
    end
    local list = {}
    for _, v in pairs(merged) do table.insert(list, v) end
    table.sort(list, function(a, b) return a.displayName < b.displayName end)
    return list
end

-- Sends one batch (up to 64) of an item from a station. Returns moved count or 0.
local function sendBatch(station, itemName, count, player)
    local vault    = peripheral.wrap(station.vault)
    local buffer   = peripheral.wrap(station.buffer)
    local packager = peripheral.wrap(station.packager)
    if not (vault and buffer and packager) then return 0 end

    -- Clear buffer
    local bufItems = buffer.list()
    for slot, _ in pairs(bufItems) do
        vault.pullItems(station.buffer, slot)
    end

    -- Find the slot in vault
    local foundSlot = nil
    local ok, vItems = pcall(vault.list)
    if ok and type(vItems) == "table" then
        for slot, item in pairs(vItems) do
            if item.name == itemName then foundSlot = slot break end
        end
    end
    if not foundSlot then return 0 end

    local moved = buffer.pullItems(station.vault, foundSlot, count)
    if moved == 0 then return 0 end

    sleep(0.1)
    packager.setAddress(player)
    local pOk, made = pcall(packager.makePackage)
    if not (pOk and made) then
        buffer.pushItems(station.vault, 1)
        return 0
    end

    return moved
end

local function sendItem(itemName, count, player)
    -- Gather all stations that have this item and total available
    local available = 0
    local stations  = {}
    for _, station in ipairs(SOURCES) do
        local vault = peripheral.wrap(station.vault)
        if vault then
            local ok, items = pcall(vault.list)
            if ok and type(items) == "table" then
                for _, item in pairs(items) do
                    if item.name == itemName then
                        available = available + item.count
                        table.insert(stations, station)
                        break
                    end
                end
            end
        end
    end

    if available == 0 then return false, "Out of stock" end
    count = math.min(count, available)

    -- Send in batches of 64, cycling through stations that have stock
    local remaining  = count
    local totalMoved = 0
    local stationIdx = 1

    while remaining > 0 and stationIdx <= #stations do
        local batch = math.min(remaining, 64)
        local moved = sendBatch(stations[stationIdx], itemName, batch, player)
        if moved > 0 then
            table.insert(pendingItems, { name=itemName, count=moved, player=player })
            totalMoved  = totalMoved + moved
            remaining   = remaining - moved
        else
            stationIdx = stationIdx + 1
        end
    end

    if totalMoved == 0 then return false, "Failed to package item" end
    return true
end

local function processQueue()
    while true do
        if #sendQueue > 0 then
            local req = table.remove(sendQueue, 1)
            local ok, err = sendItem(req.name, req.count, req.player)
            if ok then
                print("Processed: " .. req.name .. " for " .. req.player)
            else
                print("Queue failed (" .. req.player .. "): " .. (err or "unknown"))
            end
        else
            sleep(0.05)
        end
    end
end

local function deliveryLoop()
    while true do
        sleep(5)
        local i = 1
        while i <= #pendingItems do
            local item = pendingItems[i]
            local ok, result = pcall(
                inv.addItemToPlayer, DELIVERY_VAULT_DIR,
                { name=item.name, count=item.count },
                item.player
            )
            if ok and type(result) == "number" and result > 0 then
                print("Delivered to " .. item.player .. ": " .. item.name)
                table.remove(pendingItems, i)
            else
                i = i + 1
            end
        end
    end
end

local function mainLoop()
    print("Vault server online (multi-player, batched packaging)")
    while true do
        local clientId, msg = rednet.receive(PROTOCOL)
        if type(msg) == "table" then
            if msg.type == "list_request" then
                rednet.send(clientId, { type="list_response", items=listAllItems() }, PROTOCOL)
            elseif msg.type == "send_item" then
                local player = msg.player or "Player"
                rednet.send(clientId, { type="send_result", ok=true, pending=true }, PROTOCOL)
                table.insert(sendQueue, { name=msg.name, count=msg.count or 1, player=player })
                print("Queued: " .. msg.name .. " x" .. (msg.count or 1) .. " for " .. player)
            end
        end
    end
end

parallel.waitForAny(mainLoop, deliveryLoop, processQueue)