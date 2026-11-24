-- Thesito Addon: análisis de bolsas.
-- Mira cada objeto de tus bolsas y lo clasifica: qué puedes vender o tirar,
-- qué desencantar, qué es de misiones y qué guardar para tus profesiones.
-- Usa la base de datos de Questie (QuestieDB) si está cargada: para qué
-- misiones sirve un objeto, qué misión inicia y qué enseña un libro.

local _, ns = ...
local B = {}
ns.Bags = B

local call = ns.call

-- Grupos, en el orden en que se muestran.
B.GROUPS = {
    { key = "tirar",       color = "|cffff6060", title = "Puedes venderlo o tirarlo" },
    { key = "desencantar", color = "|cffc080ff", title = "Para desencantar (si no te lo vas a poner)" },
    { key = "bolsa",       color = "|cff40e0d0", title = "Bolsas" },
    { key = "mision",      color = "|cffffd200", title = "De misiones: guárdalo" },
    { key = "profesion",   color = "|cff40ff40", title = "Para tus profesiones: guárdalo" },
    { key = "otraprof",    color = "|cff80c0ff", title = "De otras profesiones: véndelo o súbelo a subasta" },
    { key = "resto",       color = "|cffffffff", title = "Lo demás" },
}

-- Profesión (skillLine) de cada tipo de receta (subclase de la clase 9).
local RECIPE_SKILL = { [1] = 165, [2] = 197, [3] = 202, [4] = 164, [5] = 185, [6] = 171, [7] = 129, [8] = 333, [9] = 356, [10] = 755, [11] = 773 }
local SKILL_NAME = {
    [197] = "Sastrería", [333] = "Encantamiento", [165] = "Peletería", [164] = "Herrería",
    [202] = "Ingeniería", [171] = "Alquimia", [186] = "Minería", [182] = "Herboristería",
    [393] = "Desuello", [185] = "Cocina", [129] = "Primeros auxilios", [356] = "Pesca",
}

-- Qué profesiones usan cada tipo de material (subclase de la clase 7).
local MATERIAL_USERS = {
    [1] = { 202 },                                  -- piezas
    [2] = { 202 },                                  -- explosivos
    [3] = { 202 },                                  -- aparatos
    [5] = { 197, 129 },                             -- tela
    [6] = { 165 },                                  -- cuero
    [7] = { 164, 202, 186 },                        -- metal y piedra
    [8] = { 185 },                                  -- carne
    [9] = { 171 },                                  -- hierbas
    [10] = { 171, 164, 165, 197, 333, 202 },        -- elementales
    [11] = { 197, 165, 164, 171, 202, 333, 185 },   -- otros (hilo, tintes, frascos...)
    [12] = { 333 },                                 -- encantamiento
}

local CLASS_CONSUMABLE, CLASS_CONTAINER, CLASS_WEAPON, CLASS_ARMOR = 0, 1, 2, 4
local CLASS_TRADEGOODS, CLASS_RECIPE, CLASS_QUEST = 7, 9, 12

---------------------------------------------------------------------------
-- Ayudas
---------------------------------------------------------------------------

local function QuestDB()
    local db = _G.LibQuestieDB
    if not (db and db.Item and db.Quest) then return nil end
    if db.RequireContract and not db.RequireContract(4) then return nil end
    return db
end

local function OnQuest(questID)
    if C_QuestLog.IsOnQuest then return call(C_QuestLog.IsOnQuest, questID) and true or false end
    return call(C_QuestLog.GetLogIndexForQuestID, questID) ~= nil
end

local function QuestDone(questID)
    return call(C_QuestLog.IsQuestFlaggedCompleted, questID) and true or false
end

local function QuestName(questID, db)
    local name = C_QuestLog.GetTitleForQuestID and call(C_QuestLog.GetTitleForQuestID, questID)
    if not name and db then name = call(db.Quest.Get, questID, "name") end
    return name or ("misión " .. questID)
end

local function SpellKnown(id)
    if not id then return false end
    if C_SpellBook and C_SpellBook.IsSpellKnown and call(C_SpellBook.IsSpellKnown, id) then return true end
    if IsPlayerSpell and call(IsPlayerSpell, id) then return true end
    if IsSpellKnown and call(IsSpellKnown, id) then return true end
    return false
end

-- Las profesiones de este personaje (skillLine), tal como las dice el juego.
local function MyProfessions()
    local have = {}
    if GetProfessions and GetProfessionInfo then
        local list = { n = select("#", GetProfessions()), GetProfessions() }
        for i = 1, list.n do
            local index = list[i]
            if index then
                local skillLine = select(7, GetProfessionInfo(index))
                if skillLine then have[skillLine] = true end
            end
        end
    end
    return have
end

B.Professions = MyProfessions

-- Textos de los objetivos de tus misiones (para cuando no hay QuestieDB).
local function ObjectiveTexts()
    local texts = {}
    local count = call(C_QuestLog.GetNumQuestLogEntries) or 0
    for i = 1, count do
        local info = call(C_QuestLog.GetInfo, i)
        if info and not info.isHeader and info.questID then
            for _, o in ipairs(call(C_QuestLog.GetQuestObjectives, info.questID) or {}) do
                if type(o.text) == "string" then texts[#texts + 1] = o.text end
            end
        end
    end
    return texts
end

local function TooltipLines(bag, slot)
    local data = C_TooltipInfo and call(C_TooltipInfo.GetBagItem, bag, slot)
    local lines = {}
    for _, line in ipairs(data and data.lines or {}) do
        local t = line.leftText
        if type(t) == "string" and not (issecretvalue and issecretvalue(t)) then lines[#lines + 1] = t end
    end
    return lines
end

-- La palabra fija de "Bolsa de %d casillas" en tu idioma (p. ej. "casillas").
local slotWord
local function SlotWord()
    if slotWord ~= nil then return slotWord end
    slotWord = false
    if type(CONTAINER_SLOTS) == "string" then
        local plain = CONTAINER_SLOTS:gsub("%%%d*%$?[ds]", " ")
        for w in plain:gmatch("%S+") do
            if not slotWord or #w > #slotWord then slotWord = w end
        end
    end
    return slotWord
end

local function BagSlots(bag, slot)
    local word = SlotWord()
    if not word then return nil end
    for _, t in ipairs(TooltipLines(bag, slot)) do
        if t:find(word, 1, true) then
            local n = tonumber(t:match("%d+"))
            if n then return n end
        end
    end
end

-- Casillas de una bolsa por su ID (nil si el juego aún no la tiene cargada).
function B.SlotsForItemID(itemID)
    local word = SlotWord()
    local data = word and C_TooltipInfo and call(C_TooltipInfo.GetItemByID, itemID)
    for _, line in ipairs(data and data.lines or {}) do
        local t = line.leftText
        if type(t) == "string" and not (issecretvalue and issecretvalue(t)) and t:find(word, 1, true) then
            local n = tonumber(t:match("%d+"))
            if n then return n end
        end
    end
end

-- Tamaño de tus bolsas puestas: { 16, 10, 8, 6, 0 } (0 = hueco sin bolsa).
local function EquippedBags()
    local sizes = {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        sizes[#sizes + 1] = call(C_Container.GetContainerNumSlots, bag) or 0
    end
    return sizes
end
B.EquippedBags = EquippedBags

-- Libros de la biblioteca de Forever: su descripción dice "Una incorporación
-- estupenda a la biblioteca de cualquier coleccionista".
local libraryCache = {}
local function IsLibraryBook(e)
    local cached = libraryCache[e.itemID]
    if cached ~= nil then return cached end
    local lines = TooltipLines(e.bag, e.slot)
    local found = false
    for _, t in ipairs(lines) do
        local low = t:lower()
        if (low:find("biblioteca", 1, true) and low:find("coleccionista", 1, true))
            or (low:find("library", 1, true) and low:find("collector", 1, true)) then
            found = true
            break
        end
    end
    -- Solo recordamos el "no" si el juego ya nos dio la descripción entera.
    if found or #lines >= 3 then libraryCache[e.itemID] = found end
    return found
end

local function Librarian()
    if UnitFactionGroup("player") == "Alliance" then
        return "Garion Wendell, el bibliotecario de Ventormenta (Barrio de los Magos)"
    end
    return "Owen Thadd, el bibliotecario de Entrañas (Barrio de la Magia, coordenadas 74, 33)"
end

---------------------------------------------------------------------------
-- Clasificación de un objeto
---------------------------------------------------------------------------

-- Pone e.group, e.tag (texto corto) y e.note (explicación).
local function Classify(e, ctx)
    local db, profs = ctx.db, ctx.profs
    local cls, sub = e.classID, e.subclassID

    -- 0) Libros de la biblioteca: nunca tirarlos.
    if IsLibraryBook(e) then
        e.group, e.tag = "mision", "biblioteca"
        e.note = ("Libro de la biblioteca de Forever: ¡no lo tires! Entrégaselo a %s. "
            .. "Cada libro da algo de experiencia y plata, y al juntar 10, 20, 25 y 35 libros "
            .. "te dan recompensas (colgante, anillo y más)."):format(Librarian())
        return
    end

    -- 1) Misiones, según QuestieDB.
    if db then
        local starts = call(db.Item.Get, e.itemID, "startQuest")
        if starts and starts > 0 then
            if QuestDone(starts) then
                e.group, e.tag, e.note = "tirar", "misión ya hecha", ("Inicia «%s», que ya completaste."):format(QuestName(starts, db))
            elseif OnQuest(starts) then
                e.group, e.tag, e.note = "mision", "en tu registro", ("Es de «%s», que ya tienes empezada."):format(QuestName(starts, db))
            else
                e.group, e.tag, e.note = "mision", "¡empieza misión!", ("Haz clic derecho sobre él para empezar «%s»."):format(QuestName(starts, db))
            end
            return
        end
        local related = call(db.Item.Get, e.itemID, "relatedQuests")
        if type(related) == "table" and #related > 0 then
            local active, pending = nil, nil
            local allDone = true
            for _, q in ipairs(related) do
                if OnQuest(q) then active = active or q end
                if not QuestDone(q) then
                    allDone = false
                    pending = pending or q
                end
            end
            if active then
                e.group, e.tag, e.note = "mision", "misión activa", ("Lo necesitas para «%s», que tienes en tu registro."):format(QuestName(active, db))
                return
            end
            if cls == CLASS_QUEST then
                if allDone then
                    e.group, e.tag, e.note = "tirar", "misión ya hecha", ("Era para «%s», que ya completaste."):format(QuestName(related[1], db))
                else
                    e.group, e.tag, e.note = "mision", "misión futura", ("Sirve para «%s», que todavía no has cogido."):format(QuestName(pending, db))
                end
                return
            end
        end
    end

    -- 2) Objeto de misión sin datos: miramos los objetivos de tu registro.
    if cls == CLASS_QUEST or (e.questInfo and e.questInfo.isQuestItem) then
        for _, text in ipairs(ctx.objectives) do
            if e.name and text:find(e.name, 1, true) then
                e.group, e.tag, e.note = "mision", "misión activa", "Aparece en los objetivos de una misión que tienes."
                return
            end
        end
        if e.questInfo and e.questInfo.questID and not e.questInfo.isActive then
            e.group, e.tag, e.note = "mision", "¡empieza misión!", "Haz clic derecho sobre él para empezar su misión."
            return
        end
        e.group, e.tag, e.note = "tirar", "¿sobra?", "Es de misión, pero no lo veo en ninguna misión que tengas. Si no recuerdas para qué es, seguramente sobra."
        return
    end

    -- 3) Basura gris.
    if e.quality == 0 then
        e.group, e.tag, e.note = "tirar", "basura", "Objeto gris: solo sirve para venderlo."
        return
    end

    -- 4) Libros, manuales y recetas.
    local teaches = db and call(db.Item.Get, e.itemID, "teachesSpell")
    local learned = (teaches and teaches > 0 and SpellKnown(teaches))
    if not learned and (cls == CLASS_RECIPE or e.readable) and ITEM_SPELL_KNOWN then
        for _, t in ipairs(TooltipLines(e.bag, e.slot)) do
            if t == ITEM_SPELL_KNOWN then learned = true break end
        end
    end
    if learned then
        e.group, e.tag, e.note = "tirar", "ya aprendido", "Ya lo has aprendido: no te aporta nada más."
        return
    end
    if cls == CLASS_RECIPE then
        local skill = RECIPE_SKILL[sub]
        if skill and not profs[skill] then
            e.group, e.tag, e.note = "otraprof", "receta ajena", "Receta de una profesión que no tienes: véndela o súbela a subasta."
        else
            e.group, e.tag, e.note = "profesion", "receta", ("Receta de %s: apréndela con clic derecho si tienes nivel."):format(SKILL_NAME[skill] or "tu profesión")
        end
        return
    end
    if e.readable and e.noValue then
        e.group, e.tag, e.note = "tirar", "solo se lee", "Solo es para leer y no se puede vender: puedes tirarlo."
        return
    end

    -- 5) Bolsas.
    if cls == CLASS_CONTAINER then
        local slots = BagSlots(e.bag, e.slot)
        local smallest = math.huge
        for i = 2, #ctx.bags do smallest = math.min(smallest, ctx.bags[i]) end
        if slots and smallest == 0 then
            e.group, e.tag, e.note = "bolsa", ("%d casillas"):format(slots), "¡Tienes un hueco de bolsa vacío! Póntela."
        elseif slots and slots > smallest then
            e.group, e.tag, e.note = "bolsa", ("%d casillas"):format(slots), ("Es más grande que tu bolsa de %d: cámbiala."):format(smallest)
        elseif slots then
            e.group, e.tag, e.note = "tirar", ("%d casillas"):format(slots), "Tus bolsas ya son iguales o más grandes: véndela."
        else
            e.group, e.tag, e.note = "bolsa", "bolsa", "Mira si es más grande que alguna de las tuyas."
        end
        return
    end

    -- 6) Equipo.
    if (cls == CLASS_WEAPON or cls == CLASS_ARMOR) and e.equipLoc and e.equipLoc ~= "" then
        if e.quality and e.quality >= 2 and profs[333] then
            e.group, e.tag, e.note = "desencantar", "desencantar", "Eres Encantador: si no te lo vas a poner, desencántalo (vale más que venderlo)."
        elseif e.quality and e.quality >= 2 then
            e.group, e.tag, e.note = "resto", "equipo", "Si no te lo vas a poner, véndelo o súbelo a subasta."
        else
            e.group, e.tag, e.note = "tirar", "equipo blanco", "Equipo blanco: si no lo llevas puesto, véndelo."
        end
        return
    end

    -- 7) Materiales de profesión: ¿lo usa alguna de las tuyas?
    if cls == CLASS_TRADEGOODS then
        for _, skill in ipairs(MATERIAL_USERS[sub] or {}) do
            if profs[skill] then
                local name = SKILL_NAME[skill] or "tu profesión"
                e.group, e.tag, e.note = "profesion", name, ("Lo usas en %s: guárdalo."):format(name)
                return
            end
        end
        e.group, e.tag, e.note = "otraprof", "material", "Material de una profesión que no tienes: véndelo o súbelo a subasta."
        return
    end

    -- 8) Lo demás.
    if cls == CLASS_CONSUMABLE then
        e.group, e.tag, e.note = "resto", "consumible", "Comida, bebida, poción o similar."
    else
        e.group, e.tag, e.note = "resto", "", ""
    end
end

---------------------------------------------------------------------------
-- Análisis completo
---------------------------------------------------------------------------

local pendingItems = false

function B.Analyze()
    local ctx = { db = QuestDB(), profs = MyProfessions(), objectives = ObjectiveTexts(), bags = EquippedBags() }
    local byItem, list = {}, {}
    local used, total = 0, 0

    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local slots = call(C_Container.GetContainerNumSlots, bag) or 0
        total = total + slots
        for slot = 1, slots do
            local info = call(C_Container.GetContainerItemInfo, bag, slot)
            if info and info.itemID then
                used = used + 1
                local e = byItem[info.itemID]
                if not e then
                    e = {
                        itemID = info.itemID, bag = bag, slot = slot, count = 0, slots = 0,
                        icon = info.iconFileID, quality = info.quality, link = info.hyperlink,
                        readable = info.isReadable, noValue = info.hasNoValue,
                        questInfo = call(C_Container.GetContainerItemQuestInfo, bag, slot),
                    }
                    e.name = type(info.hyperlink) == "string" and info.hyperlink:match("%[(.-)%]") or nil
                    local _, _, _, equipLoc, _, classID, subclassID = call(C_Item.GetItemInfoInstant, info.itemID)
                    e.equipLoc, e.classID, e.subclassID = equipLoc, classID, subclassID
                    byItem[info.itemID] = e
                    list[#list + 1] = e
                end
                e.count = e.count + (info.stackCount or 1)
                e.slots = e.slots + 1
            end
        end
    end

    pendingItems = false
    local sum = { freeSlots = 0, freeValue = 0 }
    for _, e in ipairs(list) do
        local itemName, _, _, _, _, _, _, _, _, _, sellPrice = call(C_Item.GetItemInfo, e.itemID)
        if itemName == nil then
            sellPrice = nil
            pendingItems = true
            call(C_Item.RequestLoadItemDataByID, e.itemID)
        end
        e.value = (not e.noValue and sellPrice or 0) * e.count
        Classify(e, ctx)
        if e.group == "tirar" then
            sum.freeSlots = sum.freeSlots + e.slots
            sum.freeValue = sum.freeValue + e.value
        end
    end

    local order = {}
    for i, g in ipairs(B.GROUPS) do order[g.key] = i end
    table.sort(list, function(a, b)
        if a.group ~= b.group then return order[a.group] < order[b.group] end
        if (a.value or 0) ~= (b.value or 0) then return (a.value or 0) > (b.value or 0) end
        return (a.name or "") < (b.name or "")
    end)

    sum.used, sum.total, sum.bags, sum.withQuestie = used, total, ctx.bags, ctx.db ~= nil
    return list, sum
end

-- Cuando el juego termina de cargar datos de objetos, repintamos.
ns.On("GET_ITEM_INFO_RECEIVED", function()
    if pendingItems then ns.RequestRefresh() end
end)

for _, event in ipairs({ "BAG_UPDATE_DELAYED", "QUEST_LOG_UPDATE", "SKILL_LINES_CHANGED" }) do
    ns.On(event, function()
        if ns.UI and ns.UI.IsShowing("bolsas") then ns.RequestRefresh() end
    end)
end
