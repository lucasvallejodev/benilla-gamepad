-- The Interact prompt: what X does right now, shown above the bar as a console UI shows it
-- ("[X] Loot", "[X] Talk"). With a target it is the target's action; without one, the soft target
-- the Rust side finds (BENILLAPAD_SOFT, a few times a second).

local P = BenillaPad
local Prompt = {}
P.Prompt = Prompt

local f = CreateFrame("Frame", "BenillaPadPrompt", UIParent)
f:SetWidth(160)
f:SetHeight(30)
f:SetFrameStrata("MEDIUM")
f:Hide()

local back = f:CreateTexture(nil, "BACKGROUND")
back:SetAllPoints(f)
back:SetTexture(0, 0, 0, 0.45)

local badge = f:CreateTexture(nil, "ARTWORK")
badge:SetTexture(P.ART .. "Disc")
badge:SetWidth(24)
badge:SetHeight(24)
badge:SetPoint("LEFT", f, "LEFT", 4, 0)

local glyph = f:CreateFontString(nil, "OVERLAY")
glyph:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
glyph:SetPoint("CENTER", badge, "CENTER", 0, 0)

local label = f:CreateFontString(nil, "OVERLAY")
label:SetFont("Fonts\\FRIZQT__.TTF", 15, "OUTLINE")
label:SetPoint("LEFT", badge, "RIGHT", 6, 0)
label:SetTextColor(1, 1, 1)

local soft

-- What X does to the current target, or nil.
local function targetVerb()
    if not UnitExists("target") or UnitIsUnit("target", "player") then
        return nil
    end
    if UnitIsDead("target") then
        return "Loot"
    end
    if UnitCanAttack("player", "target") then
        return "Attack"
    end
    if UnitIsPlayer("target") then
        return nil
    end
    return "Talk"
end

function Prompt.Refresh()
    local kind, value = P.Binding("X", "bare")
    local on = P.connected and P.Setting("prompt") and P.mode == "world" and kind == "action" and value == "interact"
        and not (P.Cursor and P.Cursor.Wanted())
    local verb = on and (targetVerb() or (not UnitExists("target") and soft)) or nil
    if not verb then
        f:Hide()
        return
    end
    if P.Symbols() == "playstation" then
        glyph:SetText("[]")
        badge:SetVertexColor(0.85, 0.45, 0.75)
    else
        glyph:SetText("X")
        badge:SetVertexColor(0.20, 0.45, 0.90)
    end
    label:SetText(verb)
    if UnitExists("target") and UnitName("target") then
        label:SetText(verb .. "  |cffd0d0d0" .. UnitName("target") .. "|r")
    end
    f:SetWidth(label:GetStringWidth() + 46)
    Prompt.Place()
    f:Show()
end

-- Over the name of what X acts on (BENILLAPAD_ANCHOR, absolute units from the Rust side), as a
-- console UI hangs its prompt on the thing itself; above the bar while that is off screen.
local anchorX, anchorY
function Prompt.Place()
    f:ClearAllPoints()
    if anchorX then
        local s = UIParent:GetEffectiveScale()
        f:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", anchorX / s, anchorY / s + 6)
        return
    end
    local bar = P.Bar and P.Bar.frame
    if bar and bar:IsShown() then
        f:SetPoint("BOTTOM", bar, "TOP", 0, 34)
    else
        f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 200)
    end
end

P.Listen(function(event, arg1, arg2)
    if event == "BENILLAPAD_ANCHOR" then
        -- Every frame the subject moves on screen: only the place, not a whole refresh.
        anchorX, anchorY = arg1, arg2
        if f:IsShown() then
            Prompt.Place()
        end
        return
    end
    if event == "BENILLAPAD_SOFT" then
        soft = arg1
    end
    Prompt.Refresh()
end)

local watcher = CreateFrame("Frame", nil, f)
watcher:RegisterEvent("PLAYER_TARGET_CHANGED")
watcher:RegisterEvent("UNIT_HEALTH")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
local elapsed = 0
-- The cursor mode and the windows come and go without an event of the pad's: a slow poll.
local poll = CreateFrame("Frame", nil, UIParent)
poll:SetScript("OnUpdate", function()
    elapsed = elapsed + arg1
    if elapsed > 0.25 then
        elapsed = 0
        Prompt.Refresh()
    end
end)
watcher:SetScript("OnEvent", function()
    Prompt.Refresh()
end)
