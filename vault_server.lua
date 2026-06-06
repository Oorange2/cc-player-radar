-- AeroShields Vault Server v2
-- Uses Create packagers to browse vaults and send items to player
--
-- SETUP:
--   Source side:   each vault has a Packager attached, all wired to this computer
--   Delivery side: one Packager attached to a delivery vault, wired to this computer
--                  Inventory Manager adjacent to delivery vault, wired to this computer
--
-- Set DELIVERY_ADDRESS to match the address written on your delivery packager's sign
-- Set DELIVERY_VAULT_DIR to the side of the delivery vault relative to the inventory manager

local PROTOCOL           = "vault_ui"
local DELIVERY_VAULT_DIR = "back"   -- side of delivery vault from inventory manager

-- ─── Setup ──────────────────────────────────────────────────────────────────

local inv = peripheral.find("inventory_manager")
if not inv then error("No inventory_manager found on network") end

-- Get delivery address from the player linked to the inventory manager
local DELIVERY_ADDRESS = inv.getOwner()
if not DELIVERY_ADDRESS then
    error("No memory card in inventory manager - insert one linked to a player")
end
print("Delivery address: " .. DELIVERY_ADDRESS)

-- Open ender modem
local modemSide = nil
for _, side in ipairs({"top","bottom","left","right","front","back"}) do
    if peripheral.getType(side) == "modem" and side ~= INV_MANAGER_SIDE then
        modemSide = side
        break
    end
end
if not modemSide then error("No modem found") end
rednet.open(modemSide)

-- Find all packagers on the network
local function getPackagers()
    local packagers = {}
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "create:packager" then
            packagers[name] = peripheral.wrap(name)
        end
    end
    return packagers
end

-- Find the delivery packager by address
local function getDeliveryPackager(packagers)
    for name, p in pairs(packagers) do
        local ok, addr = pcall(p.getAddress)
        if ok and addr == DELIVERY_ADDRESS then
            return name, p
        end
    end
    return nil, nil
end

-- List all items across all source packagers, merged by item name
local function listAllItems(packagers, deliveryName)
    local merged = {}  -- name -> {displayName, count, sources={packager,slot,count}}

    for name, p in pairs(packagers) do
        if name ~= deliveryName then
            local ok, items = pcall(p.list)
            if ok and type(items) == "table" then
                for slot, item in pairs(items) do
                    if not merged[item.name] then
                        -- Get display name from detail
                        local detail = nil
                        pcall(function() detail = p.getItemDetail(slot) end)
                        merged[item.name] = {
                            name        = item.name,
                            displayName = (detail and detail.displayName) or item.name,
                            count       = 0,
                            sources     = {}
                        }
                    end
                    merged[item.name].count = merged[item.name].count + item.count
                    table.insert(merged[item.name].sources, {
                        packager = name,
                        slot     = slot,
                        count    = item.count
                    })
                end
            end
        end
    end

    -- Convert to sorted list
    local list = {}
    for _, v in pairs(merged) do table.insert(list, v) end
    table.sort(list, function(a, b) return a.displayName < b.displayName end)
    return list
end

-- ─── Main loop ──────────────────────────────────────────────────────────────

print("Vault server online.")
print("Delivery address: " .. DELIVERY_ADDRESS)
print("Scanning packagers...")

while true do
    local packagers                   = getPackagers()
    local deliveryName, deliveryPack  = getDeliveryPackager(packagers)

    if not deliveryName then
        print("Warning: delivery packager '" .. DELIVERY_ADDRESS .. "' not found")
    end

    print("Found " .. (function()
        local n = 0
        for _ in pairs(packagers) do n = n + 1 end
        return n
    end)() .. " packager(s)")

    local clientId, msg = rednet.receive(PROTOCOL)
    if type(msg) == "table" then

        -- ── List request ─────────────────────────────────────────────────────
        if msg.type == "list_request" then
            packagers    = getPackagers()
            deliveryName, deliveryPack = getDeliveryPackager(packagers)
            local items  = listAllItems(packagers, deliveryName)
            rednet.send(clientId, { type = "list_response", items = items }, PROTOCOL)

        -- ── Send item request ─────────────────────────────────────────────────
        elseif msg.type == "send_item" then
            packagers    = getPackagers()
            deliveryName, deliveryPack = getDeliveryPackager(packagers)

            if not deliveryName then
                rednet.send(clientId, { type="send_result", ok=false, err="No delivery packager found" }, PROTOCOL)
            else
                -- Find a source packager that has this item
                local sourcePackager = nil
                for name, p in pairs(packagers) do
                    if name ~= deliveryName then
                        local ok, items = pcall(p.list)
                        if ok then
                            for _, item in pairs(items) do
                                if item.name == msg.name then
                                    sourcePackager = p
                                    break
                                end
                            end
                        end
                    end
                    if sourcePackager then break end
                end

                if not sourcePackager then
                    rednet.send(clientId, { type="send_result", ok=false, err="Item not found in any vault" }, PROTOCOL)
                else
                    -- Set address and send package
                    sourcePackager.setAddress(DELIVERY_ADDRESS)
                    local ok, made = pcall(sourcePackager.makePackage)

                    if ok and made then
                        -- Wait for delivery packager to receive package
                        local received = false
                        local timeout  = os.startTimer(10)
                        while not received do
                            local e, p1 = os.pullEvent()
                            if e == "create:package_received" then
                                received = true
                            elseif e == "timer" and p1 == timeout then
                                break
                            end
                        end

                        if received then
                            -- Give item to player via inventory manager
                            local result = inv.addItemToPlayer(DELIVERY_VAULT_DIR, { name=msg.name, count=msg.count or 1 })
                            rednet.send(clientId, { type="send_result", ok=true, count=result }, PROTOCOL)
                        else
                            rednet.send(clientId, { type="send_result", ok=false, err="Package delivery timed out" }, PROTOCOL)
                        end
                    else
                        rednet.send(clientId, { type="send_result", ok=false, err="Failed to create package" }, PROTOCOL)
                    end
                end
            end
        end
    end
end
