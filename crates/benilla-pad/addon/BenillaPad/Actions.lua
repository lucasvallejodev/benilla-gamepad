-- The game actions a pad button can hold instead of an action slot. Their icons are this
-- addon's own (tools/gen_art.py): a slate tile with a glyph, so none reads as a spell.
-- `command` is the binding command the Rust side runs: a stock 1.12 one (JUMP, TOGGLEAUTORUN, ...), one of this addon's
-- (Bindings.xml), or a native one with a leading "@" that the Rust side handles itself.

local P = BenillaPad
local A = {}
P.Actions = A

local function add(id, label, icon, command)
    A[id] = { id = id, label = label, icon = icon, command = command }
end

add("jump", "Jump", P.ART .. "Jump", "JUMP")
add("interact", "Interact / Loot", P.ART .. "Interact", "@INTERACT")
add("back", "Back / Stop casting", P.ART .. "Back", "BENILLAPAD_BACK")
add("inspect", "Inspect", P.ART .. "Inspect", "BENILLAPAD_INSPECT")
add("targetenemy", "Target enemy", P.ART .. "TargetEnemy", "BENILLAPAD_TARGETENEMY")
add("targetfriend", "Target friend", P.ART .. "TargetFriend", "BENILLAPAD_TARGETFRIEND")
add("targetself", "Target yourself", P.ART .. "TargetSelf", "BENILLAPAD_TARGETSELF")
add("attack", "Attack", P.ART .. "Attack", "BENILLAPAD_ATTACK")
add("autorun", "Auto run", P.ART .. "AutoRun", "TOGGLEAUTORUN")
add("sit", "Sit / Stand", P.ART .. "Sit", "SITORSTAND")
add("wheel", "Window wheel", P.ART .. "Wheel", "BENILLAPAD_WHEEL")
add("consumables", "Consumables wheel", P.ART .. "Consumables", "BENILLAPAD_CONSUMABLES")
add("questitem", "Use quest item", P.ART .. "QuestItem", "BENILLAPAD_QUESTITEM")
add("botwheel", "Bot wheel", P.ART .. "BotWheel", "BENILLAPAD_BOTWHEEL")
add("quickchat", "Quick Chat", P.ART .. "QuickChat", "BENILLAPAD_CHAT")
add("menu", "Controller menu", P.ART .. "Menu", "BENILLAPAD_MENU")

-- The bodies of this addon's action rows (Bindings.xml).

function BenillaPad_Back()
    if SpellIsTargeting() then
        SpellStopTargeting()
    elseif CastingBarFrame and CastingBarFrame:IsVisible() then
        SpellStopCasting()
    else
        ClearTarget()
    end
end

-- 1.12 inspects players only, within CheckInteractDistance's inspect range (index 1).
function BenillaPad_Inspect()
    local why
    if not UnitExists("target") then
        why = "Inspect: no target"
    elseif not UnitIsPlayer("target") then
        why = "Inspect: only players can be inspected"
    elseif not CheckInteractDistance("target", 1) then
        why = "Inspect: too far away"
    end
    if why then
        UIErrorsFrame:AddMessage(why, 1.0, 0.1, 0.1, 1.0, 5)
        return
    end
    InspectUnit("target")
end

-- Select: the controller menu. A press of the pad's Select waits for its release (Peek.lua): a
-- short press opens the menu, a hold shows the zone map.
function BenillaPad_Menu()
    if P.Peek and P.Peek.Defer() then
        return
    end
    P.Menu.Toggle()
end

-- LB held + D-pad up / down: walk the friendly target through you, then your party or raid, in
-- frame order (the friendly targeting of a console UI). Wraps at both ends.
function BenillaPad_PartyStep(step)
    local units = { "player" }
    local raid = GetNumRaidMembers() or 0
    if raid > 0 then
        for i = 1, raid do
            table.insert(units, "raid" .. i)
        end
    else
        for i = 1, GetNumPartyMembers() or 0 do
            table.insert(units, "party" .. i)
        end
    end
    local n = table.getn(units)
    local at = 0
    for i = 1, n do
        if UnitIsUnit("target", units[i]) then
            at = i
            break
        end
    end
    local i = at + step
    if at == 0 and step < 0 then
        i = n
    end
    if i < 1 then
        i = n
    elseif i > n then
        i = 1
    end
    TargetUnit(units[i])
end
