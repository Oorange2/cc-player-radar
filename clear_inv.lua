local inv = peripheral.wrap("left")
if not inv then error("No inventory_manager on left") end

local PLAYER = "cypu001"

print("Clearing " .. PLAYER .. "s inventory...")

local items = inv.getItems(PLAYER)
for _, item in pairs(items) do
    if item.name and item.name ~= "minecraft:air" then
        inv.removeItemFromPlayer(PLAYER, item.name, item.count)
    end
end

print("Done.")
