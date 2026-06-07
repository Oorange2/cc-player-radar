-- vault_setup.lua
-- Run once to pair each vault with its barrel and packager.
-- Saves the result to sources.cfg which vault_server.lua loads at startup.
-- Re-run any time you add or change stations.

local W, H = term.getSize()

local function getByPattern(pat)
    local t = {}
    for _, name in ipairs(peripheral.getNames()) do
        if name:match(pat) then table.insert(t, name) end
    end
    table.sort(t, function(a, b)
        return (tonumber(a:match("%d+$")) or 0) < (tonumber(b:match("%d+$")) or 0)
    end)
    return t
end

local vaults    = getByPattern("^create:item_vault")
local barrels   = getByPattern("^minecraft:barrel")
local packagers = getByPattern("[Pp]ackager")

if #vaults == 0 then error("No create:item_vault peripherals found — check modem connection") end

-- ─── Simple scrollable picker ─────────────────────────────────────────────────

local function pickFrom(list, used, title)
    local available = {}
    for _, name in ipairs(list) do
        if not used[name] then table.insert(available, name) end
    end
    if #available == 0 then error("No unused " .. title .. " left to assign") end

    local sel    = 1
    local scroll = 0
    local rows   = H - 4

    while true do
        term.clear()
        term.setCursorPos(1, 1)
        term.setBackgroundColor(colors.blue)
        term.setTextColor(colors.white)
        term.clearLine()
        term.write(" Select " .. title .. " (" .. #available .. " available)")
        term.setBackgroundColor(colors.black)

        for row = 1, rows do
            local idx  = row + scroll
            local name = available[idx]
            term.setCursorPos(1, row + 1)
            if name then
                if idx == sel then
                    term.setBackgroundColor(colors.gray)
                    term.setTextColor(colors.yellow)
                else
                    term.setBackgroundColor(colors.black)
                    term.setTextColor(colors.white)
                end
                local line = " " .. idx .. ") " .. name
                term.write(line .. string.rep(" ", math.max(0, W - #line)))
            else
                term.setBackgroundColor(colors.black)
                term.write(string.rep(" ", W))
            end
        end

        term.setCursorPos(1, H)
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.gray)
        term.clearLine()
        term.write(" Up/Down = navigate   Enter = confirm")

        local _, key = os.pullEvent("key")
        if key == keys.up and sel > 1 then
            sel = sel - 1
            if sel <= scroll then scroll = scroll - 1 end
        elseif key == keys.down and sel < #available then
            sel = sel + 1
            if sel > scroll + rows then scroll = scroll + 1 end
        elseif key == keys.enter then
            local chosen = available[sel]
            used[chosen] = true
            return chosen
        end
    end
end

-- ─── Main pairing loop ────────────────────────────────────────────────────────

local usedV, usedB, usedP = {}, {}, {}
local sources = {}

for i = 1, #vaults do
    -- Pick vault
    local v = pickFrom(vaults,    usedV, "VAULT (" .. i .. "/" .. #vaults .. ")")
    -- Pick barrel for this vault
    local b = pickFrom(barrels,   usedB, "BARREL for " .. v)
    -- Pick packager for this vault
    local p = pickFrom(packagers, usedP, "PACKAGER for " .. v)

    sources[i] = { vault=v, buffer=b, packager=p }

    -- Confirmation screen
    term.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.green)
    term.setTextColor(colors.black)
    term.clearLine()
    term.write(" Station " .. i .. " saved")
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.setCursorPos(1, 3)
    print("  Vault:    " .. v)
    print("  Barrel:   " .. b)
    print("  Packager: " .. p)
    term.setTextColor(colors.gray)
    print("")
    print("  Press any key for next station...")
    os.pullEvent("key")
end

-- ─── Save ─────────────────────────────────────────────────────────────────────

local f = fs.open("sources.cfg", "w")
f.write(textutils.serialize(sources))
f.close()

term.clear()
term.setCursorPos(1, 1)
term.setBackgroundColor(colors.blue)
term.setTextColor(colors.white)
term.clearLine()
term.write(" Setup complete!")
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.setCursorPos(1, 3)
print("Saved " .. #sources .. " stations to sources.cfg")
print("")
term.setTextColor(colors.gray)
print("You can now start vault_server.lua")
print("Re-run vault_setup.lua any time to change pairings.")
