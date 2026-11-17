-- The button legend: a small panel at the top left, under the player frame, listing what the
-- buttons do right now (a console UI's input legend). It follows the pad's mode: the world, a game
-- window under the pad cursor, the triggers' layers. The wheel, the menu and the keyboard print
-- their own hints, so it steps aside for them.

local P = BenillaPad
local Legend = {}
P.Legend = Legend

local ROWS = 7
local f = CreateFrame("Frame", "BenillaPadLegend", UIParent)
f:SetWidth(210)
f:SetHeight(ROWS * 16 + 12)
f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 14, -92)
f:SetFrameStrata("LOW")
f:Hide()

local back = f:CreateTexture(nil, "BACKGROUND")
back:SetAllPoints(f)
back:SetTexture(0, 0, 0, 0.35)

local lines = {}
for i = 1, ROWS do
    local key = f:CreateFontString(nil, "OVERLAY")
    key:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    key:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -6 - (i - 1) * 16)
    key:SetWidth(70)
    key:SetJustifyH("RIGHT")
    key:SetTextColor(1, 0.82, 0)
    local what = f:CreateFontString(nil, "OVERLAY")
    what:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    what:SetPoint("LEFT", key, "RIGHT", 8, 0)
    what:SetJustifyH("LEFT")
    what:SetTextColor(0.92, 0.92, 0.92)
    lines[i] = { key = key, what = what }
end

-- The face buttons as the connected pad names them.
local function face(b)
    if P.Symbols() == "playstation" then
        local ps = { A = "Cross", B = "Circle", X = "Square", Y = "Triangle" }
        return ps[b] or b
    end
    return b
end

local function worldRows()
    return {
        { "L stick", "Move" },
        { "R stick", "Camera  (LB/RB: zoom)" },
        { "LT / RT", "Action sets" },
        { "LB + D-pad", "Party targets" },
        { face("X"), "Interact / loot" },
        { "Start", "Window wheel" },
        { "Select", "Controller menu" },
    }
end

local function cursorRows()
    return {
        { "R stick", "Pointer" },
        { "D-pad", "Jump to button" },
        { face("A"), "Click" },
        { face("X"), "Right-click" },
        { "LB / RB", "Scroll" },
        { face("B"), "Close" },
        { "L stick", "Keep walking" },
    }
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
    for i = 1, ROWS do
        local r = rows[i]
        if r then
            lines[i].key:SetText(r[1])
            lines[i].what:SetText(r[2])
        else
            lines[i].key:SetText("")
            lines[i].what:SetText("")
        end
    end
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
