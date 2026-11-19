-- The gamepad action bar: a D-pad cluster of square slots, a face cluster of round ones, LB and RB
-- above them and L3 and R3 below, showing what each button does on the layer the triggers hold.
-- Round icons are built from horizontal strips of the icon texture, each cropped to the circle's
-- width at its height: 1.12 has no texture masks, and the ring hides the steps.

local P = BenillaPad
local Bar = {}
P.Bar = Bar

local ART = P.ART
local SQUARE = 40
local ROUND = 46
-- The icon art's own border, trimmed.
local TRIM = 0.07
-- The ring art (tools/gen_art.py) is drawn at 1.3x the button: its band covers the round icon's
-- edge.
local RING_SCALE = 1.3

-- The button's glyph (Glyphs.lua) at a corner of the slot.
local BADGE = 22
-- The ring and the square's border at rest; while cooling they take the colour of the share left.
local RING_COLOR = { 0.85, 0.72, 0.5 }
-- The global cooldown and shorter are not shown (GamepadBar's GCD_MAX).
local GCD_MAX = 1.6
-- The "ready" flash when a cooldown ends, seconds.
local FLASH_TIME = 0.6

-- Where each button sits, from the bar's centre.
local DPAD_X, FACE_X, STEP = -150, 150, 46
local PLACE = {
    DUP = { DPAD_X, STEP }, DDOWN = { DPAD_X, -STEP },
    DLEFT = { DPAD_X - STEP, 0 }, DRIGHT = { DPAD_X + STEP, 0 },
    Y = { FACE_X, STEP + 2 }, A = { FACE_X, -STEP - 2 },
    X = { FACE_X - STEP - 2, 0 }, B = { FACE_X + STEP + 2, 0 },
    LB = { DPAD_X - 100, 92 }, RB = { FACE_X + 100, 92 },
    L3 = { -52, -88 }, R3 = { 52, -88 },
}
local ROUND_KEYS = { Y = true, B = true, A = true, X = true, LB = true, RB = true, L3 = true, R3 = true }

local frame = CreateFrame("Frame", "BenillaPadBar", UIParent)
frame:SetWidth(560)
frame:SetHeight(260)
frame:SetFrameStrata("MEDIUM")
frame:Hide()
Bar.frame = frame
Bar.buttons = {}

local layerText = frame:CreateFontString(nil, "OVERLAY")
layerText:SetFont("Fonts\\FRIZQT__.TTF", 22, "OUTLINE")
layerText:SetPoint("CENTER", frame, "CENTER", 0, 4)
layerText:SetTextColor(1, 0.82, 0)

-- The action sets as three tabs under the label (a crossbar's set indicator): the one the
-- triggers hold is lit in its own colour, the others dim, so the set in play reads at a glance
-- and the other sets are seen to exist.
local LAYER_COLOR = {
    bare = { 1, 0.82, 0 }, lt = { 0.35, 0.75, 1 }, rt = { 1, 0.45, 0.3 }, ltrt = { 0.75, 0.5, 1 },
}
local TABS = { { "lt", "LT" }, { "ltrt", "LT+RT" }, { "rt", "RT" } }
local tabs = {}
for i = 1, 3 do
    local t = CreateFrame("Frame", nil, frame)
    t:SetWidth(58)
    t:SetHeight(16)
    t:SetPoint("CENTER", frame, "CENTER", (i - 2) * 62, -22)
    local bg = t:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(t)
    t.bg = bg
    local text = t:CreateFontString(nil, "OVERLAY")
    text:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    text:SetPoint("CENTER", t, "CENTER", 0, 0)
    text:SetText(TABS[i][2])
    t.text = text
    tabs[i] = t
end

local function paintTabs()
    for i = 1, 3 do
        local t, layer = tabs[i], TABS[i][1]
        local c = LAYER_COLOR[layer]
        if P.layer == layer then
            t.bg:SetTexture(c[1], c[2], c[3], 0.85)
            t.text:SetTextColor(0, 0, 0)
        else
            t.bg:SetTexture(0, 0, 0, 0.4)
            t.text:SetTextColor(c[1], c[2], c[3])
        end
    end
    local c = LAYER_COLOR[P.layer] or LAYER_COLOR.bare
    layerText:SetTextColor(c[1], c[2], c[3])
    Bar.PaintPips()
end

-- Set pips (GamepadBar's): four dots between the clusters, one per set in P.LAYERS order (none,
-- LT, RT, LT+RT); the held set's is lit gold and larger.
local PIP_LIT, PIP_DIM, PIP_STEP, PIP_Y = 11, 8, 16, 34
local pips = {}
for i = 1, table.getn(P.LAYERS) do
    local d = frame:CreateTexture(nil, "OVERLAY")
    d:SetTexture(ART .. "Disc")
    d:SetWidth(PIP_DIM)
    d:SetHeight(PIP_DIM)
    d:SetVertexColor(0.45, 0.45, 0.45, 0.7)
    d:SetPoint("CENTER", frame, "CENTER", (i - (table.getn(P.LAYERS) + 1) / 2) * PIP_STEP, PIP_Y)
    pips[i] = d
end

function Bar.PaintPips()
    for i = 1, table.getn(pips) do
        local d = pips[i]
        if P.LAYERS[i] == P.layer then
            d:SetWidth(PIP_LIT)
            d:SetHeight(PIP_LIT)
            d:SetVertexColor(1, 0.82, 0, 1)
        else
            d:SetWidth(PIP_DIM)
            d:SetHeight(PIP_DIM)
            d:SetVertexColor(0.45, 0.45, 0.45, 0.7)
        end
    end
end

-- The buttons that carry the other sets' previews, and a preview's size.
local PEEK_KEYS = {
    DUP = true, DDOWN = true, DLEFT = true, DRIGHT = true, A = true, B = true, X = true, Y = true,
}
local PEEK = 15

-- ── Building a button ──

local function newIconSquare(b, size)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(size - 4)
    icon:SetHeight(size - 4)
    icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    icon:SetTexCoord(TRIM, 1 - TRIM, TRIM, 1 - TRIM)
    b.strips = { icon }
end

local function newIconRound(b, size)
    b.strips = P.NewRoundIcon(b, size * 0.9)
end

local function newButton(key)
    local round = ROUND_KEYS[key]
    local size = round and ROUND or SQUARE
    if key == "LB" or key == "RB" or key == "L3" or key == "R3" then
        size = 40
    end
    local b = CreateFrame("Button", "BenillaPadButton" .. key, frame)
    b:SetWidth(size)
    b:SetHeight(size)
    b.key = key
    b.round = round
    b.size = size

    if round then
        local shadow = b:CreateTexture(nil, "BACKGROUND")
        shadow:SetTexture(ART .. "Disc")
        shadow:SetVertexColor(0, 0, 0, 0.65)
        shadow:SetWidth(size * 0.95)
        shadow:SetHeight(size * 0.95)
        shadow:SetPoint("CENTER", b, "CENTER", 0, 0)
        newIconRound(b, size)
        local ring = b:CreateTexture(nil, "OVERLAY")
        ring:SetTexture(ART .. "Ring")
        ring:SetVertexColor(RING_COLOR[1], RING_COLOR[2], RING_COLOR[3])
        ring:SetWidth(size * RING_SCALE)
        ring:SetHeight(size * RING_SCALE)
        ring:SetPoint("CENTER", b, "CENTER", 0, 0)
        b.ring = ring
        b.ringRest = RING_COLOR
        local hi = b:CreateTexture(nil, "OVERLAY")
        hi:SetTexture(ART .. "RingSelect")
        hi:SetWidth(size * RING_SCALE)
        hi:SetHeight(size * RING_SCALE)
        hi:SetPoint("CENTER", b, "CENTER", 0, 0)
        hi:Hide()
        b.pressed = hi
    else
        local slot = b:CreateTexture(nil, "BACKGROUND")
        slot:SetTexture("Interface\\Buttons\\UI-Quickslot")
        slot:SetWidth(size * 64 / 36)
        slot:SetHeight(size * 64 / 36)
        slot:SetPoint("CENTER", b, "CENTER", 0, 0)
        newIconSquare(b, size)
        local border = b:CreateTexture(nil, "OVERLAY")
        border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        border:SetWidth(size * 66 / 36)
        border:SetHeight(size * 66 / 36)
        border:SetPoint("CENTER", b, "CENTER", 0, -1)
        b.ring = border
        b.ringRest = { 1, 1, 1 }
        local hi = b:CreateTexture(nil, "OVERLAY")
        hi:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        hi:SetBlendMode("ADD")
        hi:SetAllPoints(b)
        hi:Hide()
        b.pressed = hi
    end

    local cd
    if round then
        -- Inside the ring's band (0.43 of the button), so the ring stays unshaded.
        cd = P.NewRoundSweep(b, size * 0.86)
    else
        cd = CreateFrame("Model", "BenillaPadButton" .. key .. "Cooldown", b, "CooldownFrameTemplate")
        cd:SetWidth(size * 0.9)
        cd:SetHeight(size * 0.9)
        cd:SetPoint("CENTER", b, "CENTER", 0, 0)
    end
    b.cooldown = cd

    -- Text sits on a child above the cooldown model.
    local over = CreateFrame("Frame", nil, b)
    over:SetAllPoints(b)
    over:SetFrameLevel(cd:GetFrameLevel() + 2)

    local timer = over:CreateFontString(nil, "OVERLAY")
    timer:SetFont("Fonts\\FRIZQT__.TTF", size * 0.42, "OUTLINE")
    timer:SetPoint("CENTER", b, "CENTER", 0, 0)
    timer:SetTextColor(1, 1, 1)
    b.timer = timer

    local count = over:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    b.count = count

    -- The "ready" flash: a light over the slot that fades when a cooldown ends.
    local flash = over:CreateTexture(nil, "ARTWORK")
    if round then
        flash:SetTexture(ART .. "RingSelect")
        flash:SetWidth(size * RING_SCALE)
        flash:SetHeight(size * RING_SCALE)
        flash:SetPoint("CENTER", b, "CENTER", 0, 0)
    else
        flash:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        flash:SetAllPoints(b)
    end
    flash:SetBlendMode("ADD")
    flash:Hide()
    b.flash = flash

    local badge = P.NewGlyph(over, BADGE, "OVERLAY")
    badge:SetPoint("CENTER", b, "TOPRIGHT", -3, -3)
    b.badge = badge
    if PLACE[key][1] < 0 and (key == "LB" or key == "L3") then
        badge:ClearAllPoints()
        badge:SetPoint("CENTER", b, "TOPLEFT", 3, -3)
    end
    -- The D-pad reads by its diamond; no badge.
    if string.sub(key, 1, 1) == "D" then
        badge:Hide()
        b.noBadge = true
    end

    -- Two small previews at the bottom corners (a crossbar's satellites): what the button
    -- holds on the other two trigger sets, so the layout reads without holding a trigger.
    if PEEK_KEYS[key] then
        b.peeks = {}
        for i = 1, 2 do
            local edge = over:CreateTexture(nil, "ARTWORK")
            edge:SetWidth(PEEK + 2)
            edge:SetHeight(PEEK + 2)
            local icon = over:CreateTexture(nil, "OVERLAY")
            icon:SetWidth(PEEK)
            icon:SetHeight(PEEK)
            icon:SetTexCoord(TRIM, 1 - TRIM, TRIM, 1 - TRIM)
            if i == 1 then
                edge:SetPoint("CENTER", b, "BOTTOMLEFT", 3, 3)
            else
                edge:SetPoint("CENTER", b, "BOTTOMRIGHT", -3, 3)
            end
            icon:SetPoint("CENTER", edge, "CENTER", 0, 0)
            edge:Hide()
            icon:Hide()
            b.peeks[i] = { edge = edge, icon = icon }
        end
    end

    -- The mouse: drop a spell or item on a button, drag one off, read its tooltip.
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnReceiveDrag", function()
        P.Binds.Drop(this.key, P.layer)
    end)
    b:SetScript("OnClick", function()
        if CursorHasSpell() or CursorHasItem() then
            P.Binds.Drop(this.key, P.layer)
        end
    end)
    b:SetScript("OnDragStart", function()
        if this.slot and HasAction(this.slot) then
            PickupAction(this.slot)
            P.SetOverride(this.key, P.layer, { slot = true })
        end
    end)
    b:SetScript("OnEnter", function()
        if this.slot and HasAction(this.slot) then
            GameTooltip:SetOwner(this, "ANCHOR_TOP")
            GameTooltip:SetAction(this.slot)
        end
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    b:SetPoint("CENTER", frame, "CENTER", PLACE[key][1], PLACE[key][2])
    Bar.buttons[key] = b
    return b
end

for i = 1, table.getn(P.BUTTONS) do
    newButton(P.BUTTONS[i])
end

-- ── Updating ──

local function setIcon(b, tex)
    P.SetIcon(b.strips, tex)
end

local function tintIcon(b, r, g, bl)
    P.TintIcon(b.strips, r, g, bl)
end

local function setCooldown(b, start, duration, enable)
    if b.round then
        P.SetSweep(b.cooldown, start, duration, enable)
    else
        CooldownFrame_SetTimer(b.cooldown, start, duration, enable)
    end
end

local function setGlyph(b)
    if not b.noBadge then
        P.SetGlyph(b.badge, b.key)
    end
end

-- GamepadBar's cooldown colour by the share left: red, orange, yellow, then green.
local function shareColor(share)
    if share > 0.75 then
        return 1, 0.25, 0.2
    elseif share > 0.5 then
        return 1, 0.55, 0.1
    elseif share > 0.25 then
        return 1, 0.9, 0.2
    end
    return 0.35, 1, 0.35
end

-- Short countdown text: "2h", "2m", "45".
local function shortTime(left)
    if left >= 3600 then
        return math.ceil(left / 3600) .. "h"
    elseif left >= 60 then
        return math.ceil(left / 60) .. "m"
    end
    return tostring(math.ceil(left))
end

-- The countdown, its colour, and the flash when it ends. `what` names the slot or spell the
-- cooldown belongs to, so a layer change is not taken for a cooldown ending.
local function showCooldown(b, what, start, duration, enable)
    local left = 0
    if enable == 1 and duration and duration > GCD_MAX then
        left = start + duration - GetTime()
    end
    local rest = b.ringRest
    if left > 0 then
        local r, g, bl = shareColor(left / duration)
        b.timer:SetText(shortTime(left))
        b.timer:SetTextColor(r, g, bl)
        b.ring:SetVertexColor(r, g, bl)
        b.cooling = what
    else
        b.timer:SetText("")
        if b.cooling then
            b.ring:SetVertexColor(rest[1], rest[2], rest[3])
            if b.cooling == what then
                b.flashStart = GetTime()
                b.flash:SetVertexColor(1, 1, 1, 1)
                b.flash:Show()
            end
            b.cooling = nil
        end
    end
end

local function clearCooldown(b)
    b.timer:SetText("")
    if b.cooling then
        local rest = b.ringRest
        b.ring:SetVertexColor(rest[1], rest[2], rest[3])
        b.cooling = nil
    end
end

-- The flash's fade, every frame while one shows.
local function fadeFlash(b)
    if not b.flashStart then
        return
    end
    local t = (GetTime() - b.flashStart) / FLASH_TIME
    if t >= 1 then
        b.flashStart = nil
        b.flash:Hide()
    else
        b.flash:SetVertexColor(1, 1, 1, 1 - t)
    end
end

-- The icon of a button's binding on a layer, or nil for an empty slot.
local function iconOf(key, layer)
    local kind, value = P.Binding(key, layer)
    if kind == "form" then
        return value.icon
    elseif kind == "slot" then
        local slot = P.PagedSlot(value)
        return HasAction(slot) and GetActionTexture(slot) or nil
    elseif kind == "action" then
        return P.ActionIcon(value)
    end
    return nil
end

-- The previews: left the LT set, right the RT set; the set the triggers hold gives its corner to
-- the bare set, so every other set stays in sight.
local function updatePeeks(b)
    if not b.peeks then
        return
    end
    local on = P.Setting("peek")
    local layers = { (P.layer == "lt") and "bare" or "lt", (P.layer == "rt") and "bare" or "rt" }
    for i = 1, 2 do
        local peek, layer = b.peeks[i], layers[i]
        local tex = on and iconOf(b.key, layer)
        if tex then
            local c = LAYER_COLOR[layer]
            peek.edge:SetTexture(c[1], c[2], c[3], 0.95)
            peek.icon:SetTexture(tex)
            peek.edge:Show()
            peek.icon:Show()
        else
            peek.edge:Hide()
            peek.icon:Hide()
        end
    end
end

-- What a button shows: its binding on the held layer.
function Bar.UpdateButton(b)
    local kind, value = P.Binding(b.key, P.layer)
    b.slot = nil
    b.spellIndex = nil
    local tex
    if kind == "form" then
        tex = value.icon
        b.spellIndex = value.spell and P.SpellIndex(value.spell, value.rank)
    elseif kind == "slot" then
        b.slot = P.PagedSlot(value)
        tex = GetActionTexture(b.slot)
    elseif kind == "action" then
        tex = P.ActionIcon(value)
    end
    setIcon(b, tex)
    setGlyph(b)
    updatePeeks(b)
    if b.slot and HasAction(b.slot) then
        setCooldown(b, GetActionCooldown(b.slot))
        if IsConsumableAction(b.slot) then
            b.count:SetText(GetActionCount(b.slot))
        else
            b.count:SetText("")
        end
    elseif b.spellIndex then
        setCooldown(b, GetSpellCooldown(b.spellIndex, "spell"))
        b.count:SetText("")
    else
        b.cooldown:Hide()
        b.count:SetText("")
    end
    Bar.UpdateState(b)
end

-- The fast-changing look: range and power tint, the countdown, the press highlight.
function Bar.UpdateState(b)
    if P.held[b.key] then
        b.pressed:Show()
    else
        b.pressed:Hide()
    end
    local slot = b.slot
    if b.spellIndex then
        tintIcon(b, 1, 1, 1)
        local start, duration, enable = GetSpellCooldown(b.spellIndex, "spell")
        showCooldown(b, "spell" .. b.spellIndex, start, duration, enable)
        return
    end
    if not slot or not HasAction(slot) then
        tintIcon(b, 1, 1, 1)
        clearCooldown(b)
        return
    end
    local usable, noMana = IsUsableAction(slot)
    if IsActionInRange(slot) == 0 then
        tintIcon(b, 1, 0.5, 0.5)
    elseif usable then
        tintIcon(b, 1, 1, 1)
    elseif noMana then
        tintIcon(b, 0.4, 0.45, 1)
    else
        tintIcon(b, 0.4, 0.4, 0.4)
    end
    local start, duration, enable = GetActionCooldown(slot)
    showCooldown(b, "slot" .. slot, start, duration, enable)
end

-- The stock bars, gone while the gamepad bar shows: each is hidden and moved under a hidden frame,
-- and its OnShow hides it again, so nothing in the stock code brings it back; afterwards it returns
-- to its own parent and shown state. The pet bar stays.
local STOCK = { "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft", "MultiBarRight" }
local hider = CreateFrame("Frame")
hider:Hide()
local stockState = {}
local stockHidden = false

local function guardOnShow(f, name)
    if f.benillaPadGuard then
        return
    end
    f.benillaPadGuard = true
    local old = f:GetScript("OnShow")
    f:SetScript("OnShow", function()
        if stockHidden then
            this:Hide()
            return
        end
        if old then
            old()
        end
    end)
end

-- The new-player tutorial alerts sit above the stock bar (TutorialFrameParent, BOTTOM +55), where
-- the pad bar's stick buttons now are: they move to the bar's left while it shows.
local function placeTutorials(onBar)
    local parent = TutorialFrameParent
    if not parent then
        return
    end
    parent:ClearAllPoints()
    if onBar then
        parent:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", -8, 24)
    else
        parent:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 55)
    end
end

function Bar.StockBar()
    local hide = (P.Setting("hideStockBars") and frame:IsShown()) and true or false
    if hide == stockHidden then
        return
    end
    stockHidden = hide
    placeTutorials(hide)
    for i = 1, table.getn(STOCK) do
        local name = STOCK[i]
        local f = getglobal(name)
        if f then
            if hide then
                stockState[name] = { parent = f:GetParent(), shown = f:IsShown() }
                guardOnShow(f, name)
                f:Hide()
                f:SetParent(hider)
            elseif stockState[name] then
                local was = stockState[name]
                f:SetParent(was.parent)
                -- benilla keeps a frame moved back from a hidden parent invisible; a Hide and
                -- Show recomputes it, as 1.12's SetParent does by itself.
                f:Hide()
                if was.shown then
                    f:Show()
                end
            end
        end
    end
end

function Bar.Layout()
    frame:SetScale(P.Setting("scale"))
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, P.Setting("offsetY"))
end

function Bar.Refresh()
    if P.connected or P.Setting("alwaysShow") then
        frame:Show()
    else
        frame:Hide()
    end
    Bar.StockBar()
    if P.Xp then
        P.Xp.Refresh()
    end
    if not frame:IsShown() then
        return
    end
    layerText:SetText(P.LAYER_LABEL[P.layer] or "")
    paintTabs()
    for key, b in pairs(Bar.buttons) do
        Bar.UpdateButton(b)
    end
end

-- ── Events ──

P.Listen(function(event, arg1, arg2)
    if event == "BENILLAPAD_BUTTON" then
        local b = Bar.buttons[arg1]
        if b and frame:IsVisible() then
            Bar.UpdateState(b)
        end
    else
        Bar.Refresh()
    end
end)

local watcher = CreateFrame("Frame", nil, frame)
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
watcher:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
watcher:RegisterEvent("ACTIONBAR_UPDATE_USABLE")
watcher:RegisterEvent("ACTIONBAR_UPDATE_STATE")
watcher:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
watcher:RegisterEvent("PLAYER_TARGET_CHANGED")
watcher:RegisterEvent("BAG_UPDATE")
watcher:RegisterEvent("SPELL_UPDATE_COOLDOWN")
watcher:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
watcher:SetScript("OnEvent", function()
    if event == "PLAYER_ENTERING_WORLD" then
        Bar.Layout()
    end
    Bar.Refresh()
end)

-- Range, power and countdowns move without events: ten times a second.
local elapsedSince = 0
frame:SetScript("OnUpdate", function()
    -- A wheel is drawn over the screen's centre: the bar steps out of its way while one is open.
    local alpha = (P.mode == "wheel") and 0 or 1
    if frame:GetAlpha() ~= alpha then
        frame:SetAlpha(alpha)
    end
    for key, b in pairs(Bar.buttons) do
        if b.flashStart then
            fadeFlash(b)
        end
    end
    elapsedSince = elapsedSince + arg1
    if elapsedSince < 0.1 then
        return
    end
    elapsedSince = 0
    for key, b in pairs(Bar.buttons) do
        Bar.UpdateState(b)
    end
end)

-- ── Cooldowns from the other layers ──
-- A row above the bar: what is cooling down (past the global cooldown) on the layers the
-- triggers do not hold, soonest first, so a trigger need not be held to check.

local ROW_MAX, ROW_ICON = 10, 26
local row = CreateFrame("Frame", nil, frame)
row:SetWidth(ROW_MAX * (ROW_ICON + 4))
row:SetHeight(ROW_ICON)
row:SetPoint("BOTTOM", frame, "TOP", 0, 2)
local rowIcons = {}
for i = 1, ROW_MAX do
    local f = CreateFrame("Frame", nil, row)
    f:SetWidth(ROW_ICON)
    f:SetHeight(ROW_ICON)
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(f)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon:SetVertexColor(0.6, 0.6, 0.6)
    f.icon = icon
    local text = f:CreateFontString(nil, "OVERLAY")
    text:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    text:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.text = text
    local layer = f:CreateFontString(nil, "OVERLAY")
    layer:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
    layer:SetPoint("BOTTOM", f, "TOP", 0, 1)
    layer:SetTextColor(1, 0.82, 0)
    f.layer = layer
    f:Hide()
    rowIcons[i] = f
end

local function cooldownLeft(start, duration, enable)
    if enable == 1 and duration and duration > 1.6 then
        return start + duration - GetTime()
    end
    return 0
end

function Bar.UpdateCooldownRow()
    local list = {}
    if P.Setting("layerCooldowns") then
        for l = 1, table.getn(P.LAYERS) do
            local layer = P.LAYERS[l]
            if layer ~= P.layer then
                for i = 1, table.getn(P.BUTTONS) do
                    local kind, value = P.Binding(P.BUTTONS[i], layer)
                    local tex, left = nil, 0
                    if kind == "slot" then
                        local slot = P.PagedSlot(value)
                        if HasAction(slot) then
                            tex = GetActionTexture(slot)
                            left = cooldownLeft(GetActionCooldown(slot))
                        end
                    elseif kind == "form" and value.spell then
                        local index = P.SpellIndex(value.spell, value.rank)
                        if index then
                            tex = value.icon
                            left = cooldownLeft(GetSpellCooldown(index, "spell"))
                        end
                    end
                    if tex and left > 0 then
                        table.insert(list, { tex = tex, left = left, layer = P.LAYER_LABEL[layer] })
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.left < b.left end)
    local n = math.min(table.getn(list), ROW_MAX)
    for i = 1, ROW_MAX do
        local f = rowIcons[i]
        local e = list[i]
        if e and i <= n then
            f:ClearAllPoints()
            f:SetPoint("LEFT", row, "LEFT", (ROW_MAX - n) * (ROW_ICON + 4) / 2 + (i - 1) * (ROW_ICON + 4), 0)
            f.icon:SetTexture(e.tex)
            if e.left >= 60 then
                f.text:SetText(math.ceil(e.left / 60) .. "m")
            else
                f.text:SetText(math.ceil(e.left))
            end
            if e.layer == "" then f.layer:SetText("-") else f.layer:SetText(e.layer) end
            f:Show()
        else
            f:Hide()
        end
    end
end

local rowElapsed = 0
row:SetScript("OnUpdate", function()
    rowElapsed = rowElapsed + arg1
    if rowElapsed > 0.25 then
        rowElapsed = 0
        Bar.UpdateCooldownRow()
    end
end)

Bar.Layout()
