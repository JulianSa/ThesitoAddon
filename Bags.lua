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
    [40] = "Venenos",
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
local CLASS_TRADEGOODS, CLASS_RECIPE, CLASS_QUIVER, CLASS_QUEST = 7, 9, 11, 12
local WEAPON_FISHING_POLE = 20 -- subclase de arma "caña de pescar"

-- Herramientas de profesión: [itemID] = profesión (skillLine).
local PROFESSION_TOOLS = {
    [2901] = 186,                                                   -- Pico de minero
    [7005] = 393,                                                   -- Cuchillo de desollar
    [5956] = 164,                                                   -- Martillo de herrero
    [6219] = 202, [10498] = 202,                                    -- Llave inglesa arcoluz, Microajustador giromático
    [6218] = 333, [6339] = 333, [11130] = 333, [11145] = 333, [16207] = 333, -- Varillas rúnicas
    [9149] = 171,                                                   -- Piedra filosofal
}

-- Cebos de pesca (se ponen en la caña): van con las cosas de Pesca.
local FISHING_LURES = {
    [6529] = true, [6530] = true, [6532] = true, [6533] = true,     -- Adorno lustroso, Gusanos nocturnos, Adornos brillantes, Atrayente acuadinámico
    [6811] = true, [7307] = true, [34861] = true,                   -- Lente acuadinámica, Gusano carnívoro, Anzuelo afilado
}
for id in pairs(FISHING_LURES) do PROFESSION_TOOLS[id] = 356 end

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

-- Hechizo de cada profesión: su nombre y su icono son los de la profesión en
-- tu idioma. Sirve para reconocerla, porque en Forever el juego no siempre da
-- el número clásico de la profesión (a veces da 8167, 8175...).
local PROFESSION_SPELL = {
    [164] = 2018, [165] = 2108, [171] = 2259, [182] = 2366, [186] = 2575, [197] = 3908,
    [202] = 4036, [333] = 7411, [393] = 8613, [185] = 2550, [129] = 3273, [356] = 7620,
}

local function ProfessionSkillLine(name, icon, reported)
    if PROFESSION_SPELL[reported] then return reported end
    local wanted = type(name) == "string" and name ~= "" and name:lower()
    if wanted then
        for skillLine, spell in pairs(PROFESSION_SPELL) do
            local spellName = ns.SpellName(spell)
            if type(spellName) == "string" and spellName:lower() == wanted then return skillLine end
            local display = C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName
                and call(C_TradeSkillUI.GetTradeSkillDisplayName, skillLine)
            if type(display) == "string" and display:lower() == wanted then return skillLine end
        end
    end
    if icon then
        for skillLine, spell in pairs(PROFESSION_SPELL) do
            if ns.SpellIcon(spell) == icon then return skillLine end
        end
    end
    return reported
end

-- Hechizos que aprende todo el que tiene la profesión (Desencantar, la
-- primera receta...). Si conoces alguno, tienes la profesión, la llame el
-- juego como la llame.
local SIGNATURE_SPELLS = {
    [333] = { 13262, 7411 },        -- Desencantar
    [197] = { 2963, 3908 },         -- Rollo de tela de lino
    [165] = { 2152, 2149, 2108 },   -- Kit de armadura ligera, Botas de cuero cosidas a mano
    [164] = { 2660, 2018 },         -- Piedra de afilar basta
    [171] = { 2330, 2259 },         -- Poción de sanación menor
    [202] = { 3918, 4036 },         -- Polvo explosivo basto
    [186] = { 2656, 2580, 2575 },   -- Fundición, Encontrar minerales
    [182] = { 2383, 2366 },         -- Encontrar hierbas
    [393] = { 8613 },               -- Desollar
    [185] = { 2538, 2550 },         -- Carne de lobo carbonizada
    [129] = { 3275, 3273 },         -- Venda de lino
    [356] = { 7620 },               -- Pesca
}

-- Las profesiones de este personaje: [skillLine clásico] = nivel (0 si solo
-- se sabe que la tiene).
local function MyProfessions()
    local have = {}
    if GetProfessions and GetProfessionInfo then
        local list = { n = select("#", GetProfessions()), GetProfessions() }
        for i = 1, list.n do
            local index = list[i]
            if index then
                local name, icon, rank, _, _, _, reported = GetProfessionInfo(index)
                local skillLine = ProfessionSkillLine(name, icon, reported)
                if skillLine then have[skillLine] = rank or 0 end
            end
        end
    end
    for skillLine, spells in pairs(SIGNATURE_SPELLS) do
        if not have[skillLine] then
            for _, spell in ipairs(spells) do
                if SpellKnown(spell) then
                    have[skillLine] = 0
                    break
                end
            end
        end
    end
    return have
end

B.Professions = MyProfessions

-- Para /thesito debug: cómo ha reconocido cada profesión.
function B.ProfessionReport()
    local parts = {}
    if GetProfessions and GetProfessionInfo then
        local list = { n = select("#", GetProfessions()), GetProfessions() }
        for i = 1, list.n do
            local index = list[i]
            if index then
                local name, icon, rank, _, _, _, reported = GetProfessionInfo(index)
                parts[#parts + 1] = ("%s %s (juego %s → %s)"):format(tostring(name), tostring(rank),
                    tostring(reported), tostring(ProfessionSkillLine(name, icon, reported)))
            end
        end
    end
    local found = {}
    for skillLine in pairs(MyProfessions()) do
        if SKILL_NAME[skillLine] then found[#found + 1] = SKILL_NAME[skillLine] end
    end
    table.sort(found)
    return (#parts > 0 and table.concat(parts, ", ") or "ninguna") .. ". Reconocidas: " .. table.concat(found, ", ")
end

-- Objetos que piden las misiones de tu registro, según QuestieDB: los de sus
-- objetivos, el objeto con que empiezan y los que hay que llevar a alguien
-- (por ejemplo, los Informes Grito de Guerra de su fardo).
local function ActiveQuestItems(db)
    local items = {}
    if not db then return items end
    local count = call(C_QuestLog.GetNumQuestLogEntries) or 0
    for i = 1, count do
        local info = call(C_QuestLog.GetInfo, i)
        local q = info and not info.isHeader and info.questID
        if q then
            local function Add(id)
                if type(id) == "number" and id > 0 and not items[id] then items[id] = q end
            end
            local objectives = call(db.Quest.Get, q, "objectives")
            if type(objectives) == "table" and type(objectives[3]) == "table" then
                for _, o in ipairs(objectives[3]) do Add(type(o) == "table" and o[1]) end
            end
            Add(call(db.Quest.Get, q, "sourceItemId"))
            local required = call(db.Quest.Get, q, "requiredSourceItems")
            if type(required) == "table" then
                for _, id in ipairs(required) do Add(id) end
            end
        end
    end
    return items
end

-- Materiales de Encantamiento (polvos, esencias y fragmentos), por si no hay
-- datos de recetas: con ellos no se suben otras profesiones.
local ENCHANTING_MATS = {}
for _, id in ipairs({
    10940, 11083, 11137, 11176, 16204,                                       -- polvos
    10938, 10939, 10998, 11082, 11134, 11135, 11174, 11175, 16202, 16203,    -- esencias
    10978, 11084, 11138, 11139, 11177, 11178, 14343, 14344, 20725,           -- fragmentos y Cristal de nexo
}) do ENCHANTING_MATS[id] = { [333] = true } end

-- Qué profesiones usan cada material, según las recetas de esta versión de
-- Forever que trae SkillUpForever: [itemID] = { [skillLine] = true }.
-- SkillUpForever carga sus recetas un poco después de entrar al juego: hasta
-- que las da, se vuelve a preguntar cada vez.
local reagentUsers
B.reagentStatus = "sin preguntar"
local function ReagentUsers(itemID)
    if not reagentUsers then
        local api = _G.SkillUpForever and _G.SkillUpForever.API
        if not (api and api.Recipes and api.Recipe) then
            B.reagentStatus = "SkillUpForever no está activado"
        else
            local ids, reason = call(api.Recipes)
            if type(ids) ~= "table" or #ids == 0 then
                B.reagentStatus = "SkillUpForever aún no da recetas (" .. tostring(reason) .. ")"
            else
                local built, count = {}, 0
                for _, id in ipairs(ids) do
                    local recipe = call(api.Recipe, id)
                    if type(recipe) == "table" and recipe.skillLineID then
                        for _, reagent in ipairs(recipe.reagents or {}) do
                            local users = built[reagent.itemID]
                            if not users then
                                users = {}
                                built[reagent.itemID] = users
                                count = count + 1
                            end
                            users[recipe.skillLineID] = true
                        end
                    end
                end
                if count > 0 then
                    reagentUsers = built
                    B.reagentStatus = ("%d recetas y %d materiales de SkillUpForever"):format(#ids, count)
                else
                    B.reagentStatus = "SkillUpForever da recetas sin materiales"
                end
            end
        end
    end
    return (reagentUsers and reagentUsers[itemID]) or ENCHANTING_MATS[itemID]
end
B.ReagentUsers = ReagentUsers

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

---------------------------------------------------------------------------
-- Tipos de bolsa
-- Además de las normales hay bolsas que solo guardan un tipo de cosa (de
-- hierbas, de encantamiento, de almas...) y la bolsa de componentes, que va en
-- la quinta casilla de bolsa y solo guarda materiales de profesión.
---------------------------------------------------------------------------

B.LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
B.REAGENT_BAG = (NUM_BAG_SLOTS or 4) + 1
local REAGENT_FAMILY = "componentes"

-- Bolsas especiales que puedes encontrar (subclase de la clase 1).
B.SPECIAL_BAGS = {
    [1]  = { name = "bolsa de almas", holds = "fragmentos de alma", class = "WARLOCK" },
    [2]  = { name = "bolsa de hierbas", holds = "hierbas", skill = 182 },
    [3]  = { name = "bolsa de encantamiento", holds = "materiales de Encantamiento", skill = 333 },
    [4]  = { name = "bolsa de ingeniería", holds = "piezas de Ingeniería", skill = 202 },
    [5]  = { name = "bolsa de gemas", holds = "gemas", skill = 755 },
    [6]  = { name = "bolsa de minería", holds = "minerales y piedras", skill = 186 },
    [7]  = { name = "bolsa de peletería", holds = "cuero y pieles", skill = 165 },
    [8]  = { name = "bolsa de inscripción", holds = "materiales de Inscripción", skill = 773 },
    [9]  = { name = "caja de pesca", holds = "cosas de pesca", skill = 356 },
    [10] = { name = "bolsa de cocina", holds = "ingredientes de cocina", skill = 185 },
    [11] = { name = "bolsa de componentes", holds = "materiales de profesión", reagent = true },
}

-- Familia de una bolsa puesta (qué cabe en ella, en bits del juego) → nombre.
local FAMILY_NAMES = {
    [0x1] = "carcaj", [0x2] = "bolsa de munición", [0x4] = "bolsa de almas", [0x8] = "bolsa de peletería",
    [0x10] = "bolsa de inscripción", [0x20] = "bolsa de hierbas", [0x40] = "bolsa de encantamiento",
    [0x80] = "bolsa de ingeniería", [0x200] = "bolsa de gemas", [0x400] = "bolsa de minería",
    [0x8000] = "caja de pesca", [0x10000] = "bolsa de cocina",
}

-- Qué cabe en una bolsa puesta: 0 = de todo; "componentes" = la bolsa de
-- componentes (el juego la da como normal, se reconoce por su casilla); si
-- no, los bits de familia del juego.
function B.BagFamily(bag)
    if bag > (NUM_BAG_SLOTS or 4) then return REAGENT_FAMILY end
    if bag <= 0 then return 0 end
    local _, family = call(C_Container.GetContainerNumFreeSlots, bag)
    return family or 0
end

function B.FamilyName(family)
    if family == 0 then return "normal" end
    if family == REAGENT_FAMILY then return "bolsa de componentes" end
    for flag, name in pairs(FAMILY_NAMES) do
        if bit.band(family, flag) > 0 then return name end
    end
    return "bolsa especial"
end

-- ¿Cabe este objeto en una bolsa de esa familia?
function B.FitsIn(itemID, family)
    if family == 0 then return true end
    local _, _, _, equipLoc = call(C_Item.GetItemInfoInstant, itemID)
    if equipLoc == "INVTYPE_BAG" then return false end
    if family == REAGENT_FAMILY then
        return select(17, call(C_Item.GetItemInfo, itemID)) and true or false
    end
    local itemFamily = call(C_Item.GetItemFamily, itemID) or 0
    return type(family) == "number" and bit.band(itemFamily, family) > 0
end

-- Tamaño de tus bolsas puestas: { 16, 10, 8, 6, 0 } (0 = hueco sin bolsa) y
-- qué cabe en cada una.
local function EquippedBags()
    local sizes, families = {}, {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        sizes[#sizes + 1] = call(C_Container.GetContainerNumSlots, bag) or 0
        families[#families + 1] = B.BagFamily(bag)
    end
    return sizes, families
end
B.EquippedBags = EquippedBags

-- La bolsa normal más pequeña que llevas (0 si tienes un hueco de bolsa
-- vacío). Las especiales no cuentan: no sirven para cualquier cosa.
function B.SmallestNormalBag()
    local sizes, families = EquippedBags()
    local smallest = math.huge
    for i = 2, #sizes do
        if sizes[i] == 0 then return 0 end
        if families[i] == 0 then smallest = math.min(smallest, sizes[i]) end
    end
    return smallest
end

-- Casillas de tu bolsa de componentes (0 si el hueco está vacío; nil si el
-- juego no tiene ese hueco).
function B.ReagentBagSlots()
    if B.LAST_BAG < B.REAGENT_BAG then return nil end
    return call(C_Container.GetContainerNumSlots, B.REAGENT_BAG) or 0
end

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

-- "Clases: Mago" en la ayuda del objeto: solo esas clases pueden usarlo.
-- Devuelve la lista tal cual ("Mago" o "Mago, Brujo") o nil si no hay.
local classesPattern
local classCache = {}
local function AllowedClasses(e)
    local cached = classCache[e.itemID]
    if cached ~= nil then return cached or nil end
    if classesPattern == nil then
        classesPattern = false
        if type(ITEM_CLASSES_ALLOWED) == "string" then
            local escaped = ITEM_CLASSES_ALLOWED:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
            classesPattern = "^" .. escaped:gsub("%%s", "(.+)") .. "$"
        end
    end
    if not classesPattern then return nil end
    local lines = TooltipLines(e.bag, e.slot)
    local found = false
    for _, t in ipairs(lines) do
        local list = t:match(classesPattern)
        if list then
            found = list
            break
        end
    end
    -- Solo recordamos el "no" si el juego ya nos dio la ayuda entera.
    if found or #lines >= 3 then classCache[e.itemID] = found end
    return found or nil
end

-- ¿Está tu clase en esa lista? (en español, las clases pueden ir en
-- masculino o femenino).
local function MyClassIn(list)
    local mine = {}
    for _, name in ipairs({ ns.className,
        LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[ns.class or ""],
        LOCALIZED_CLASS_NAMES_FEMALE and LOCALIZED_CLASS_NAMES_FEMALE[ns.class or ""] }) do
        if type(name) == "string" then mine[name:lower()] = true end
    end
    for name in list:gmatch("[^,]+") do
        if mine[strtrim(name):lower()] then return true end
    end
    return false
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
        local needed = ctx.questItems[e.itemID]
        if needed then
            e.group, e.tag, e.note = "mision", "misión activa", ("Lo necesitas para «%s», que tienes en tu registro."):format(QuestName(needed, db))
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
        -- Sin saber de qué misión es, mejor no decir que lo tires.
        e.group, e.tag, e.note = "mision", "¿de qué misión?", "Es un objeto de misión, pero no sé de cuál. No lo tires sin mirar: si no recuerdas para qué era y no tienes misiones de esa zona, seguramente sobra."
        return
    end

    -- 3) Basura gris.
    if e.quality == 0 then
        e.group, e.tag, e.note = "tirar", "basura", "Objeto gris: solo sirve para venderlo."
        return
    end

    -- 3b) Solo para otras clases ("Clases: Mago" y no eres mago).
    local allowed = AllowedClasses(e)
    if allowed and not MyClassIn(allowed) then
        e.group, e.tag, e.note = "tirar", "otra clase", ("Solo lo pueden usar: %s. Véndelo o súbelo a subasta."):format(allowed)
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
        e.skill = skill
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

    -- 5) Bolsas. Las especiales solo guardan un tipo de cosa: se comparan
    -- aparte (y solo te sirven si tienes esa profesión o clase).
    if cls == CLASS_QUIVER then
        if ns.class == "HUNTER" then
            e.group, e.tag, e.note = "bolsa", "carcaj", "Carcaj o bolsa de munición: solo guarda flechas o balas."
        else
            e.group, e.tag, e.note = "tirar", "solo cazadores", "Carcaj o bolsa de munición: solo les sirve a los cazadores. Véndelo."
        end
        return
    end
    local special = cls == CLASS_CONTAINER and sub and sub ~= 0 and B.SPECIAL_BAGS[sub]
    if special then
        local slots = BagSlots(e.bag, e.slot)
        local size = slots and (" de %d casillas"):format(slots) or ""
        local Name = special.name:sub(1, 1):upper() .. special.name:sub(2)
        local tag = slots and ("%d · %s"):format(slots, special.name) or special.name
        e.skill = special.skill
        if special.reagent then
            local current = ctx.reagentSlots
            if current == 0 then
                e.group, e.tag, e.note = "bolsa", tag, ("%s%s: póntela en la quinta casilla de bolsa. Guarda solo materiales de profesión y te deja libres las demás casillas."):format(Name, size)
            elseif current and slots and slots > current then
                e.group, e.tag, e.note = "bolsa", tag, ("Es más grande que tu bolsa de componentes de %d: cámbiala."):format(current)
            elseif current and slots then
                e.group, e.tag, e.note = "tirar", tag, "Tu bolsa de componentes ya es igual o más grande: véndela."
            else
                e.group, e.tag, e.note = "bolsa", tag, ("%s%s: guarda solo materiales de profesión."):format(Name, size)
            end
        elseif (special.skill and ctx.profs[special.skill]) or (special.class and special.class == ns.class) then
            e.group, e.tag, e.note = "bolsa", tag, ("%s%s: solo guarda %s, pero así te deja libres las casillas normales."):format(Name, size, special.holds)
        else
            e.group, e.tag, e.note = "otraprof", tag, ("%s%s: solo guarda %s, y no lo usas. Véndela o súbela a subasta."):format(Name, size, special.holds)
        end
        return
    end
    if cls == CLASS_CONTAINER then
        local slots = BagSlots(e.bag, e.slot)
        local smallest = ctx.smallestBag
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

    -- 6) Herramientas de profesión (cañas de pescar, varillas rúnicas, pico,
    -- cuchillo de desollar...): aunque sean "armas" blancas, no son para vender.
    local toolSkill = PROFESSION_TOOLS[e.itemID] or ((cls == CLASS_WEAPON and sub == WEAPON_FISHING_POLE) and 356) or nil
    if toolSkill then
        local name = SKILL_NAME[toolSkill] or "una profesión"
        local what = FISHING_LURES[e.itemID] and "Cebo de pesca (se pone en la caña)" or ("Herramienta de " .. name)
        e.skill = toolSkill
        if profs[toolSkill] then
            e.group, e.tag, e.note = "profesion", name, what .. ": guárdalo."
        else
            e.group, e.tag, e.note = "otraprof", FISHING_LURES[e.itemID] and "cebo" or "herramienta",
                ("%s, y no tienes %s: guárdalo si la vas a aprender; si no, véndelo."):format(what, name)
        end
        return
    end

    -- 7) Equipo.
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

    -- 8) Materiales de profesión: ¿lo usa alguna de las tuyas? Primero por las
    -- recetas de SkillUpForever; si no las hay, por el tipo de material.
    local users = cls ~= CLASS_CONSUMABLE and ReagentUsers(e.itemID)
    if users then
        local others, first = {}, nil
        for skill in pairs(users) do
            if profs[skill] then
                local name = SKILL_NAME[skill] or "tu profesión"
                e.skill = skill
                e.group, e.tag, e.note = "profesion", name, ("Lo usas en %s: guárdalo."):format(name)
                return
            end
            others[#others + 1] = SKILL_NAME[skill] or ("profesión " .. skill)
            if not first or skill < first then first = skill end
        end
        if cls == CLASS_TRADEGOODS then
            e.skill = first
            table.sort(others)
            e.group, e.tag, e.note = "otraprof", "material", ("Lo usan %s, que no tienes: véndelo o súbelo a subasta."):format(table.concat(others, ", "))
            return
        end
    end
    if cls == CLASS_TRADEGOODS then
        for _, skill in ipairs(MATERIAL_USERS[sub] or {}) do
            if profs[skill] then
                local name = SKILL_NAME[skill] or "tu profesión"
                e.skill = skill
                e.group, e.tag, e.note = "profesion", name, ("Lo usas en %s: guárdalo."):format(name)
                return
            end
        end
        e.skill = (MATERIAL_USERS[sub] or {})[1]
        e.group, e.tag, e.note = "otraprof", "material", "Material de una profesión que no tienes: véndelo o súbelo a subasta."
        return
    end

    -- 9) Lo demás.
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
    local db = QuestDB()
    local ctx = {
        db = db, profs = MyProfessions(), objectives = ObjectiveTexts(), bags = EquippedBags(),
        smallestBag = B.SmallestNormalBag(), reagentSlots = B.ReagentBagSlots(), questItems = ActiveQuestItems(db),
    }
    local byItem, list = {}, {}
    local used, total = 0, 0

    -- La mochila, tus cuatro bolsas y la bolsa de componentes (la quinta
    -- casilla de bolsa, donde van los materiales de profesión).
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
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

---------------------------------------------------------------------------
-- Liberar una casilla
-- Como DeleteCheapestItem, pero solo entre lo que Thesito ya pone en "Para
-- vender o tirar" (nunca materiales de tus profesiones ni cosas de misiones):
-- el montón que menos vale. Con un vendedor abierto lo vende; si no, lo
-- borra. Siempre pregunta antes.
---------------------------------------------------------------------------

-- El montón de "Para vender o tirar" que menos vale, o nil.
function B.FreeSlotCandidate()
    local list = B.Analyze()
    local byItem = {}
    for _, e in ipairs(list) do byItem[e.itemID] = e end
    local best
    for bag = 0, B.LAST_BAG do
        for slot = 1, (call(C_Container.GetContainerNumSlots, bag) or 0) do
            local info = call(C_Container.GetContainerItemInfo, bag, slot)
            local e = info and info.itemID and byItem[info.itemID]
            if e and e.group == "tirar" and not info.isLocked and info.itemID ~= 6948 then
                local price = select(11, call(C_Item.GetItemInfo, info.itemID)) or 0
                local value = info.hasNoValue and 0 or price * (info.stackCount or 1)
                local c = {
                    bag = bag, slot = slot, itemID = info.itemID, link = info.hyperlink,
                    count = info.stackCount or 1, value = value, quality = info.quality or 0, note = e.note,
                }
                if not best or c.value < best.value or (c.value == best.value and c.quality < best.quality) then
                    best = c
                end
            end
        end
    end
    return best
end

-- ¿Sigue ahí lo mismo que se eligió? (por si algo se ha movido mientras
-- preguntábamos)
local function StillThere(c)
    if GetCursorInfo() then return false end
    local info = call(C_Container.GetContainerItemInfo, c.bag, c.slot)
    return info ~= nil and not info.isLocked and info.itemID == c.itemID and (info.stackCount or 1) == c.count
end

local function MerchantOpen()
    return MerchantFrame ~= nil and MerchantFrame:IsShown()
end

local function DoFreeSlot(c)
    if not StillThere(c) then
        ns.Print("ese objeto se ha movido; vuelve a pulsar el botón.")
        return
    end
    if MerchantOpen() and c.value > 0 then
        C_Container.UseContainerItem(c.bag, c.slot)
        ns.Print(("vendido: %s por %s."):format(c.link or "?", ns.Money(c.value)))
        return
    end
    C_Container.PickupContainerItem(c.bag, c.slot)
    local kind, id = GetCursorInfo()
    if kind ~= "item" or id ~= c.itemID then
        ClearCursor()
        ns.Print("no he podido coger ese objeto; no he borrado nada.")
        return
    end
    DeleteCursorItem()
    if GetCursorInfo() then
        ClearCursor()
        ns.Print("el juego no ha dejado borrarlo.")
        return
    end
    ns.Print(("borrado: %s."):format(c.link or "?"))
end

StaticPopupDialogs.THESITO_FREE_SLOT = {
    text = "%s",
    button1 = YES or "Sí",
    button2 = NO or "No",
    OnAccept = function(_, data) if data then DoFreeSlot(data) end end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    preferredIndex = 3,
}

-- Qué haría el botón ahora mismo (para su ayuda).
function B.FreeSlotText(c)
    if not c then return "No hay nada en «Para vender o tirar»." end
    local what = (c.link or "?") .. (c.count > 1 and (" x" .. c.count) or "")
    if MerchantOpen() and c.value > 0 then
        return ("Vendería %s por %s."):format(what, ns.Money(c.value))
    end
    return ("Borraría %s (en el vendedor vale %s)."):format(what, c.value > 0 and ns.Money(c.value) or "nada")
end

function B.FreeSlot()
    if InCombatLockdown() then
        ns.Print("en combate no; espera a terminar.")
        return
    end
    local c = B.FreeSlotCandidate()
    if not c then
        ns.Print("no hay nada en «Para vender o tirar» que liberar.")
        return
    end
    local what = (c.link or "?") .. (c.count > 1 and (" x" .. c.count) or "")
    local text
    if MerchantOpen() and c.value > 0 then
        text = ("¿Vender %s por %s?\n\n%s"):format(what, ns.Money(c.value), c.note or "")
    else
        text = ("¿Borrar %s?\n\nEn el vendedor vale %s. %s\n\nNo se puede deshacer."):format(what,
            c.value > 0 and ns.Money(c.value) or "nada", c.note or "")
    end
    StaticPopup_Show("THESITO_FREE_SLOT", text, nil, c)
end

-- Para /thesito debug: lo que dice el juego de cada profesión y de cada
-- objeto de tus bolsas, y cómo lo clasifica Thesito.
function B.DebugLines()
    local lines = {}
    local function Add(fmt, ...) lines[#lines + 1] = fmt:format(...) end
    if GetProfessions and GetProfessionInfo then
        local list = { n = select("#", GetProfessions()), GetProfessions() }
        for i = 1, list.n do
            local index = list[i]
            if index then
                local name, icon, rank, maxRank, _, _, reported = GetProfessionInfo(index)
                Add("prof[%d]: nombre=%s icono=%s nivel=%s/%s juego=%s -> %s", i, tostring(name), tostring(icon),
                    tostring(rank), tostring(maxRank), tostring(reported), tostring(ProfessionSkillLine(name, icon, reported)))
            end
        end
    end
    for skillLine, spells in pairs(SIGNATURE_SPELLS) do
        local parts = {}
        for _, spell in ipairs(spells) do
            parts[#parts + 1] = ("%d=%s(%s)"):format(spell, tostring(ns.SpellName(spell)), SpellKnown(spell) and "sabe" or "no")
        end
        local main = PROFESSION_SPELL[skillLine]
        Add("hechizos %d: %s; principal %s=%s icono %s", skillLine, table.concat(parts, " "), tostring(main),
            tostring(main and ns.SpellName(main)), tostring(main and ns.SpellIcon(main)))
    end
    local profs = MyProfessions()
    local mine = {}
    for skillLine, rank in pairs(profs) do mine[#mine + 1] = ("%s=%s"):format(tostring(skillLine), tostring(rank)) end
    Add("profesiones reconocidas: %s", table.concat(mine, ", "))
    for bag = 0, B.LAST_BAG do
        local _, family = call(C_Container.GetContainerNumFreeSlots, bag)
        Add("bolsa %d: %s casillas, tipo %s (juego %s)", bag, tostring(call(C_Container.GetContainerNumSlots, bag)),
            B.FamilyName(B.BagFamily(bag)), tostring(family))
    end
    Add("materiales: %s", tostring(B.reagentStatus))
    local list = B.Analyze()
    for _, e in ipairs(list) do
        local users = {}
        for skill in pairs(ReagentUsers(e.itemID) or {}) do users[#users + 1] = tostring(skill) end
        Add("obj %d %s: clase %s/%s calidad %s grupo %s (%s) usan[%s]", e.itemID, tostring(e.name),
            tostring(e.classID), tostring(e.subclassID), tostring(e.quality), tostring(e.group), tostring(e.tag),
            table.concat(users, ","))
    end
    return lines
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

---------------------------------------------------------------------------
-- Ordenar las bolsas por grupos
-- Primero junta los montones a medias del mismo objeto y luego coloca cada
-- cosa con las de su sección, en el orden de abajo, de la primera casilla
-- que ves a la última. Cada sección empieza en una fila nueva si hay sitio;
-- si no, deja una casilla vacía entre secciones. Las bolsas especiales (de
-- profesión) no se tocan.
---------------------------------------------------------------------------

B.SORT_SECTIONS = {
    { title = "misiones",                      groups = { "mision" } },
    { title = "piedra de hogar y consumibles", groups = { "fijo", "consumible" } },
    { title = "bolsas",                        groups = { "bolsa" } },
    { title = "equipo",                        groups = { "equipo" } },
    { title = "tus profesiones",               groups = { "profesion" } },
    { title = "otras profesiones",             groups = { "otraprof" } },
    { title = "lo demás",                      groups = { "resto" } },
    { title = "para desencantar",              groups = { "desencantar" } },
    { title = "para vender o tirar",           groups = { "tirar" } },
}
local FIXED_ITEMS = { [6948] = true } -- Piedra de hogar: la primera de su sección.
local MAX_MOVES_PER_STEP = 10

function B.SortOrderText()
    local names = {}
    for _, s in ipairs(B.SORT_SECTIONS) do names[#names + 1] = s.title end
    return table.concat(names, ", ")
end

local function SortGroup(e)
    if FIXED_ITEMS[e.itemID] then return "fijo" end
    if e.group == "resto" then
        if e.classID == CLASS_CONSUMABLE then return "consumible" end
        if e.classID == CLASS_WEAPON or e.classID == CLASS_ARMOR then return "equipo" end
    end
    return e.group or "resto"
end

-- Clave de orden de cada objeto, con la misma clasificación que la pestaña
-- Bolsas (list: lo que devuelve B.Analyze; si no se da, se calcula).
local function SortKeys(list)
    local rank, section = {}, {}
    for s, sec in ipairs(B.SORT_SECTIONS) do
        for _, g in ipairs(sec.groups) do
            rank[g] = #section + 1
            section[#section + 1] = s
        end
    end
    local function Key(group, e)
        local r = rank[group] or rank.resto
        return {
            rank = r, section = section[r],
            -- Dentro de cada sección, lo de la misma profesión va junto (la caña y su cebo...).
            skill = e and e.skill or 0,
            class = e and e.classID or 99, sub = e and e.subclassID or 99,
            quality = e and e.quality or 0, name = e and e.name or "",
        }
    end
    local keys = { default = Key("resto") }
    for _, e in ipairs(list or (B.Analyze())) do
        keys[e.itemID] = Key(SortGroup(e), e)
    end
    return keys
end
B.SortKeys = SortKeys

local function NormalBag(bag)
    return B.BagFamily(bag) == 0
end

-- Casillas de tus bolsas especiales (y la de componentes), las de profesión
-- primero: ahí se llevan los materiales que caben, para liberar las normales.
local function SpecialSlots()
    local list = {}
    for bag = 1, B.LAST_BAG do
        local family = B.BagFamily(bag)
        local n = call(C_Container.GetContainerNumSlots, bag) or 0
        if family ~= 0 and n > 0 then
            for slot = 1, n do
                list[#list + 1] = { bag = bag, slot = slot, family = family, last = family == REAGENT_FAMILY }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.last ~= b.last then return not a.last end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
    return list
end

-- Ventana de inventario de Bagnon (o Combuctor), si la tienes. Los dos cargan
-- el código de BagBrother dentro de su propia tabla global.
local function BagnonInventory()
    for _, name in ipairs({ "Bagnon", "Combuctor", "BagBrother" }) do
        local addon = _G[name]
        local frames = type(addon) == "table" and addon.Frames
        if type(frames) == "table" and type(frames.Get) == "function" then
            local frame = call(frames.Get, frames, "inventory")
            if type(frame) == "table" and frame[0] then return frame end
        end
    end
end

local function BagsShown()
    local bagnon = BagnonInventory()
    if bagnon then return bagnon:IsShown() end
    local combined, backpack = _G.ContainerFrameCombinedBags, _G.ContainerFrame1
    return (combined and combined:IsShown()) or (backpack and backpack:IsShown()) or false
end

-- Casillas de la ventana abierta según su posición en pantalla (de arriba
-- abajo y de izquierda a derecha), con la fila de cada una. nil si no se puede.
local function SlotsByPosition()
    local last = NUM_BAG_SLOTS or 4
    local buttons = {}
    local bagnon = BagnonInventory()
    if bagnon then
        if not bagnon:IsShown() then return nil end
        local group = rawget(bagnon, "ItemGroup")
        for _, button in ipairs(type(group) == "table" and type(group.buttons) == "table" and group.buttons or {}) do
            buttons[#buttons + 1] = { button = button, bag = button.bag }
        end
    else
        local combined = _G.ContainerFrameCombinedBags
        if not (combined and combined:IsShown() and combined.EnumerateValidItems) then return nil end
        pcall(function()
            for k, v in combined:EnumerateValidItems() do
                local button = type(k) == "table" and k or v
                if type(button) == "table" and button.GetBagID then
                    buttons[#buttons + 1] = { button = button, bag = button:GetBagID() }
                end
            end
        end)
    end

    local slots = {}
    for _, b in ipairs(buttons) do
        local ok, x, y = pcall(b.button.GetCenter, b.button)
        local slot = b.button.GetID and b.button:GetID()
        if not (ok and x and y and slot) then return nil end
        if type(b.bag) == "number" and b.bag >= 0 and b.bag <= last and NormalBag(b.bag) then
            slots[#slots + 1] = { bag = b.bag, slot = slot, x = x, y = y }
        end
    end
    if #slots == 0 then return nil end
    table.sort(slots, function(a, b)
        local ay, by = math.floor(a.y + 0.5), math.floor(b.y + 0.5)
        if ay ~= by then return ay > by end
        return a.x < b.x
    end)
    local row, lastY = 0, nil
    for _, s in ipairs(slots) do
        local y = math.floor(s.y + 0.5)
        if y ~= lastY then row, lastY = row + 1, y end
        s.row = row
    end
    return slots
end

-- Casillas en el orden en que las ves. Si no se puede leer la ventana, por
-- bolsas y casillas (Bagnon puede invertir unas u otras), sin filas.
local function SlotOrder()
    local slots = SlotsByPosition()
    if slots then return slots end

    local last = NUM_BAG_SLOTS or 4
    local bagnon = BagnonInventory()
    local profile = bagnon and bagnon.profile
    local reverseBags = type(profile) == "table" and profile.reverseBags
    local reverseSlots = type(profile) == "table" and profile.reverseSlots
    slots = {}
    for k = 0, last do
        local bag = reverseBags and (last - k) or k
        local n = call(C_Container.GetContainerNumSlots, bag) or 0
        if n > 0 and NormalBag(bag) then
            for i = 1, n do
                slots[#slots + 1] = { bag = bag, slot = reverseSlots and (n - i + 1) or i }
            end
        end
    end
    return slots
end

local function MaxStack(itemID)
    local n = C_Item.GetItemMaxStackCount and call(C_Item.GetItemMaxStackCount, itemID)
    if not n then n = select(8, call(C_Item.GetItemInfo, itemID)) end
    return tonumber(n) or 1
end

local sorter -- ordenado en marcha: { slots, keys, moves, limit, tried, waits }

-- A qué casilla va cada objeto (items ya ordenados). Entre secciones salta a
-- la fila siguiente si queda sitio para eso y para separar las que faltan;
-- si no, deja una casilla vacía; si tampoco cabe, ninguna.
local function Targets(items, slots)
    local keys = sorter.keys
    local function SectionOf(id) return (keys[id] or keys.default).section end
    local n = #slots
    local free = n - #items
    local pending = 0
    for i = 2, #items do
        if SectionOf(items[i]) ~= SectionOf(items[i - 1]) then pending = pending + 1 end
    end
    local target, pos = {}, 1
    for i, id in ipairs(items) do
        if i > 1 and SectionOf(id) ~= SectionOf(items[i - 1]) then
            pending = pending - 1
            local spare = free - pending -- lo que podemos gastar sin dejar sin hueco a las siguientes
            local here, prev = slots[pos], slots[pos - 1]
            if here and prev and here.row and prev.row then
                local skip = 0
                while slots[pos + skip] and slots[pos + skip].row == prev.row do skip = skip + 1 end
                if skip == 0 then
                    -- ya empieza fila: no hace falta hueco
                elseif skip <= spare then
                    pos, free = pos + skip, free - skip
                elseif spare >= 1 then
                    pos, free = pos + 1, free - 1
                end
            elseif spare >= 1 then
                pos, free = pos + 1, free - 1
            end
        end
        target[pos] = id
        pos = pos + 1
    end
    for p = 1, n do
        if target[p] == nil then target[p] = false end
    end
    return target
end

local function SortDone(msg)
    sorter = nil
    if msg then ns.Print(msg) end
    ns.RequestRefresh()
end

local function Less(a, b)
    if a == b then return false end
    local keys = sorter.keys
    local ka, kb = keys[a] or keys.default, keys[b] or keys.default
    if ka.rank ~= kb.rank then return ka.rank < kb.rank end
    if ka.skill ~= kb.skill then return ka.skill < kb.skill end
    if ka.class ~= kb.class then return ka.class < kb.class end
    if ka.sub ~= kb.sub then return ka.sub < kb.sub end
    if ka.quality ~= kb.quality then return ka.quality > kb.quality end
    if ka.name ~= kb.name then return ka.name < kb.name end
    return a < b
end

-- Coge lo de "from" y lo suelta en "to": si "to" tiene otra cosa, se
-- intercambian; si es el mismo objeto a medias, se juntan los montones.
local function Move(from, to)
    call(C_Container.PickupContainerItem, from.bag, from.slot)
    call(C_Container.PickupContainerItem, to.bag, to.slot)
    if GetCursorInfo() then
        ClearCursor()
        return false
    end
    sorter.moves = sorter.moves + 1
    return true
end

local function SortStep()
    if not sorter then return end
    if InCombatLockdown() then return SortDone("He parado de ordenar las bolsas: has entrado en combate.") end
    if GetCursorInfo() then return SortDone("He parado de ordenar las bolsas: tienes algo cogido con el ratón.") end
    if sorter.moves > sorter.limit then return SortDone("He parado de ordenar las bolsas: algo no cuadra. Prueba otra vez.") end

    -- Qué hay en cada casilla. Si algo se está moviendo todavía, esperamos.
    local infos, cur, wanted = {}, {}, {}
    for i, s in ipairs(sorter.slots) do
        local info = call(C_Container.GetContainerItemInfo, s.bag, s.slot)
        if info and info.isLocked then
            sorter.waits = sorter.waits + 1
            if sorter.waits > 50 then
                return SortDone("He parado de ordenar las bolsas: hay un objeto bloqueado (¿en una ventana de comercio o de correo?).")
            end
            C_Timer.After(0.1, SortStep)
            return
        end
        infos[i] = info
        cur[i] = info and info.itemID or false
        if cur[i] then wanted[#wanted + 1] = cur[i] end
    end
    sorter.waits = 0

    local busy, moved = {}, 0
    local function Done(ok)
        if not ok then
            SortDone("No he podido mover un objeto; dejo las bolsas como están.")
            return true
        end
        moved = moved + 1
        return moved >= MAX_MOVES_PER_STEP
    end

    -- 1) Juntar montones a medias del mismo objeto.
    local partial = {}
    for i = 1, #sorter.slots do
        local info = infos[i]
        local id = info and info.itemID
        if id and (info.stackCount or 1) < MaxStack(id) then
            local first = partial[id]
            local pair = first and (first .. ":" .. i)
            if not first then
                partial[id] = i
            elseif not busy[first] and not busy[i] and not sorter.tried[pair] then
                -- Cada pareja se intenta una vez: si no se juntan (uno ligado
                -- y otro no, por ejemplo), no insistimos.
                sorter.tried[pair] = true
                busy[first], busy[i] = true, true
                if Done(Move(sorter.slots[i], sorter.slots[first])) then break end
            end
        end
    end
    if not sorter then return end
    if moved > 0 then
        C_Timer.After(0.2, SortStep)
        return
    end

    -- 2) Llevar a tus bolsas especiales lo que cabe en ellas (hierbas a la de
    -- hierbas, materiales a la de componentes...), para liberar casillas
    -- normales. Cada intento se hace una vez: si el juego no lo deja, no se insiste.
    local fits = {}
    local function Fits(id, family)
        local key = id .. ":" .. tostring(family)
        if fits[key] == nil then fits[key] = B.FitsIn(id, family) end
        return fits[key]
    end
    for _, s in ipairs(sorter.special or {}) do
        if not sorter or moved >= MAX_MOVES_PER_STEP then break end
        if not call(C_Container.GetContainerItemInfo, s.bag, s.slot) then
            for i = 1, #cur do
                local id = cur[i]
                local try = id and ("%d:%d:%d"):format(s.bag, s.slot, id)
                if id and not busy[i] and not sorter.tried[try] and Fits(id, s.family) then
                    sorter.tried[try] = true
                    busy[i], cur[i] = true, false
                    Done(Move(sorter.slots[i], s))
                    break
                end
            end
        end
    end
    if not sorter then return end
    if moved > 0 then
        C_Timer.After(0.2, SortStep)
        return
    end

    -- 3) Colocar cada cosa en su casilla (con los huecos entre secciones).
    -- Cada movimiento deja bien al menos una casilla, que ya no se vuelve a
    -- tocar; si el intercambio deja bien las dos, mejor.
    table.sort(wanted, Less)
    local target = Targets(wanted, sorter.slots)
    for p = 1, #cur do
        local want = target[p]
        if want and cur[p] ~= want and not busy[p] then
            local q
            for j = 1, #cur do
                if j ~= p and cur[j] == want and target[j] ~= want and not busy[j] then
                    if target[j] == cur[p] then
                        q = j
                        break
                    end
                    q = q or j
                end
            end
            if q then
                busy[p], busy[q] = true, true
                cur[p], cur[q] = cur[q], cur[p]
                if Done(Move(sorter.slots[q], sorter.slots[p])) then break end
            end
        end
    end
    if not sorter then return end
    if moved > 0 then
        C_Timer.After(0.2, SortStep)
    else
        SortDone("bolsas ordenadas: " .. B.SortOrderText() .. ".")
    end
end

function B.IsSorting() return sorter ~= nil end

function B.Sort()
    if sorter then return end
    if InCombatLockdown() then
        ns.Print("no puedo ordenar las bolsas en combate.")
        return
    end
    if GetCursorInfo() then
        ns.Print("suelta primero lo que tienes cogido con el ratón.")
        return
    end
    sorter = { keys = SortKeys(), moves = 0, tried = {}, waits = 0 }
    local function Begin()
        if not sorter then return end
        sorter.slots = SlotOrder()
        sorter.special = SpecialSlots()
        sorter.limit = (#sorter.slots + #sorter.special) * 4
        ns.RequestRefresh()
        SortStep()
    end
    -- Con las bolsas abiertas se ven las filas (y cómo se ordena).
    if not BagsShown() and OpenAllBags then
        OpenAllBags()
        C_Timer.After(0.3, Begin)
    else
        Begin()
    end
end

---------------------------------------------------------------------------
-- Botón de ordenar en la ventana de las bolsas (Bagnon o la del juego)
---------------------------------------------------------------------------

local attached = {}

-- where: "bagnon" (barra de abajo), "backpack" (solo en la mochila) o nada.
local function AttachSortButton(frame, where)
    if not frame or attached[frame] then return end
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(66, 20)
    b:SetNormalFontObject(GameFontNormalSmall)
    b:SetHighlightFontObject(GameFontHighlightSmall)
    b:SetText("Ordenar")
    b:SetFrameLevel(frame:GetFrameLevel() + 10)
    local close = frame.CloseButton or (frame.GetName and frame:GetName() and _G[frame:GetName() .. "CloseButton"])
    local function Place()
        b:ClearAllPoints()
        if where == "bagnon" then
            -- Arriba Bagnon no deja hueco (título, opciones y cerrar): va en
            -- la barra de abajo, entre el contador de casillas y el dinero.
            b:SetPoint("BOTTOM", frame, "BOTTOM", 0, 9)
        elseif close then
            b:SetPoint("RIGHT", close, "LEFT", -4, 0)
        else
            b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -6)
        end
    end
    Place()
    frame:HookScript("OnShow", function() C_Timer.After(0, Place) end)
    b:SetScript("OnClick", function() B.Sort() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Ordenar bolsas (Thesito Addon)")
        GameTooltip:AddLine("Junta los montones y pone juntas las cosas del mismo tipo, en este orden: "
            .. B.SortOrderText() .. ".", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    -- Se ve si está activado en Opciones y, con bolsas separadas, solo en la
    -- ventana de la mochila.
    function b.Check()
        local show = ns.IsOn("sortButton")
        if show and where == "backpack" then
            local bag = frame.GetBagID and call(frame.GetBagID, frame) or frame:GetID()
            show = bag == 0
        end
        b:SetShown(show)
    end
    frame:HookScript("OnShow", function() C_Timer.After(0, b.Check) end)
    b.Check()
    attached[frame] = b
end

function B.UpdateSortButtons()
    for _, b in pairs(attached) do b.Check() end
end

local function AttachSortButtons()
    AttachSortButton(BagnonInventory(), "bagnon")
    AttachSortButton(_G.ContainerFrameCombinedBags)
    AttachSortButton(_G.ContainerFrame1, "backpack")
end

ns.On("PLAYER_LOGIN", function()
    AttachSortButtons()
    -- Bagnon crea su ventana la primera vez que abres las bolsas.
    for _, fn in ipairs({ "ToggleAllBags", "OpenAllBags", "ToggleBackpack", "OpenBackpack", "ToggleBag" }) do
        if type(_G[fn]) == "function" then
            hooksecurefunc(fn, function() C_Timer.After(0.1, AttachSortButtons) end)
        end
    end
end)
ns.On("BAG_UPDATE_DELAYED", function()
    if ns.ready then AttachSortButtons() end
end)
