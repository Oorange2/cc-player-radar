-- AeroShields Vault Server
-- Reads vault contents and handles item requests from pocket computer
--
-- SETUP:
--   VAULT_SIDE     = side of vault relative to THIS computer
--   VAULT_INV_DIR  = side of vault relative to the inventory manager block

local PROTOCOL    = "vault_ui"
local VAULT_SIDE  = "right"   -- change to whichever side the vault is on
local VAULT_INV_DIR = "left"  -- direction of vault from the inventory manager

local inv   = peripheral.wrap("left")   -- inventory manager side
local vault = peripheral.wrap(VAULT_SIDE)

if not inv   then error("No inventory_manager found") end
if not vault then error("No vault found on " .. VAULT_SIDE) end

-- Open ender modem
local modemSide = nil
for _, side in ipairs({"top","bottom","left","right","front","back"}) do
    if peripheral.getType(side) == "modem" and side ~= "left" and side ~= VAULT_SIDE then
        modemSide = side
        break
    end
end
if not modemSide then error("No ender modem found") end
rednet.open(modemSide)

print("Vault server online. Listening...")

local function getVaultItems()
    local merged = {}
    local raw    = vault.list()
    for _, item in pairs(raw) do
        local found = false
        for _, entry in ipairs(merged) do
            if entry.name == item.name then
                entry.count = entry.count + item.count
                found = true
                break
            end
        end
        if not found then
            table.insert(merged, {
                name        = item.name,
                displayName = item.displayName or item.name,
                count       = item.count,
            })
        end
    end
    table.sort(merged, function(a, b) return a.displayName < b.displayName end)
    return merged
end

while true do
    local senderId, msg = rednet.receive(PROTOCOL)
    if type(msg) == "table" then

        if msg.type == "list_request" then
            local items = getVaultItems()
            rednet.send(senderId, { type = "list_response", items = items }, PROTOCOL)

        elseif msg.type == "send_item" then
            local ok, result = pcall(
                inv.addItemToPlayer, VAULT_INV_DIR,
                { name = msg.name, count = msg.count or 1 }
            )
            rednet.send(senderId, {
                type  = "send_result",
                count = ok and result or 0,
            }, PROTOCOL)
        end
    end
end
