-- AeroShields Vault Server v4
-- Selective item sending via buffer chests + frogport delivery
-- Background delivery loop checks every 5 seconds
--
-- SETUP PER SOURCE STATION:
--   [Vault+Modem] --- [Buffer Chest+Modem] --- [Packager+Modem] --- [Frogport]
--   Packager reads from buffer chest, NOT the vault directly
--   Run peripheral.getNames() and fill in SOURCES below

local PROTOCOL         = "vault_ui"
local DELIVERY_VAULT_DIR = "back"   -- side of delivery vault from inventory manager

-- ── Configure your source stations here ──────────────────────────────────────
-- vault:    wired peripheral name of the source vault
-- buffer:   wired peripheral name of the buffer chest next to the packager
-- packager: wired peripheral name of the packager

local SOURCES = {
    { vault="create:item_vault_1", buffer="minecraft:barrel_0", packager="Create_Packager_1" },
    { vault="create:item_vault_2", buffer="minecraft:barrel_1", packager="Create_Packager_2" },
    { vault="create:item_vault_3", buffer="minecraft:barrel_2", packager="Create_Packager_3" },
    { vault="create:item_vault_4", buffer="minecraft:barrel_3", packager="Create_Packager_4" },
}

-- ─── Setup ───────────────────────────────────────────────────────────────────

local inv = peripheral.find("inventory_manager")
if not inv then error("No inventory_manager found on network") end

local DELIVERY_ADDRESS = inv.getOwner()
if not DELIVERY_ADDRESS then
    error("No memory card in inventory manager - insert one linked to a player")
end
print("Delivery address: " .. DELIVERY_ADDRESS)

local modemSide = nil
for _, side in ipairs({"top","bottom","left","right","front","back"}) do
    if peripheral.getType(side) == "modem" then modemSide = side break end
end
if not modemSide then error("No modem found") end
rednet.open(modemSide)

-- ─── State ───────────────────────────────────────────────────────────────────

local pendingItems = {}  -- items sent via frogport waiting to be delivered

-- ─── Helpers ─────────────────────────────────────────────────────────────────

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

local function sendItem(itemName, count)
    -- Find which station has the item
    local foundStation, foundSlot = nil, nil
    for _, station in ipairs(SOURCES) do
        local vault = peripheral.wrap(station.vault)
        if vault then
            local ok, items = pcall(vault.list)
            if ok and type(items) == "table" then
                for slot, item in pairs(items) do
                    if item.name == itemName then
                        foundStation = station
                        foundSlot    = slot
                        break
                    end
                end
            end
        end
        if foundStation then break end
    end

    if not foundStation then return false, "Item not found in any vault" end

    local vault    = peripheral.wrap(foundStation.vault)
    local buffer   = peripheral.wrap(foundStation.buffer)
    local packager = peripheral.wrap(foundStation.packager)

    if not (vault and buffer and packager) then
        return false, "Station peripheral missing - check wiring"
    end

    -- Clear the buffer first (send any leftover items back to vault)
    local bufItems = buffer.list()
    for slot, _ in pairs(bufItems) do
        buffer.pushItems(foundStation.vault, slot)
    end

    -- Move just the requested item from vault to buffer
    local moved = vault.pushItems(foundStation.buffer, foundSlot, count)
    if moved == 0 then return false, "Failed to move item to buffer" end

    -- Address package to player and fire packager
    packager.setAddress(DELIVERY_ADDRESS)
    local ok, made = pcall(packager.makePackage)

    if not (ok and made) then
        -- Move item back if packaging failed
        buffer.pushItems(foundStation.vault, 1)
        return false, "Package failed"
    end

    -- Queue for delivery loop
    table.insert(pendingItems, { name=itemName, count=moved })
    return true
end

-- ─── Delivery loop (runs every 5 seconds) ────────────────────────────────────

local function deliveryLoop()
    while true do
        sleep(5)
        local i = 1
        while i <= #pendingItems do
            local item = pendingItems[i]
            local ok, result = pcall(
                inv.addItemToPlayer, DELIVERY_VAULT_DIR,
                { name=item.name, count=item.count }
            )
            if ok and type(result) == "number" and result > 0 then
                print("Delivered: " .. item.name)
                table.remove(pendingItems, i)
            else
                i = i + 1  -- not arrived yet, try again next tick
            end
        end
    end
end

-- ─── Main request loop ───────────────────────────────────────────────────────

local function mainLoop()
    print("Vault server online. Delivery: " .. DELIVERY_ADDRESS)

    while true do
        local clientId, msg = rednet.receive(PROTOCOL)
        if type(msg) == "table" then

            if msg.type == "list_request" then
                rednet.send(clientId, { type="list_response", items=listAllItems() }, PROTOCOL)

            elseif msg.type == "send_item" then
                local ok, err = sendItem(msg.name, msg.count or 1)
                if ok then
                    rednet.send(clientId, { type="send_result", ok=true, pending=true }, PROTOCOL)
                    print("Sent: " .. msg.name .. " (awaiting frogport delivery)")
                else
                    rednet.send(clientId, { type="send_result", ok=false, err=err }, PROTOCOL)
                    print("Failed: " .. (err or "unknown"))
                end
            end
        end
    end
end

-- ─── Run both loops in parallel ──────────────────────────────────────────────

parallel.waitForAny(mainLoop, deliveryLoop)
