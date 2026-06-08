-- vault_setup.lua
-- Type the number after each prefix and press Enter.
-- Leave Vault # blank to finish and save.

local VAULT_PREFIX    = "create:item_vault_"
local BARREL_PREFIX   = "minecraft:barrel_"
local PACKAGER_PREFIX = "Create_Packager_"

local function ask(label, prefix)
    term.setTextColor(colors.yellow)
    io.write("  " .. label .. ": ")
    term.setTextColor(colors.gray)
    io.write(prefix)
    term.setTextColor(colors.white)
    local val = read():match("^%s*(.-)%s*$")
    return prefix .. val, val
end

-- ─── Main loop ────────────────────────────────────────────────────────────────

local sources = {}

term.clear()
term.setCursorPos(1, 1)
term.setBackgroundColor(colors.blue)
term.setTextColor(colors.white)
term.clearLine()
term.write(" Vault Setup")
term.setBackgroundColor(colors.black)
term.setTextColor(colors.gray)
term.setCursorPos(1, 3)
print("  Type the number after each prefix, press Enter.")
print("  Leave Vault blank to finish.\n")

while true do
    local v, vn = ask("Vault   ", VAULT_PREFIX)
    if vn == "" or vn:lower() == "done" then break end

    local b = ask("Barrel  ", BARREL_PREFIX)
    local p = ask("Packager", PACKAGER_PREFIX)

    table.insert(sources, { vault=v, buffer=b, packager=p })

    term.setTextColor(colors.lime)
    print("  >> Station " .. #sources .. " saved\n")
    term.setTextColor(colors.white)
end

-- ─── Save ─────────────────────────────────────────────────────────────────────

if #sources == 0 then
    term.setTextColor(colors.red)
    print("\n  Nothing saved.")
    return
end

local f = fs.open("sources.cfg", "w")
f.write(textutils.serialize(sources))
f.close()

term.setTextColor(colors.lime)
print("\n  Done! Saved " .. #sources .. " stations to sources.cfg")
term.setTextColor(colors.gray)
print("  You can now run vault_server.lua")
