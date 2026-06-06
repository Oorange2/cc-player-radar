-- AeroShields Vault Server v3
-- Source packagers wired to this computer, frogports handle delivery
-- Delivery packager address = player name from inventory manager memory card

local PROTOCOL         = "vault_ui"
local DELIVERY_VAULT_DIR = "back"  -- side of delivery vault relative to inventory manager
local DELIVERY_DELAY   = 8         -- seconds to wait for frogport delivery (increase if needed)

-- ─── Setup ──────────────────────────────────────────────────────────────────

local inv = peripheral.find("inventory_manager")
if not inv then error("No inventory_manager found on network") end

local DELIVERY_ADDRESS = inv.getOwner()
if not DELIVERY_ADDRESS then
    error("No memory card in inventory manager - insert one linked to a player")
end
print("Delivery address: " .. DELIVERY_ADDRESS)

-- Open ender modem
local modemSide = nil
for _, side in ipairs({"top","bottom","left","right","front","back"}) do
    if peripheral.getType(side) == "modem" then
        modemSide = side
        break
    end
end
if not modemSide then error("No modem found") end
rednet.open(modemSide)

-- ─── Helpers ────────────────────────────────────────────────────────────────

local function getPackagers()
    local packagers = {}
    for _, name in ipairs(peripheral.getNames()) do
        local t = peripheral.getType(name) or ""
        if t:lower():find("packager") then
            packagers[name] = peripheral.wrap(name)
        end
    end
    return packagers
end

local function listAllItems()
    local merged = {}
    for _, p in pairs(getPackagers()) do
        local ok, items = pcall(p.list)
        if ok and type(items) == "table" then
            for slot, item in pairs(items) do
                if not merged[item.name] then
                    local detail = nil
                    pcall(function() detail = p.getItemDetail(slot) end)
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
    local list = {}
    for _, v in pairs(merged) do table.insert(list, v) end
    table.sort(list, function(a, b) return a.displayName < b.displayName end)
    return list
end

local function findSourcePackager(itemName)
    for _, p in pairs(getPackagers()) do
        local ok, items = pcall(p.list)
        if ok and type(items) == "table" then
            for _, item in pairs(items) do
                if item.name == itemName then return p end
            end
        end
    end
    return nil
end

-- ─── Main loop ──────────────────────────────────────────────────────────────

print("Vault server online.")
print("Found " .. (function()
    local n = 0
    for _ in pairs(getPackagers()) do n = n + 1 end
    return n
end)() .. " packager(s)")

while true do
    local clientId, msg = rednet.receive(PROTOCOL)
    if type(msg) == "table" then

        -- ── List items ───────────────────────────────────────────────────────
        if msg.type == "list_request" then
            rednet.send(clientId, { type="list_response", items=listAllItems() }, PROTOCOL)

        -- ── Send item ────────────────────────────────────────────────────────
        elseif msg.type == "send_item" then
            local source = findSourcePackager(msg.name)

            if not source then
                rednet.send(clientId, { type="send_result", ok=false, err="Item not found" }, PROTOCOL)
            else
                -- Address package to player and send via frogport
                source.setAddress(DELIVERY_ADDRESS)
                local ok, made = pcall(source.makePackage)

                if not (ok and made) then
                    rednet.send(clientId, { type="send_result", ok=false, err="Package failed" }, PROTOCOL)
                else
                    -- Tell client it's on the way
                    rednet.send(clientId, { type="send_result", ok=true, pending=true }, PROTOCOL)

                    -- Wait for frogport delivery then give just the requested item
                    sleep(DELIVERY_DELAY)
                    inv.addItemToPlayer(DELIVERY_VAULT_DIR, { name=msg.name, count=msg.count or 1 })
                    print("Delivered: " .. msg.name .. " to " .. DELIVERY_ADDRESS)
                end
            end
        end
    end
end
