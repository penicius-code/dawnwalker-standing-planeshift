-- Upright Wall Stance 1.0.3
-- Coen stands upright on walls instead of crouching.
--
-- On a wall the game attaches the ABP_CoenAntiGravLayers animation layer,
-- which holds the crouched wall poses. While Coen clings to a wall this mod
-- detaches it, so the default locomotion layer takes over (normal standing
-- pose, rotated to the wall). Nothing in the game files or the save changes.

local VERSION = "1.0.3"
local POLL_MS = 100
local CONFIG_POLL_MS = 2000

local WALL_LAYER = "ABP_CoenAntiGravLayers_C"
local DEFAULT_LAYER = "ABP_HumanLocomotionDefaultLayers_C"
local CONTROL_RIG_LAYER = "ABP_HumanControlRigLayers_Male_C"
local DEFAULT_LAYER_PATH =
    "/Game/_Dawnwalker/Animation_MH/Humans/LinkedLayers/ABP_HumanLocomotionDefaultLayers.ABP_HumanLocomotionDefaultLayers_C"

-- Wall entries within WOLF_RECENT_S of wolf form wait WOLF_SETTLE_S before the
-- first layer swap (log 2026-09-30: the game re-transformed 0.6 to 1 s after
-- entry, 2 to 3 s after the wolf form ended).
local WOLF_RECENT_S = 5.0
local WOLF_SETTLE_S = 2.0

local S = {
    enabled = true,
    logging = false,
    cfgEnabled = nil,        -- last value read from config.ini
    pawn = nil,
    defaultLayerClass = nil,
    wallLayerClass = nil,
    wasOnWall = false,
    triedPathLookup = false,
    lastWolfAt = nil,        -- os.clock() of the last tick in wolf form
    wallEnterAt = nil,       -- os.clock() of the last wall entry
    settleLogged = false,
    fixWolf = true,          -- FixWolfHaste in config.ini
    wolfLayerClasses = {},   -- layer name -> class (classes may be cached)
    wolfOddSince = nil,
}

---------------------------------------------------------------- config

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function configPath()
    for _, p in ipairs({
        "ue4ss/Mods/UprightWallStance/config.ini",
        "Mods/UprightWallStance/config.ini",
    }) do
        local f = io.open(p, "r")
        if f then f:close() return p end
    end
    return nil
end

local CONFIG = configPath()

local function readConfig()
    local cfg = {}
    if not CONFIG then return cfg end
    local f = io.open(CONFIG, "r")
    if not f then return cfg end
    for line in f:lines() do
        line = trim(line:gsub(";.*$", ""))
        local k, v = line:match("^([%w_]+)%s*=%s*(.-)$")
        if k then cfg[k:lower()] = trim(v) end
    end
    f:close()
    return cfg
end

---------------------------------------------------------------- logging

local logHandle = nil
local t0 = os.clock()

local function log(fmt, ...)
    if not S.logging then return end
    local msg = string.format(fmt, ...)
    print("[UprightWallStance] " .. msg .. "\n")
    if not logHandle then logHandle = io.open("UprightWallStance.log", "a") end
    if logHandle then
        logHandle:write(string.format("[%s +%.2fs] %s\n", os.date("%H:%M:%S"), os.clock() - t0, msg))
        logHandle:flush()
    end
end

---------------------------------------------------------------- helpers

local function valid(o) return o ~= nil and o:IsValid() end

local function className(obj)
    local ok, n = pcall(function() return obj:GetClass():GetFName():ToString() end)
    return ok and n or "?"
end

local function isCutsceneCopy(p)
    local okN, n = pcall(function() return p:GetFullName() end)
    if okN and n and n:find("/Cutscenes/", 1, true) then return true end
    local okC, cine = pcall(function() return p.bCinematicMode end)
    return okC and cine == true
end

-- The player pawn is cached and only looked up again when it becomes invalid
-- (load, respawn), so the regular check stays cheap.
local function getPawn()
    if valid(S.pawn) then return S.pawn end
    S.pawn = nil
    local pc = FindFirstOf("BP_PlayerController_C")
    if not valid(pc) then return nil end
    local okP, p = pcall(function() return pc.Pawn end)
    if okP and valid(p) and not isCutsceneCopy(p) and className(p) == "BP_PlayerCharacter_C" then
        S.pawn = p
        log("player pawn found")
    end
    return S.pawn
end

local function linkedLayers(mesh)
    local result = {}
    pcall(function()
        local arr = mesh.LinkedInstances
        for i = 1, #arr do
            local li = arr[i]
            if valid(li) then table.insert(result, { inst = li, name = className(li) }) end
        end
    end)
    return result
end

local function layerNames(layers)
    local names = {}
    for _, l in ipairs(layers) do table.insert(names, l.name) end
    return table.concat(names, ", ")
end

---------------------------------------------------------------- diagnostics

-- Logging only: writes Coen's form, wall state and linked layers whenever any
-- of them changes, plus every skinned mesh on the pawn (visibility, anim
-- class, height offset). Used to trace the wolf model staying under Coen's
-- feet after wolf Haste + Shadowstep onto a wall.
local skinnedClass = nil
local lastState = nil

local function meshReport(pawn)
    if not valid(skinnedClass) then
        local ok, c = pcall(StaticFindObject, "/Script/Engine.SkinnedMeshComponent")
        skinnedClass = ok and c or nil
    end
    if not valid(skinnedClass) then return "?" end
    local parts = {}
    pcall(function()
        local arr = pawn:K2_GetComponentsByClass(skinnedClass)
        for i = 1, #arr do
            local m = arr[i]
            if valid(m) then
                local name = "?"
                pcall(function() name = m:GetFName():ToString() end)
                local vis = "?"
                pcall(function() vis = m:IsVisible() and "vis" or "hid" end)
                local anim = "-"
                pcall(function()
                    local a = m:GetAnimInstance()
                    if valid(a) then anim = className(a) end
                end)
                local z = "?"
                pcall(function() z = string.format("%.0f", m.RelativeLocation.Z) end)
                table.insert(parts, string.format("%s(%s z=%s %s)", name, vis, z, anim))
            end
        end
    end)
    return table.concat(parts, ", ")
end

local function logState(pawn, onWall)
    local wolf, form = "?", "?"
    pcall(function() wolf = tostring(pawn:IsInWolfForm()) end)
    pcall(function() form = tostring(pawn.Form) end)
    local layers = "?"
    pcall(function() layers = layerNames(linkedLayers(pawn.Mesh)) end)
    local state = string.format("wall=%s wolf=%s form=%s mod=%s layers=[%s]",
        tostring(onWall), wolf, form, S.enabled and "on" or "off", layers)
    if state == lastState then return end
    lastState = state
    log("state %s", state)
    log("  meshes: %s", meshReport(pawn))
end

---------------------------------------------------------------- wolf mesh repair

-- Vanilla bug (WolfProbe, 2026-09-30): the wolf is its own mesh
-- (FastTravelSkeletal), and in wolf form pawn.Mesh points at it. Shadowstep out
-- of wolf Haste plays the Shadowstep montage and links the wall layers on the
-- wolf mesh; the game then turns Coen human and hides the wolf with that state
-- left on it. The next time the wolf shows up it still carries the Shadowstep
-- loop montage and the wall layer instead of its own locomotion layers, so it
-- slides around stuck in one pose until Coen transforms a few times.
-- Repair, only while nothing is in motion (walking mode, no Shadowstep):
--   hidden wolf mesh out of wolf form: stop its montages, unlink its layers
--     (a hidden wolf normally has neither)
--   visible wolf on the ground: stop a leftover Shadowstep/wall/claw montage,
--     unlink foreign layers, relink its own locomotion layers
local WOLF_MESH = "FastTravelSkeletal"
local HUMAN_MESH = "CharacterMesh0"
local WOLF_LAYERS = { "ABP_WolfLocomotionLayers_C", "ABP_Wolf_Coen_LegIKLayer_C" }
local WOLF_BAD_MONTAGE = { "shadowstep", "antigrav", "clawride" }
local skelClass = nil

local function isWolfLayer(name)
    for _, n in ipairs(WOLF_LAYERS) do if n == name then return true end end
    return false
end

local function meshByName(pawn, wanted)
    if not valid(skelClass) then
        local ok, c = pcall(StaticFindObject, "/Script/Engine.SkeletalMeshComponent")
        skelClass = ok and c or nil
    end
    if not valid(skelClass) then return nil end
    local found = nil
    pcall(function()
        local arr = pawn:K2_GetComponentsByClass(skelClass)
        for i = 1, #arr do
            local m = arr[i]
            if valid(m) and m:GetFName():ToString() == wanted then found = m; break end
        end
    end)
    return found
end

local function montageName(anim)
    local n = nil
    pcall(function()
        local m = anim:GetCurrentActiveMontage()
        if valid(m) then n = m:GetFName():ToString() end
    end)
    return n
end

local function badMontage(name)
    if not name then return false end
    local l = name:lower()
    for _, w in ipairs(WOLF_BAD_MONTAGE) do
        if l:find(w, 1, true) then return true end
    end
    return false
end

-- StopAllMontages alone left the montage active (1.0.3-test log). Try the
-- stop calls one after another until GetCurrentActiveMontage comes back empty,
-- and report what each did ("name ok/err -> still playing?").
local function stopMontage(anim)
    local out = {}
    local function attempt(label, fn)
        if not montageName(anim) then return end
        local ok, err = pcall(fn)
        local still = montageName(anim)
        table.insert(out, string.format("%s %s%s", label, ok and "ok" or ("err " .. tostring(err)),
            still and " still" or " cleared"))
    end
    local m = nil
    pcall(function() m = anim:GetCurrentActiveMontage() end)
    if valid(m) then attempt("Montage_Stop", function() anim:Montage_Stop(0.0, m) end) end
    attempt("StopAllMontages", function() anim:StopAllMontages(0.0) end)
    if valid(m) then
        local slots = {}
        pcall(function()
            local tracks = m.SlotAnimTracks
            for i = 1, #tracks do
                local n = tracks[i].SlotName:ToString()
                if n and n ~= "" then table.insert(slots, n) end
            end
        end)
        for _, s in ipairs(slots) do
            attempt("StopSlot " .. s, function() anim:StopSlotAnimation(0.0, FName(s)) end)
        end
        if #slots == 0 then table.insert(out, "no slot names") end
    end
    return out
end

local function boolProp(o, prop)
    local ok, v = pcall(function() return o[prop] end)
    return ok and v == true
end

local function repairWolf(pawn, now, wolf)
    local wm = meshByName(pawn, WOLF_MESH)
    if not wm then return end
    local okA, wa = pcall(function() return wm:GetAnimInstance() end)
    if not (okA and valid(wa)) then return end
    local wLayers = linkedLayers(wm)
    for _, l in ipairs(wLayers) do
        if isWolfLayer(l.name) and not valid(S.wolfLayerClasses[l.name]) then
            S.wolfLayerClasses[l.name] = l.inst:GetClass()
            log("wolf layer class captured: %s", l.name)
        end
    end
    if not S.fixWolf then return end

    -- calm: walking on the ground (world gravity), no Shadowstep. The hidden
    -- wolf's own anim flags are stale (bHasCustomGravity stayed true for
    -- seconds after the wall in 1.0.3-test2), so they are only read while the
    -- wolf is visible.
    local okM, mode = pcall(function() return pawn.CharacterMovement.MovementMode end)
    local okD, gz = pcall(function() return pawn.CharacterMovement:GetGravityDirection().Z end)
    local hm = meshByName(pawn, HUMAN_MESH)
    local ha = nil
    if hm then pcall(function() ha = hm:GetAnimInstance() end) end
    local vis = false
    pcall(function() vis = wm:IsVisible() end)
    local calm = okM and mode == 1 and okD and type(gz) == "number" and gz < -0.99
        and not (valid(ha) and boolProp(ha, "bUsingShadowstep"))
        and not (vis and boolProp(wa, "bUsingShadowstep"))
    local mont = montageName(wa)

    -- Layers that are not the wolf's own (wall, Shadowstep, claw ride).
    local foreign = {}
    local hasLoco = false
    for _, l in ipairs(wLayers) do
        if isWolfLayer(l.name) then
            if l.name == WOLF_LAYERS[1] then hasLoco = true end
        else
            table.insert(foreign, l)
        end
    end

    local problem = nil
    if calm and wolf and vis then
        if not hasLoco then problem = "wolf without its locomotion layers"
        elseif badMontage(mont) then problem = "wolf stuck in montage " .. mont
        elseif #foreign > 0 then problem = "wolf carries foreign layers" end
    elseif calm and not wolf and not vis and (mont or #foreign > 0) then
        problem = "hidden wolf keeps " .. (mont and ("montage " .. mont .. " ") or "") .. "layers [" .. layerNames(wLayers) .. "]"
    end
    if not problem then S.wolfOddSince = nil; return end
    S.wolfOddSince = S.wolfOddSince or now
    -- visible: next tick (it is already on screen); hidden: short grace
    if now - S.wolfOddSince < (wolf and 0.05 or 0.3) then return end
    S.wolfOddSince = nil

    -- Same problem again and again: retry every 5 s only, not every 0.5 s.
    if problem == S.wolfLastProblem and now - (S.wolfLastTry or 0) < 5 then return end
    S.wolfLastProblem, S.wolfLastTry = problem, now

    local tried = {}
    if mont and (not wolf or badMontage(mont)) then
        tried = stopMontage(wa)
    end
    -- Only foreign layers go; the wolf's own stay linked even while hidden
    -- (removing them made the next wolf appear without them for ~0.5 s).
    for _, l in ipairs(foreign) do
        pcall(function() wm:UnlinkAnimClassLayers(l.inst:GetClass()) end)
    end
    if wolf then
        for _, n in ipairs(WOLF_LAYERS) do
            local has = false
            for _, l in ipairs(linkedLayers(wm)) do if l.name == n then has = true end end
            if not has and valid(S.wolfLayerClasses[n]) then
                pcall(function() wm:LinkAnimClassLayers(S.wolfLayerClasses[n]) end)
            end
        end
    end
    log("wolf repair: %s -> %smontage %s, layers [%s]", problem,
        #tried > 0 and ("[" .. table.concat(tried, "; ") .. "] ") or "",
        montageName(wa) or "none", layerNames(linkedLayers(wm)))
end

---------------------------------------------------------------- core

local function tick()
    local pawn = getPawn()
    if not pawn then return end
    local okA, anim = pcall(function() return pawn.Mesh:GetAnimInstance() end)
    if not (okA and valid(anim)) then return end

    local okG, g = pcall(function() return anim.bHasCustomGravity end)
    local onWall = okG and g == true
    local now = os.clock()
    if onWall ~= S.wasOnWall then
        S.wasOnWall = onWall
        if onWall then S.wallEnterAt = now end
        log("wall %s", onWall and "enter" or "exit")
    end
    if S.logging then logState(pawn, onWall) end

    local okW, w = pcall(function() return pawn:IsInWolfForm() end)
    local wolf = okW and w == true
    local okR, errR = pcall(repairWolf, pawn, now, wolf)
    if not okR then log("wolf repair error: %s", tostring(errR)) end

    -- Wolf form: pawn.Mesh is the wolf mesh then, so never touch its layers
    -- here. Linking the human layer onto the wolf left it under Coen's feet.
    if wolf then
        S.lastWolfAt = now
        return
    end
    -- Wolf Haste + Shadowstep: Coen lands on the wall as a human and the game
    -- turns him back into the wolf about a second later. Swapping layers in
    -- that window breaks the transformation, so wait it out.
    if onWall and S.lastWolfAt and S.wallEnterAt
        and S.wallEnterAt - S.lastWolfAt < WOLF_RECENT_S
        and now - S.wallEnterAt < WOLF_SETTLE_S then
        if not S.settleLogged then
            S.settleLogged = true
            log("wall enter shortly after wolf form, waiting %.1fs", WOLF_SETTLE_S)
        end
        return
    end
    S.settleLogged = false
    local mesh = pawn.Mesh
    -- Learn the default layer class. On the wall the game has already swapped
    -- it out, so waiting until then left nothing to relink (T pose). Look it up
    -- by path once per wall entry (StaticFindObject is slow), and also take it
    -- from the linked layers while Coen is off the wall.
    if not valid(S.defaultLayerClass) then
        if onWall then
            if not S.triedPathLookup then
                S.triedPathLookup = true
                local okF, c = pcall(StaticFindObject, DEFAULT_LAYER_PATH)
                if okF and valid(c) then
                    S.defaultLayerClass = c
                    log("default layer class found by path")
                end
            end
        else
            S.triedPathLookup = false
            for _, l in ipairs(linkedLayers(mesh)) do
                if l.name == DEFAULT_LAYER then
                    S.defaultLayerClass = l.inst:GetClass()
                    log("default layer class captured")
                end
            end
        end
    end
    if not (S.enabled and onWall) then return end
    local layers = linkedLayers(mesh)
    local wallLayer = nil
    for _, l in ipairs(layers) do
        if l.name == WALL_LAYER then
            wallLayer = l.inst
            if not S.wallLayerClass then S.wallLayerClass = l.inst:GetClass() end
        elseif l.name == DEFAULT_LAYER and not S.defaultLayerClass then
            S.defaultLayerClass = l.inst:GetClass()
        elseif l.name ~= CONTROL_RIG_LAYER then
            -- A transition layer (shadowstep, claw ride) is attached: Coen is
            -- leaving the wall. Let the game play its own transition.
            return
        end
    end
    if not wallLayer then return end
    -- Without a standing layer to fall back to, unlinking leaves Coen in a
    -- T pose. Keep the vanilla crouch until the class is known.
    if not valid(S.defaultLayerClass) then return end

    local okU = pcall(function() mesh:UnlinkAnimClassLayers(wallLayer:GetClass()) end)

    local hasDefault = false
    for _, l in ipairs(linkedLayers(mesh)) do
        if l.name == DEFAULT_LAYER then hasDefault = true end
    end
    if not hasDefault and valid(S.defaultLayerClass) then
        pcall(function() mesh:LinkAnimClassLayers(S.defaultLayerClass) end)
    end
    log("wall layer detached (%s), layers now: [%s]", okU and "ok" or "failed", layerNames(linkedLayers(mesh)))
end

local function restoreWallLayer()
    local pawn = getPawn()
    if not pawn then return end
    pcall(function()
        if pawn.Mesh:GetAnimInstance().bHasCustomGravity and valid(S.wallLayerClass) then
            pawn.Mesh:LinkAnimClassLayers(S.wallLayerClass)
            log("wall layer restored")
        end
    end)
end

local function setEnabled(on, source)
    if S.enabled == on then return end
    S.enabled = on
    log("%s via %s", on and "ON" or "OFF", source)
    if not on then ExecuteInGameThread(restoreWallLayer) end
end

---------------------------------------------------------------- startup

local cfg = readConfig()
S.logging = cfg.logging == "1"
S.cfgEnabled = cfg.enabled ~= "0"
S.enabled = S.cfgEnabled
S.fixWolf = cfg.fixwolfhaste ~= "0"

local keyName = (cfg.togglekey or "NUM_FOUR"):upper()
if keyName ~= "" then
    local key = Key[keyName]
    if key then
        RegisterKeyBind(key, function() setEnabled(not S.enabled, "hotkey") end)
    else
        print("[UprightWallStance] unknown ToggleKey '" .. keyName .. "', hotkey disabled\n")
        keyName = ""
    end
end

LoopAsync(POLL_MS, function()
    ExecuteInGameThread(function()
        local ok, err = pcall(tick)
        if not ok then log("error: %s", tostring(err)) end
    end)
    return false
end)

-- Live config: picks up changes from Mod Setting Menu or a text editor.
-- Enabled is only applied when the file value changes, so the hotkey state
-- is not overwritten every poll.
LoopAsync(CONFIG_POLL_MS, function()
    local c = readConfig()
    S.logging = c.logging == "1"
    S.fixWolf = c.fixwolfhaste ~= "0"
    local fileEnabled = c.enabled ~= "0"
    if fileEnabled ~= S.cfgEnabled then
        S.cfgEnabled = fileEnabled
        setEnabled(fileEnabled, "config")
    end
    return false
end)

print(string.format("[UprightWallStance] %s loaded (%s, hotkey %s, config %s)\n",
    VERSION, S.enabled and "on" or "off", keyName ~= "" and keyName or "none", CONFIG or "not found, using defaults"))
log("==== session start %s", VERSION)
