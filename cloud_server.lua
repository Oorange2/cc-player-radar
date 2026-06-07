-- Cloud Server v2
local PROTOCOL  = "cloud_ui"
local SAVE_FILE = "cloud_accounts.dat"

local modemSide = nil
for _, s in ipairs({"top","bottom","left","right","front","back"}) do
    if peripheral.getType(s) == "modem" then modemSide = s break end
end
if not modemSide then error("No modem found") end
rednet.open(modemSide)

local accounts = {}
local sessions  = {}

local function save()
    local f = fs.open(SAVE_FILE, "w")
    f.write(textutils.serialize(accounts))
    f.close()
end

local function load()
    if fs.exists(SAVE_FILE) then
        local f = fs.open(SAVE_FILE, "r")
        accounts = textutils.unserialize(f.readAll()) or {}
        f.close()
    end
    if not accounts["admin"] then
        accounts["admin"] = { password="2007", isAdmin=true, vault=nil, invmanager=nil, vaultDir="back", log={} }
        save()
    end
end
load()

local function makeToken()
    math.randomseed(os.clock() * 100000)
    local s = ""
    for i = 1, 16 do s = s .. string.format("%x", math.random(0,15)) end
    return s
end

local function getSession(tok)
    local s = sessions[tok]
    if not s then return nil end
    if os.time() > s.exp then sessions[tok] = nil return nil end
    s.exp = os.time() + 3600
    return s
end

-- Try multiple method names on a peripheral, return first that works
local function pcallMethod(name, ...)
    local methods = {...}
    for _, method in ipairs(methods) do
        if peripheral.isPresent(name) then
            local ok, result = pcall(function()
                return peripheral.call(name, method)
            end)
            if ok and type(result) == "table" then
                return result, method
            end
        end
    end
    return nil, nil
end

local function listVault(uname)
    local acc = accounts[uname]
    if not acc or not acc.vault then return {}, "No vault configured" end
    if not peripheral.isPresent(acc.vault) then
        return {}, "Vault peripheral '" .. acc.vault .. "' not found - run debug to see available peripherals"
    end
    local ok, items = pcall(function() return peripheral.call(acc.vault, "list") end)
    if not ok or type(items) ~= "table" then
        return {}, "vault.list() failed: " .. tostring(items)
    end
    local merged = {}
    for slot, item in pairs(items) do
        if item and item.name then
            if not merged[item.name] then
                local d
                pcall(function() d = peripheral.call(acc.vault, "getItemDetail", slot) end)
                merged[item.name] = { name=item.name, displayName=(d and d.displayName) or item.name, count=0 }
            end
            merged[item.name].count = merged[item.name].count + item.count
        end
    end
    local list = {}
    for _, v in pairs(merged) do table.insert(list, v) end
    table.sort(list, function(a,b) return a.displayName < b.displayName end)
    return list, nil
end

local function listInv(uname)
    local acc = accounts[uname]
    if not acc or not acc.invmanager then return {}, "No inv manager configured" end
    if not peripheral.isPresent(acc.invmanager) then
        return {}, "InvMgr peripheral '" .. acc.invmanager .. "' not found"
    end
    -- inventory_manager is not a standard inventory — try known Plethora method names
    local items, method = pcallMethod(acc.invmanager, "getItems", "getInventory", "list")
    if not items then
        return {}, "Could not list player inventory — inv manager returned nothing (tried getItems/getInventory/list)"
    end
    local merged = {}
    local function merge(tbl)
        if type(tbl) ~= "table" then return end
        for _, item in pairs(tbl) do
            if item and item.name then
                if not merged[item.name] then
                    merged[item.name] = { name=item.name, displayName=item.displayName or item.name, count=0 }
                end
                merged[item.name].count = merged[item.name].count + (item.count or 1)
            end
        end
    end
    merge(items)
    -- Also grab armor separately
    local ok2, armor = pcall(function() return peripheral.call(acc.invmanager, "getArmour") end)
    if not ok2 then ok2, armor = pcall(function() return peripheral.call(acc.invmanager, "getArmor") end) end
    if ok2 then merge(armor) end
    local list = {}
    for _, v in pairs(merged) do table.insert(list, v) end
    table.sort(list, function(a,b) return a.displayName < b.displayName end)
    return list, nil
end

local function addLog(uname, entry)
    local acc = accounts[uname]
    if not acc then return end
    acc.log = acc.log or {}
    table.insert(acc.log, { time=os.date("%H:%M %d/%m"), event=entry })
    while #acc.log > 200 do table.remove(acc.log, 1) end
    save()
end

local function doWithdraw(uname, name, count)
    local acc = accounts[uname]
    if not acc or not acc.vault or not acc.invmanager then return false, "Account not configured" end
    if not peripheral.isPresent(acc.vault)      then return false, "Vault not found: "   .. (acc.vault or "?") end
    if not peripheral.isPresent(acc.invmanager) then return false, "InvMgr not found: " .. (acc.invmanager or "?") end
    -- Cap to available stock
    local ok, items = pcall(function() return peripheral.call(acc.vault, "list") end)
    local avail = 0
    if ok and type(items) == "table" then
        for _, item in pairs(items) do
            if item.name == name then avail = avail + item.count end
        end
    end
    if avail == 0 then return false, "Item not in vault" end
    count = math.min(count, avail)
    local moved
    local pok, err = pcall(function()
        moved = peripheral.call(acc.invmanager, "addItemToPlayer", acc.vaultDir or "back", { name=name, count=count })
    end)
    if not pok then return false, "addItemToPlayer error: " .. tostring(err) end
    if not moved or moved == 0 then return false, "Transfer returned 0 — check vaultDir setting" end
    return true, moved
end

local function doDeposit(uname, name, count)
    local acc = accounts[uname]
    if not acc or not acc.vault or not acc.invmanager then return false, "Account not configured" end
    if not peripheral.isPresent(acc.invmanager) then return false, "InvMgr not found: " .. (acc.invmanager or "?") end
    local moved
    local ok, err = pcall(function()
        moved = peripheral.call(acc.invmanager, "removeItemFromPlayer", acc.vaultDir or "back", { name=name, count=count })
    end)
    if not ok then return false, "removeItemFromPlayer error: " .. tostring(err) end
    if not moved or moved == 0 then return false, "Transfer returned 0 — player may not have item" end
    return true, moved
end

local function handle(cid, msg)
    if type(msg) ~= "table" then return end

    if msg.type == "login" then
        local acc = accounts[msg.username]
        if not acc or acc.password ~= msg.password then
            rednet.send(cid, { type="login_result", ok=false, err="Invalid credentials" }, PROTOCOL) return
        end
        local tok   = makeToken()
        local admin = acc.isAdmin or msg.username == "admin"
        sessions[tok] = { username=msg.username, isAdmin=admin, exp=os.time()+3600 }
        if not admin then addLog(msg.username, "Logged in") end
        rednet.send(cid, { type="login_result", ok=true, token=tok, isAdmin=admin }, PROTOCOL)
        print(msg.username .. " logged in")
        return
    end

    -- Debug: list all peripherals (no auth needed so admin can diagnose)
    if msg.type == "debug_peripherals" then
        rednet.send(cid, { type="debug_result", names=peripheral.getNames() }, PROTOCOL) return
    end

    local sess = getSession(msg.token)
    if not sess then
        rednet.send(cid, { type="error", err="Session expired" }, PROTOCOL) return
    end
    local uname = sess.username

    if msg.type == "list_vault" then
        local items, err = listVault(uname)
        rednet.send(cid, { type="vault_list", items=items, err=err }, PROTOCOL)

    elseif msg.type == "list_inventory" then
        local items, err = listInv(uname)
        rednet.send(cid, { type="inventory_list", items=items, err=err }, PROTOCOL)

    elseif msg.type == "withdraw" then
        local ok, r = doWithdraw(uname, msg.name, msg.count or 1)
        if ok then
            local label = msg.displayName or msg.name
            addLog(uname, "Withdrew x"..r.." "..label)
        end
        rednet.send(cid, { type="action_result", ok=ok, err=not ok and r or nil }, PROTOCOL)
        print((ok and "Withdrew" or "Withdraw fail").." ("..uname.."): "..msg.name.." - "..(ok and r or r))

    elseif msg.type == "deposit" then
        local ok, r = doDeposit(uname, msg.name, msg.count or 1)
        if ok then
            local label = msg.displayName or msg.name
            addLog(uname, "Deposited x"..r.." "..label)
        end
        rednet.send(cid, { type="action_result", ok=ok, err=not ok and r or nil }, PROTOCOL)
        print((ok and "Deposited" or "Deposit fail").." ("..uname.."): "..msg.name.." - "..(ok and r or r))

    elseif msg.type == "get_log" then
        local acc = accounts[uname]
        rednet.send(cid, { type="log_result", log=(acc and acc.log) or {} }, PROTOCOL)

    elseif msg.type == "admin_list_users" then
        if not sess.isAdmin then rednet.send(cid, { type="error", err="Not authorized" }, PROTOCOL) return end
        local list = {}
        for u, acc in pairs(accounts) do
            if u ~= "admin" then table.insert(list, { username=u, vault=acc.vault, invmanager=acc.invmanager }) end
        end
        rednet.send(cid, { type="user_list", users=list }, PROTOCOL)

    elseif msg.type == "admin_create_user" then
        if not sess.isAdmin then rednet.send(cid, { type="error", err="Not authorized" }, PROTOCOL) return end
        if accounts[msg.username] then
            rednet.send(cid, { type="action_result", ok=false, err="User already exists" }, PROTOCOL) return
        end
        accounts[msg.username] = {
            password=msg.password, vault=msg.vault,
            invmanager=msg.invmanager, vaultDir=msg.vaultDir or "back", log={}
        }
        save()
        rednet.send(cid, { type="action_result", ok=true }, PROTOCOL)
        print("Created user: "..msg.username)

    elseif msg.type == "admin_delete_user" then
        if not sess.isAdmin then rednet.send(cid, { type="error", err="Not authorized" }, PROTOCOL) return end
        accounts[msg.username] = nil
        save()
        rednet.send(cid, { type="action_result", ok=true }, PROTOCOL)

    elseif msg.type == "admin_view_vault" then
        if not sess.isAdmin then rednet.send(cid, { type="error", err="Not authorized" }, PROTOCOL) return end
        local items, err = listVault(msg.username)
        rednet.send(cid, { type="vault_list", items=items, err=err }, PROTOCOL)

    elseif msg.type == "admin_view_inventory" then
        if not sess.isAdmin then rednet.send(cid, { type="error", err="Not authorized" }, PROTOCOL) return end
        local items, err = listInv(msg.username)
        rednet.send(cid, { type="inventory_list", items=items, err=err }, PROTOCOL)

    elseif msg.type == "admin_withdraw" then
        if not sess.isAdmin then rednet.send(cid, { type="error", err="Not authorized" }, PROTOCOL) return end
        local ok, r = doWithdraw(msg.username, msg.name, msg.count or 1)
        rednet.send(cid, { type="action_result", ok=ok, err=not ok and r or nil }, PROTOCOL)

    elseif msg.type == "admin_deposit" then
        if not sess.isAdmin then rednet.send(cid, { type="error", err="Not authorized" }, PROTOCOL) return end
        local ok, r = doDeposit(msg.username, msg.name, msg.count or 1)
        rednet.send(cid, { type="action_result", ok=ok, err=not ok and r or nil }, PROTOCOL)
    end
end

print("Cloud server online")
print("Connected peripherals: " .. table.concat(peripheral.getNames(), ", "))
while true do
    local cid, msg = rednet.receive(PROTOCOL)
    handle(cid, msg)
end