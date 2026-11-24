-- Thesito Addon: instructor de tu clase.
-- Cuando hablas con el instructor guardamos su lista (con niveles y precios)
-- y la clasificamos con los consejos de Data.lua: esencial / útil / saltar.

local _, ns = ...
local Tr = {}
ns.Trainer = Tr

local call = ns.call
local KINDS = { available = true, unavailable = true, used = true }
local ORDER = { esencial = 1, util = 2, desconocido = 3, saltar = 4 }

-- Consejos por nombre del hechizo en tu idioma (el nombre lo da el juego).
local function AdviceByName()
    local map = {}
    for spellID, advice in pairs(ns.ClassAdvice[ns.class or ""] or {}) do
        local name = ns.SpellName(spellID)
        if name then map[name] = advice end
    end
    return map
end

local function RankNumber(rank)
    if type(rank) ~= "string" then return nil end
    return tonumber(rank:match("%d+"))
end

local function SpellKnown(id)
    if not id then return false end
    if C_SpellBook and C_SpellBook.IsSpellKnown and call(C_SpellBook.IsSpellKnown, id) then return true end
    if IsPlayerSpell and call(IsPlayerSpell, id) then return true end
    if IsSpellKnown and call(IsSpellKnown, id) then return true end
    return false
end

-- Lee la lista del instructor abierto. Devuelve true si es el de tu clase.
function Tr.Scan()
    if not (ns.db and GetNumTrainerServices and GetTrainerServiceInfo) then return false end
    if IsTradeskillTrainer and call(IsTradeskillTrainer) then return false end
    local count = call(GetNumTrainerServices) or 0
    if count == 0 then return false end

    local advice = AdviceByName()
    local found, matches = {}, 0
    for i = 1, count do
        local a1, a2, a3, a4, a5 = GetTrainerServiceInfo(i)
        if i == 1 then
            ns.db.trainerRaw = ("%s | %s | %s | %s | %s"):format(tostring(a1), tostring(a2), tostring(a3), tostring(a4), tostring(a5))
        end
        -- Forever: nombre, tipo, icono, nivel, rango. Clásico: nombre, rango, tipo.
        local name, kind, icon, level, rank = a1, a2, a3, a4, a5
        if not KINDS[kind] and KINDS[a3] then
            name, rank, kind, icon, level = a1, a2, a3, nil, nil
        end
        if type(name) == "string" and KINDS[kind] then
            local tip = C_TooltipInfo and call(C_TooltipInfo.GetTrainerService, i)
            local spell = tip and tip.id
            if spell and issecretvalue and issecretvalue(spell) then spell = nil end
            if type(level) ~= "number" then level = call(GetTrainerServiceLevelReq, i) end
            if type(icon) ~= "number" and type(icon) ~= "string" then icon = call(GetTrainerServiceIcon, i) end
            if not icon and spell then icon = ns.SpellIcon(spell) end
            if type(rank) ~= "string" or rank == "" then rank = nil end
            if advice[name] then matches = matches + 1 end
            found[#found + 1] = {
                name = name, rank = rank, rankNum = RankNumber(rank), level = level,
                cost = call(GetTrainerServiceCost, i) or 0, icon = icon, spell = spell, kind = kind,
            }
        end
    end
    -- Sin consejos para tu clase lo reconocemos por tener bastantes hechizos.
    local hasAdvice = next(ns.ClassAdvice[ns.class or ""] or {}) ~= nil
    if (hasAdvice and matches == 0) or (not hasAdvice and #found < 5) then return false end

    for _, s in ipairs(found) do
        ns.db.trainer[s.name .. "|" .. (s.rank or "")] = s
    end
    ns.db.trainerScanned = time()
    return true
end

-- La lista guardada, clasificada y ordenada por nivel. nil si aún no hay.
function Tr.List()
    if not (ns.db and next(ns.db.trainer)) then return nil end
    local advice = AdviceByName()
    local list, best = {}, {}
    for _, s in pairs(ns.db.trainer) do
        local e = { name = s.name, rank = s.rank, rankNum = s.rankNum, level = s.level, cost = s.cost or 0, icon = s.icon, spell = s.spell }
        if s.kind == "used" or SpellKnown(s.spell) then
            best[s.name] = math.max(best[s.name] or 0, s.rankNum or 1)
        end
        local a = advice[s.name]
        if a then
            e.advice, e.note = a[1], a[2]
            if a[3] and (s.rankNum or 1) > 1 then
                e.advice, e.note = "saltar", "Con el primer rango te basta."
            end
        else
            e.advice, e.note = "desconocido", "No está en mi lista de consejos: lee la descripción y decide tú."
        end
        list[#list + 1] = e
    end
    for _, e in ipairs(list) do
        e.known = (best[e.name] or 0) >= (e.rankNum or 1)
    end
    table.sort(list, function(a, b)
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
        if ORDER[a.advice] ~= ORDER[b.advice] then return ORDER[a.advice] < ORDER[b.advice] end
        if a.name ~= b.name then return a.name < b.name end
        return (a.rankNum or 0) < (b.rankNum or 0)
    end)
    return list
end

-- Lo que puedes aprender ya (nivel <= el tuyo y sin aprender), por tipo.
function Tr.Summary(level)
    local list = Tr.List()
    if not list then return nil end
    local sum = { esencial = { 0, 0 }, util = { 0, 0 }, saltar = { 0, 0 }, desconocido = { 0, 0 } }
    for _, e in ipairs(list) do
        if not e.known and e.level and e.level <= level then
            local c = sum[e.advice]
            c[1], c[2] = c[1] + 1, c[2] + e.cost
        end
    end
    return sum, list
end

function Tr.LevelUpLine(level)
    local sum = Tr.Summary(level)
    if not sum then
        return "Instructor: háblale una vez al instructor de tu clase para que pueda aconsejarte."
    end
    if sum.esencial[1] + sum.util[1] == 0 then
        return "Instructor: nada recomendado por aprender ahora mismo."
    end
    return ("Instructor: |cff40ff40%d esencial(es)|r (%s) y |cffffd200%d útil(es)|r (%s) por aprender."):format(
        sum.esencial[1], ns.Money(sum.esencial[2]), sum.util[1], ns.Money(sum.util[2]))
end

---------------------------------------------------------------------------
-- Visita al instructor: guarda la lista y abre la ventana a su lado.
---------------------------------------------------------------------------

local visit -- nil, "open" (ventana del instructor abierta) o "shown" (abrimos la nuestra)

local function OnTrainerUpdate()
    if not (visit and ns.ready) then return end
    if not Tr.Scan() then return end
    ns.RequestRefresh()
    if visit == "open" and ns.db.autoOpenTrainer ~= false then
        visit = ns.UI.OpenBesideTrainer() and "shown" or "seen"
    end
end

ns.On("TRAINER_SHOW", function()
    visit = "open"
    C_Timer.After(0.3, OnTrainerUpdate)
end)

ns.On("TRAINER_UPDATE", OnTrainerUpdate)

ns.On("TRAINER_CLOSED", function()
    if visit == "shown" then ns.UI.Close() end
    visit = nil
end)
