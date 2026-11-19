-- Game windows with the pad. While a stock window that wants the pointer is open (bags, vendor,
-- loot, quest, gossip, trainer, mail, popups, ...), BenillaPad_Mode() answers "cursor": the Rust
-- side moves the mouse cursor with the right stick, clicks with A (left) and X (right), closes
-- with B (the Escape ladder), scrolls with LB / RB, and snaps to the nearest button with the
-- D-pad through BenillaPad_Snap. The left stick still walks.

local P = BenillaPad
local Cursor = {}
P.Cursor = Cursor

-- The stock windows that take the pointer, by global name.
local WINDOWS = {
    "MerchantFrame", "LootFrame", "QuestFrame", "GossipFrame", "ClassTrainerFrame", "TaxiFrame",
    "BankFrame", "MailFrame", "OpenMailFrame", "AuctionFrame", "TradeFrame", "CharacterFrame",
    "SpellBookFrame", "TalentFrame", "QuestLogFrame", "WorldMapFrame", "FriendsFrame",
    "GameMenuFrame", "OptionsFrame", "SoundOptionsFrame", "UIOptionsFrame", "KeyBindingFrame",
    "MacroFrame", "PetStableFrame", "TradeSkillFrame", "CraftFrame", "InspectFrame",
    "ItemTextFrame", "GuildRegistrarFrame", "PetitionFrame", "TabardFrame", "HelpFrame",
    "DressUpFrame", "BattlefieldFrame", "PetPaperDollFrame", "AddonList",
    "StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4",
    "GroupLootFrame1", "GroupLootFrame2", "GroupLootFrame3", "GroupLootFrame4",
}
for i = 1, 12 do
    table.insert(WINDOWS, "ContainerFrame" .. i)
end

-- The open windows, as a set of frames.
function Cursor.Open()
    local open, any = {}, false
    for i = 1, table.getn(WINDOWS) do
        local f = getglobal(WINDOWS[i])
        if f and f:IsVisible() then
            open[f] = true
            any = true
        end
    end
    return open, any
end

function Cursor.Wanted()
    if not P.Setting("padCursor") then
        return false
    end
    local _, any = Cursor.Open()
    return any
end

-- Add the visible buttons under `f` to `list`. Only shown frames are entered, so a window's
-- hidden tabs and pages cost nothing.
local function collect(f, list, depth)
    local children = { f:GetChildren() }
    for i = 1, table.getn(children) do
        local c = children[i]
        if c:IsVisible() then
            local kind = c:GetObjectType()
            if kind == "Button" or kind == "CheckButton" then
                local left, bottom = c:GetLeft(), c:GetBottom()
                local w, h = c:GetWidth(), c:GetHeight()
                if left and bottom and w > 4 and h > 4 then
                    local s = c:GetEffectiveScale()
                    table.insert(list, { x = (left + w / 2) * s, y = (bottom + h / 2) * s, frame = c })
                end
            end
            if depth < 8 then
                collect(c, list, depth + 1)
            end
        end
    end
end

-- The clickable buttons of the open windows, as { x, y } centres in absolute units (UI units
-- times the effective scale; 768 is the screen's height). It walks each open window's own
-- children: a walk over every frame in the game (EnumerateFrames) costs tens of milliseconds a
-- press once addons have made thousands of them.
function Cursor.Targets()
    local open = Cursor.Open()
    local list = {}
    for f in pairs(open) do
        collect(f, list, 1)
    end
    return list
end

-- Popups whose first button can't be undone (StaticPopup.lua's `which`): the cursor lands on
-- Cancel instead, so a stray A press never deletes, abandons, binds or wipes anything.
local DESTRUCTIVE = {
    DELETE_ITEM = true, DELETE_GOOD_ITEM = true, ABANDON_QUEST = true,
    ABANDON_QUEST_WITH_ITEMS = true, ABANDON_PET = true, CONFIRM_TALENT_WIPE = true,
    CONFIRM_BINDER = true, UNLEARN_SKILL = true, DELETE_MAIL = true, CONFIRM_GUILD_DISBAND = true,
    CONFIRM_GUILD_LEAVE = true, CONFIRM_RESET_INSTANCES = true, CONFIRM_LOOT_DISTRIBUTION = true,
    CONFIRM_BUY_BANK_SLOT = true, CONFIRM_BUY_STABLE_SLOT = true, EQUIP_BIND = true,
    AUTOEQUIP_BIND = true, LOOT_BIND = true, USE_BIND = true, QUIT = true, CAMP = true,
    CONFIRM_TEAM_DISBAND = true, CONFIRM_REMOVE_FRIEND = true,
}
Cursor.DESTRUCTIVE = DESTRUCTIVE

-- The button "enter" snaps an open popup to: its second (Cancel) on a destructive popup.
function Cursor.PopupButton(i)
    local popup = getglobal("StaticPopup" .. i)
    if not (popup and popup:IsVisible()) then
        return nil
    end
    local index = 1
    local second = getglobal("StaticPopup" .. i .. "Button2")
    if popup.which and DESTRUCTIVE[popup.which] and second and second:IsVisible() then
        index = 2
    end
    return getglobal("StaticPopup" .. i .. "Button" .. index)
end

-- ── The primary button ──
-- What A most likely wants in the open windows (a console UI's default focus): a popup's button,
-- a quest's Accept / Continue / Complete, the first gossip option, the first loot, the trainer's
-- Train. The pointer lands on it when the windows change, so a quest hand-in is A, A, A.

local function shown(name)
    local f = getglobal(name)
    if f and f:IsVisible() then
        return f
    end
    return nil
end

-- A shown button that is not greyed out (1.12's IsEnabled answers 1 or nil / 0).
local function usable(name)
    local f = shown(name)
    if f and f.IsEnabled then
        local e = f:IsEnabled()
        if not e or e == 0 then
            return nil
        end
    end
    return f
end

function Cursor.Primary()
    for i = 1, 4 do
        local button = Cursor.PopupButton(i)
        if button and button:IsVisible() then
            return button
        end
    end
    if shown("QuestFrame") then
        if shown("QuestFrameDetailPanel") then
            return shown("QuestFrameAcceptButton")
        end
        if shown("QuestFrameProgressPanel") then
            return usable("QuestFrameCompleteButton") or shown("QuestFrameGoodbyeButton")
        end
        if shown("QuestFrameRewardPanel") then
            -- A reward to choose first; once one is chosen, the hand-in.
            local chosen = QuestFrameRewardPanel.itemChoice or 0
            if GetNumQuestChoices and GetNumQuestChoices() > 1 and chosen == 0 then
                return shown("QuestRewardItem1")
            end
            return usable("QuestFrameCompleteQuestButton")
        end
        if shown("QuestFrameGreetingPanel") then
            return shown("QuestTitleButton1") or shown("QuestFrameGreetingGoodbyeButton")
        end
        -- Any other state of the window: its way out.
        return shown("QuestFrameGoodbyeButton") or shown("QuestFrameGreetingGoodbyeButton")
            or shown("QuestFrameCloseButton")
    end
    if shown("GossipFrame") then
        return shown("GossipTitleButton1") or shown("GossipFrameGreetingGoodbyeButton")
    end
    if shown("LootFrame") then
        return shown("LootButton1")
    end
    if shown("ClassTrainerFrame") then
        return usable("ClassTrainerTrainButton")
    end
    if shown("MerchantFrame") then
        return shown("MerchantItem1ItemButton")
    end
    if shown("TaxiFrame") then
        return nil
    end
    if shown("GameMenuFrame") then
        return shown("GameMenuButtonContinue")
    end
    return nil
end

-- A number that steps each time the primary button becomes another one: the Rust side moves the
-- pointer onto it when the number changes (BenillaPad_Mode's third answer).
local serial, lastKey = 0, ""
function Cursor.Serial()
    local f = Cursor.Primary()
    local key = f and f:GetName() or ""
    if key ~= lastKey then
        lastKey = key
        if f then
            serial = serial + 1
        end
    end
    return serial
end

-- The button to jump to from (x, y) toward `dir` (DUP / DDOWN / DLEFT / DRIGHT), or, for "enter",
-- the primary button (Cancel on a destructive popup). Answers absolute units, or nothing.
function BenillaPad_Snap(dir, x, y)
    if dir == "enter" then
        local button = Cursor.Primary()
        if button and button:GetLeft() then
            Cursor.Snapped(button)
            local s = button:GetEffectiveScale()
            return (button:GetLeft() + button:GetWidth() / 2) * s,
                (button:GetBottom() + button:GetHeight() / 2) * s
        end
        return nil
    end
    local best, bestScore
    local targets = Cursor.Targets()
    for i = 1, table.getn(targets) do
        local t = targets[i]
        local dx, dy = t.x - x, t.y - y
        local along, across
        if dir == "DUP" then along, across = dy, dx
        elseif dir == "DDOWN" then along, across = -dy, dx
        elseif dir == "DLEFT" then along, across = -dx, dy
        else along, across = dx, dy end
        if along > 4 then
            local score = along + 2 * math.abs(across)
            if not bestScore or score < bestScore then
                best, bestScore = t, score
            end
        end
    end
    if best then
        Cursor.Snapped(best.frame)
        return best.x, best.y
    end
    return nil
end

-- ── The focus glow ──
-- A gold outline round the button under the pad cursor (a console UI's frame focus), so the
-- pointer is never lost: the OS cursor is small, the outline follows whatever it is over. Two
-- looks: a button the D-pad snapped to (BenillaPad_Snap) gets Forever's SmartNav focus, a gold
-- arrow bobbing at its left edge and a thin gold stroke round it (Art/Focus_Arrow and
-- Art/Focus_Select, ImprovedForever's ic_tri and ic_select, MIT); once the stick moves the
-- pointer off it, the plainer outline and faint fill follow the pointer. Drawn in the TOOLTIP
-- strata over the windows it outlines.

local glow = CreateFrame("Frame", "BenillaPadFocusGlow", UIParent)
glow:SetFrameStrata("TOOLTIP")
glow:Hide()
local function edge()
    local t = glow:CreateTexture(nil, "OVERLAY")
    t:SetTexture(1, 0.82, 0.2, 0.95)
    return t
end
local TH = 2
local top, bottom, left, right = edge(), edge(), edge(), edge()
top:SetPoint("TOPLEFT", glow, "TOPLEFT", 0, 0)
top:SetPoint("TOPRIGHT", glow, "TOPRIGHT", 0, 0)
top:SetHeight(TH)
bottom:SetPoint("BOTTOMLEFT", glow, "BOTTOMLEFT", 0, 0)
bottom:SetPoint("BOTTOMRIGHT", glow, "BOTTOMRIGHT", 0, 0)
bottom:SetHeight(TH)
left:SetPoint("TOPLEFT", glow, "TOPLEFT", 0, 0)
left:SetPoint("BOTTOMLEFT", glow, "BOTTOMLEFT", 0, 0)
left:SetWidth(TH)
right:SetPoint("TOPRIGHT", glow, "TOPRIGHT", 0, 0)
right:SetPoint("BOTTOMRIGHT", glow, "BOTTOMRIGHT", 0, 0)
right:SetWidth(TH)
local fill = glow:CreateTexture(nil, "ARTWORK")
fill:SetAllPoints(glow)
fill:SetTexture(1, 0.82, 0.2, 0.12)
local plain = { top, bottom, left, right, fill }

-- The snapped look: the stroke just outside the button, the arrow left of it. ic_tri points
-- down; the 8-value texcoord turns it a quarter left, to point right.
local stroke = P.AddSelect(glow, { corner = 6, out = 0, hollow = true, layer = "OVERLAY" })
local arrow = glow:CreateTexture(nil, "OVERLAY")
arrow:SetTexture(P.ART .. "Focus_Arrow")
arrow:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1)
arrow:SetVertexColor(1, 0.82, 0.2)
arrow:SetWidth(18)
arrow:SetHeight(18)
arrow:Hide()

-- The button the last D-pad snap landed on, and when.
local snapped, snapAt = nil, 0
function Cursor.Snapped(f)
    snapped = f
    snapAt = GetTime()
end

local function look(isSnapped)
    for i = 1, table.getn(plain) do
        if isSnapped then plain[i]:Hide() else plain[i]:Show() end
    end
    P.ShowSelect(stroke, isSnapped)
    if isSnapped then arrow:Show() else arrow:Hide() end
end

local glowElapsed = 0
local poll = CreateFrame("Frame", nil, UIParent)
poll:SetScript("OnUpdate", function()
    glowElapsed = glowElapsed + arg1
    if glowElapsed < 0.05 then
        return
    end
    glowElapsed = 0
    if not (P.connected and P.mode == "world" and Cursor.Wanted()) then
        snapped = nil
        glow:Hide()
        return
    end
    local f = GetMouseFocus()
    -- A snap holds while the pointer is on its button, and for a moment while it gets there.
    if snapped and (not snapped:IsVisible() or (f ~= snapped and GetTime() - snapAt > 0.3)) then
        snapped = nil
    end
    if snapped then
        f = snapped
    end
    local kind = f and f.GetObjectType and f:GetObjectType()
    if not (f and (kind == "Button" or kind == "CheckButton") and f:IsVisible() and f:GetLeft()) then
        glow:Hide()
        return
    end
    -- In UIParent's units: the button's absolute rectangle over UIParent's scale.
    local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    glow:ClearAllPoints()
    glow:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", f:GetLeft() * s - 3, f:GetBottom() * s - 3)
    glow:SetWidth(f:GetWidth() * s + 6)
    glow:SetHeight(f:GetHeight() * s + 6)
    look(snapped ~= nil)
    if snapped then
        -- Forever's bob: 3 px in and out over 0.8 s.
        local bob = 3 * math.sin(GetTime() * 2 * math.pi / 0.8)
        arrow:ClearAllPoints()
        arrow:SetPoint("RIGHT", glow, "LEFT", bob - 1, 0)
    end
    glow:Show()
end)

-- ── Quest text ──
-- 1.12 writes a quest's text in letter by letter and keeps Accept greyed until it is done. A
-- pressed meanwhile finishes the writing (the panel's own OnUpdate then shows the objectives
-- and enables Accept), so a quest is X, A, A without waiting on the scroll.
P.Listen(function(event, button, down)
    if event ~= "BENILLAPAD_BUTTON" or button ~= "A" or not down then
        return
    end
    local panel = QuestFrameDetailPanel
    if panel and panel:IsVisible() and panel.fading then
        panel.fadingProgress = 100000
    end
end)
