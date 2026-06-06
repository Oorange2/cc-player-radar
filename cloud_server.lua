-- Cloud Server v1
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
    for i = 1, 16 do s = s .. string.format("%x", math.random(0, 15)) end
    return s
end

local function getSession(tok)
    local s = sessions[tok]
    if not s then return nil end
    if os.time() > s.exp then sessions[tok] = nil return nil end
    s.exp = os.time() + 3600
    return s
end

local function listVault(uname)
    local acc = accounts[uname]
    if not acc or not acc.vault then return {} end
    local v = peripheral.wrap(acc.vault)
    if not v then return {} end
    local merged = {}
    local ok, items = pcall(v.list)
    if ok and type(items) == "table" then
        for slot, item in pairs(items) do
            if not merged[item.name] then
                local d; pcall(function() d = v.getItemDetail(slot) end)
                merged[item.name] = { name=item.name, displayName=(d and d.displayName) or item.name, count=0 }
            end
            merged[item.name].count = merged[item.name].count + item.count
        end
    end
    local list = {}
    for _, v2 in pairs(merged) do table.insert(list, v2) end
    table.sort(list, function(a, b) return a.displayName < b.displayName end)
    return list
end

local function listInv(uname)
    local acc = accounts[uname]
    if not acc or not acc.invmanager then return {} end
    local im = peripheral.wrap(acc.invmanager)
    if not im then return {} end
    local merged = {}
    local function merge(items)
        if type(items) ~= "table" then return end
        for _, item in pairs(items) do
            if item and item.name then
                if not merged[item.name] then
                    merged[item.name] = { name=item.name, displayName=item.displayName or item.name, count=0 }
                end
                merged[item.name].count = merged[item.name].count + (item.count or 1)
            end
        end
    end
    local ok, items = pcall(im.list)
    if not ok then ok, items = pcall(im.getItems) end
    merge(items)
    local ok2, armor = pcall(im.getArmour)
    if ok2 then merge(armor) end
    local list = {}
    for _, v in pairs(merged) do table.insert(list, v) end
    table.sort(list, function(a, b) return a.displayName < b.displayName end)
    return list
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
    local v  = peripheral.wrap(acc.vault)
    local im = peripheral.wrap(acc.invmanager)
    if not v or not im then return false, "Peripheral missing" end
    local avail, slot = 0, nil
    local ok, items = pcall(v.list)
    if ok and type(items) == "table" then
        for s, item in pairs(items) do
            if item.name == name then avail = avail + item.count if not slot then slot = s end end
        end
    end
    if not slot then return false, "Item not found" end
    count = math.min(count, avail)
    local moved
    local pok, err = pcall(function()
        moved = im.addItemToPlayer(acc.vaultDir or "back", { name=name, count=count })
    end)
    if not pok then return false, tostring(err) end
    if not moved or moved == 0 then return false, "Failed to give item" end
    return true, moved
end

local function doDeposit(uname, name, count)
    local acc = accounts[uname]
    if not acc or not acc.vault or not acc.invmanager then return false, "Account not configured" end
    local im = peripheral.wrap(acc.invmanager)
    if not im then return false, "Peripheral missing" end
    local moved
    local ok, err = pcall(function()
        moved = im.removeItemFromPlayer(acc.vaultDir or "back", { name=name, count=count })
    end)
    if not ok then return false, tostring(err) end
    if not moved or moved == 0 then return false, "Failed to take item" end
    return true, moved
end

local function handle(cid, msg)
    if type(msg) ~= "table" then return end

    if msg.type == "login" then
        local acc = accounts[msg.username]
        if not acc or acc.password ~= msg.password then
            rednet.send(cid, { type="login_result", ok=false, err="Invalid credentials" }, PROTOCOL)
            return
        end
        local tok = makeToken()
        local admin = acc.isAdmin or msg.username == "admin"
        sessions[tok] = { username=msg.username, isAdmin=admin, exp=os.time() + 3600 }
        if not admin then addLog(msg.username, "Logged in") end
        rednet.send(cid, { type="login_result", ok=true, token=tok, isAdmin=admin }, PROTOCOL)
        print(msg.username .. " logged in")
        return
    end

    local sess = getSession(msg.token)
    if not sess then
        rednet.send(cid, { type="error", err="Session expired" }, PROTOCOL)
        return
    end
    local uname = sess.username

    if msg.type == "list_vault" then
        rednet.send(cid, { type="vault_list", items=listVault(uname) }, PROTOCOL)

    elseif msg.type == "list_inventory" then
        rednet.send(cid, { type="inventory_list", items=listInv(uname) }, PROTOCOL)

    elseif msg.type == "withdraw" then
        local ok, r = doWithdraw(uname, msg.name, msg.count or 1)
        if ok then addLog(uname, "Withdrew x" .. r .. " " .. msg.name) end
        rednet.send(cid, { type="action_result", ok=ok, err=not ok and r or nil }, PROTOCOL)

    elseif msg.type == "deposit" then
        local ok, r = doDeposit(uname, msg.name, msg.count or 1)
        if ok then addLog(uname, "Deposited x" .. r .. " " .. msg.name) end
        rednet.send(cid, { type="action_result", ok=ok, err=not ok and r or nil }, PROTOCOL)

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
        print("Created user: " .. msg.username)

    elseif msg.type == "admin_delete_user" then
        if not sess.isAdmin then rednet.send(cid, { type="error", err="Not authorized" }, PROTOCOL) return end
        accounts[msg.username] = nil
        save()
        rednet.send(cid, { type="action_result", ok=true }, PROTOCOL)

    elseif msg.type == "admin_view_vault" then
        if not sess.isAdmin then rednet.send(cid, { type="error", err="Not authorized" }, PROTOCOL) return end
        rednet.send(cid, { type="vault_list", items=listVault(msg.username) }, PROTOCOL)

    elseif msg.type == "admin_view_inventory" then
        if not sess.isAdmin then rednet.send(cid, { type="error", err="Not authorized" }, PROTOCOL) return end
        rednet.send(cid, { type="inventory_list", items=listInv(msg.username) }, PROTOCOL)

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
while true do
    local cid, msg = rednet.receive(PROTOCOL)
    handle(cid, msg)
end