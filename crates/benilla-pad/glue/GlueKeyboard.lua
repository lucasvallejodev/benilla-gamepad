-- The login screens' on-screen keyboard, run by benilla-pad in the glue VM (the BenillaPad addon
-- loads only in the world). While a glue EditBox has the keyboard focus (the account name, the
-- password, a new character's name), the pad types into it: D-pad moves, A types the key, X
-- deletes, LB shifts, RB swaps letters and symbols; Y (Tab) and Start (Enter) stay the screen's
-- keys. Lua 5.0 and the 1.12 glue API only.
--   BenillaPadGlue_Sync(editName)  -- show for that EditBox, or hide on nil
--   BenillaPadGlue_Press(button)   -- a pad press; answers true when the keyboard took it

if BenillaPadGlue then
    return
end
BenillaPadGlue = {}
local G = BenillaPadGlue

local KEY = 34
local GAP = 4
local PAGES = {
    { "1234567890", "qwertyuiop", "asdfghjkl-", "zxcvbnm_.@" },
    { "1234567890", "!#$%&*()+=", "[]{}<>/\\|~", ";:'\",?^`_ " },
}
local COLS, ROWS = 10, 4

G.page = 1
G.shift = false
G.row = 2
G.col = 1
G.edit = nil

local win = CreateFrame("Frame", "BenillaPadGlueKeyboard", GlueParent or UIParent)
win:SetWidth(COLS * (KEY + GAP) + 20)
win:SetHeight(ROWS * (KEY + GAP) + 44)
win:SetFrameStrata("FULLSCREEN_DIALOG")
win:Hide()

local back = win:CreateTexture(nil, "BACKGROUND")
back:SetAllPoints(win)
back:SetTexture(0.02, 0.03, 0.06, 0.88)

local hint = win:CreateFontString(nil, "ARTWORK")
hint:SetFont("Fonts\\FRIZQT__.TTF", 11)
hint:SetPoint("BOTTOM", win, "BOTTOM", 0, 8)
hint:SetTextColor(0.8, 0.8, 0.8)
hint:SetText("A type   X delete   LB shift   RB symbols   Y next box   Start enter")

local keys = {}
for r = 1, ROWS do
    keys[r] = {}
    for c = 1, COLS do
        local k = CreateFrame("Frame", nil, win)
        k:SetWidth(KEY)
        k:SetHeight(KEY)
        k:SetPoint("TOPLEFT", win, "TOPLEFT", 10 + (c - 1) * (KEY + GAP), -10 - (r - 1) * (KEY + GAP))
        local bg = k:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(k)
        k.bg = bg
        local t = k:CreateFontString(nil, "OVERLAY")
        t:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
        t:SetPoint("CENTER", k, "CENTER", 0, 0)
        k.text = t
        keys[r][c] = k
    end
end

local function char(r, c)
    local s = PAGES[G.page][r]
    local ch = string.sub(s, c, c)
    if G.page == 1 and G.shift then
        ch = string.upper(ch)
    end
    return ch
end

local function paint()
    for r = 1, ROWS do
        for c = 1, COLS do
            local k = keys[r][c]
            local ch = char(r, c)
            if ch == " " then
                k.text:SetText("_")
            else
                k.text:SetText(ch)
            end
            if r == G.row and c == G.col then
                k.bg:SetTexture(1, 0.75, 0.1, 0.95)
                k.text:SetTextColor(0, 0, 0)
            else
                k.bg:SetTexture(0.15, 0.17, 0.25, 0.95)
                k.text:SetTextColor(1, 1, 1)
            end
        end
    end
end

function BenillaPadGlue_Sync(editName)
    local edit = editName and getglobal(editName)
    G.edit = edit
    if not edit then
        win:Hide()
        return
    end
    win:ClearAllPoints()
    win:SetPoint("TOP", edit, "BOTTOM", 0, -8)
    paint()
    win:Show()
end

function BenillaPadGlue_Press(button)
    local edit = G.edit
    if not (edit and win:IsShown()) then
        return false
    end
    if button == "DUP" then
        G.row = G.row - 1
        if G.row < 1 then G.row = ROWS end
    elseif button == "DDOWN" then
        G.row = G.row + 1
        if G.row > ROWS then G.row = 1 end
    elseif button == "DLEFT" then
        G.col = G.col - 1
        if G.col < 1 then G.col = COLS end
    elseif button == "DRIGHT" then
        G.col = G.col + 1
        if G.col > COLS then G.col = 1 end
    elseif button == "A" then
        edit:Insert(char(G.row, G.col))
    elseif button == "X" then
        local t = edit:GetText() or ""
        if string.len(t) > 0 then
            edit:SetText(string.sub(t, 1, string.len(t) - 1))
        end
    elseif button == "LB" then
        G.shift = not G.shift
    elseif button == "RB" then
        if G.page == 1 then G.page = 2 else G.page = 1 end
    else
        return false
    end
    paint()
    return true
end
