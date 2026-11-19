-- The wheels, in the Forever radial's layout: eight wedges round a hub, slot 1 at the top and
-- clockwise every 45 degrees, pages of eight on LB / RB. The window wheel (Start, LT+RT+A) opens
-- game windows and has an emote page; the consumables wheel (LT+RT+X) uses a potion, food,
-- bandage, scroll or weapon oil from the bags; the bot wheel (LT+RT+Y) sends a bot command. While
-- a wheel is up the Rust side is in "wheel" mode: the sticks arrive as BENILLAPAD_STICK, the
-- buttons as BENILLAPAD_NAV, and the body stays. The pick is sticky: it stays on the wedge last
-- pointed at when the stick springs back, and A uses it.
-- The quest item (LT+RT+B) uses the bags' usable quest item straight away.
--
-- 1.12 cannot turn a texture, so the wedge art (Art/Wheel_Fill, _Rim, _Glow) is three wedges in
-- one 512x512 atlas per kind (top, right, top-right diagonal); the other five slots are mirror
-- flips of those through SetTexCoord.

local P = BenillaPad
local Wheel = {}
P.Wheel = Wheel

local SIZE = 540
local SLOTS = 8
-- The wedges' art: 256 px cells, one texel a UI px, centred this far from the wheel's centre.
local CELL = 256
local CELL_AXIS = 152
local CELL_DIAGONAL = 123
-- The icon's and the label's distance from the centre (the wedges run from 75 to 235).
local ICON_RADIUS = 128
local LABEL_RADIUS = 182
local ICON = 40
local BUTTON = 60
local HUB = 136
-- Stick lengths: past PICK a direction selects; under it the pick stays where it was.
local PICK = 0.5
local MAX_ENTRIES = 24
local MAX_DOTS = 5

-- ── The entries ──

local function runBinding(command)
    return function() RunBinding(command) end
end

local function emote(token)
    return function() DoEmote(token) end
end

-- The first trade skill with a window, cast from the spellbook.
local PROFESSIONS = { "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Leatherworking",
    "Tailoring", "Cooking", "First Aid", "Smelting", "Poisons" }

local function professionIndex()
    local _, _, offset, count = GetSpellTabInfo(1)
    for i = 1, (offset or 0) + (count or 0) do
        local name = GetSpellName(i, "spell")
        for j = 1, table.getn(PROFESSIONS) do
            if name == PROFESSIONS[j] then
                return i
            end
        end
    end
    return nil
end

-- The window wheel's groups; a group of more than eight runs over several pages.
local WINDOW_PAGES = {
    {
        title = "Windows",
        entries = {
            { label = "Character", icon = P.ART .. "Character", run = runBinding("TOGGLECHARACTER0") },
            { label = "Bags", icon = P.ART .. "Bags", run = runBinding("OPENALLBAGS"),
                sub = function()
                    local free = 0
                    for bag = 0, 4 do
                        for slot = 1, GetContainerNumSlots(bag) do
                            if not GetContainerItemLink(bag, slot) then free = free + 1 end
                        end
                    end
                    return free .. " free"
                end },
            { label = "Spellbook", icon = P.ART .. "Spellbook", run = runBinding("TOGGLESPELLBOOK") },
            { label = "Talents", icon = P.ART .. "Talents", run = runBinding("TOGGLETALENTS") },
            { label = "Quest Log", icon = P.ART .. "QuestLog", run = runBinding("TOGGLEQUESTLOG") },
            { label = "World Map", icon = P.ART .. "Map", run = runBinding("TOGGLEWORLDMAP") },
            { label = "Social", icon = P.ART .. "Social", run = runBinding("TOGGLESOCIAL") },
            { label = "Professions", icon = P.ART .. "Professions",
                run = function()
                    local i = professionIndex()
                    if i then
                        CastSpell(i, "spell")
                    else
                        UIErrorsFrame:AddMessage("No profession with a window", 1, 0.1, 0.1, 1, 5)
                    end
                end },
            { label = "Controller", icon = P.ART .. "Menu", run = function() P.Menu.Open() end },
            { label = "Quick Chat", icon = P.ART .. "QuickChat", run = function() P.Chat.Open() end },
            { label = "Game Menu", icon = P.ART .. "GameMenu", run = runBinding("TOGGLEGAMEMENU") },
        },
    },
    {
        title = "Emotes",
        -- ImprovedForever's line icons (MIT, THIRD-PARTY-NOTICES.md), drawn whole, not cropped round.
        entries = {
            { label = "Sit / Stand", icon = P.ART .. "Emote_Sit", line = true, run = function() SitOrStand() end },
            { label = "Wave", icon = P.ART .. "Emote_Wave", line = true, run = emote("WAVE") },
            { label = "Dance", icon = P.ART .. "Emote_Dance", line = true, run = emote("DANCE") },
            { label = "Cheer", icon = P.ART .. "Emote_Cheer", line = true, run = emote("CHEER") },
            { label = "Bow", icon = P.ART .. "Emote_Bow", line = true, run = emote("BOW") },
            { label = "Thank", icon = P.ART .. "Emote_Thank", line = true, run = emote("THANK") },
            { label = "Laugh", icon = P.ART .. "Emote_Laugh", line = true, run = emote("LAUGH") },
            { label = "Point", icon = P.ART .. "Emote_Point", line = true, run = emote("POINT") },
        },
    },
}

-- Weapon imbues go on the main hand after the use: 1.12 asks for the item with the targeting
-- cursor, which a click on the main-hand slot (inventory slot 16) answers.
local IMBUE_WORDS = { "Sharpening Stone", "Weightstone", "Oil", "Poison" }

local function isImbue(name)
    for i = 1, table.getn(IMBUE_WORDS) do
        if string.find(name, IMBUE_WORDS[i], 1, true) then
            return true
        end
    end
    return false
end

-- ── A consumable's values, read off its tooltip's "Use:" line ──
-- ("Restores 455 to 585 health." -> "+455-585 HP"; "Restores 1344 mana over 27 sec." ->
-- "+1344 Mana"; "Heals 400 damage over 8 sec." -> "+400 HP"; an elixir's "Increases your
-- Agility by 25" -> "+25 Agi"). After ImprovedForever's RingContent.lua (MIT), for 1.12: the
-- tooltip is the hidden scanner BenillaPadScanTip (Keybinds.lua), read line by line.

local STAT_SHORT = {
    stamina = "Sta", spirit = "Spi", strength = "Str", agility = "Agi", intellect = "Int",
    armor = "Armor", ["attack power"] = "AP", ["spell damage"] = "Spell", healing = "Heal",
    defense = "Def",
}
local HP_COLOR = "|cff40ff40"
local MANA_COLOR = "|cff59b3ff"
local BUFF_COLOR = "|cffff9933"

-- "455-585" or "2148" before a word ("health"), or nil.
local function amountOf(text, word)
    local _, _, low, high = string.find(text, "(%d+) to (%d+) " .. word)
    if low then
        return low .. "-" .. high
    end
    local _, _, n = string.find(text, "(%d+) " .. word)
    return n
end

local function statName(subject)
    local _, _, rest = string.find(subject, "^your (.*)$")
    subject = rest or subject
    if STAT_SHORT[subject] then
        return STAT_SHORT[subject]
    end
    return string.upper(string.sub(subject, 1, 1)) .. string.sub(subject, 2)
end

-- The short values of a "Use:" text (lower-cased here), at most two, or nil.
local function parseStat(text)
    text = string.lower(text)
    local parts = {}
    local hp = amountOf(text, "health")
    if not hp then
        local _, _, n = string.find(text, "heals (%d+) damage")
        hp = n
    end
    if hp and not string.find(text, "increases [%a' ]-health by") then
        table.insert(parts, HP_COLOR .. "+" .. hp .. " HP|r")
    end
    local mana = amountOf(text, "mana")
    if mana and not string.find(text, "increases [%a' ]-mana by") then
        table.insert(parts, MANA_COLOR .. "+" .. mana .. " Mana|r")
    end
    if table.getn(parts) == 0 then
        local _, _, subject, n = string.find(text, "increases ([%a' ]-) by [upto ]*(%d+)")
        if subject then
            table.insert(parts, BUFF_COLOR .. "+" .. n .. " " .. statName(subject) .. "|r")
        end
    end
    if table.getn(parts) == 0 then
        return nil
    end
    if table.getn(parts) > 2 then
        parts = { parts[1], parts[2] }
    end
    return table.concat(parts, " ")
end

-- By item id: the text, or false once read with nothing to show (not kept while the tooltip
-- has not loaded the item yet).
local statCache = {}

local function consumableStat(id, bag, slot)
    if statCache[id] ~= nil then
        return statCache[id] or nil
    end
    local tip = BenillaPadScanTip
    if not tip then
        return nil
    end
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip:SetBagItem(bag, slot)
    local lines = tip:NumLines() or 0
    local use = ""
    local trigger = ITEM_SPELL_TRIGGER_ONUSE or "Use:"
    for line = 1, lines do
        local left = getglobal("BenillaPadScanTipTextLeft" .. line)
        local text = left and left:GetText() or ""
        if string.find(text, trigger, 1, true) == 1 then
            use = use .. " " .. string.sub(text, string.len(trigger) + 1)
        end
    end
    tip:Hide()
    if lines < 2 then
        return nil
    end
    local stat = parseStat(use)
    statCache[id] = stat or false
    return stat
end

-- The bags' consumables, one entry per item, with the stack counts summed.
local function consumableEntries()
    local _, _, _, consumable = GetAuctionItemClasses()
    consumable = consumable or "Consumable"
    local byId, list = {}, {}
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            local _, _, id = string.find(link or "", "item:(%d+)")
            if id then
                local name, _, _, _, itemType, subType, _, _, texture = GetItemInfo(tonumber(id))
                if name and itemType == consumable then
                    local _, count = GetContainerItemInfo(bag, slot)
                    local e = byId[id]
                    if e then
                        e.count = e.count + (count or 1)
                    else
                        e = { label = name, icon = texture, count = count or 1, bag = bag, slot = slot,
                            kind = subType or "", imbue = isImbue(name),
                            stat = consumableStat(id, bag, slot) }
                        byId[id] = e
                        table.insert(list, e)
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.kind ~= b.kind then return a.kind < b.kind end
        return a.label < b.label
    end)
    while table.getn(list) > MAX_ENTRIES do
        table.remove(list)
    end
    for i = 1, table.getn(list) do
        local e = list[i]
        local stat = e.stat
        e.sub = function() return stat end
        e.countText = e.count
        e.cooldown = function() return GetContainerItemCooldown(e.bag, e.slot) end
        e.run = function()
            UseContainerItem(e.bag, e.slot)
            if e.imbue and SpellIsTargeting() then
                PickupInventoryItem(16)
            end
        end
    end
    return list
end

-- The bot wheel's entries: the favourite bot commands (Bots.lua), each with an icon.
local BOT_ICONS = {
    follow = "BotFollow", stay = "BotStay", guard = "BotGuard", flee = "BotFlee",
    summon = "BotSummon", attack = "Attack", tankattack = "BotTank", pull = "BotPull",
    maxdps = "BotMaxDps", savemana = "BotMana", acceptall = "BotAccept", autoaccept = "BotAccept",
    quests = "QuestLog", talk = "QuickChat", loot = "BotLoot", addallloot = "BotLoot",
    inventory = "Bags", release = "BotRelease", revive = "BotRevive", selfres = "BotRevive",
    ready = "BotAccept", cast = "Spellbook", whoami = "Character", stats = "Character",
    where = "Map", home = "Map", trainer = "Talents", repair = "Professions",
}

local function botEntries()
    local list = {}
    local favorites = P.Bots.Favorites()
    for i = 1, table.getn(favorites) do
        local c = P.Bots.Command(favorites[i])
        if c then
            local icon = P.ART .. (BOT_ICONS[c.id] or "BotOther")
            table.insert(list, { label = c.label, icon = icon, run = function() P.Bots.Run(c) end })
        end
    end
    return list
end

-- ── The frame ──

local win = CreateFrame("Frame", "BenillaPadWheel", UIParent)
win:SetWidth(SIZE)
win:SetHeight(SIZE)
win:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
win:SetFrameStrata("DIALOG")
win:EnableMouse(true)
win:Hide()
tinsert(UISpecialFrames, "BenillaPadWheel")
Wheel.frame = win

-- Each slot's wedge: its atlas cell as SetTexCoord(left, right, top, bottom), a mirror flip
-- swapping a pair, and where the cell's centre sits from the wheel's centre.
local WEDGE = {
    { 0, 0.5, 0, 0.5, 0, CELL_AXIS },                           -- 1 top
    { 0, 0.5, 0.5, 1, CELL_DIAGONAL, CELL_DIAGONAL },           -- 2 top right
    { 0.5, 1, 0, 0.5, CELL_AXIS, 0 },                           -- 3 right
    { 0, 0.5, 1, 0.5, CELL_DIAGONAL, -CELL_DIAGONAL },          -- 4 bottom right
    { 0, 0.5, 0.5, 0, 0, -CELL_AXIS },                          -- 5 bottom
    { 0.5, 0, 1, 0.5, -CELL_DIAGONAL, -CELL_DIAGONAL },         -- 6 bottom left
    { 1, 0.5, 0, 0.5, -CELL_AXIS, 0 },                          -- 7 left
    { 0.5, 0, 0.5, 1, -CELL_DIAGONAL, CELL_DIAGONAL },          -- 8 top left
}

local function wedgeTexture(i, art, layer)
    local w = WEDGE[i]
    local t = win:CreateTexture(nil, layer)
    t:SetTexture(art)
    t:SetWidth(CELL)
    t:SetHeight(CELL)
    t:SetTexCoord(w[1], w[2], w[3], w[4])
    t:SetPoint("CENTER", win, "CENTER", w[5], w[6])
    return t
end

local wedges = {}
for i = 1, SLOTS do
    local fill = wedgeTexture(i, P.ART .. "Wheel_Fill", "BACKGROUND")
    local rim = wedgeTexture(i, P.ART .. "Wheel_Rim", "BORDER")
    local glow = wedgeTexture(i, P.ART .. "Wheel_Glow", "ARTWORK")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.78, 0.3)
    glow:Hide()
    wedges[i] = { fill = fill, rim = rim, glow = glow }
end

-- The hub: the wheel's title, the picked entry's name, the page dots.
local hub = win:CreateTexture(nil, "ARTWORK")
hub:SetTexture(P.ART .. "Wheel_Hub")
hub:SetWidth(HUB)
hub:SetHeight(HUB)
hub:SetPoint("CENTER", win, "CENTER", 0, 0)

local pageTitle = win:CreateFontString(nil, "OVERLAY")
pageTitle:SetFont("Fonts\\FRIZQT__.TTF", 15, "OUTLINE")
pageTitle:SetPoint("CENTER", win, "CENTER", 0, 22)
pageTitle:SetTextColor(1, 0.82, 0)

local chosen = win:CreateFontString(nil, "OVERLAY")
chosen:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
chosen:SetWidth(HUB - 24)
chosen:SetPoint("CENTER", win, "CENTER", 0, 0)

local dots = {}
for i = 1, MAX_DOTS do
    local d = win:CreateTexture(nil, "OVERLAY")
    d:SetTexture(P.ART .. "Disc")
    d:SetWidth(10)
    d:SetHeight(10)
    d:Hide()
    dots[i] = d
end

-- The footer: the prompts as glyphs and gold verbs on a plate (Glyphs.lua).
local hint = P.NewHints(win, { size = 22, pad = 8, spacing = 14, font = "GameFontNormalSmall",
    maxWidth = SIZE, plate = true })
hint:SetPoint("TOP", win, "BOTTOM", 0, 2)

local slots = {}
for i = 1, SLOTS do
    local a = math.rad(90 - (i - 1) * 45)
    local x, y = math.cos(a), math.sin(a)
    local b = CreateFrame("Button", nil, win)
    b:SetWidth(BUTTON)
    b:SetHeight(BUTTON)
    b:SetPoint("CENTER", win, "CENTER", x * ICON_RADIUS, y * ICON_RADIUS)
    local disc = b:CreateTexture(nil, "BACKGROUND")
    disc:SetTexture(P.ART .. "Wheel_Slot")
    disc:SetWidth(ICON + 10)
    disc:SetHeight(ICON + 10)
    disc:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.disc = disc
    b.strips = P.NewRoundIcon(b, ICON)
    local plain = b:CreateTexture(nil, "ARTWORK")
    plain:SetWidth(ICON - 2)
    plain:SetHeight(ICON - 2)
    plain:SetPoint("CENTER", b, "CENTER", 0, 0)
    plain:Hide()
    b.plain = plain
    local ring = b:CreateTexture(nil, "OVERLAY")
    ring:SetTexture(P.ART .. "Ring")
    ring:SetVertexColor(0.85, 0.72, 0.5)
    ring:SetWidth(ICON * 1.45)
    ring:SetHeight(ICON * 1.45)
    ring:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.ring = ring
    local glow = b:CreateTexture(nil, "OVERLAY")
    glow:SetTexture(P.ART .. "Wheel_IconGlow")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.82, 0.35)
    glow:SetWidth(ICON * 1.95)
    glow:SetHeight(ICON * 1.95)
    glow:SetPoint("CENTER", b, "CENTER", 0, 0)
    glow:Hide()
    b.glow = glow
    local timer = b:CreateFontString(nil, "OVERLAY")
    timer:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
    timer:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.timer = timer
    local count = b:CreateFontString(nil, "OVERLAY")
    count:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    count:SetPoint("BOTTOMRIGHT", b, "CENTER", ICON / 2 + 4, -ICON / 2 + 1)
    b.count = count
    local label = win:CreateFontString(nil, "OVERLAY")
    label:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    label:SetWidth(124)
    label:SetPoint("CENTER", win, "CENTER", x * LABEL_RADIUS, y * LABEL_RADIUS)
    b.label = label
    local sub = win:CreateFontString(nil, "OVERLAY")
    sub:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    sub:SetTextColor(0.85, 0.85, 0.85)
    sub:SetPoint("TOP", label, "BOTTOM", 0, -1)
    b.sub = sub
    b.index = i
    b:SetScript("OnClick", function()
        if Wheel.entries[this.index] then
            Wheel.selected = this.index
            Wheel.Activate()
        end
    end)
    b:SetScript("OnEnter", function()
        if Wheel.entries[this.index] then
            Wheel.selected = this.index
            Wheel.Refresh()
        end
    end)
    slots[i] = b
end

-- ── State ──

Wheel.set = nil
Wheel.page = 1
Wheel.pages = {}
Wheel.selected = nil
Wheel.entries = {}

local function entryText(value)
    if type(value) == "function" then
        return value()
    end
    return value
end

-- Groups of entries as pages of eight; an empty group is one empty page.
local function paginate(groups)
    local pages = {}
    for g = 1, table.getn(groups) do
        local group = groups[g]
        local n = table.getn(group.entries)
        local count = math.max(1, math.ceil(n / SLOTS))
        for p = 1, count do
            local entries = {}
            for i = (p - 1) * SLOTS + 1, math.min(n, p * SLOTS) do
                table.insert(entries, group.entries[i])
            end
            table.insert(pages, { title = group.title, entries = entries })
        end
    end
    return pages
end

-- Put the current page's entries in their slots.
function Wheel.Layout()
    for i = 1, SLOTS do
        local b = slots[i]
        local e = Wheel.entries[i]
        if e then
            if e.line then
                P.SetIcon(b.strips, nil)
                b.plain:SetTexture(e.icon)
                b.plain:Show()
            else
                b.plain:Hide()
                P.SetIcon(b.strips, e.icon)
            end
            b.label:SetText(e.label)
            if e.countText then
                b.count:SetText(e.countText)
            else
                b.count:SetText("")
            end
            b:Show()
            b.label:Show()
            b.sub:Show()
        else
            b:Hide()
            b.label:Hide()
            b.sub:Hide()
        end
    end
    local n = table.getn(Wheel.pages)
    for i = 1, MAX_DOTS do
        local d = dots[i]
        if n > 1 and i <= n then
            d:ClearAllPoints()
            d:SetPoint("CENTER", win, "CENTER", (i - (n + 1) / 2) * 16, -30)
            if i == Wheel.page then
                d:SetVertexColor(1, 0.78, 0.1)
            else
                d:SetVertexColor(0.3, 0.3, 0.3)
            end
            d:Show()
        else
            d:Hide()
        end
    end
end

-- What changes as the selection or the clock moves.
function Wheel.Refresh()
    if not win:IsVisible() then
        return
    end
    for i = 1, SLOTS do
        local b, e, w = slots[i], Wheel.entries[i], wedges[i]
        if not e then
            -- An empty wedge, dimmed.
            w.fill:SetVertexColor(0.7, 0.7, 0.7, 0.55)
            w.rim:SetVertexColor(1, 1, 1, 0.55)
            w.glow:Hide()
        else
            w.fill:SetVertexColor(1, 1, 1, 1)
            w.rim:SetVertexColor(1, 1, 1, 1)
            if i == Wheel.selected then
                w.glow:Show()
                b.glow:Show()
                b.label:SetTextColor(1, 1, 1)
            else
                w.glow:Hide()
                b.glow:Hide()
                b.label:SetTextColor(1, 0.82, 0)
            end
            b.sub:SetText(entryText(e.sub) or "")
            local left = 0
            if e.cooldown then
                local start, duration, enable = e.cooldown()
                if enable == 1 and duration and duration > 1.5 then
                    left = start + duration - GetTime()
                end
            end
            if left > 0 then
                b.timer:SetText(math.ceil(left))
                P.TintIcon(b.strips, 0.45, 0.45, 0.45)
            else
                b.timer:SetText("")
                P.TintIcon(b.strips, 1, 1, 1)
            end
        end
    end
    local e = Wheel.selected and Wheel.entries[Wheel.selected]
    chosen:SetText(e and e.label or "")
end

-- The footer's prompts for the open wheel.
local function setHint()
    local paged = table.getn(Wheel.pages) > 1
    local page = paged and "   LB / RB: page" or ""
    if Wheel.set == "windows" then
        P.SetHintText(hint, "Stick: point   A: open" .. page .. "   B: close")
    elseif Wheel.set == "bots" then
        P.SetHintText(hint, "To: " .. P.Bots.TargetLabel() .. "   Y: change   A: send" .. page .. "   B: close")
    elseif table.getn(Wheel.entries) == 0 then
        P.SetHintText(hint, "Nothing to use in your bags   B: close")
    else
        P.SetHintText(hint, "Stick: point   A: use" .. page .. "   B: close")
    end
end

function Wheel.Fill()
    local groups
    if Wheel.set == "windows" then
        groups = WINDOW_PAGES
    elseif Wheel.set == "bots" then
        groups = { { title = "Bots", entries = botEntries() } }
    else
        groups = { { title = "Consumables", entries = consumableEntries() } }
    end
    Wheel.pages = paginate(groups)
    local n = table.getn(Wheel.pages)
    if Wheel.page > n then Wheel.page = n end
    if Wheel.page < 1 then Wheel.page = 1 end
    local page = Wheel.pages[Wheel.page]
    Wheel.entries = page.entries
    pageTitle:SetText(page.title)
    if Wheel.selected and not Wheel.entries[Wheel.selected] then
        Wheel.selected = nil
    end
    setHint()
    Wheel.Layout()
    Wheel.Refresh()
end

function Wheel.Open(set)
    if P.Menu and P.Menu.frame:IsVisible() then P.Menu.Close() end
    if P.Binds and P.Binds.frame:IsVisible() then P.Binds.frame:Hide() end
    Wheel.set = set
    Wheel.page = 1
    Wheel.selected = nil
    win:Show()
    Wheel.Fill()
end

function Wheel.Close()
    win:Hide()
end

function Wheel.Toggle(set)
    if win:IsVisible() and Wheel.set == set then
        Wheel.Close()
    else
        Wheel.Open(set)
    end
end

-- A on the selection: run it and close (the window it opens takes over).
function Wheel.Activate()
    local e = Wheel.selected and Wheel.entries[Wheel.selected]
    if not e then
        return
    end
    Wheel.Close()
    e.run()
end

-- The selection from a stick: the wedge whose middle is nearest the stick's angle, slot 1 at
-- the top and clockwise; an empty wedge or a stick at rest leaves the pick where it is.
function Wheel.Aim(x, y)
    local n = table.getn(Wheel.entries)
    if n == 0 or math.sqrt(x * x + y * y) < PICK then
        return
    end
    local degrees = math.deg(math.atan2(x, y))
    if degrees < 0 then
        degrees = degrees + 360
    end
    local index = math.floor((degrees + 22.5) / 45)
    index = index - SLOTS * math.floor(index / SLOTS) + 1
    if index <= n and index ~= Wheel.selected then
        Wheel.selected = index
        Wheel.Refresh()
    end
end

function Wheel.Step(dir)
    local n = table.getn(Wheel.entries)
    if n == 0 then
        return
    end
    local i = (Wheel.selected or 0) + dir
    if i < 1 then i = n end
    if i > n then i = 1 end
    Wheel.selected = i
    Wheel.Refresh()
end

-- LB / RB: the previous or next page of eight, round.
function Wheel.Page(dir)
    local n = table.getn(Wheel.pages)
    if n < 2 then
        return
    end
    Wheel.page = Wheel.page + dir
    if Wheel.page < 1 then Wheel.page = n end
    if Wheel.page > n then Wheel.page = 1 end
    Wheel.selected = nil
    Wheel.Fill()
end

function Wheel.Nav(btn)
    if btn == "A" then
        Wheel.Activate()
    elseif btn == "B" or btn == "START" or btn == "SELECT" then
        Wheel.Close()
    elseif btn == "Y" and Wheel.set == "bots" then
        P.Bots.CycleTarget(1)
        setHint()
    elseif btn == "DRIGHT" or btn == "DDOWN" then
        Wheel.Step(1)
    elseif btn == "DLEFT" or btn == "DUP" then
        Wheel.Step(-1)
    elseif btn == "LB" then
        Wheel.Page(-1)
    elseif btn == "RB" then
        Wheel.Page(1)
    end
end

win:SetScript("OnShow", function() P.mode = "wheel" end)
win:SetScript("OnHide", function()
    if not ((P.Menu and P.Menu.frame:IsVisible()) or (P.Binds and P.Binds.frame:IsVisible())) then
        P.mode = "world"
    end
end)

P.Listen(function(event, a1, a2, a3, a4)
    if not win:IsVisible() then
        return
    end
    if event == "BENILLAPAD_NAV" then
        if a2 then
            Wheel.Nav(a1)
        end
        return true
    elseif event == "BENILLAPAD_STICK" then
        -- The left stick, then the right; the one pushed further aims.
        local lx, ly, rx, ry = a1 or 0, a2 or 0, a3 or 0, a4 or 0
        if rx * rx + ry * ry >= lx * lx + ly * ly then
            Wheel.Aim(rx, ry)
        else
            Wheel.Aim(lx, ly)
        end
    end
end)

local watcher = CreateFrame("Frame", nil, win)
watcher:RegisterEvent("BAG_UPDATE")
watcher:RegisterEvent("BAG_UPDATE_COOLDOWN")
watcher:SetScript("OnEvent", function()
    if Wheel.set == "consumables" and win:IsVisible() then
        local keep = Wheel.selected
        Wheel.Fill()
        if keep and Wheel.entries[keep] then
            Wheel.selected = keep
        end
        Wheel.Refresh()
    end
end)

local elapsedSince = 0
win:SetScript("OnUpdate", function()
    elapsedSince = elapsedSince + arg1
    if elapsedSince > 0.2 then
        elapsedSince = 0
        Wheel.Refresh()
    end
end)

-- ── The quest item ──

local Quest = {}
P.Quest = Quest

-- The first usable quest item in the bags, read off the tooltips: a "Quest Item" line and a
-- "Use:" line (1.12 has no GetItemSpell). Rescanned when the bags change.
local found, dirty = nil, true
local tip = BenillaPadScanTip

function Quest.Find()
    if not dirty then
        return found
    end
    dirty = false
    found = nil
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            if GetContainerItemLink(bag, slot) then
                tip:SetOwner(UIParent, "ANCHOR_NONE")
                tip:SetBagItem(bag, slot)
                local quest, use = false, false
                for line = 1, tip:NumLines() do
                    local text = getglobal("BenillaPadScanTipTextLeft" .. line):GetText() or ""
                    if text == ITEM_BIND_QUEST then
                        quest = true
                    elseif string.find(text, ITEM_SPELL_TRIGGER_ONUSE, 1, true) == 1 then
                        use = true
                    end
                end
                tip:Hide()
                if quest and use then
                    local texture = GetContainerItemInfo(bag, slot)
                    found = { bag = bag, slot = slot, icon = texture }
                    return found
                end
            end
        end
    end
    return nil
end

function Quest.Use()
    local item = Quest.Find()
    if not item then
        UIErrorsFrame:AddMessage("No usable quest item in your bags", 1, 0.1, 0.1, 1, 5)
        return
    end
    UseContainerItem(item.bag, item.slot)
end

local questWatch = CreateFrame("Frame")
questWatch:RegisterEvent("BAG_UPDATE")
questWatch:SetScript("OnEvent", function()
    dirty = true
    if P.Bar then P.Bar.Refresh() end
end)

P.Actions.questitem.iconFn = function()
    local item = Quest.Find()
    return item and item.icon
end
