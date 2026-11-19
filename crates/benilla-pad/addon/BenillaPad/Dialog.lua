-- NPC dialogue as subtitles. With a pad connected and the "NPC dialogue" setting on Subtitles,
-- a gossip or quest interaction shows here instead of the stock GossipFrame / QuestFrame: a band
-- low in the middle of the screen with the NPC's round portrait, its name in gold, its words in
-- white (paged five lines at a time: A turns the page), then the rewards and the answers as
-- rows, a glyph and a word. While it is up the pad is in the "dialog" mode, which the Rust side
-- treats as any window of ours: every button arrives as BENILLAPAD_NAV, the body stays put.
--
-- The stock windows keep running unseen underneath (moved off the screen, alpha 0): they are
-- never hidden by us, since their OnHide closes the interaction. Our answers go through the
-- gossip and quest API, and the stock windows change or close from their own events.
-- The layout follows ImprovedForever_Immersion's NpcDialog.lua (MIT, THIRD-PARTY-NOTICES.md):
-- its band at 210 px, round face, gold name, 30 px reward icons, glyph + word answers. The Lua is
-- our own, for Lua 5.0 and the 1.12 API.

local P = BenillaPad
local Dialog = {}
P.Dialog = Dialog

local C = P.COLOR
local WIDTH = 560
local BOTTOM_Y = 210
local PAD = 16
local FACE = 46
local TEXT_W = WIDTH - 2 * PAD
local BODY_FONT = "GameFontHighlight"
-- The body's lines a page, and a line's height in that font.
local LINES = 5
local LINE_H = 15
local ROW_H = 24
local ROW_MAX = 14
local ITEM = 30
local ITEM_MAX = 13
local CELL_W = (TEXT_W - 8) / 2
local CELL_H = ITEM + 6
local SECTION_MAX = 3

-- ── The panel ──

local win = CreateFrame("Frame", "BenillaPadDialog", UIParent)
win:SetWidth(WIDTH)
win:SetHeight(200)
win:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, BOTTOM_Y)
win:SetFrameStrata("DIALOG")
win:EnableMouse(true)
win:Hide()
P.AddPlate(win)
Dialog.frame = win

-- The face: a dark disc, the NPC's portrait (round, SetPortraitTexture), a bronze ring.
local face = CreateFrame("Frame", nil, win)
face:SetWidth(FACE)
face:SetHeight(FACE)
face:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -PAD)
local faceBg = face:CreateTexture(nil, "BACKGROUND")
faceBg:SetTexture(P.ART .. "Disc")
faceBg:SetVertexColor(0, 0, 0, 0.9)
faceBg:SetWidth(FACE - 4)
faceBg:SetHeight(FACE - 4)
faceBg:SetPoint("CENTER", face, "CENTER", 0, 0)
local portrait = face:CreateTexture(nil, "ARTWORK")
portrait:SetWidth(FACE - 6)
portrait:SetHeight(FACE - 6)
portrait:SetPoint("CENTER", face, "CENTER", 0, 0)
local ring = face:CreateTexture(nil, "OVERLAY")
ring:SetTexture(P.ART .. "Ring")
ring:SetVertexColor(0.85, 0.7, 0.42)
ring:SetWidth((FACE - 6) * 1.45)
ring:SetHeight((FACE - 6) * 1.45)
ring:SetPoint("CENTER", face, "CENTER", 0, 0)

local name = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
name:SetJustifyH("LEFT")
P.Paint(name, C.title)
local sub = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
sub:SetJustifyH("LEFT")
P.Paint(sub, C.help)

local body = win:CreateFontString(nil, "OVERLAY", BODY_FONT)
body:SetWidth(TEXT_W)
body:SetJustifyH("LEFT")
body:SetJustifyV("TOP")
body:SetTextColor(1, 1, 1)

local pageText = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
P.Paint(pageText, C.grey)

-- A hidden twin of the body, to measure words for the page breaks.
local measure = win:CreateFontString(nil, "OVERLAY", BODY_FONT)
measure:Hide()

-- The reward and required-item sections: a gold heading, then cells of an icon and a name.
local headings = {}
for i = 1, SECTION_MAX do
    local h = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:SetJustifyH("LEFT")
    P.Paint(h, C.title)
    h:Hide()
    headings[i] = h
end
local moneyText = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
moneyText:SetJustifyH("LEFT")
moneyText:Hide()

local cells = {}
for i = 1, ITEM_MAX do
    local c = CreateFrame("Button", nil, win)
    c:SetWidth(CELL_W)
    c:SetHeight(CELL_H)
    c.select = P.AddSelect(c, { corner = 8 })
    local icon = c:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(ITEM)
    icon:SetHeight(ITEM)
    icon:SetPoint("LEFT", c, "LEFT", 3, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    c.icon = icon
    local count = c:CreateFontString(nil, "OVERLAY")
    count:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 1)
    c.count = count
    local label = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    label:SetWidth(CELL_W - ITEM - 14)
    label:SetJustifyH("LEFT")
    c.label = label
    c.index = i
    c:SetScript("OnClick", function()
        local v = Dialog.view
        if v and this.choice then
            Dialog.choice = this.choice
            Dialog.Layout()
        end
    end)
    c:Hide()
    cells[i] = c
end

-- The answers: the A glyph on the lit one, a mark ("!" / "?") or the gossip icon, the words.
local rows = {}
for i = 1, ROW_MAX do
    local r = CreateFrame("Button", nil, win)
    r:SetWidth(TEXT_W)
    r:SetHeight(ROW_H - 2)
    r.select = P.AddSelect(r, { corner = 8 })
    r.glyph = P.NewGlyph(r, 18, "OVERLAY")
    r.glyph:SetPoint("LEFT", r, "LEFT", 4, 0)
    local mark = r:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    mark:SetPoint("CENTER", r, "LEFT", 34, 0)
    r.mark = mark
    local icon = r:CreateTexture(nil, "OVERLAY")
    icon:SetWidth(16)
    icon:SetHeight(16)
    icon:SetPoint("CENTER", r, "LEFT", 34, 0)
    r.icon = icon
    local text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", r, "LEFT", 48, 0)
    text:SetWidth(TEXT_W - 56)
    text:SetJustifyH("LEFT")
    r.text = text
    r.index = i
    r:SetScript("OnClick", function()
        Dialog.sel = this.index
        Dialog.Activate()
    end)
    r:SetScript("OnEnter", function()
        local v = Dialog.view
        if v and v.rows[this.index] and Dialog.sel ~= this.index then
            Dialog.sel = this.index
            Dialog.Layout()
        end
    end)
    r:Hide()
    rows[i] = r
end

local hint = P.NewHints(win, { size = 18, pad = 0, spacing = 12, font = "GameFontNormalSmall", maxWidth = TEXT_W })
hint:SetPoint("BOTTOM", win, "BOTTOM", 0, 10)

-- ── Text ──

local function textWidth(s)
    measure:SetText(s)
    local w = measure:GetStringWidth() or 0
    if w <= 0 then
        -- No measure yet (the font engine answers later): an average letter.
        w = string.len(s) * 6.5
    end
    return w
end

-- The NPC's words as the stock frames print them: $B is a line break, $N the player's name
-- (the engine expands them; a leftover one is caught here).
local function clean(text)
    text = text or ""
    text = string.gsub(text, "\r", "")
    text = string.gsub(text, "%$[Bb]", "\n")
    local me = UnitName("player") or ""
    text = string.gsub(text, "%$[Nn]", function() return me end)
    return text
end

-- One paragraph's words into lines no wider than the body.
local function wrapParagraph(para, lines)
    local line, pos = "", 1
    while true do
        local s, e, word = string.find(para, "(%S+)", pos)
        if not s then
            break
        end
        pos = e + 1
        local try = word
        if line ~= "" then
            try = line .. " " .. word
        end
        if line ~= "" and textWidth(try) > TEXT_W - 6 then
            table.insert(lines, line)
            line = word
        else
            line = try
        end
    end
    if line ~= "" then
        table.insert(lines, line)
    end
end

-- Text into lines; a blank line between paragraphs is kept, runs of them are one.
local function wrap(text, lines)
    lines = lines or {}
    text = clean(text)
    local start = 1
    while true do
        local at = string.find(text, "\n", start, true)
        local para
        if at then
            para = string.sub(text, start, at - 1)
        else
            para = string.sub(text, start)
        end
        if string.find(para, "%S") then
            wrapParagraph(para, lines)
        else
            local n = table.getn(lines)
            if n > 0 and lines[n] ~= "" then
                table.insert(lines, "")
            end
        end
        if not at then
            break
        end
        start = at + 1
    end
    return lines
end

-- Lines into pages of LINES, no page starting or ending on a blank line.
local function paginate(lines)
    local pages, page = {}, {}
    local function finish()
        while table.getn(page) > 0 and page[table.getn(page)] == "" do
            table.remove(page)
        end
        if table.getn(page) > 0 then
            table.insert(pages, page)
        end
        page = {}
    end
    for i = 1, table.getn(lines) do
        local l = lines[i]
        if not (l == "" and table.getn(page) == 0) then
            table.insert(page, l)
            if table.getn(page) >= LINES then
                finish()
            end
        end
    end
    finish()
    if table.getn(pages) == 0 then
        pages = { {} }
    end
    return pages
end

local function moneyString(copper)
    copper = math.floor(copper or 0)
    local g = math.floor(copper / 10000)
    local s = math.floor(math.mod(copper, 10000) / 100)
    local c = math.mod(copper, 100)
    local out = ""
    if g > 0 then out = out .. "|cffffd700" .. g .. "g|r " end
    if s > 0 then out = out .. "|cffc7c7cf" .. s .. "s|r " end
    if c > 0 or out == "" then out = out .. "|cffeda55f" .. c .. "c|r" end
    return out
end

-- ── The views ──
-- A view: kind, title, lines, sections ({ label, items = { name, icon, count, quality, choice } }),
-- money (text), rows ({ text, mark, icon, run, dim, verb }), back (B) and backVerb, choices.

local function newView(kind)
    return { kind = kind, lines = {}, sections = {}, rows = {}, choices = 0 }
end

local function itemInfo(kind, i)
    if not GetQuestItemInfo then
        return nil
    end
    local ok, iname, tex, count, quality = pcall(GetQuestItemInfo, kind, i)
    if not ok then
        return nil
    end
    return { name = iname or "", icon = tex, count = count or 0, quality = quality or 1 }
end

local function addItems(v, kind, n, label, selectable)
    n = math.min(n or 0, 6)
    if n <= 0 then
        return
    end
    local section = { label = label, items = {} }
    for i = 1, n do
        local it = itemInfo(kind, i)
        if it then
            if selectable then
                it.choice = i
            end
            table.insert(section.items, it)
        end
    end
    table.insert(v.sections, section)
end

-- The quest's rewards: the choice items, the items, the money.
local function addRewards(v, selectable)
    local choices = GetNumQuestChoices and GetNumQuestChoices() or 0
    local rewards = GetNumQuestRewards and GetNumQuestRewards() or 0
    local money = GetRewardMoney and GetRewardMoney() or 0
    if choices > 0 then
        local label = REWARD_CHOICES or "You will be able to choose one of these rewards:"
        if choices == 1 then
            label = REWARD_ITEMS_ONLY or "You will receive:"
        end
        addItems(v, "choice", choices, label, selectable)
        if selectable then
            v.choices = math.min(choices, 6)
        end
    end
    if rewards > 0 then
        local label = REWARD_ITEMS_ONLY or "You will receive:"
        if choices > 0 then
            label = REWARD_ITEMS or "You will also receive:"
        end
        addItems(v, "reward", rewards, label, false)
    end
    if money > 0 then
        v.money = moneyString(money)
    end
end

local function gossipIcon(kind)
    if not kind or kind == "" then
        kind = "gossip"
    end
    return "Interface\\GossipFrame\\" .. kind .. "GossipIcon"
end

local BUILD = {}

BUILD.gossip = function()
    local v = newView("gossip")
    v.lines = wrap(GetGossipText and GetGossipText() or "")
    -- 1.12's lists are flat returns: title, level pairs; text, type pairs.
    local avail = { GetGossipAvailableQuests() }
    for i = 1, table.getn(avail), 2 do
        local index = (i + 1) / 2
        table.insert(v.rows, { text = avail[i], mark = "!", verb = "Choose",
            run = function() SelectGossipAvailableQuest(index) end })
    end
    local active = { GetGossipActiveQuests() }
    for i = 1, table.getn(active), 2 do
        local index = (i + 1) / 2
        table.insert(v.rows, { text = active[i], mark = "?", markGrey = true, verb = "Choose",
            run = function() SelectGossipActiveQuest(index) end })
    end
    local options = { GetGossipOptions() }
    for i = 1, table.getn(options), 2 do
        local index = (i + 1) / 2
        table.insert(v.rows, { text = options[i], icon = gossipIcon(options[i + 1]), verb = "Choose",
            run = function() SelectGossipOption(index) end })
    end
    v.back = function() CloseGossip() end
    v.backVerb = "Goodbye"
    return v
end

BUILD.greeting = function()
    local v = newView("greeting")
    v.lines = wrap(GetGreetingText and GetGreetingText() or "")
    -- The stock greeting lists the quests in progress first, then the new ones.
    for i = 1, (GetNumActiveQuests and GetNumActiveQuests() or 0) do
        local index = i
        table.insert(v.rows, { text = GetActiveTitle(i) or "?", mark = "?", markGrey = true, verb = "Choose",
            run = function() SelectActiveQuest(index) end })
    end
    for i = 1, (GetNumAvailableQuests and GetNumAvailableQuests() or 0) do
        local index = i
        table.insert(v.rows, { text = GetAvailableTitle(i) or "?", mark = "!", verb = "Choose",
            run = function() SelectAvailableQuest(index) end })
    end
    v.back = function() CloseQuest() end
    v.backVerb = "Goodbye"
    return v
end

BUILD.detail = function()
    local v = newView("detail")
    v.title = GetTitleText and GetTitleText() or nil
    local lines = wrap(GetQuestText and GetQuestText() or "")
    local objectives = GetObjectiveText and GetObjectiveText() or ""
    if string.find(objectives, "%S") then
        table.insert(lines, "")
        table.insert(lines, "|cffffd100" .. (QUEST_OBJECTIVES or "Quest Objectives") .. "|r")
        wrap(objectives, lines)
    end
    v.lines = lines
    addRewards(v, false)
    table.insert(v.rows, { text = ACCEPT or "Accept", verb = "Accept", run = function() AcceptQuest() end })
    table.insert(v.rows, { text = DECLINE or "Decline", verb = "Decline", back = true,
        run = function() Dialog.Decline() end })
    v.back = function() Dialog.Decline() end
    v.backVerb = "Decline"
    return v
end

BUILD.progress = function()
    local v = newView("progress")
    v.title = GetTitleText and GetTitleText() or nil
    v.lines = wrap(GetProgressText and GetProgressText() or "")
    addItems(v, "required", GetNumQuestItems and GetNumQuestItems() or 0,
        TURN_IN_ITEMS or "Required items:", false)
    local need = GetQuestMoneyToGet and GetQuestMoneyToGet() or 0
    if need > 0 then
        v.money = (REQUIRED_MONEY or "Required money:") .. " " .. moneyString(need)
    end
    local ready = IsQuestCompletable and IsQuestCompletable()
    table.insert(v.rows, { text = CONTINUE or "Continue", verb = "Continue", dim = not ready,
        run = function() CompleteQuest() end })
    table.insert(v.rows, { text = CANCEL or "Cancel", verb = "Close", back = true,
        run = function() CloseQuest() end })
    v.back = function() CloseQuest() end
    v.backVerb = "Close"
    return v
end

BUILD.reward = function()
    local v = newView("reward")
    v.title = GetTitleText and GetTitleText() or nil
    v.lines = wrap(GetRewardText and GetRewardText() or "")
    addRewards(v, true)
    table.insert(v.rows, { text = COMPLETE_QUEST or "Complete Quest", verb = "Complete",
        run = function()
            local choice = Dialog.choice or 0
            if (GetNumQuestChoices and GetNumQuestChoices() or 0) > 0 and choice == 0 then
                return
            end
            GetQuestReward(choice)
        end })
    v.back = function() CloseQuest() end
    v.backVerb = "Close"
    return v
end

-- ── The stock windows, unseen while ours is up ──

local STOCK = { "GossipFrame", "QuestFrame" }
local concealed = {}
local OFF_X = -4000

local function conceal()
    for i = 1, table.getn(STOCK) do
        local f = getglobal(STOCK[i])
        if f then
            if not concealed[f] then
                local saved = { alpha = f:GetAlpha(), mouse = f:IsMouseEnabled() }
                if f.GetNumPoints and f:GetNumPoints() > 0 then
                    local point, rel, relPoint, x, y = f:GetPoint(1)
                    saved.point = { point, rel, relPoint, x, y }
                end
                concealed[f] = saved
                f:EnableMouse(false)
            end
            if f:GetAlpha() > 0 then
                f:SetAlpha(0)
            end
            -- ShowUIPanel puts a panel back in its slot each time it shows: moved off again.
            if f:IsShown() then
                local left = f:GetLeft()
                if not left or left > OFF_X / 2 then
                    f:ClearAllPoints()
                    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", OFF_X, -104)
                end
            end
        end
    end
end

local function reveal()
    for f, saved in pairs(concealed) do
        f:SetAlpha(saved.alpha or 1)
        f:ClearAllPoints()
        local p = saved.point
        if p and p[1] then
            f:SetPoint(p[1], p[2] or UIParent, p[3] or p[1], p[4] or 0, p[5] or 0)
        else
            -- 1.12's left panel slot.
            f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -104)
        end
        if saved.mouse then
            f:EnableMouse(true)
        end
    end
    concealed = {}
end

-- ── Drawing ──

local function setTip(cell)
    if cell and GameTooltip and GameTooltip.SetQuestItem then
        GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
        GameTooltip:SetQuestItem("choice", cell.choice)
        GameTooltip:Show()
        Dialog.tip = true
    elseif Dialog.tip then
        Dialog.tip = nil
        if GameTooltip then
            GameTooltip:Hide()
        end
    end
end

local function setHints(v, last)
    local back = v.backVerb or "Close"
    if not last then
        P.SetHintText(hint, "A: next   Y: skip   B: " .. back)
        return
    end
    local s = ""
    if table.getn(v.rows) > 1 then
        s = s .. "Up / Down: choose   "
    end
    if v.choices > 1 then
        s = s .. "Left / Right: reward   "
    end
    local row = v.rows[Dialog.sel]
    if row and not row.dim then
        if row.back then
            s = s .. "A: " .. (row.verb or back) .. "   "
        else
            s = s .. "A: " .. (row.verb or "Choose") .. "   "
        end
    end
    if table.getn(v.pages) > 1 then
        s = s .. "LB: page back   "
    end
    P.SetHintText(hint, s .. "B: " .. back)
end

function Dialog.Layout()
    local v = Dialog.view
    if not v then
        return
    end
    local n = table.getn(v.pages)
    if Dialog.page > n then Dialog.page = n end
    if Dialog.page < 1 then Dialog.page = 1 end
    local last = Dialog.page == n

    -- Header: the face, the name, the quest's title.
    local x = PAD
    if v.face then
        face:Show()
        x = PAD + FACE + 10
    else
        face:Hide()
    end
    name:ClearAllPoints()
    sub:ClearAllPoints()
    name:SetWidth(WIDTH - x - PAD)
    sub:SetWidth(WIDTH - x - PAD)
    name:SetText(v.name or "")
    if v.title and v.title ~= "" then
        name:SetPoint("TOPLEFT", win, "TOPLEFT", x, -PAD - 4)
        sub:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
        sub:SetText(v.title)
        sub:Show()
    else
        name:SetPoint("LEFT", win, "TOPLEFT", x, -PAD - FACE / 2)
        sub:Hide()
    end
    local y = PAD + FACE + 10

    -- Body: this page's lines.
    local page = v.pages[Dialog.page]
    local count = math.max(1, table.getn(page))
    body:ClearAllPoints()
    body:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -y)
    -- No set height: a line the measure got wrong wraps rather than being cut off.
    body:SetText(table.concat(page, "\n"))
    y = y + count * LINE_H + 4
    pageText:ClearAllPoints()
    if n > 1 then
        pageText:SetPoint("TOPRIGHT", win, "TOPRIGHT", -PAD, -y)
        pageText:SetText(Dialog.page .. " / " .. n)
        pageText:Show()
        y = y + 14
    else
        pageText:Hide()
    end

    -- Rewards or required items, then the answers: on the last page only.
    local usedCells, usedHeads = 0, 0
    local tipCell
    if last then
        for s = 1, table.getn(v.sections) do
            local section = v.sections[s]
            if usedHeads < SECTION_MAX then
                usedHeads = usedHeads + 1
                local h = headings[usedHeads]
                h:ClearAllPoints()
                h:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -y)
                h:SetText(section.label)
                h:Show()
                y = y + 18
            end
            local items = section.items
            for i = 1, table.getn(items) do
                if usedCells < ITEM_MAX then
                    usedCells = usedCells + 1
                    local it = items[i]
                    local c = cells[usedCells]
                    local col = math.mod(i - 1, 2)
                    local line = math.floor((i - 1) / 2)
                    c:ClearAllPoints()
                    c:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + col * (CELL_W + 8), -(y + line * CELL_H))
                    c.icon:SetTexture(it.icon)
                    if it.count and it.count > 1 then
                        c.count:SetText(it.count)
                    else
                        c.count:SetText("")
                    end
                    c.label:SetText(it.name)
                    local q = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[it.quality]
                    if q then
                        c.label:SetTextColor(q.r, q.g, q.b)
                    else
                        c.label:SetTextColor(1, 1, 1)
                    end
                    c.choice = it.choice
                    local lit = it.choice and v.choices > 0 and it.choice == Dialog.choice
                    P.ShowSelect(c.select, lit)
                    if lit then
                        tipCell = c
                    end
                    c:Show()
                end
            end
            y = y + math.ceil(table.getn(items) / 2) * CELL_H + 4
        end
        if v.money then
            moneyText:ClearAllPoints()
            moneyText:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -y)
            moneyText:SetText(v.money)
            moneyText:Show()
            y = y + 18
        else
            moneyText:Hide()
        end
        y = y + 2
    else
        moneyText:Hide()
    end
    for i = usedHeads + 1, SECTION_MAX do
        headings[i]:Hide()
    end
    for i = usedCells + 1, ITEM_MAX do
        cells[i]:Hide()
    end
    setTip(tipCell)

    local shownRows = 0
    if last then
        shownRows = math.min(table.getn(v.rows), ROW_MAX)
    end
    for i = 1, ROW_MAX do
        local r = rows[i]
        local row = v.rows[i]
        if row and i <= shownRows then
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -y)
            y = y + ROW_H
            r.text:SetText(row.text or "")
            local lit = i == Dialog.sel
            P.ShowSelect(r.select, lit)
            if lit then
                P.SetGlyph(r.glyph, "A")
                r.glyph:Show()
            else
                r.glyph:Hide()
                r.glyph.chipName:Hide()
            end
            if row.mark then
                r.mark:SetText(row.mark)
                if row.markGrey then
                    P.Paint(r.mark, C.grey)
                else
                    P.Paint(r.mark, C.gold)
                end
                r.mark:Show()
                r.icon:Hide()
            elseif row.icon then
                r.icon:SetTexture(row.icon)
                r.icon:Show()
                r.mark:Hide()
            else
                r.mark:Hide()
                r.icon:Hide()
            end
            if row.dim then
                P.Paint(r.text, C.grey)
            elseif lit then
                r.text:SetTextColor(1, 1, 1)
            elseif row.back then
                P.Paint(r.text, C.help)
            else
                P.Paint(r.text, C.cream)
            end
            r:Show()
        else
            r:Hide()
        end
    end

    setHints(v, last)
    y = y + 8
    win:SetHeight(y + hint:GetHeight() + 14)
end

-- ── Opening, answering, closing ──

-- Whether the pad takes NPC dialogue: a pad connected and the setting on Subtitles.
function Dialog.Wanted()
    return P.connected and P.Setting("npcDialog") ~= "classic"
end

local KINDS = {
    GOSSIP_SHOW = "gossip", QUEST_GREETING = "greeting", QUEST_DETAIL = "detail",
    QUEST_PROGRESS = "progress", QUEST_COMPLETE = "reward",
}

-- The first answer that goes on, else the first that can be taken at all (a quest not ready to
-- hand in lights Cancel).
local function firstRow(v)
    for i = 1, table.getn(v.rows) do
        if not v.rows[i].dim and not v.rows[i].back then
            return i
        end
    end
    for i = 1, table.getn(v.rows) do
        if not v.rows[i].dim then
            return i
        end
    end
    return 1
end

-- Build the view for `kind`; `keep` holds the page, row and reward choice (an item update).
function Dialog.Open(kind, keep)
    local build = BUILD[kind]
    if not build then
        return
    end
    if P.Keyboard and P.Keyboard.IsOpen() then
        -- Typing: the stock window stays, under the pad cursor once the keyboard goes.
        return
    end
    -- Our other windows give way (their OnHide hands the mode back first).
    if P.Menu and P.Menu.frame:IsVisible() then P.Menu.Close() end
    if P.Binds and P.Binds.frame:IsVisible() then P.Binds.frame:Hide() end
    if P.Wheel and P.Wheel.frame:IsVisible() then P.Wheel.Close() end
    if P.Chat and P.Chat.frame and P.Chat.frame:IsVisible() then P.Chat.frame:Hide() end
    if P.Peek then P.Peek.Hide() end
    local v = build()
    v.name = UnitName("npc")
    v.face = UnitExists("npc") and SetPortraitTexture and true or false
    if v.face then
        SetPortraitTexture(portrait, "npc")
    end
    if not v.name or v.name == "" then
        v.name = v.title or ""
        if v.title then
            v.title = nil
        end
    end
    v.pages = paginate(v.lines)
    Dialog.kind = kind
    Dialog.view = v
    if not keep then
        Dialog.busy = nil
        Dialog.declinedAt = nil
    end
    if keep then
        Dialog.page = keep.page
        Dialog.sel = keep.sel
        Dialog.choice = keep.choice
    else
        Dialog.page = 1
        Dialog.sel = firstRow(v)
        -- A single choice is the reward; with several the first is lit, Left / Right change it.
        Dialog.choice = (v.choices > 0) and 1 or 0
    end
    if Dialog.sel > table.getn(v.rows) then
        Dialog.sel = 1
    end
    P.mode = "dialog"
    conceal()
    win:Show()
    Dialog.Layout()
end

-- Our panel goes; the interaction stays as it is (the caller closes it, or it closed itself).
function Dialog.Release()
    win:Hide()
end

-- Decline a quest's offer. For an NPC 1.12 sends a new hello (its gossip or greeting comes back);
-- if nothing comes the window is closed.
function Dialog.Decline()
    DeclineQuest()
    Dialog.declinedAt = GetTime()
end

function Dialog.Activate()
    local v = Dialog.view
    local row = v and v.rows[Dialog.sel]
    if not row or row.dim then
        return
    end
    -- One answer per view: the next one comes with the NPC's reply (a second A within two
    -- seconds is a double press, not a second answer).
    if Dialog.busy and GetTime() - Dialog.busy < 2 then
        return
    end
    if not row.back then
        Dialog.busy = GetTime()
    end
    row.run()
end

function Dialog.Back()
    local v = Dialog.view
    if v and v.back then
        v.back()
    else
        win:Hide()
    end
end

local function step(dir)
    local v = Dialog.view
    local n = table.getn(v.rows)
    if n == 0 then
        return
    end
    local i = Dialog.sel + dir
    if i < 1 then i = n end
    if i > n then i = 1 end
    Dialog.sel = i
end

function Dialog.Nav(btn)
    local v = Dialog.view
    if not v then
        return
    end
    local n = table.getn(v.pages)
    local last = Dialog.page >= n
    if btn == "B" then
        Dialog.Back()
        return
    elseif btn == "LB" then
        Dialog.page = Dialog.page - 1
    elseif btn == "RB" then
        Dialog.page = Dialog.page + 1
    elseif not last then
        if btn == "A" or btn == "DRIGHT" or btn == "DDOWN" then
            Dialog.page = Dialog.page + 1
        elseif btn == "Y" then
            Dialog.page = n
        elseif btn == "DLEFT" or btn == "DUP" then
            Dialog.page = Dialog.page - 1
        end
    elseif btn == "A" then
        Dialog.Activate()
        return
    elseif btn == "DUP" then
        step(-1)
    elseif btn == "DDOWN" then
        step(1)
    elseif btn == "DLEFT" or btn == "DRIGHT" then
        if v.choices > 1 then
            local c = (Dialog.choice or 1) + ((btn == "DLEFT") and -1 or 1)
            if c < 1 then c = v.choices end
            if c > v.choices then c = 1 end
            Dialog.choice = c
        elseif btn == "DLEFT" then
            Dialog.page = Dialog.page - 1
        end
    end
    Dialog.Layout()
end

win:SetScript("OnShow", function()
    P.mode = "dialog"
end)

win:SetScript("OnHide", function()
    reveal()
    setTip(nil)
    Dialog.kind = nil
    Dialog.view = nil
    Dialog.declinedAt = nil
    if P.mode == "dialog" then
        P.mode = "world"
    end
end)

-- Every frame the stock windows stay out of sight; a few times a second, whether ours should
-- still be up: the pad gone or the setting changed hands back to them, and a stock window that
-- closed without its event closes ours.
local pollElapsed, missing = 0, 0
win:SetScript("OnUpdate", function()
    conceal()
    pollElapsed = pollElapsed + arg1
    if pollElapsed < 0.2 then
        return
    end
    local dt = pollElapsed
    pollElapsed = 0
    if not Dialog.Wanted() then
        this:Hide()
        return
    end
    local open = (GossipFrame and GossipFrame:IsShown()) or (QuestFrame and QuestFrame:IsShown())
    if open then
        missing = 0
    else
        missing = missing + dt
        if missing > 0.6 then
            missing = 0
            this:Hide()
            return
        end
    end
    if Dialog.declinedAt and GetTime() - Dialog.declinedAt > 1.5 then
        Dialog.declinedAt = nil
        if Dialog.kind == "detail" and CloseQuest then
            CloseQuest()
        end
    end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("GOSSIP_SHOW")
events:RegisterEvent("GOSSIP_CLOSED")
events:RegisterEvent("QUEST_GREETING")
events:RegisterEvent("QUEST_DETAIL")
events:RegisterEvent("QUEST_PROGRESS")
events:RegisterEvent("QUEST_COMPLETE")
events:RegisterEvent("QUEST_FINISHED")
events:RegisterEvent("QUEST_ITEM_UPDATE")
events:SetScript("OnEvent", function()
    if event == "GOSSIP_CLOSED" then
        if Dialog.kind == "gossip" then
            Dialog.Release()
        end
        return
    elseif event == "QUEST_FINISHED" then
        if Dialog.kind and Dialog.kind ~= "gossip" then
            Dialog.Release()
        end
        return
    elseif event == "QUEST_ITEM_UPDATE" then
        -- An item's name and icon arrived: the same view, redrawn in place.
        if win:IsShown() and Dialog.kind and Dialog.kind ~= "gossip" then
            Dialog.Open(Dialog.kind, { page = Dialog.page, sel = Dialog.sel, choice = Dialog.choice })
        end
        return
    end
    local kind = KINDS[event]
    if kind and Dialog.Wanted() then
        missing = 0
        Dialog.Open(kind)
    end
end)

-- The pad's buttons while the panel is up; a pad going away hands the stock window back.
P.Listen(function(event, a1, a2)
    if event == "BENILLAPAD_DISCONNECTED" then
        if win:IsShown() then
            win:Hide()
        end
        return
    end
    if not win:IsVisible() then
        return
    end
    if event == "BENILLAPAD_NAV" then
        if a2 then
            Dialog.Nav(a1)
        end
        return true
    end
end)
