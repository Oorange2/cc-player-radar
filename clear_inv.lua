local inv = peripheral.find("inventoryManager")
if not inv then error("No inventoryManager found") end

local PLAYER = "PlayerName" -- change this

print("Clearing " .. PLAYER .. "s inventory...")

local items = inv.getItems(PLAYER)
for _, item in pairs(items) do
    if item.name and item.name ~= "minecraft:air" then
        inv.removeItemFromPlayer(PLAYER, {name=item.name, count=item.count})
    end
end

print("Done.")
