-- Button glyphs and hint rows. The glyph art is 64x64 TGA in Art/: the PlayStation set is
-- ImprovedForever's (MIT, see THIRD-PARTY-NOTICES.md), the Xbox set, Start / Select and the
-- single-direction D-pads are ours, drawn in the same style. A hint row is the Forever footer's
-- layout: glyph, 4 px, gold verb; pairs as two glyphs with "/" between.

local P = BenillaPad
local ART = P.ART

local DPAD = {
    DPAD = ART .. "Glyph_DPad", DLR = ART .. "Glyph_DPad_LR", DUD = ART .. "Glyph_DPad_UD",
    DUP = ART .. "Glyph_DPad_Up", DDOWN = ART .. "Glyph_DPad_Down",
    DLEFT = ART .. "Glyph_DPad_Left", DRIGHT = ART .. "Glyph_DPad_Right",
}

local SETS = {
    xbox = {
        A = ART .. "Glyph_XB_A", B = ART .. "Glyph_XB_B", X = ART .. "Glyph_XB_X", Y = ART .. "Glyph_XB_Y",
        LB = ART .. "Glyph_XB_LB", RB = ART .. "Glyph_XB_RB", LT = ART .. "Glyph_XB_LT", RT = ART .. "Glyph_XB_RT",
        L3 = ART .. "Glyph_XB_LS", R3 = ART .. "Glyph_XB_RS",
        START = ART .. "Glyph_XB_Start", SELECT = ART .. "Glyph_XB_Select",
    },
    playstation = {
        A = ART .. "Glyph_PS_A", B = ART .. "Glyph_PS_B", X = ART .. "Glyph_PS_X", Y = ART .. "Glyph_PS_Y",
        LB = ART .. "Glyph_PS_LB", RB = ART .. "Glyph_PS_RB", LT = ART .. "Glyph_PS_LT", RT = ART .. "Glyph_PS_RT",
        L3 = ART .. "Glyph_PS_LS", R3 = ART .. "Glyph_PS_RS",
        START = ART .. "Glyph_PS_Start", SELECT = ART .. "Glyph_PS_Select",
    },
}
local CHIP = ART .. "Glyph_Chip"

-- Other names the hints use for the same buttons.
local ALIAS = { LS = "L3", RS = "R3", BACK = "SELECT", VIEW = "SELECT", MENU = "START" }

-- The glyph set the symbol setting picks: PlayStation shapes, else Xbox letters.
function P.GlyphStyle()
    if P.Symbols() == "playstation" then
        return "playstation"
    end
    return "xbox"
end

-- The texture path of a button's glyph in the active style (BUTTONS names, LT, RT, START,
-- SELECT, DPAD, DLR, DUD), or the grey chip for a button with no art (and false).
function P.Glyph(button)
    local key = string.upper(button or "")
    key = ALIAS[key] or key
    if DPAD[key] then
        return DPAD[key], true
    end
    local path = SETS[P.GlyphStyle()][key]
    if path then
        return path, true
    end
    return CHIP, false
end

-- A glyph texture of `size` on `parent`; P.SetGlyph points it at a button. A key with no art
-- shows its name on the chip.
function P.NewGlyph(parent, size, layer)
    local t = parent:CreateTexture(nil, layer or "OVERLAY")
    t:SetWidth(size)
    t:SetHeight(size)
    local name = parent:CreateFontString(nil, "OVERLAY")
    name:SetFont("Fonts\\FRIZQT__.TTF", math.max(8, math.floor(size * 0.36)), "OUTLINE")
    name:SetPoint("CENTER", t, "CENTER", 0, 0)
    name:Hide()
    t.chipName = name
    return t
end

function P.SetGlyph(t, button)
    local path, art = P.Glyph(button)
    if t.glyphPath ~= path then
        t:SetTexture(path)
        t.glyphPath = path
    end
    if art then
        t.chipName:Hide()
    else
        t.chipName:SetText(button or "")
        t.chipName:Show()
    end
end

-- ── Hint rows ──

-- The words a hint's key part may use, as glyph names.
local TOKEN = {
    A = "A", B = "B", X = "X", Y = "Y", LB = "LB", RB = "RB", LT = "LT", RT = "RT",
    L3 = "L3", R3 = "R3", LS = "L3", RS = "R3",
    START = "START", SELECT = "SELECT", BACK = "SELECT",
    ["D-PAD"] = "DPAD", DPAD = "DPAD", STICK = "L3",
    UP = "DUP", DOWN = "DDOWN", LEFT = "DLEFT", RIGHT = "DRIGHT",
}

-- A plate as Forever's footer draws it: a dark fill and a thin bronze edge.
function P.AddPlate(f)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetTexture(0.05, 0.04, 0.03, 0.92)
    local function edge(a, b, w, h)
        local e = f:CreateTexture(nil, "BORDER")
        e:SetTexture(0.45, 0.38, 0.25, 1)
        e:SetPoint(a, f, a, 0, 0)
        e:SetPoint(b, f, b, 0, 0)
        if w then e:SetWidth(w) end
        if h then e:SetHeight(h) end
    end
    edge("TOPLEFT", "TOPRIGHT", nil, 1)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
    edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
end

-- The bronze and gold palette of ImprovedForever's ConfigKit (K.C): titles and headings gold,
-- labels cream, help text sand, lines bronze.
P.COLOR = {
    title = { 0.95, 0.77, 0.24 },   -- F2C43C
    focus = { 1, 0.82, 0.29 },      -- FFD24A
    gold = { 1, 0.82, 0 },
    cream = { 0.94, 0.89, 0.78 },   -- EFE4C8
    help = { 0.73, 0.67, 0.55 },    -- B9AB8C
    grey = { 0.62, 0.57, 0.48 },    -- 9D917A
    line = { 0.35, 0.27, 0.19 },    -- 5A4630
    danger = { 1, 0.48, 0.36 },     -- FF7A5C
}

function P.Paint(fs, color)
    fs:SetTextColor(color[1], color[2], color[3])
end

-- A thin bronze rule under a heading, `width` wide, its top `y` below `parent`'s top.
function P.AddRule(parent, width, y)
    local t = parent:CreateTexture(nil, "BORDER")
    t:SetTexture(P.COLOR.line[1], P.COLOR.line[2], P.COLOR.line[3], 1)
    t:SetWidth(width)
    t:SetHeight(1)
    t:SetPoint("TOP", parent, "TOP", 0, -y)
    return t
end

-- The gold focus stroke (Art/Focus_Select, ImprovedForever's ic_select: 128x32, 10 px corners)
-- as a nine-slice on `f`, `out` px outside its edges; `hollow` leaves out the faint gold
-- middle. Drawn in `layer` (BORDER: under the row's text). P.ShowSelect turns it on and off.
local SLICE_U = { 0, 10 / 128, 118 / 128, 1 }
local SLICE_V = { 0, 10 / 32, 22 / 32, 1 }

function P.AddSelect(f, opts)
    opts = opts or {}
    local d = opts.corner or 8
    local o = opts.out or 0
    local c = opts.color or { 1, 0.9, 0.4 }
    -- Each piece: its column and row in the texture, then one or two anchors (point, x, y),
    -- and whether it is d wide and d high (corners both, edges one, the middle neither).
    local spec = {
        { 1, 1, { "TOPLEFT", -o, o }, nil, true, true },
        { 2, 1, { "TOPLEFT", d - o, o }, { "TOPRIGHT", o - d, o }, false, true },
        { 3, 1, { "TOPRIGHT", o, o }, nil, true, true },
        { 1, 2, { "TOPLEFT", -o, o - d }, { "BOTTOMLEFT", -o, d - o }, true, false },
        { 2, 2, { "TOPLEFT", d - o, o - d }, { "BOTTOMRIGHT", o - d, d - o }, false, false },
        { 3, 2, { "TOPRIGHT", o, o - d }, { "BOTTOMRIGHT", o, d - o }, true, false },
        { 1, 3, { "BOTTOMLEFT", -o, -o }, nil, true, true },
        { 2, 3, { "BOTTOMLEFT", d - o, -o }, { "BOTTOMRIGHT", o - d, -o }, false, true },
        { 3, 3, { "BOTTOMRIGHT", o, -o }, nil, true, true },
    }
    local pieces = {}
    for i = 1, table.getn(spec) do
        local s = spec[i]
        local col, row = s[1], s[2]
        if not (opts.hollow and col == 2 and row == 2) then
            local t = f:CreateTexture(nil, opts.layer or "BORDER")
            t:SetTexture(P.ART .. "Focus_Select")
            t:SetTexCoord(SLICE_U[col], SLICE_U[col + 1], SLICE_V[row], SLICE_V[row + 1])
            t:SetPoint(s[3][1], f, s[3][1], s[3][2], s[3][3])
            if s[4] then
                t:SetPoint(s[4][1], f, s[4][1], s[4][2], s[4][3])
            end
            if s[5] then
                t:SetWidth(d)
            end
            if s[6] then
                t:SetHeight(d)
            end
            t:SetVertexColor(c[1], c[2], c[3], opts.alpha or 1)
            t:Hide()
            table.insert(pieces, t)
        end
    end
    return pieces
end

function P.ShowSelect(pieces, on)
    for i = 1, table.getn(pieces) do
        if on then
            pieces[i]:Show()
        else
            pieces[i]:Hide()
        end
    end
end

-- A row of hints on `parent`. opts: size (glyph, 24), font (the verb's, "GameFontNormal"),
-- pad (10), spacing between hints (15), maxWidth (wraps whole hints onto more lines), plate.
function P.NewHints(parent, opts)
    opts = opts or {}
    local row = CreateFrame("Frame", opts.name, parent)
    row.size = opts.size or 24
    row.font = opts.font or "GameFontNormal"
    row.pad = opts.pad or 10
    row.spacing = opts.spacing or 15
    row.maxWidth = opts.maxWidth
    row.glyphs = {}
    row.texts = {}
    row:SetWidth(1)
    row:SetHeight(row.size + 2 * row.pad)
    if opts.plate then
        P.AddPlate(row)
    end
    return row
end

local function glyphAt(row, i)
    local t = row.glyphs[i]
    if not t then
        t = P.NewGlyph(row, row.size, "ARTWORK")
        row.glyphs[i] = t
    end
    return t
end

local function textAt(row, i)
    local s = row.texts[i]
    if not s then
        s = row:CreateFontString(nil, "OVERLAY", row.font)
        row.texts[i] = s
    end
    return s
end

-- Split a key part ("LB / RB", "A / Right", "Hold LT / RT") into glyphs and words; nil when no
-- word is a button.
local function keyParts(key)
    local parts, any = {}, false
    local word = ""
    local function flush()
        if word ~= "" then
            local g = TOKEN[string.upper(word)]
            if g then
                table.insert(parts, { glyph = g })
                any = true
            else
                table.insert(parts, { text = word })
            end
            word = ""
        end
    end
    for i = 1, string.len(key) do
        local c = string.sub(key, i, i)
        if c == " " then
            flush()
        elseif c == "/" or c == "+" then
            flush()
            table.insert(parts, { text = c, sep = true })
        else
            word = word .. c
        end
    end
    flush()
    if not any then
        return nil
    end
    return parts
end

-- items: { { keys = { "LB", "/", "RB" } or "A", text = "Page" }, { text = "plain words" }, ... }.
-- A key that is "/" or "+" is drawn as a divider; any other unknown key as its own word.
function P.SetHints(row, items)
    local nG, nT = 0, 0
    local placed = {}
    local size, gap = row.size, 4
    -- Measure each hint as a run of pieces.
    local hints = {}
    for h = 1, table.getn(items) do
        local item = items[h]
        local pieces, width = {}, 0
        local keys = item.keys
        if type(keys) == "string" then
            keys = { keys }
        end
        local function add(p, w)
            if table.getn(pieces) > 0 then
                width = width + p.before
            end
            p.x = width
            table.insert(pieces, p)
            width = width + w
        end
        if keys then
            for k = 1, table.getn(keys) do
                local key = keys[k]
                local name = TOKEN[string.upper(key)] or key
                local _, art = P.Glyph(name)
                if key == "/" or key == "+" then
                    nT = nT + 1
                    local s = textAt(row, nT)
                    s:SetText(key)
                    s:SetTextColor(0.8, 0.78, 0.72)
                    add({ region = s, before = 3 }, s:GetStringWidth())
                elseif art then
                    nG = nG + 1
                    local t = glyphAt(row, nG)
                    P.SetGlyph(t, name)
                    add({ region = t, before = 2 }, size)
                else
                    nT = nT + 1
                    local s = textAt(row, nT)
                    s:SetText(key)
                    s:SetTextColor(1, 0.82, 0)
                    add({ region = s, before = gap }, s:GetStringWidth())
                end
            end
        end
        if item.text and item.text ~= "" then
            nT = nT + 1
            local s = textAt(row, nT)
            s:SetText(item.text)
            if keys then
                s:SetTextColor(1, 0.82, 0)
            else
                s:SetTextColor(0.9, 0.9, 0.9)
            end
            add({ region = s, before = gap }, s:GetStringWidth())
        end
        if table.getn(pieces) > 0 then
            table.insert(hints, { pieces = pieces, width = width })
        end
    end
    -- Lines: whole hints, wrapped at maxWidth.
    local lines, line = {}, nil
    for h = 1, table.getn(hints) do
        local hint = hints[h]
        if line and row.maxWidth and line.width + row.spacing + hint.width > row.maxWidth - 2 * row.pad then
            line = nil
        end
        if not line then
            line = { hints = {}, width = 0 }
            table.insert(lines, line)
        else
            line.width = line.width + row.spacing
        end
        hint.x = line.width
        table.insert(line.hints, hint)
        line.width = line.width + hint.width
    end
    local widest = 0
    for l = 1, table.getn(lines) do
        widest = math.max(widest, lines[l].width)
    end
    local lineH = size + 4
    for l = 1, table.getn(lines) do
        local ln = lines[l]
        local x0 = row.pad + (widest - ln.width) / 2
        local y = -(row.pad + (l - 1) * lineH + size / 2)
        for h = 1, table.getn(ln.hints) do
            local hint = ln.hints[h]
            for p = 1, table.getn(hint.pieces) do
                local piece = hint.pieces[p]
                local r = piece.region
                r:ClearAllPoints()
                r:SetPoint("LEFT", row, "TOPLEFT", x0 + hint.x + piece.x, y)
                r:Show()
                placed[r] = true
            end
        end
    end
    -- Hide what this set did not use.
    for i = 1, table.getn(row.glyphs) do
        local t = row.glyphs[i]
        if i > nG or not placed[t] then
            t:Hide()
            t.chipName:Hide()
        end
    end
    for i = 1, table.getn(row.texts) do
        if i > nT or not placed[row.texts[i]] then
            row.texts[i]:Hide()
        end
    end
    local n = table.getn(lines)
    if n == 0 then
        row:SetWidth(1)
        row:SetHeight(1)
        return
    end
    row:SetWidth(widest + 2 * row.pad)
    row:SetHeight(n * lineH - 4 + 2 * row.pad)
end

-- The same from a hint string as the windows write them: hints three spaces apart, each
-- "Key: verb" ("A: open   LB / RB: page   B: close"). A chunk with no button in its key part is
-- drawn as plain words.
function P.SetHintText(row, s)
    local items = {}
    local pos = 1
    s = s or ""
    while pos <= string.len(s) do
        local a, b = string.find(s, "%s%s+", pos)
        local chunk
        if a then
            chunk = string.sub(s, pos, a - 1)
            pos = b + 1
        else
            chunk = string.sub(s, pos)
            pos = string.len(s) + 1
        end
        if chunk ~= "" then
            local _, _, key, verb = string.find(chunk, "^([^:]+):%s*(.*)$")
            -- A key part is a few words ("Hold LT / RT"); a longer one is a sentence.
            local parts = key and string.len(key) <= 16 and keyParts(key)
            if parts then
                local keys = {}
                for i = 1, table.getn(parts) do
                    table.insert(keys, parts[i].glyph or parts[i].text)
                end
                table.insert(items, { keys = keys, text = verb })
            else
                table.insert(items, { text = chunk })
            end
        end
    end
    P.SetHints(row, items)
end
