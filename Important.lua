-- Thesito Addon: misiones importantes para ti.
--  · Misiones que dan bolsas de más de 10 casillas.
--  · Premios especiales al final de una cadena (ns.NotableRewards de
--    Data.lua, como el Saco de dormir acogedor): por dónde vas y la siguiente.
--  · Misiones de tu clase que aún no has hecho.
--  · Recompensas que mejoran lo que llevas puesto.
-- Datos: QuestieDB. Sus objetos dicen qué misiones los dan; recorremos todos
-- una vez (poco a poco, sin congelar el juego) para saber qué da cada misión.

local _, ns = ...
local I = {}
ns.Important = I

local call = ns.call
local band = bit.band

local BAG_MIN_SLOTS = 10   -- "más de 10 casillas"
local UPGRADE_BELOW = 4    -- misiones de hasta 4 niveles por debajo del tuyo
local MAX_ABOVE = 3        -- y como mucho 3 niveles por encima
local HARD_ABOVE = 6       -- mejoras "algo más difíciles": de 4 a 6 niveles por encima

local status = "idle"      -- idle | scanning | ready | nodb
local progress = 0
local rewardsByQuest = {}  -- questID -> { itemID, ... }
local bagItems = {}        -- itemID -> true (bolsas que son recompensa)
local classQuests = {}     -- misiones de tu clase
local pending = false      -- hay objetos esperando a cargar
local slotsCache = {}      -- itemID -> casillas de la bolsa

---------------------------------------------------------------------------
-- Tú
---------------------------------------------------------------------------

local function Me()
    local _, _, raceID = UnitRace("player")
    local _, _, classID = UnitClass("player")
    local faction = UnitFactionGroup("player") == "Alliance" and "A" or "H"
    return {
        level = UnitLevel("player") or 1,
        raceBit = raceID and 2 ^ (raceID - 1) or 0,
        classBit = classID and 2 ^ (classID - 1) or 0,
        faction = faction,
    }
end

local function BitCount(n)
    local c = 0
    while n > 0 do
        c = c + n % 2
        n = math.floor(n / 2)
    end
    return c
end

---------------------------------------------------------------------------
-- Recorrido de la base de datos (una vez por sesión)
---------------------------------------------------------------------------

function I.Status() return status, progress end

function I.Start()
    if status ~= "idle" then return end
    local db = ns.Quests.DB()
    if not db then
        status = "nodb"
        return
    end
    status = "scanning"
    local me = Me()
    local work = coroutine.create(function()
        local items = db.Item.GetAllIds()
        local total = #items
        for i, itemID in ipairs(items) do
            local quests = db.Item.Get(itemID, "questRewards")
            if type(quests) == "table" and #quests > 0 then
                for _, q in ipairs(quests) do
                    local list = rewardsByQuest[q]
                    if not list then
                        list = {}
                        rewardsByQuest[q] = list
                    end
                    list[#list + 1] = itemID
                end
                if db.Item.Get(itemID, "class") == 1 then bagItems[itemID] = true end
            end
            if i % 400 == 0 then
                progress = i / total * 0.8
                coroutine.yield()
            end
        end
        local quests = db.Quest.GetAllIds()
        for i, q in ipairs(quests) do
            local classes = db.Quest.Get(q, "requiredClasses")
            if type(classes) == "number" and classes > 0 and band(classes, me.classBit) ~= 0 and BitCount(classes) <= 2 then
                classQuests[#classQuests + 1] = q
            end
            if i % 800 == 0 then
                progress = 0.8 + i / #quests * 0.2
                coroutine.yield()
            end
        end
        progress = 1
    end)
    local ticker
    ticker = C_Timer.NewTicker(0.01, function()
        local ok, err = coroutine.resume(work)
        if not ok then
            ticker:Cancel()
            status = "nodb"
            geterrorhandler()(err)
            return
        end
        if coroutine.status(work) == "dead" then
            ticker:Cancel()
            status = "ready"
        end
        ns.RequestRefresh()
    end)
end

---------------------------------------------------------------------------
-- ¿Puedes hacer esta misión?
---------------------------------------------------------------------------

local function Done(q)
    if not (type(q) == "number" and q > 0) then return false end
    if C_QuestLog.IsQuestFlaggedCompleted then return call(C_QuestLog.IsQuestFlaggedCompleted, q) and true or false end
    return call(IsQuestFlaggedCompleted, q) and true or false
end
local function InLog(q) return call(C_QuestLog.GetLogIndexForQuestID, q) ~= nil end

-- Misiones de relleno que están en la base de datos pero no en el juego.
local function IsPlaceholder(name)
    if type(name) ~= "string" then return false end
    local upper = name:upper()
    return upper:find("<NYI>", 1, true) or upper:find("<TXT>", 1, true) or upper:find("DEPRECATED", 1, true)
        or upper:find("UNUSED", 1, true) or upper:find("<NOT USED>", 1, true) or upper:find("^ZZ") or upper:find("^%[PH%]")
end

local function Available(db, q, me, profs)
    if Done(q) then return false end
    if IsPlaceholder(db.Quest.Get(q, "name")) then return false end
    local races = db.Quest.Get(q, "requiredRaces")
    if type(races) == "number" and races > 0 and band(races, me.raceBit) == 0 then return false end
    local classes = db.Quest.Get(q, "requiredClasses")
    if type(classes) == "number" and classes > 0 and band(classes, me.classBit) == 0 then return false end
    local maxLevel = db.Quest.Get(q, "requiredMaxLevel")
    if type(maxLevel) == "number" and maxLevel > 0 and me.level > maxLevel then return false end
    local skill = db.Quest.Get(q, "requiredSkill")
    if type(skill) == "table" and skill[1] and not profs[skill[1]] then return false end
    for _, other in ipairs(db.Quest.Get(q, "exclusiveTo") or {}) do
        if Done(other) or InLog(other) then return false end
    end
    -- Cadenas: si ya vas más adelante, esta ya no se puede coger (o ya la hiciste).
    local nextQuest = db.Quest.Get(q, "nextQuestInChain")
    if type(nextQuest) == "number" and (Done(nextQuest) or InLog(nextQuest)) then return false end
    for _, child in ipairs(db.Quest.Get(q, "childQuests") or {}) do
        if Done(child) or InLog(child) then return false end
    end
    local untilQuest = db.Quest.Get(q, "availableUntilCompleted")
    if type(untilQuest) == "number" and Done(untilQuest) then return false end
    local leadsTo = db.Quest.Get(q, "breadcrumbForQuestId")
    if type(leadsTo) == "number" and (Done(leadsTo) or InLog(leadsTo)) then return false end
    local disabledBy = db.Quest.Get(q, "disabledByQuest")
    if type(disabledBy) == "number" and InLog(disabledBy) then return false end
    -- Quien la da tiene que ser amistoso con tu facción.
    local starters = db.Quest.Get(q, "startedBy") or {}
    local npcs = starters[1]
    if type(npcs) == "table" and #npcs > 0 then
        local friendly = false
        for _, npc in ipairs(npcs) do
            local f = db.Npc.Get(npc, "friendlyToFaction")
            if f == nil or f:find(me.faction, 1, true) then
                friendly = true
                break
            end
        end
        if not friendly then return false end
    end
    return true
end

---------------------------------------------------------------------------
-- Dónde se coge o se entrega, en tu lado
-- Algunas misiones las dan (o las reciben) varios PNJ u objetos: uno para la
-- Horda y otro para la Alianza. Los objetos no dicen de qué facción son, así
-- que lo deducimos de las otras misiones que dan o reciben y de dónde acaba
-- la misión anterior de tu facción. Ejemplo: «Peldaños» la da un tablón en
-- Los Baldíos a la Alianza y otro en Páramos de Poniente a la Horda.
---------------------------------------------------------------------------

local LOW32 = 2 ^ 32
-- Razas de cada facción (bits bajos de la máscara de razas).
local FACTION_RACES = { Horde = 2 + 16 + 32 + 128, Alliance = 1 + 4 + 8 + 64 }

local function FactionMask(me)
    local masks = LibQuestieDB and LibQuestieDB.Enum and LibQuestieDB.Enum.factionRaceMasks
    local mask = masks and masks[UnitFactionGroup("player") or ""]
    if type(mask) ~= "number" then mask = FACTION_RACES[UnitFactionGroup("player") or ""] or 0 end
    return bit.bor(mask % LOW32, me.raceBit % LOW32)
end

-- ¿Es de tu facción? true sí, false es de la otra, nil es de las dos.
local function ForMySide(db, q, me)
    local races = db.Quest.Get(q, "requiredRaces")
    if type(races) ~= "number" or races <= 0 then return nil end
    return band(races % LOW32, me.factionMask) ~= 0
end

-- Zonas donde acaban las misiones anteriores de tu facción.
local function PreviousZones(db, q, me)
    local zones = {}
    for _, key in ipairs({ "preQuestSingle", "preQuestGroup" }) do
        local list = db.Quest.Get(q, key)
        for _, p in ipairs(type(list) == "table" and list or {}) do
            if ForMySide(db, p, me) ~= false then
                local finished = db.Quest.Get(p, "finishedBy") or {}
                for _, npc in ipairs(finished[1] or {}) do
                    local z = db.Npc.Get(npc, "zoneID")
                    if z then zones[z] = true end
                end
                for _, obj in ipairs(finished[2] or {}) do
                    local z = db.Object.Get(obj, "zoneID")
                    if z then zones[z] = true end
                end
            end
        end
    end
    return zones
end

-- PNJ y objetos que dan (field = "startedBy") o reciben ("finishedBy") una
-- misión, los de tu lado primero y sin los de la otra facción si hay alguno
-- tuyo. Devuelve { { npc = true|false, id = ... }, ... }.
local function Places(db, q, field, me)
    local data = db.Quest.Get(q, field)
    if type(data) ~= "table" then return {} end
    local list = {}
    for i, key in ipairs({ 1, 2 }) do
        local ids = data[key]
        for _, id in ipairs(type(ids) == "table" and ids or {}) do
            list[#list + 1] = { npc = (i == 1), id = id, order = #list + 1, score = 0 }
        end
    end
    if #list < 2 then return list end
    me.factionMask = me.factionMask or FactionMask(me)
    local zones = PreviousZones(db, q, me)
    local anyHostile, anyFriendly, best = false, false, -math.huge
    for _, p in ipairs(list) do
        local store = p.npc and db.Npc or db.Object
        if p.npc then
            local f = db.Npc.Get(p.id, "friendlyToFaction")
            p.hostile = type(f) == "string" and not f:find(me.faction, 1, true)
        end
        for _, key in ipairs({ "questStarts", "questEnds" }) do
            local others = store.Get(p.id, key)
            for _, other in ipairs(type(others) == "table" and others or {}) do
                if other ~= q then
                    local mine = ForMySide(db, other, me)
                    if mine == true then p.score = p.score + 2 elseif mine == false then p.score = p.score - 1 end
                end
            end
        end
        if zones[store.Get(p.id, "zoneID") or 0] then p.score = p.score + 1 end
        if p.hostile then anyHostile = true else anyFriendly = true end
        if not p.hostile and p.score > best then best = p.score end
    end
    local out = {}
    for _, p in ipairs(list) do
        local keep = not (p.hostile and anyFriendly)
        -- De la otra facción (solo tiene misiones suyas) habiendo otro mejor.
        if keep and p.score < 0 and best >= 0 then keep = false end
        if keep then out[#out + 1] = p end
    end
    table.sort(out, function(a, b)
        if (a.hostile or false) ~= (b.hostile or false) then return not a.hostile end
        if a.score ~= b.score then return a.score > b.score end
        return a.order < b.order
    end)
    return out
end

function I.Places(q, field)
    local db = ns.Quests.DB()
    return db and Places(db, q, field, Me()) or {}
end

-- Quién da la misión: { name, spot, isItem }
local function Starter(db, q, me)
    for _, p in ipairs(Places(db, q, "startedBy", me)) do
        if p.npc then
            local f = db.Npc.Get(p.id, "friendlyToFaction")
            if f == nil or f:find(me.faction, 1, true) then
                return { name = db.Npc.Get(p.id, "name") or "?", spot = ns.Quests.BestSpot(db.Npc.Get(p.id, "spawns")) }
            end
        else
            return { name = db.Object.Get(p.id, "name") or "?", spot = ns.Quests.BestSpot(db.Object.Get(p.id, "spawns")) }
        end
    end
    local starters = db.Quest.Get(q, "startedBy") or {}
    for _, item in ipairs(starters[3] or {}) do
        return { name = (C_Item.GetItemNameByID and C_Item.GetItemNameByID(item)) or db.Item.Get(item, "name") or "un objeto", isItem = true }
    end
end

function I.StarterOf(q)
    local db = ns.Quests.DB()
    return db and Starter(db, q, Me()) or nil
end

function I.RewardsOf(q)
    return rewardsByQuest[q]
end

-- ¿Puede tu personaje hacer esta misión (raza, clase, facción, no hecha…)?
function I.CanDo(q)
    local db = ns.Quests.DB()
    return db ~= nil and Available(db, q, Me(), ns.Bags.Professions()) or false
end

local function QuestInfo(db, q, me)
    local info = {
        questID = q,
        name = db.Quest.Get(q, "name") or ("Misión " .. q),
        level = db.Quest.Get(q, "questLevel") or 0,
        minLevel = db.Quest.Get(q, "requiredLevel") or 1,
        inLog = InLog(q),
        starter = Starter(db, q, me),
    }
    local pre = db.Quest.Get(q, "preQuestSingle")
    if type(pre) == "table" and #pre > 0 then
        local met = false
        for _, p in ipairs(pre) do if Done(p) then met = true end end
        if not met then info.needs = db.Quest.Get(pre[1], "name") end
    end
    return info
end

-- Las misiones previas que te faltan para llegar a q, de la primera que
-- tienes que hacer a la última (vacía si ya puedes cogerla). De varias
-- alternativas, la que llevas o la de tu lado.
local function ChainTo(db, q, me, profs)
    local chain, seen, current = {}, { [q] = true }, q
    for _ = 1, 15 do
        local pre
        local single = db.Quest.Get(current, "preQuestSingle")
        if type(single) == "table" and #single > 0 then
            local met = false
            for _, p in ipairs(single) do
                if Done(p) then met = true break end
            end
            if not met then
                for _, p in ipairs(single) do
                    if InLog(p) then pre = p break end
                end
                if not pre then
                    for _, p in ipairs(single) do
                        if Available(db, p, me, profs) then pre = p break end
                    end
                end
                pre = pre or single[1]
            end
        end
        if not pre then
            local group = db.Quest.Get(current, "preQuestGroup")
            for _, p in ipairs(type(group) == "table" and group or {}) do
                if not Done(p) then pre = p break end
            end
        end
        if not pre or seen[pre] then break end
        seen[pre] = true
        table.insert(chain, 1, pre)
        if InLog(pre) then break end
        current = pre
    end
    return chain
end

---------------------------------------------------------------------------
-- Comparar con tu equipo
---------------------------------------------------------------------------

local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_2HWEAPON = { 16 },
    INVTYPE_HOLDABLE = { 17 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
}
local SLOT_NAMES = {
    [1] = "cabeza", [2] = "cuello", [3] = "hombros", [5] = "pecho", [6] = "cintura", [7] = "piernas",
    [8] = "pies", [9] = "muñecas", [10] = "manos", [11] = "anillo", [12] = "anillo", [13] = "abalorio",
    [14] = "abalorio", [15] = "capa", [16] = "arma", [17] = "mano izquierda", [18] = "a distancia",
}

I.SLOT_NAMES = SLOT_NAMES

-- Huecos donde el tipo de armadura no importa (joyas, capas, mano izquierda).
local ANY_ARMOR = { INVTYPE_NECK = true, INVTYPE_FINGER = true, INVTYPE_TRINKET = true, INVTYPE_CLOAK = true, INVTYPE_HOLDABLE = true }

-- ¿Puede (y le conviene) llevarlo tu clase? Según ns.ClassGear de Data.lua.
-- Las bolsas especiales (de hierbas, de encantamiento, carcajes...) solo te
-- sirven si son de tu profesión o tu clase. Devuelve si sirve y qué tipo es.
local function UsefulBag(itemID, profs)
    local _, _, _, _, _, classID, sub = call(C_Item.GetItemInfoInstant, itemID)
    if classID == 11 then return ns.class == "HUNTER", "carcaj" end
    local special = sub and sub ~= 0 and ns.Bags.SPECIAL_BAGS[sub]
    if not special then return true, nil end
    if special.reagent then return true, special.name end
    local mine = (special.skill and profs[special.skill]) or (special.class and special.class == ns.class)
    return mine and true or false, special.name
end

local function ClassCanUse(classID, subclassID, equipLoc, level)
    local gear = ns.ClassGear[ns.class or ""]
    if not gear then return false end
    if classID == 4 then
        if ANY_ARMOR[equipLoc] then return true end
        if subclassID == 6 then return gear.shield == true end -- escudo
        -- Solo el mejor tipo que ya puedes llevar (p. ej. placas desde el 40).
        local best = 0
        for _, a in ipairs(gear.armor) do
            if level >= a[2] then best = math.max(best, a[1]) end
        end
        return subclassID == best
    elseif classID == 2 then
        for _, w in ipairs(gear.weapons) do if w == subclassID then return true end end
    end
    return false
end

-- Daño por segundo: cuánto vale según el hueco (arma, mano izquierda, a distancia).
local DPS_WEIGHT = { [16] = "MAINHAND_DPS", [17] = "OFFHAND_DPS", [18] = "RANGED_DPS" }

local function Score(link, slot)
    if not link then return 0 end
    local stats = C_Item.GetItemStats and call(C_Item.GetItemStats, link)
    if type(stats) ~= "table" then return nil end
    local w, s = ns.ClassWeights[ns.class or ""] or {}, 0
    for key, value in pairs(stats) do
        if key == "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" then
            s = s + value * (w[DPS_WEIGHT[slot] or ""] or 0)
        else
            s = s + value * (w[key] or 0)
        end
    end
    return s
end

local function EquippedScore(slot)
    local link = GetInventoryItemLink("player", slot)
    return Score(link, slot) or 0, link
end

-- Compara una recompensa con lo que llevas. Devuelve mejora, slot o nil.
local function Upgrade(itemID)
    local _, _, _, equipLoc, _, classID, subclassID = call(C_Item.GetItemInfoInstant, itemID)
    if not (equipLoc and SLOTS[equipLoc] and ClassCanUse(classID, subclassID, equipLoc, UnitLevel("player") or 1)) then return nil end
    local _, link = call(C_Item.GetItemInfo, itemID)
    if not link then
        pending = true
        call(C_Item.RequestLoadItemDataByID, itemID)
        return nil
    end
    local slots = SLOTS[equipLoc]
    -- Algo para la mano izquierda no sirve si llevas un bastón (arma a dos manos).
    if slots[1] == 17 then
        local mainHand = GetInventoryItemLink("player", 16)
        local _, _, _, mainLoc = call(C_Item.GetItemInfoInstant, mainHand or 0)
        if mainLoc == "INVTYPE_2HWEAPON" then return nil end
    end
    local newScore = Score(link, slots[1])
    if not newScore then return nil end
    local current, currentSlot
    if equipLoc == "INVTYPE_2HWEAPON" then
        current = EquippedScore(16) + EquippedScore(17)
        currentSlot = 16
    else
        for _, slot in ipairs(slots) do
            local s = EquippedScore(slot)
            if not current or s < current then current, currentSlot = s, slot end
        end
    end
    local gain = newScore - current
    if gain >= (ns.UpgradeMargin or 2) then
        return gain, currentSlot, current, newScore
    end
end

---------------------------------------------------------------------------
-- Las tres listas
---------------------------------------------------------------------------

function I.Lists()
    local db = ns.Quests.DB()
    if status ~= "ready" or not db then return nil end
    local me = Me()
    local profs = ns.Bags.Professions and ns.Bags.Professions() or {}
    pending = false
    local out = { bags = {}, prizes = {}, class = {}, upgrades = {}, upgradesHard = {}, later = 0, hard = 0 }

    -- Solo las que puedes coger ya y no son demasiado difíciles (misión de
    -- más de 3 niveles por encima del tuyo); las demás solo se cuentan.
    -- Las mejoras de equipo de 4 a 6 niveles por encima van aparte (hardList).
    local function Keep(list, info, hardList)
        if info.minLevel > me.level then
            out.later = out.later + 1
        elseif info.level and info.level > me.level + MAX_ABOVE then
            if hardList and info.level <= me.level + HARD_ABOVE then
                hardList[#hardList + 1] = info
            else
                out.hard = out.hard + 1
            end
        else
            list[#list + 1] = info
        end
    end

    -- Bolsas grandes.
    for itemID in pairs(bagItems) do
        local slots = slotsCache[itemID] or ns.Bags.SlotsForItemID(itemID)
        slotsCache[itemID] = slots
        if not slots then
            pending = true
            call(C_Item.RequestLoadItemDataByID, itemID)
        elseif slots > BAG_MIN_SLOTS and UsefulBag(itemID, profs) then
            local _, kind = UsefulBag(itemID, profs)
            for _, q in ipairs(db.Item.Get(itemID, "questRewards") or {}) do
                if Available(db, q, me, profs) then
                    local info = QuestInfo(db, q, me)
                    info.itemID, info.slots, info.kind = itemID, slots, kind
                    Keep(out.bags, info)
                end
            end
        end
    end

    -- Premios especiales (ns.NotableRewards de Data.lua): la misión que los
    -- da, cuántas te faltan de su cadena y cuál es la siguiente.
    for itemID, fallbackName in pairs(ns.NotableRewards or {}) do
        local itemName = C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
        if not itemName then
            pending = true
            call(C_Item.RequestLoadItemDataByID, itemID)
        end
        for _, q in ipairs(db.Item.Get(itemID, "questRewards") or {}) do
            if Available(db, q, me, profs) then
                local info = QuestInfo(db, q, me)
                local chain = ChainTo(db, q, me, profs)
                local nextQuest = chain[1] or q
                info.itemID, info.itemName, info.chain = itemID, itemName or fallbackName, chain
                info.nextQuest = nextQuest
                info.nextName = db.Quest.Get(nextQuest, "name") or ("Misión " .. nextQuest)
                info.nextInLog = InLog(nextQuest)
                info.nextStarter = Starter(db, nextQuest, me)
                info.left = #chain + 1
                Keep(out.prizes, info)
            end
        end
    end

    -- Misiones de tu clase (de tu nivel menos 5 en adelante).
    for _, q in ipairs(classQuests) do
        local level = db.Quest.Get(q, "questLevel") or 0
        if level <= 0 then level = db.Quest.Get(q, "requiredLevel") or 1 end
        if level >= me.level - 5 and Available(db, q, me, profs) then
            local info = QuestInfo(db, q, me)
            local rewards = {}
            for _, itemID in ipairs(rewardsByQuest[q] or {}) do
                rewards[#rewards + 1] = (C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)) or db.Item.Get(itemID, "name") or "?"
            end
            info.rewards = rewards
            Keep(out.class, info)
        end
    end

    -- Mejoras de equipo.
    for q, items in pairs(rewardsByQuest) do
        local minLevel = db.Quest.Get(q, "requiredLevel") or 1
        if minLevel >= me.level - UPGRADE_BELOW and minLevel <= me.level and Available(db, q, me, profs) then
            for _, itemID in ipairs(items) do
                local needLevel = db.Item.Get(itemID, "requiredLevel") or 0
                if needLevel <= me.level then
                    local gain, slot, before, after = Upgrade(itemID)
                    if gain then
                        local info = QuestInfo(db, q, me)
                        info.itemID, info.gain, info.slot, info.before, info.after = itemID, gain, slot, before, after
                        Keep(out.upgrades, info, out.upgradesHard)
                    end
                end
            end
        end
    end

    local function byLevel(a, b)
        if a.minLevel ~= b.minLevel then return a.minLevel < b.minLevel end
        return a.name < b.name
    end
    table.sort(out.bags, byLevel)
    table.sort(out.prizes, byLevel)
    table.sort(out.class, byLevel)
    local function byGain(a, b)
        if a.gain ~= b.gain then return a.gain > b.gain end
        return a.name < b.name
    end
    table.sort(out.upgrades, byGain)
    table.sort(out.upgradesHard, byGain)
    out.me = me
    return out
end

-- Al hacer clic: si la tienes, su detalle; si no, rumbo a quien la da.
function I.Open(info)
    if info.inLog then
        ns.UI.ShowQuest(info.questID)
        return
    end
    local s = info.starter
    if s and s.spot and s.spot.x then
        ns.Nav.Go({ zone = s.spot.zone, x = s.spot.x, y = s.spot.y, title = "Coger «" .. info.name .. "» (" .. s.name .. ")", questID = info.questID, kind = "coger" })
    elseif s and s.isItem then
        ns.Print(("«%s» la empieza un objeto: %s."):format(info.name, s.name))
    else
        ns.Print(("no sé dónde empieza «%s»."):format(info.name))
    end
end

-- Al aceptar la misión hacia la que ibas, quitamos el rumbo.
ns.On("QUEST_ACCEPTED", function(a, b)
    local questID = b or a -- según la versión llega (índice, misión) o solo (misión)
    local t = ns.Nav.Target()
    if t and t.kind == "coger" and (t.questID == questID) then ns.Nav.Clear(true) end
end)

ns.On("GET_ITEM_INFO_RECEIVED", function()
    if pending and ns.UI and ns.UI.IsShowing("importante") then ns.RequestRefresh() end
end)

for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP", "QUEST_ACCEPTED" }) do
    ns.On(event, function()
        if ns.UI and ns.UI.IsShowing("importante") then ns.RequestRefresh() end
    end)
end
