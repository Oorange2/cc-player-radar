-- Vault Server v6
-- Multi-player with per-player send queue
-- Selective item sending via buffer chests + frogport delivery

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

local pendingItems = {}  -- frogport delivery queue
local sendQueue    = {}  -- packaging work queue

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

local function sendItem(itemName, count, player)
    -- Find item in vault and count available stock
    local foundStation, foundSlot, available = nil, nil, 0
    for _, station in ipairs(SOURCES) do
        local vault = peripheral.wrap(station.vault)
        if vault then
            local ok, items = pcall(vault.list)
            if ok and type(items) == "table" then
                for slot, item in pairs(items) do
                    if item.name == itemName then
                        available = available + item.count
                        if not foundStation then
                            foundStation = station
                            foundSlot    = slot
                        end
                    end
                end
            end
        end
    end

    if not foundStation then return false, "Item not found in any vault" end
    if available == 0   then return false, "Out of stock" end

    -- Cap to what actually exists
    count = math.min(count, available)

    local vault    = peripheral.wrap(foundStation.vault)
    local buffer   = peripheral.wrap(foundStation.buffer)
    local packager = peripheral.wrap(foundStation.packager)

    if not (vault and buffer and packager) then
        return false, "Station peripheral missing - check wiring"
    end

    local bufItems = buffer.list()
    for slot, _ in pairs(bufItems) do
        vault.pullItems(foundStation.buffer, slot)
    end

    local moved = buffer.pullItems(foundStation.vault, foundSlot, count)
    if moved == 0 then return false, "Failed to pull item into buffer" end

    sleep(0.1)

    packager.setAddress(player)
    local ok, made = pcall(packager.makePackage)

    if not (ok and made) then
        buffer.pushItems(foundStation.vault, 1)
        return false, "Package failed"
    end

    table.insert(pendingItems, { name=itemName, count=moved, player=player })
    return true
end

-- ─── Queue processor ─────────────────────────────────────────────────────────

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

-- ─── Delivery loop ───────────────────────────────────────────────────────────

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

-- ─── Main request loop ───────────────────────────────────────────────────────

local function mainLoop()
    print("Vault server online (multi-player, queued)")
    while true do
        local clientId, msg = rednet.receive(PROTOCOL)
        if type(msg) == "table" then

            if msg.type == "list_request" then
                rednet.send(clientId, { type="list_response", items=listAllItems() }, PROTOCOL)

            elseif msg.type == "send_item" then
                local player = msg.player or "Player"
                -- Acknowledge immediately, queue the work
                rednet.send(clientId, { type="send_result", ok=true, pending=true }, PROTOCOL)
                table.insert(sendQueue, { name=msg.name, count=msg.count or 1, player=player })
                print("Queued: " .. msg.name .. " for " .. player .. " (queue size: " .. #sendQueue .. ")")
            end
        end
    end
end

parallel.waitForAny(mainLoop, deliveryLoop, processQueue)