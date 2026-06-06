local inv = peripheral.wrap("left")
if not inv then error("No inventory_manager on left") end

local CHEST_DIR = "top"  -- direction of chest relative to the inventory manager

print("Clearing inventory...")

local items = inv.getItems()
for _, item in pairs(items) do
    if item.name and item.name ~= "minecraft:air" then
        inv.removeItemFromPlayer(CHEST_DIR, {name=item.name, count=item.count})
    end
end

print("Done.")
