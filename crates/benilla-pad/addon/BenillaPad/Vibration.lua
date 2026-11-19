-- Controller vibration on game events. A pattern is a list of { low, high, seconds } steps (low
-- the strong left motor, high the weak right one, 0..1; 0, 0 is a pause), played one step after
-- the other through BenillaPad_Rumble (Core.lua), which the Vibration setting scales. A playing
-- pattern gives way only to one of at least its priority.
-- The step values follow ImprovedForever_Vibration's pattern table (MIT), itself adapted from
-- Easy Controller - Forever (MIT): both notices are in THIRD-PARTY-NOTICES.md. The Lua is ours,
-- for Lua 5.0 and the 1.12 events.

local P = BenillaPad
local Vibe = {}
P.Vibe = Vibe

-- gap: the shortest time between two plays of the same pattern, in seconds.
Vibe.PATTERNS = {
    -- Taking a hit: short and strong (IF "impact", left-heavy); a critical one knocks twice.
    hit = { priority = 50, gap = 0.4, steps = { { 0.9, 0.45, 0.14 } } },
    hitCrit = { priority = 55, gap = 0.4, steps = { { 1, 0.6, 0.12 }, { 0, 0, 0.1 }, { 0.7, 0.45, 0.12 } } },
    -- Dealing a critical hit: short and sharp (IF "tick").
    crit = { priority = 45, gap = 0.15, steps = { { 0.6, 0.6, 0.12 } } },
    -- A cast starts: a light tick (IF "micro"); it lands: medium (IF "pulse", softer).
    castStart = { priority = 10, gap = 0.2, steps = { { 0.35, 0.35, 0.1 } } },
    castDone = { priority = 30, gap = 0.2, steps = { { 0.6, 0.6, 0.16 } } },
    -- Level up: a long celebratory ramp (IF "rise", carried on and let down).
    levelUp = { priority = 90, gap = 1, steps = {
        { 0.3, 0.3, 0.12 }, { 0.6, 0.6, 0.12 }, { 1, 1, 0.18 }, { 0, 0, 0.1 },
        { 0.5, 0.5, 0.12 }, { 0.8, 0.8, 0.12 }, { 1, 1, 0.3 }, { 0.6, 0.6, 0.2 }, { 0.3, 0.3, 0.2 } } },
    -- A quest handed in: two pulses (IF "double").
    questDone = { priority = 60, gap = 1, steps = { { 0.7, 0.7, 0.12 }, { 0, 0, 0.12 }, { 0.7, 0.7, 0.12 } } },
    -- Low health: a soft double beat (IF "heart", at about half strength).
    heartbeat = { priority = 20, gap = 1, steps = { { 0.45, 0.45, 0.1 }, { 0, 0, 0.12 }, { 0.3, 0.3, 0.1 } } },
    -- Death: a long fade (IF "fade", drawn out).
    death = { priority = 100, gap = 2, steps = {
        { 1, 1, 0.15 }, { 0.6, 0.6, 0.15 }, { 0.3, 0.3, 0.2 }, { 0.15, 0.15, 0.3 }, { 0.06, 0.06, 0.4 } } },
    -- Loot opened: a tiny tick.
    loot = { priority = 10, gap = 0.3, steps = { { 0.2, 0.2, 0.1 } } },
    -- Fall damage: a thud and its settle (IF "impact", then low).
    fall = { priority = 70, gap = 0.5, steps = { { 1, 1, 0.16 }, { 0.35, 0.2, 0.12 } } },
    -- The setting's sample, when it changes in the menu.
    sample = { priority = 200, gap = 0.1, steps = { { 0.8, 0.8, 0.18 } } },
}

-- Below this share of health the heartbeat plays, every HEARTBEAT seconds.
local LOW_HEALTH = 0.25
local HEARTBEAT = 1.2
-- A step is sent this much longer than it lasts, so the next one joins it without a gap.
local OVERLAP = 0.05

local playing, stepIndex, stepLeft = nil, 0, 0
local lastPlayed = {}

local function startStep()
    local s = playing.steps[stepIndex]
    BenillaPad_Rumble(s[1], s[2], s[3] + OVERLAP)
    stepLeft = s[3]
end

function Vibe.Enabled()
    return P.connected and P.Setting("vibration") ~= "off"
end

function Vibe.Play(key)
    if not Vibe.Enabled() then
        return
    end
    local p = Vibe.PATTERNS[key]
    if not p then
        return
    end
    if playing and p.priority < playing.priority then
        return
    end
    local now = GetTime()
    if lastPlayed[key] and now - lastPlayed[key] < (p.gap or 0) then
        return
    end
    lastPlayed[key] = now
    playing = p
    stepIndex = 1
    startStep()
end

function Vibe.Stop()
    if playing then
        playing = nil
        BenillaPad_Rumble(0, 0, 0)
    end
end

-- ── Events ──

local casting = false
local castLanded = nil
local lowHealth = false
local beat = 0

-- The start of the fall-damage line ("You fall and lose %d health."), and the word in a
-- critical hit's line ("You crit ...", "Your Fireball crits ...").
local FALL = "You fall and lose"
if VSENVIRONMENTALDAMAGE_FALLING_SELF then
    local at = string.find(VSENVIRONMENTALDAMAGE_FALLING_SELF, "%", 1, true)
    if at and at > 1 then
        FALL = string.sub(VSENVIRONMENTALDAMAGE_FALLING_SELF, 1, at - 1)
    end
end
local CRIT = " crit"

local function checkHealth()
    local max = UnitHealthMax("player") or 0
    local hp = UnitHealth("player") or 0
    lowHealth = max > 0 and hp > 0 and hp / max < LOW_HEALTH and not UnitIsDeadOrGhost("player")
end

local frame = CreateFrame("Frame", "BenillaPadVibration")
frame:RegisterEvent("UNIT_COMBAT")
frame:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
frame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
frame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS")
frame:RegisterEvent("CHAT_MSG_COMBAT_MISC_INFO")
frame:RegisterEvent("SPELLCAST_START")
frame:RegisterEvent("SPELLCAST_CHANNEL_START")
frame:RegisterEvent("SPELLCAST_STOP")
frame:RegisterEvent("SPELLCAST_FAILED")
frame:RegisterEvent("SPELLCAST_INTERRUPTED")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("QUEST_COMPLETE")
frame:RegisterEvent("UNIT_HEALTH")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_ALIVE")
frame:RegisterEvent("PLAYER_UNGHOST")
frame:RegisterEvent("PLAYER_DEAD")
frame:RegisterEvent("LOOT_OPENED")

frame:SetScript("OnEvent", function()
    if event == "UNIT_COMBAT" then
        -- arg1 unit, arg2 action, arg3 "CRITICAL" / "CRUSHING" / "GLANCING" / "", arg4 amount.
        if arg1 == "player" and arg2 == "WOUND" and (tonumber(arg4) or 0) > 0 then
            if arg3 == "CRITICAL" then
                Vibe.Play("hitCrit")
            else
                Vibe.Play("hit")
            end
        end
    elseif event == "CHAT_MSG_COMBAT_SELF_HITS" or event == "CHAT_MSG_SPELL_SELF_DAMAGE"
        or event == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS" or event == "CHAT_MSG_COMBAT_MISC_INFO" then
        local text = arg1 or ""
        if string.find(text, FALL, 1, true) == 1 then
            Vibe.Play("fall")
        elseif (event == "CHAT_MSG_COMBAT_SELF_HITS" or event == "CHAT_MSG_SPELL_SELF_DAMAGE")
            and string.find(text, CRIT, 1, true) then
            Vibe.Play("crit")
        end
    elseif event == "SPELLCAST_START" or event == "SPELLCAST_CHANNEL_START" then
        casting = true
        castLanded = nil
        Vibe.Play("castStart")
    elseif event == "SPELLCAST_STOP" then
        -- The landing is felt a moment later, unless a failure or interruption follows the stop.
        if casting then
            castLanded = GetTime() + 0.1
        end
        casting = false
    elseif event == "SPELLCAST_FAILED" or event == "SPELLCAST_INTERRUPTED" then
        casting = false
        castLanded = nil
    elseif event == "PLAYER_LEVEL_UP" then
        Vibe.Play("levelUp")
    elseif event == "QUEST_COMPLETE" then
        Vibe.Play("questDone")
    elseif event == "UNIT_HEALTH" then
        if arg1 == "player" then
            checkHealth()
        end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        checkHealth()
    elseif event == "PLAYER_DEAD" then
        lowHealth = false
        casting = false
        castLanded = nil
        Vibe.Play("death")
    elseif event == "LOOT_OPENED" then
        Vibe.Play("loot")
    end
end)

-- The player: the next step when one is over; the cast's landing; the heartbeat.
frame:SetScript("OnUpdate", function()
    local dt = arg1 or 0
    if playing then
        stepLeft = stepLeft - dt
        if stepLeft <= 0 then
            stepIndex = stepIndex + 1
            if stepIndex > table.getn(playing.steps) then
                playing = nil
            else
                startStep()
            end
        end
    end
    if castLanded and GetTime() >= castLanded then
        castLanded = nil
        Vibe.Play("castDone")
    end
    if lowHealth then
        beat = beat + dt
        if beat >= HEARTBEAT then
            beat = 0
            Vibe.Play("heartbeat")
        end
    else
        beat = HEARTBEAT
    end
end)

-- A pad going away stops the motors' pattern.
P.Listen(function(event)
    if event == "BENILLAPAD_DISCONNECTED" then
        playing = nil
    end
end)
