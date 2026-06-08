-- vault_setup.lua
-- Type the number for each vault/barrel/packager, station by station.
-- Type "done" at the vault prompt (or leave blank) to finish and save.

local VAULT_PREFIX    = "create:item_vault_"
local BARREL_PREFIX   = "minecraft:barrel_"
local PACKAGER_PREFIX = "Create_Packager_"

local function header(title)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.setCursorPos(1, 1)
    term.clearLine()
    term.write(" " .. title)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

local function prompt(label, prefix)
    term.setTextColor(colors.yellow)
    io.write("  " .. label .. " #: ")
    term.setTextColor(colors.gray)
    io.write(prefix)
    term.setTextColor(colors.white)
    local val = read()
    val = val:match("^%s*(.-)%s*$")  -- trim whitespace
    return prefix .. val, val
end

-- ─── Main loop ────────────────────────────────────────────────────────────────

local sources = {}

while true do
    local n = #sources + 1

    term.clear()
    header("Vault Setup  —  Station " .. n)

    term.setCursorPos(1, 3)
    term.setTextColor(colors.gray)
    print("  Just type the number for each peripheral.")
    print("  Leave Vault # blank (or type 'done') to finish.\n")

    local v, vn = prompt("Vault",    VAULT_PREFIX)
    if vn == "" or vn:lower() == "done" then break end

    local b = prompt("Barrel",   BARREL_PREFIX)
    local p = prompt("Packager", PACKAGER_PREFIX)

    -- Confirm
    term.setCursorPos(1, 9)
    term.setTextColor(colors.lime)
    print("  Saved station " .. n .. ":")
    term.setTextColor(colors.white)
    print("    Vault:    " .. v)
    print("    Barrel:   " .. b)
    print("    Packager: " .. p)

    table.insert(sources, { vault=v, buffer=b, packager=p })

    term.setTextColor(colors.gray)
    print("\n  Press Enter for next station...")
    io.read()
end

-- ─── Save ─────────────────────────────────────────────────────────────────────

if #sources == 0 then
    term.clear()
    header("Vault Setup")
    term.setCursorPos(1, 3)
    term.setTextColor(colors.red)
    print("  No stations entered. Nothing saved.")
    return
end

local f = fs.open("sources.cfg", "w")
f.write(textutils.serialize(sources))
f.close()

term.clear()
header("Vault Setup  —  Done!")
term.setCursorPos(1, 3)
term.setTextColor(colors.lime)
print("  Saved " .. #sources .. " stations to sources.cfg")
term.setTextColor(colors.gray)
print("  You can now run vault_server.lua")
print("  Re-run vault_setup.lua any time to redo the config.")
