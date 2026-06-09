-- Cloud Solutions Billboard v1
-- Connect a 3x4 Advanced Monitor above/beside this computer
-- Adjust SCALE below if text is too big or too small

local SCALE = 1   -- try 0.5 for more content, 1.5 for bigger text

-- ── Find monitor ─────────────────────────────────────────────────────────────
local mon, monSide
for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "monitor" then
        mon     = peripheral.wrap(name)
        monSide = name
        break
    end
end
if not mon then
    print("ERROR: No monitor connected!")
    print("Attach an advanced monitor then rerun.")
    return
end

mon.setTextScale(SCALE)
local W, H = mon.getSize()

-- ── State ─────────────────────────────────────────────────────────────────────
local page    = "main"
local tutPage = 1
local NUM_TUT = 4
local btns    = {}

-- ── Drawing helpers ───────────────────────────────────────────────────────────
local function cls()
    mon.setBackgroundColor(colors.black) mon.clear()
end

local function fillRow(y, bg, fg, txt)
    mon.setBackgroundColor(bg) mon.setTextColor(fg or colors.white)
    mon.setCursorPos(1, y) mon.write(string.rep(" ", W))
    if txt then
        local x = math.max(1, math.floor((W - #txt) / 2) + 1)
        mon.setCursorPos(x, y) mon.write(txt)
    end
end

local function cw(y, txt, fg, bg)
    mon.setBackgroundColor(bg or colors.black)
    mon.setTextColor(fg or colors.white)
    local x = math.max(1, math.floor((W - #txt) / 2) + 1)
    mon.setCursorPos(x, y) mon.write(txt)
end

local function lw(y, txt, fg, bg, x0)
    x0 = x0 or 2
    mon.setBackgroundColor(bg or colors.black)
    mon.setTextColor(fg or colors.white)
    mon.setCursorPos(x0, y) mon.write(txt:sub(1, W - x0))
end

local function div(y, char, fg)
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(fg or colors.gray)
    mon.setCursorPos(1, y) mon.write(string.rep(char or "-", W))
end

-- ── Button system ─────────────────────────────────────────────────────────────
local function regBtn(x1, x2, y, fn)
    table.insert(btns, {x1=x1, x2=x2, y=y, fn=fn})
end

-- Draws a button, registers click zone, returns x position after button
local function drawBtn(x, y, label, fg, bg, fn)
    local txt = " " .. label .. " "
    mon.setBackgroundColor(bg or colors.blue)
    mon.setTextColor(fg or colors.white)
    mon.setCursorPos(x, y) mon.write(txt)
    regBtn(x, x + #txt - 1, y, fn)
    return x + #txt
end

local function handleClick(mx, my)
    for _, b in ipairs(btns) do
        if my == b.y and mx >= b.x1 and mx <= b.x2 then
            b.fn() return
        end
    end
end

-- ═════════════════════════════════════════════════════════════════════════════
--  MAIN PAGE
-- ═════════════════════════════════════════════════════════════════════════════
local function drawMain()
    W, H = mon.getSize()
    cls() btns = {}

    -- ── BOTTOM-ANCHORED fixed rows (always visible) ──
    -- H   : footer
    -- H-1 : CTA button
    -- H-2 : divider
    -- H-3 : contact
    -- H-4 : pricing
    -- H-5 : divider

    fillRow(H,   colors.black, colors.gray, "Cloud Solutions  --  Always Online")
    fillRow(H-1, colors.blue)
    cw(H-1, "[ Click Here  --  Controls & Setup Guide ]", colors.white, colors.blue)
    regBtn(1, W, H-1, function() page="tutorial" tutPage=1 end)
    div(H-2, "-", colors.gray)
    fillRow(H-3, colors.gray, colors.white,  "cypu  /  ooranges  /  Lux_silver")
    fillRow(H-4, colors.gray, colors.yellow, "First-time setup: only 6 Spurs!")
    div(H-5, "=", colors.gray)

    -- ── TOP-ANCHORED header (rows 1-3) ──
    fillRow(1, colors.blue, colors.white,     "CLOUD  SOLUTIONS")
    fillRow(2, colors.blue, colors.lightBlue, "Secure Vaults & Banking  |  CC:Tweaked")
    div(3, "=", colors.cyan)

    -- ── Services: fill rows 4 .. H-6 ──
    local svcs = {
        { colors.lime,      "VAULT STORAGE",      "Your items, locked away safely"          },
        { colors.cyan,      "DEPOSIT / WITHDRAW",  "Drop off or pick up from a pocket PC"   },
        { colors.yellow,    "BANKING",             "2%/day interest on deposited Spurs"      },
        { colors.orange,    "LOANS",               "Borrow spurs, repay in 5 irl days"      },
        { colors.pink,      "MARKETPLACE",         "Buy & sell items with other players"     },
        { colors.magenta,   "CREDIT SCORE",        "Good history = lower loan rates"         },
        { colors.lightBlue, "ACTIVITY LOG",        "Every transaction on record"             },
    }

    local svcTop = 4
    local svcBot = H - 6        -- last usable row before bottom block
    local svcRows = svcBot - svcTop + 1
    local rowsPer = math.floor(svcRows / #svcs)  -- rows per service (1 or 2)

    for i, s in ipairs(svcs) do
        local y = svcTop + (i - 1) * rowsPer
        if y > svcBot then break end

        -- Label row
        mon.setCursorPos(2, y)
        mon.setBackgroundColor(colors.black) mon.setTextColor(s[1])
        if rowsPer >= 2 then
            -- Two-row format: label then description
            mon.write((">> " .. s[2]):sub(1, W - 2))
            if y + 1 <= svcBot then
                mon.setCursorPos(4, y + 1)
                mon.setTextColor(colors.lightGray)
                mon.write(s[3]:sub(1, W - 4))
            end
        else
            -- Single-row: label + abbreviated description inline
            local lbl = ">> " .. s[2]
            local desc = "  " .. s[3]
            local space = W - 2 - #lbl
            mon.write(lbl)
            if space > 6 then
                mon.setTextColor(colors.lightGray)
                mon.write(desc:sub(1, space))
            end
        end
    end
end

-- ═════════════════════════════════════════════════════════════════════════════
--  TUTORIAL PAGES
-- ═════════════════════════════════════════════════════════════════════════════
local tutContent = {

    -- ── Page 1: Getting Started ──────────────────────────────────────────────
    function()
        fillRow(1, colors.green, colors.black, "HOW TO GET STARTED")
        div(2, "=", colors.green)

        lw(3,  "Requirements:", colors.yellow)
        lw(4,  "  6 Numismatic Spurs in your inventory", colors.white)

        div(5, "-", colors.gray)
        lw(6,  "Steps:", colors.yellow)
        lw(7,  "  1. Find an admin and ask to sign up", colors.white)
        lw(8,  "  2. Give them 6 Spurs as the setup fee", colors.white)
        lw(9,  "  3. Admin creates your account & links", colors.white)
        lw(10, "     your personal item vault for you", colors.white)
        lw(11, "  4. Log in at the terminal below this", colors.white)
        lw(12, "     screen using your new username &", colors.white)
        lw(13, "     password. You're ready to go!", colors.lime)

        div(14, "-", colors.gray)
        lw(15, "Admins to contact:", colors.yellow)
        lw(16, "  cypu", colors.lime)
        lw(17, "  ooranges", colors.lime)
        lw(18, "  Lux_silver", colors.lime)
    end,

    -- ── Page 2: Controls ─────────────────────────────────────────────────────
    function()
        fillRow(1, colors.cyan, colors.black, "CONTROLS GUIDE")
        div(2, "=", colors.cyan)

        local KW = math.floor(W * 0.42)  -- key column width
        local function ctrl(y, col, key, desc)
            mon.setCursorPos(2, y)
            mon.setBackgroundColor(colors.black) mon.setTextColor(col)
            local k = key:sub(1, KW)
            mon.write(k .. string.rep(" ", KW - #k))
            mon.setTextColor(colors.lightGray)
            mon.write(desc:sub(1, W - KW - 2))
        end

        ctrl(3,  colors.yellow, "Left click item",     "Select + show quantity")
        ctrl(4,  colors.yellow, "Left click again",    "Confirm & move item")
        ctrl(5,  colors.orange, "Right click item",    "Send full stack (64) instantly")
        ctrl(6,  colors.lime,   "Scroll on item",      "Adjust quantity up / down")
        ctrl(7,  colors.cyan,   "/ key",               "Search items by name")
        ctrl(8,  colors.cyan,   "R key",               "Refresh the item list")
        ctrl(9,  colors.red,    "Q key",               "Back / deselect current item")
        ctrl(10, colors.gray,   "< Back button",       "Return to previous screen")

        div(11, "-", colors.gray)
        lw(12, "The terminal is a Pocket Computer.", colors.lightGray)
        lw(13, "Carry it with you to access your vault", colors.lightGray)
        lw(14, "from anywhere on the server.", colors.lightGray)
    end,

    -- ── Page 3: Banking Guide ─────────────────────────────────────────────────
    function()
        fillRow(1, colors.yellow, colors.black, "BANKING GUIDE")
        div(2, "=", colors.yellow)

        lw(3,  "DEPOSIT INTEREST", colors.lime)
        lw(4,  "  Bank your Spurs to earn passive income.", colors.white)
        lw(5,  "  2% interest added every real-life day.", colors.lime)
        lw(6,  "  Compounds automatically -- no action needed.", colors.white)
        lw(7,  "  Withdraw anytime to your item vault.", colors.white)

        div(8, "-", colors.gray)
        lw(9,  "LOANS", colors.orange)
        lw(10, "  Borrow Spurs against your credit score.", colors.white)
        lw(11, "  Daily interest accrues -- repay in 5 irl days.", colors.white)
        lw(12, "  Pay on time: +20 to +40 credit score.", colors.lime)
        lw(13, "  Late payment: -100 credit score!", colors.red)

        div(14, "-", colors.gray)
        lw(15, "CREDIT SCORE TIERS", colors.magenta)
        lw(16, "  300+ Eligible  |  600+ Good  |  800+ Excellent", colors.white)
        lw(17, "  Better score = lower loan interest rate.", colors.lightGray)
    end,

    -- ── Page 4: Marketplace Guide ─────────────────────────────────────────────
    function()
        fillRow(1, colors.pink, colors.black, "MARKETPLACE GUIDE")
        div(2, "=", colors.pink)

        lw(3,  "BUYING ITEMS", colors.lime)
        lw(4,  "  Open the Market tab on your pocket PC.", colors.white)
        lw(5,  "  Browse listings and tap to see details.", colors.white)
        lw(6,  "  Payment is taken from your bank balance.", colors.white)
        lw(7,  "  Items are delivered straight to your vault.", colors.lime)

        div(8, "-", colors.gray)
        lw(9,  "SELLING ITEMS", colors.yellow)
        lw(10, "  Go to My Listings and create a listing.", colors.white)
        lw(11, "  Set a lot size (items per purchase) & price.", colors.white)
        lw(12, "  Add stock from your inventory or vault.", colors.white)
        lw(13, "  5% market tax deducted from each sale.", colors.orange)

        div(14, "-", colors.gray)
        lw(15, "NOTES", colors.lightGray)
        lw(16, "  Listings with no stock for 3+ days are", colors.lightGray)
        lw(17, "  removed automatically. Keep stock topped up!", colors.lightGray)
    end,
}

local function drawTutorial()
    W, H = mon.getSize()
    cls() btns = {}

    -- Draw page content
    if tutContent[tutPage] then tutContent[tutPage]() end

    -- ── Nav bar ──
    div(H - 2, "=", colors.gray)
    fillRow(H - 1, colors.black)
    fillRow(H, colors.black, colors.gray,
        "Cloud Solutions  --  Page " .. tutPage .. "/" .. NUM_TUT)

    -- Main menu (left)
    drawBtn(2, H - 1, "< Main Menu", colors.white, colors.gray,
        function() page = "main" end)

    -- Prev (mid-left, only if not first page)
    if tutPage > 1 then
        local px = math.floor(W * 0.45)
        drawBtn(px, H - 1, "< Prev", colors.white, colors.blue,
            function() tutPage = tutPage - 1 end)
    end

    -- Next (right, only if not last page)
    if tutPage < NUM_TUT then
        drawBtn(W - 8, H - 1, "Next >", colors.white, colors.blue,
            function() tutPage = tutPage + 1 end)
    else
        -- Last page: show a "Done" hint
        cw(H - 1, "That's everything!", colors.lime, colors.black)
    end
end

-- ═════════════════════════════════════════════════════════════════════════════
--  MAIN LOOP
-- ═════════════════════════════════════════════════════════════════════════════
local function draw()
    if page == "main" then
        drawMain()
    else
        drawTutorial()
    end
end

-- Auto-reset: return to main page after 60 seconds of no interaction
local TIMEOUT  = 60
local timerId  = nil

local function resetTimer()
    if timerId then os.cancelTimer(timerId) end
    timerId = os.startTimer(TIMEOUT)
end

-- Initial draw + start timer
draw()
resetTimer()

-- Event loop
while true do
    local ev, p1, p2, p3 = os.pullEvent()
    W, H = mon.getSize()
    if ev == "monitor_touch" then
        -- p1=side, p2=x, p3=y
        handleClick(p2, p3)
        resetTimer()
        draw()
    elseif ev == "timer" and p1 == timerId then
        if page ~= "main" then
            page = "main"
            draw()
        end
        resetTimer()  -- keep the timer ticking on main page too
    end
end
