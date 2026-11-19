-- The button legend: what the buttons do right now (a console UI's input legend), drawn as
-- Forever's footer (Glyphs.lua): a dark plate with a bronze edge, each hint a glyph and a gold
-- verb, bottom centre above the gamepad bar. It follows the pad's mode: the world, a game window
-- under the pad cursor, the triggers' layers. The wheel, the menu and the keyboard print their
-- own hints, so it steps aside for them.

local P = BenillaPad
local Legend = {}
P.Legend = Legend

-- Wider than this the hints wrap onto a second line.
local MAX_WIDTH = 470

local f = P.NewHints(UIParent, { name = "BenillaPadLegend", plate = true, size = 24, pad = 10,
    spacing = 15, font = "GameFontNormal", maxWidth = MAX_WIDTH })
f:SetFrameStrata("LOW")
f:Hide()
Legend.frame = f

local function worldRows()
    return {
        { keys = "LS", text = "Move" },
        { keys = "RS", text = "Camera  (LB/RB: zoom)" },
        { keys = { "LT", "/", "RT" }, text = "Action sets" },
        { keys = { "LB", "+", "DPAD" }, text = "Party targets" },
        { keys = "X", text = "Interact / loot" },
        { keys = "START", text = "Window wheel" },
        { keys = "SELECT", text = "Controller menu" },
    }
end

-- What A does in the open windows: the primary button's own label ("Accept", "Complete Quest"),
-- while the pointer is on it; "Click" otherwise.
local function primaryLabel()
    local p = P.Cursor and P.Cursor.Primary and P.Cursor.Primary()
    if p and GetMouseFocus() == p and p.GetText then
        local text = p:GetText()
        if text and text ~= "" and string.len(text) <= 22 then
            return text
        end
    end
    return "Click"
end

local function cursorRows()
    return {
        { keys = "RS", text = "Pointer" },
        { keys = "DPAD", text = "Jump to button" },
        { keys = "A", text = primaryLabel() },
        { keys = "X", text = "Right-click" },
        { keys = { "LB", "/", "RB" }, text = "Scroll" },
        { keys = "B", text = "Close" },
        { keys = "LS", text = "Keep walking" },
    }
end

-- The screen's bottom right corner, clear of the bar in the middle and the chat on the left.
local function place()
    f:ClearAllPoints()
    f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -14, 26)
end

-- A key for what is drawn, so an unchanged legend is not laid out again.
local function signature(rows)
    local s = P.GlyphStyle()
    for i = 1, table.getn(rows) do
        s = s .. "|" .. rows[i].text
    end
    return s
end

function Legend.Refresh()
    if not (P.connected and P.Setting("legend")) or P.mode ~= "world" then
        f:Hide()
        return
    end
    local rows
    if P.Cursor and P.Cursor.Wanted() then
        rows = cursorRows()
    else
        rows = worldRows()
    end
    local sig = signature(rows)
    if sig ~= f.shown then
        f.shown = sig
        P.SetHints(f, rows)
    end
    place()
    f:Show()
end

P.Listen(function()
    Legend.Refresh()
end)

local elapsed = 0
local poll = CreateFrame("Frame", nil, UIParent)
poll:SetScript("OnUpdate", function()
    elapsed = elapsed + arg1
    if elapsed > 0.25 then
        elapsed = 0
        Legend.Refresh()
    end
end)
