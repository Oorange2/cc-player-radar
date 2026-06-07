-- Cloud User v3
local PROTOCOL = "cloud_ui"

local modemSide = nil
for _, s in ipairs({"top","bottom","left","right","front","back"}) do
    if peripheral.getType(s) == "modem" then modemSide = s break end
end
if not modemSide then error("No wireless modem found") end
rednet.open(modemSide)

local W, H     = term.getSize()
local serverId = nil
local token    = nil
local username = nil
local isAdmin  = false

local iconColors = {
    colors.orange, colors.magenta, colors.lightBlue, colors.yellow,
    colors.lime, colors.pink, colors.cyan, colors.purple,
    colors.blue, colors.brown, colors.green, colors.red,
}
local function itemColor(name)
    local h = 0
    for i = 1, #name do h = (h * 31 + string.byte(name, i)) % #iconColors end
    return iconColors[h + 1]
end

local function rpc(msg, timeout)
    if serverId then rednet.send(serverId, msg, PROTOCOL)
    else rednet.broadcast(msg, PROTOCOL) end
    local id, res = rednet.receive(PROTOCOL, timeout or 5)
    if id then serverId = id end
    return res
end

-- Login
local function doLogin()
    while true do
        term.setBackgroundColor(colors.black) term.clear()
        term.setBackgroundColor(colors.blue) term.setTextColor(colors.white)
        term.setCursorPos(1,1) term.clearLine() term.write(" Cloud Storage")
        term.setBackgroundColor(colors.black) term.setTextColor(colors.white)
        term.setCursorPos(1,3) term.write("Username: ")
        local uname = read()
        term.setCursorPos(1,4) term.write("Password: ")
        local pass = read("*")
        local res = rpc({ type="login", username=uname, password=pass })
        if res and res.ok then
            token=res.token username=uname isAdmin=res.isAdmin or false return
        else
            term.setCursorPos(1,6) term.setTextColor(colors.red)
            term.write((res and res.err) or "Server not found")
            term.setCursorPos(1,7) term.setTextColor(colors.gray) term.write("Press any key...")
            os.pullEvent("key")
        end
    end
end

-- Shared item list UI
local function itemListUI(cfg)
    local items       = {}
    local filtered    = {}
    local selected    = 1
    local scroll      = 0
    local shiftHeld   = false
    local sendCount   = 1
    local searchMode  = false
    local searchQuery = ""
    local message     = ""
    local msgTimer    = 0
    local postTimer   = nil
    local fetchErr    = nil

    local function doFetch()
        local res = cfg.fetchFn()
        items    = res.items or {}
        fetchErr = res.err
        return items
    end

    local function applyFilter()
        local prev = filtered[selected] and filtered[selected].name
        if searchQuery == "" then
            filtered = items
        else
            local q = searchQuery:lower()
            filtered = {}
            for _, item in ipairs(items) do
                if (item.displayName or item.name):lower():find(q,1,true) then
                    table.insert(filtered, item)
                end
            end
        end
        selected = 1
        scroll   = 0
        if prev then
            for i, item in ipairs(filtered) do
                if item.name == prev then
                    selected = i
                    if selected <= scroll then scroll = selected-1
                    elseif selected > scroll+(H-2) then scroll = selected-(H-2) end
                    return
                end
            end
        end
    end

    doFetch()
    applyFilter()

    local function draw()
        term.setBackgroundColor(colors.black) term.clear()
        term.setBackgroundColor(colors.blue) term.setTextColor(colors.white)
        term.setCursorPos(1,1) term.clearLine()
        local cur  = filtered[selected]
        local cap  = cur and math.min(sendCount, cur.count) or sendCount
        local cLbl = " x"..cap
        if searchMode then
            local pr = "/"..searchQuery
            term.write(pr..string.rep(" ",math.max(0,W-#pr-#cLbl))..cLbl)
        else
            local hdr = " "..cfg.title.." ["..#filtered.."]"
            term.write(hdr..string.rep(" ",math.max(0,W-#hdr-#cLbl))..cLbl)
        end
        if fetchErr and #filtered == 0 then
            term.setCursorPos(1,3)
            term.setBackgroundColor(colors.black) term.setTextColor(colors.red)
            local s = fetchErr
            local row = 0
            while #s > 0 and row+3 < H do
                row = row+1
                term.setCursorPos(1, row+2) term.write(s:sub(1,W))
                s = s:sub(W+1)
            end
        else
            for row = 1, H-2 do
                local idx  = row+scroll
                local item = filtered[idx]
                term.setCursorPos(1, row+1)
                if item then
                    local isSel = idx == selected
                    term.setBackgroundColor(itemColor(item.name)) term.setTextColor(colors.black) term.write("  ")
                    local cs  = "x"..item.count
                    local lbl = (item.displayName or item.name):sub(1, W-3-#cs)
                    term.setBackgroundColor(isSel and colors.gray or colors.black)
                    term.setTextColor(isSel and colors.yellow or colors.white)
                    term.write(" "..lbl)
                    term.setTextColor(colors.cyan)
                    term.write(string.rep(" ", math.max(0,W-3-#lbl-#cs))..cs)
                else
                    term.setBackgroundColor(colors.black) term.write(string.rep(" ",W))
                end
            end
        end
        term.setCursorPos(1,H) term.setBackgroundColor(colors.black)
        if message ~= "" and os.clock() < msgTimer then
            term.setTextColor(colors.lime) term.write(message:sub(1,W))
        elseif searchMode then
            term.setTextColor(colors.gray) term.write("Bksp=cancel  Enter=confirm")
        else
            term.setTextColor(colors.gray) term.write("R=refresh  Q=back")
        end
    end

    while true do
        draw()
        local event, p1 = os.pullEvent()
        if event == "term_resize" then shiftHeld=false W,H=term.getSize() end
        if searchMode then
            if event == "char" then
                searchQuery = searchQuery..p1
                applyFilter()
            elseif event == "key" then
                if p1 == keys.backspace then
                    if searchQuery == "" then searchMode=false applyFilter()
                    else searchQuery=searchQuery:sub(1,-2) applyFilter() end
                elseif p1 == keys.enter then
                    searchMode = false
                end
            end
        else
            if event == "key" then
                if p1 == keys.leftShift or p1 == keys.rightShift then
                    shiftHeld = true
                elseif p1 == keys.up then
                    if selected > 1 then
                        selected = selected-1
                        if selected <= scroll then scroll = scroll-1 end
                    end
                elseif p1 == keys.down then
                    if selected < #filtered then
                        selected = selected+1
                        if selected > scroll+(H-2) then scroll = scroll+1 end
                    end
                elseif p1 == keys.enter then
                    local stack = shiftHeld
                    shiftHeld = false
                    local item = filtered[selected]
                    if item and not cfg.readOnly and cfg.actionFn then
                        local amt = math.min(stack and 64 or sendCount, item.count)
                        local ok, err = cfg.actionFn(item, amt)
                        if ok then
                            message  = cfg.actionLabel.." x"..amt..": "..(item.displayName or item.name)
                            msgTimer = os.clock()+3
                            postTimer = os.startTimer(1)
                        else
                            message  = err or "Failed"
                            msgTimer = os.clock()+3
                        end
                    end
                elseif p1 == keys.r then
                    doFetch() applyFilter() message="Refreshed" msgTimer=os.clock()+1
                elseif p1 == keys.q then
                    return
                elseif p1 == keys.slash then
                    searchMode=true searchQuery="" applyFilter()
                end
            elseif event == "key_up" then
                if p1 == keys.leftShift or p1 == keys.rightShift then shiftHeld=false end
            elseif event == "mouse_scroll" then
                if shiftHeld then
                    local cur = filtered[selected]
                    sendCount = math.max(1, math.min(sendCount-p1, cur and cur.count or 9999))
                else
                    if p1 == -1 and selected > 1 then
                        selected = selected-1
                        if selected <= scroll then scroll=scroll-1 end
                    elseif p1 == 1 and selected < #filtered then
                        selected = selected+1
                        if selected > scroll+(H-2) then scroll=scroll+1 end
                    end
                end
            elseif event == "timer" and p1 == postTimer then
                postTimer = nil
                doFetch()
                applyFilter()
            end
        end
    end
end

-- Log screen
local function logScreen()
    local res = rpc({ type="get_log", token=token })
    local log = (res and res.log) or {}
    local scroll = 0
    while true do
        term.setBackgroundColor(colors.black) term.clear()
        term.setBackgroundColor(colors.blue) term.setTextColor(colors.white)
        term.setCursorPos(1,1) term.clearLine() term.write(" Activity Log ["..#log.."]")
        for row = 1, H-2 do
            local idx = #log - scroll - row + 1
            term.setCursorPos(1, row+1) term.setBackgroundColor(colors.black)
            if log[idx] then
                term.setTextColor(colors.white)
                term.write((log[idx].event or ""):sub(1,W))
            else
                term.setTextColor(colors.black) term.write(string.rep(" ",W))
            end
        end
        term.setCursorPos(1,H) term.setTextColor(colors.gray) term.write("Scroll=browse  Q=back")
        local ev, p1 = os.pullEvent()
        if ev == "key" then
            if p1 == keys.q then return
            elseif p1 == keys.up then scroll=math.max(0,scroll-1)
            elseif p1 == keys.down then scroll=math.min(math.max(0,#log-(H-2)),scroll+1) end
        elseif ev == "mouse_scroll" then
            scroll = math.max(0, math.min(scroll+p1, math.max(0,#log-(H-2))))
        end
    end
end

-- User menu
local function userMenu()
    local opts = {"Withdraw","Deposit","Log","Logout"}
    local sel  = 1
    while true do
        term.setBackgroundColor(colors.black) term.clear()
        term.setBackgroundColor(colors.blue) term.setTextColor(colors.white)
        term.setCursorPos(1,1) term.clearLine() term.write(" Cloud - "..username)
        for i, opt in ipairs(opts) do
            term.setCursorPos(3, i+2)
            if i == sel then term.setBackgroundColor(colors.gray) term.setTextColor(colors.yellow)
            else term.setBackgroundColor(colors.black) term.setTextColor(colors.white) end
            term.clearLine() term.write(" "..opt)
        end
        term.setBackgroundColor(colors.black)
        local ev, p1 = os.pullEvent("key")
        if p1 == keys.up and sel > 1 then sel=sel-1
        elseif p1 == keys.down and sel < #opts then sel=sel+1
        elseif p1 == keys.enter then
            if sel == 1 then
                itemListUI({
                    title="Withdraw", actionLabel="Withdrew",
                    fetchFn=function()
                        local r = rpc({type="list_vault", token=token})
                        return r or {}
                    end,
                    actionFn=function(item, amt)
                        local r = rpc({type="withdraw", token=token, name=item.name, displayName=item.displayName, count=amt}, 10)
                        return r and r.ok, r and r.err
                    end,
                })
            elseif sel == 2 then
                itemListUI({
                    title="Deposit", actionLabel="Deposited",
                    fetchFn=function()
                        local r = rpc({type="list_inventory", token=token})
                        return r or {}
                    end,
                    actionFn=function(item, amt)
                        local r = rpc({type="deposit", token=token, name=item.name, displayName=item.displayName, count=amt}, 10)
                        return r and r.ok, r and r.err
                    end,
                })
            elseif sel == 3 then
                logScreen()
            elseif sel == 4 then
                token=nil username=nil isAdmin=false return
            end
        end
    end
end

-- Admin: pick user from list, returns username or nil
local function pickUser()
    local res   = rpc({type="admin_list_users", token=token})
    local ulist = (res and res.users) or {}
    if #ulist == 0 then return nil, "No users found" end
    local usel = 1
    local uscr = 0
    while true do
        term.setBackgroundColor(colors.black) term.clear()
        term.setBackgroundColor(colors.blue) term.setTextColor(colors.white)
        term.setCursorPos(1,1) term.clearLine() term.write(" Select User")
        for row = 1, H-2 do
            local u = ulist[row+uscr]
            term.setCursorPos(1, row+1)
            if u then
                if row+uscr == usel then
                    term.setBackgroundColor(colors.gray) term.setTextColor(colors.yellow)
                else
                    term.setBackgroundColor(colors.black) term.setTextColor(colors.white)
                end
                term.clearLine() term.write(" "..(u.username or ""):sub(1,W-2))
            else
                term.setBackgroundColor(colors.black) term.write(string.rep(" ",W))
            end
        end
        term.setCursorPos(1,H) term.setBackgroundColor(colors.black)
        term.setTextColor(colors.gray) term.write("Enter=select  Q=back")
        local ev, p1 = os.pullEvent()
        if ev == "key" then
            if p1 == keys.q then return nil
            elseif p1 == keys.up and usel > 1 then
                usel = usel-1
                if usel <= uscr then uscr=usel-1 end
            elseif p1 == keys.down and usel < #ulist then
                usel = usel+1
                if usel > uscr+(H-2) then uscr=uscr+1 end
            elseif p1 == keys.enter then
                return ulist[usel] and ulist[usel].username
            end
        elseif ev == "mouse_scroll" then
            if p1 == -1 and usel > 1 then
                usel=usel-1 if usel<=uscr then uscr=usel-1 end
            elseif p1 == 1 and usel < #ulist then
                usel=usel+1 if usel>uscr+(H-2) then uscr=uscr+1 end
            end
        end
    end
end

-- Admin menu
local function adminMenu()
    local opts = {"List Users","Create User","Manage User","Debug Peripherals","Logout"}
    local sel  = 1
    local msg2 = ""
    local mt2  = 0
    while true do
        term.setBackgroundColor(colors.black) term.clear()
        term.setBackgroundColor(colors.blue) term.setTextColor(colors.white)
        term.setCursorPos(1,1) term.clearLine() term.write(" Cloud Admin")
        for i, opt in ipairs(opts) do
            term.setCursorPos(3, i+2)
            if i == sel then term.setBackgroundColor(colors.gray) term.setTextColor(colors.yellow)
            else term.setBackgroundColor(colors.black) term.setTextColor(colors.white) end
            term.clearLine() term.write(" "..opt)
        end
        term.setCursorPos(1,H) term.setBackgroundColor(colors.black)
        if msg2 ~= "" and os.clock() < mt2 then
            term.setTextColor(colors.lime) term.write(msg2:sub(1,W))
        else
            msg2 = ""
        end
        local ev, p1 = os.pullEvent("key")
        if p1 == keys.up and sel > 1 then sel=sel-1
        elseif p1 == keys.down and sel < #opts then sel=sel+1
        elseif p1 == keys.enter then

            if sel == 1 then
                -- List users (read-only view)
                local res   = rpc({type="admin_list_users", token=token})
                local users = (res and res.users) or {}
                local us    = 0
                while true do
                    term.setBackgroundColor(colors.black) term.clear()
                    term.setBackgroundColor(colors.blue) term.setTextColor(colors.white)
                    term.setCursorPos(1,1) term.clearLine() term.write(" Users ["..#users.."]")
                    for row = 1, H-2 do
                        local u = users[row+us]
                        term.setCursorPos(1, row+1) term.setBackgroundColor(colors.black)
                        if u then
                            term.setTextColor(colors.yellow) term.write(u.username:sub(1,12))
                            term.setTextColor(colors.gray) term.write("  "..(u.vault or "no vault"):sub(1,W-14))
                        else
                            term.setTextColor(colors.black) term.write(string.rep(" ",W))
                        end
                    end
                    term.setCursorPos(1,H) term.setTextColor(colors.gray) term.write("Scroll=browse  Q=back")
                    local ev2, p2 = os.pullEvent()
                    if ev2=="key" and p2==keys.q then break
                    elseif ev2=="mouse_scroll" then us=math.max(0,math.min(us+p2,math.max(0,#users-(H-2))))
                    elseif ev2=="key" then
                        if p2==keys.up then us=math.max(0,us-1)
                        elseif p2==keys.down then us=math.min(math.max(0,#users-(H-2)),us+1) end
                    end
                end

            elseif sel == 2 then
                -- Create user
                term.setBackgroundColor(colors.black) term.clear()
                term.setBackgroundColor(colors.blue) term.setTextColor(colors.white)
                term.setCursorPos(1,1) term.clearLine() term.write(" Create User")
                term.setBackgroundColor(colors.black) term.setTextColor(colors.white)
                local function prompt(row, label)
                    term.setCursorPos(1,row) term.write(label) return read()
                end
                local uname = prompt(3,"Username:   ")
                local pass  = prompt(4,"Password:   ")
                local vnum  = prompt(5,"Vault #:    ")
                local imnum = prompt(6,"InvMgr #:   ")
                local vdir  = prompt(7,"VaultDir:   ")
                if vdir == "" then vdir = "back" end
                local vault  = "create:item_vault_"..vnum
                local invmgr = "inventory_manager_"..imnum
                local r = rpc({type="admin_create_user", token=token,
                    username=uname, password=pass, vault=vault, invmanager=invmgr, vaultDir=vdir}, 10)
                if r and r.ok then msg2="Created: "..uname mt2=os.clock()+3
                else msg2=(r and r.err) or "Failed" mt2=os.clock()+3 end

            elseif sel == 3 then
                -- Manage user - pick from list
                local target, err = pickUser()
                if not target then
                    if err then msg2=err mt2=os.clock()+2 end
                else
                    local subOpts = {"View Vault","View Inventory","Withdraw","Deposit","Delete User","Back"}
                    local subSel  = 1
                    while true do
                        term.setBackgroundColor(colors.black) term.clear()
                        term.setBackgroundColor(colors.blue) term.setTextColor(colors.white)
                        term.setCursorPos(1,1) term.clearLine() term.write(" Manage: "..target)
                        for i, opt in ipairs(subOpts) do
                            term.setCursorPos(3, i+2)
                            if i == subSel then term.setBackgroundColor(colors.gray) term.setTextColor(colors.yellow)
                            else term.setBackgroundColor(colors.black) term.setTextColor(colors.white) end
                            term.clearLine() term.write(" "..opt)
                        end
                        term.setBackgroundColor(colors.black)
                        local ev3, p3 = os.pullEvent("key")
                        if p3 == keys.up and subSel > 1 then subSel=subSel-1
                        elseif p3 == keys.down and subSel < #subOpts then subSel=subSel+1
                        elseif p3 == keys.enter then
                            if subSel == 1 then
                                itemListUI({title=target.." Vault", readOnly=true,
                                    fetchFn=function()
                                        local r=rpc({type="admin_view_vault",token=token,username=target})
                                        return r or {} end})
                            elseif subSel == 2 then
                                itemListUI({title=target.." Inventory", readOnly=true,
                                    fetchFn=function()
                                        local r=rpc({type="admin_view_inventory",token=token,username=target})
                                        return r or {} end})
                            elseif subSel == 3 then
                                itemListUI({title="Withdraw: "..target, actionLabel="Withdrew",
                                    fetchFn=function()
                                        local r=rpc({type="admin_view_vault",token=token,username=target})
                                        return r or {} end,
                                    actionFn=function(item,amt)
                                        local r=rpc({type="admin_withdraw",token=token,username=target,name=item.name,count=amt},10)
                                        return r and r.ok, r and r.err end})
                            elseif subSel == 4 then
                                itemListUI({title="Deposit: "..target, actionLabel="Deposited",
                                    fetchFn=function()
                                        local r=rpc({type="admin_view_inventory",token=token,username=target})
                                        return r or {} end,
                                    actionFn=function(item,amt)
                                        local r=rpc({type="admin_deposit",token=token,username=target,name=item.name,count=amt},10)
                                        return r and r.ok, r and r.err end})
                            elseif subSel == 5 then
                                term.setBackgroundColor(colors.black) term.clear()
                                term.setCursorPos(1,3) term.setTextColor(colors.red)
                                term.write("Delete "..target.."? (Y/N) ")
                                local ev4, p4 = os.pullEvent("key")
                                if p4 == keys.y then
                                    local r = rpc({type="admin_delete_user",token=token,username=target},10)
                                    if r and r.ok then msg2="Deleted: "..target mt2=os.clock()+3 break end
                                end
                            elseif subSel == 6 then
                                break
                            end
                        end
                    end
                end

            elseif sel == 4 then
                -- Debug peripherals
                local res   = rpc({type="debug_peripherals"})
                local names = (res and res.names) or {}
                local ds    = 0
                while true do
                    term.setBackgroundColor(colors.black) term.clear()
                    term.setBackgroundColor(colors.blue) term.setTextColor(colors.white)
                    term.setCursorPos(1,1) term.clearLine() term.write(" Server Peripherals ["..#names.."]")
                    for row = 1, H-2 do
                        local n = names[row+ds]
                        term.setCursorPos(1, row+1) term.setBackgroundColor(colors.black)
                        if n then term.setTextColor(colors.white) term.write(n:sub(1,W))
                        else term.setTextColor(colors.black) term.write(string.rep(" ",W)) end
                    end
                    term.setCursorPos(1,H) term.setTextColor(colors.gray) term.write("Scroll=browse  Q=back")
                    local ev2, p2 = os.pullEvent()
                    if ev2=="key" and p2==keys.q then break
                    elseif ev2=="mouse_scroll" then ds=math.max(0,math.min(ds+p2,math.max(0,#names-(H-2))))
                    elseif ev2=="key" then
                        if p2==keys.up then ds=math.max(0,ds-1)
                        elseif p2==keys.down then ds=math.min(math.max(0,#names-(H-2)),ds+1) end
                    end
                end

            elseif sel == 5 then
                token=nil username=nil isAdmin=false return
            end

        end
    end
end

while true do
    doLogin()
    if isAdmin then adminMenu() else userMenu() end
end