-- The peek map: hold Select for longer than HOLD seconds and a see-through map of the current
-- zone shows in the middle of the screen, the player a gold dot on it; letting go hides it. A
-- short press of Select still opens the controller menu, on its release (Actions.lua's
-- BenillaPad_Menu defers to Peek.Defer). The pad stays in the world mode meanwhile, so the
-- character keeps walking. After ImprovedForever_Map's PeekMap.lua (MIT, THIRD-PARTY-NOTICES.md),
-- drawn here in our own frame from the zone's twelve map tiles, as the stock WorldMapFrame
-- draws them, without opening the full-screen map.

local P = BenillaPad
local Peek = {}
P.Peek = Peek

local HOLD = 0.35
local ALPHA = 0.8
-- A zone map is 1002 x 668 of a 4 x 3 grid of 256 px tiles (1024 x 768).
local MAP_W, MAP_H = 1002, 668
local TILE = 256

-- The outer frame is the plate, with the zone's name along its top; the map is a child inside.
local win = CreateFrame("Frame", "BenillaPadPeek", UIParent)
win:SetFrameStrata("HIGH")
win:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
win:SetWidth(MAP_W / 2 + 12)
win:SetHeight(MAP_H / 2 + 34)
win:SetAlpha(ALPHA)
win:Hide()
P.AddPlate(win)
Peek.frame = win

local map = CreateFrame("Frame", nil, win)
map:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 6, 6)
map:SetWidth(MAP_W / 2)
map:SetHeight(MAP_H / 2)

local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("BOTTOM", map, "TOP", 0, 7)
P.Paint(title, P.COLOR.title)

local empty = map:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
empty:SetPoint("CENTER", map, "CENTER", 0, 0)
empty:SetText("No map here")
empty:Hide()

local tiles = {}
for i = 1, 12 do
    local t = map:CreateTexture(nil, "ARTWORK")
    tiles[i] = t
end

-- The player: a gold dot in a dark ring.
local dot = CreateFrame("Frame", nil, map)
dot:SetWidth(18)
dot:SetHeight(18)
dot:SetFrameLevel(map:GetFrameLevel() + 1)
local dotRing = dot:CreateTexture(nil, "ARTWORK")
dotRing:SetTexture(P.ART .. "Disc")
dotRing:SetVertexColor(0, 0, 0, 0.9)
dotRing:SetAllPoints(dot)
local dotFill = dot:CreateTexture(nil, "OVERLAY")
dotFill:SetTexture(P.ART .. "Disc")
dotFill:SetVertexColor(1, 0.82, 0.2)
dotFill:SetWidth(12)
dotFill:SetHeight(12)
dotFill:SetPoint("CENTER", dot, "CENTER", 0, 0)
dot:Hide()

-- The map's size on screen: 60% of the screen's height.
local function size()
    local h = (UIParent:GetHeight() or 768) * 0.6
    return h * MAP_W / MAP_H, h
end

-- Lay the twelve tiles of `file` out over the frame, the last column and row cut to the map.
local function layTiles(file, w, h)
    local scale = h / MAP_H
    local t = TILE * scale
    for row = 0, 2 do
        for col = 0, 3 do
            local i = row * 4 + col + 1
            local tex = tiles[i]
            local u = math.min(1, (MAP_W - col * TILE) / TILE)
            local v = math.min(1, (MAP_H - row * TILE) / TILE)
            tex:SetTexture("Interface\\WorldMap\\" .. file .. "\\" .. file .. i)
            tex:SetTexCoord(0, u, 0, v)
            tex:SetWidth(t * u)
            tex:SetHeight(t * v)
            tex:ClearAllPoints()
            tex:SetPoint("TOPLEFT", map, "TOPLEFT", col * t, -row * t)
            tex:Show()
        end
    end
end

local function placeDot()
    if not GetPlayerMapPosition then
        dot:Hide()
        return
    end
    local x, y = GetPlayerMapPosition("player")
    if not x or (x == 0 and y == 0) then
        dot:Hide()
        return
    end
    dot:ClearAllPoints()
    dot:SetPoint("CENTER", map, "TOPLEFT", x * map:GetWidth(), -y * map:GetHeight())
    dot:Show()
end

function Peek.Show()
    -- The full map already open says it all; our windows on screen have the pad.
    if (WorldMapFrame and WorldMapFrame:IsVisible()) or P.mode ~= "world" then
        return
    end
    local w, h = size()
    map:SetWidth(w)
    map:SetHeight(h)
    win:SetWidth(w + 12)
    win:SetHeight(h + 34)
    local file
    if SetMapToCurrentZone and GetMapInfo then
        SetMapToCurrentZone()
        file = GetMapInfo()
    end
    if file then
        layTiles(file, w, h)
        empty:Hide()
    else
        for i = 1, 12 do
            tiles[i]:Hide()
        end
        empty:Show()
    end
    local zone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
    title:SetText(zone)
    win:Show()
    placeDot()
end

function Peek.Hide()
    win:Hide()
end

-- ── Select: a press or a hold ──

local pending, downAt = nil, 0

-- BenillaPad_Menu on a pad Select press: hold back the menu until the release (or the peek).
-- Answers whether it took the press.
function Peek.Defer()
    if not (P.connected and P.held.SELECT) then
        return false
    end
    pending = "press"
    downAt = GetTime()
    return true
end

P.Listen(function(event, button, down)
    if event == "BENILLAPAD_DISCONNECTED" then
        pending = nil
        win:Hide()
        return
    end
    if event ~= "BENILLAPAD_BUTTON" or button ~= "SELECT" or down then
        return
    end
    local was = pending
    pending = nil
    if was == "press" then
        P.Menu.Toggle()
    elseif was == "peek" then
        win:Hide()
    end
end)

local elapsed = 0
local watch = CreateFrame("Frame", nil, UIParent)
watch:SetScript("OnUpdate", function()
    if pending == "press" and P.held.SELECT and GetTime() - downAt >= HOLD then
        pending = "peek"
        Peek.Show()
    end
    if win:IsShown() then
        -- Another window took the pad: the map gives way.
        if P.mode ~= "world" then
            win:Hide()
            return
        end
        elapsed = elapsed + arg1
        if elapsed > 0.1 then
            elapsed = 0
            placeDot()
        end
    end
end)
