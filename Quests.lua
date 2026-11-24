-- Thesito Addon: misiones de tu registro.
-- El juego da el texto y tu progreso; la base de datos de Questie (QuestieDB)
-- da dónde están los objetivos y quién recibe la misión. TomTom (o el marcador
-- del propio juego) pone la flecha.

local _, ns = ...
local Q = {}
ns.Quests = Q

local call = ns.call
local MAX_SOURCES = 3

---------------------------------------------------------------------------
-- Ayudas
---------------------------------------------------------------------------

local function DB()
    local db = _G.LibQuestieDB
    if not (db and db.Quest and db.Npc and db.Object and db.Item) then return nil end
    if db.RequireContract and not db.RequireContract(4) then return nil end
    return db
end

local function Get(entity, id, key)
    return entity and call(entity.Get, id, key)
end

function Q.ZoneName(areaId)
    local name = C_Map and C_Map.GetAreaInfo and call(C_Map.GetAreaInfo, areaId)
    return name or ("zona " .. tostring(areaId))
end

-- Mapa de una zona (para la flecha), con la tabla de zonas de Questie.
local function UiMapID(areaId)
    if not areaId then return nil end
    if not (QuestieLoader and QuestieLoader.ImportModule) then return nil end
    local zoneDB = call(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB")
    if zoneDB and zoneDB.GetUiMapIdByAreaId then
        return call(zoneDB.GetUiMapIdByAreaId, zoneDB, areaId)
    end
end

-- De una lista de apariciones {[zona] = {{x, y}, ...}} saca un punto
-- representativo: la zona con más apariciones (o la preferida) y el punto
-- más cercano al centro de todas ellas.
local function BestSpot(spawns, preferZone)
    if type(spawns) ~= "table" then return nil end
    local bestZone, bestList
    for zone, list in pairs(spawns) do
        if type(list) == "table" and #list > 0 then
            if zone == preferZone then
                bestZone, bestList = zone, list
                break
            end
            if not bestList or #list > #bestList then bestZone, bestList = zone, list end
        end
    end
    if not bestList then return nil end
    local sx, sy, n = 0, 0, 0
    for _, p in ipairs(bestList) do
        if type(p[1]) == "number" and p[1] >= 0 then sx, sy, n = sx + p[1], sy + p[2], n + 1 end
    end
    if n == 0 then return { zone = bestZone, count = 0 } end
    local cx, cy = sx / n, sy / n
    local px, py, best = nil, nil, math.huge
    for _, p in ipairs(bestList) do
        if type(p[1]) == "number" and p[1] >= 0 then
            local d = (p[1] - cx) ^ 2 + (p[2] - cy) ^ 2
            if d < best then best, px, py = d, p[1], p[2] end
        end
    end
    return { zone = bestZone, x = px, y = py, count = n }
end

local function SpotText(spot)
    if not spot then return "|cff9d9d9dsin ubicación conocida|r" end
    local text = Q.ZoneName(spot.zone)
    if spot.x then text = text .. ("  |cffffffff(%.0f, %.0f)|r"):format(spot.x, spot.y) end
    if spot.count and spot.count > 1 then text = text .. (" |cff9d9d9d· %d sitios|r"):format(spot.count) end
    return text
end

local function Done(questID)
    return call(C_QuestLog.IsQuestFlaggedCompleted, questID) and true or false
end

local function ItemName(db, itemID)
    local name = C_Item and C_Item.GetItemNameByID and call(C_Item.GetItemNameByID, itemID)
    return name or Get(db and db.Item, itemID, "name") or ("objeto " .. itemID)
end

---------------------------------------------------------------------------
-- Lista de tu registro
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Nivel y tipo de una misión, como en otros addons: "[25E]" en el color de
-- su dificultad (gris = ya no da casi experiencia; verde = fácil; amarillo =
-- de tu nivel; naranja = difícil; rojo = muy difícil). La letra es el tipo:
-- E élite, D mazmorra, R banda, P JcJ, H heroica, L legendaria.
---------------------------------------------------------------------------

-- Tipos de misión según el juego (los mismos números que usa Questie).
local QUEST_TAGS = {
    [1]  = { "E", "Élite: mejor en grupo, los enemigos son más fuertes." },
    [41] = { "P", "JcJ: contra otros jugadores." },
    [62] = { "R", "Banda: para un grupo de banda." },
    [81] = { "D", "Mazmorra: hay que hacerla dentro de una mazmorra, en grupo." },
    [83] = { "L", "Legendaria." },
    [85] = { "H", "Heroica: mazmorra en dificultad heroica." },
    [88] = { "R", "Banda (10 jugadores)." },
    [89] = { "R", "Banda (25 jugadores)." },
}

local tagCache, tagTries = {}, {}
local tagRetry = false
-- Letra y explicación del tipo de misión, o nil si es normal. El juego no da
-- nada para las normales, pero a veces tampoco para las demás hasta que carga
-- el dato: se pregunta otra vez al segundo y, si sigue sin nada, es normal.
function Q.Tag(questID)
    if not questID then return nil end
    local cached = tagCache[questID]
    if cached ~= nil then return cached and cached[1], cached and cached[2] end
    if not (C_QuestLog and C_QuestLog.GetQuestTagInfo) then return nil end
    local info = call(C_QuestLog.GetQuestTagInfo, questID)
    if type(info) ~= "table" then
        local now = GetTime and GetTime() or 0
        local first = tagTries[questID]
        if not first then
            tagTries[questID] = now
        elseif now - first >= 1 then
            tagCache[questID] = false
        end
        if not first and not tagRetry then
            tagRetry = true
            C_Timer.After(1, function()
                tagRetry = false
                ns.RequestRefresh()
            end)
        end
        return nil
    end
    local tag = QUEST_TAGS[info.tagID]
    if not tag and info.isElite then tag = QUEST_TAGS[1] end
    tagCache[questID] = tag or false
    if tag then return tag[1], tag[2] end
end

-- Color de dificultad de una misión de ese nivel para ti.
function Q.DifficultyColor(level)
    if type(level) ~= "number" or level <= 0 then return "|cffffffff" end
    if GetQuestDifficultyColor then
        local c = call(GetQuestDifficultyColor, level)
        if type(c) == "table" and c.r then
            return ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255)
        end
    end
    local me = UnitLevel("player") or 1
    local diff = level - me
    if diff >= 5 then return "|cffff1a1a" end   -- rojo
    if diff >= 3 then return "|cffff8040" end   -- naranja
    if diff >= -2 then return "|cffffff00" end  -- amarillo
    local gray = (GetQuestGreenRange and call(GetQuestGreenRange))
        or (me <= 5 and 5) or (me <= 39 and 5 + math.floor(me / 10)) or (me <= 59 and 1 + math.floor(me / 5)) or 9
    if -diff <= gray then return "|cff40c040" end -- verde
    return "|cff808080"                           -- gris
end

-- "[25E]" con su color.
function Q.LevelText(questID, level)
    local letter = Q.Tag(questID)
    if type(level) ~= "number" or level <= 0 then
        return letter and ("|cffffffff[" .. letter .. "]|r") or ""
    end
    return ("%s[%d%s]|r"):format(Q.DifficultyColor(level), level, letter or "")
end

-- { { header = "Zona" } | { questID, title, level, complete, done, total } ... }
function Q.List()
    local out, quests, complete = {}, 0, 0
    local count = call(C_QuestLog.GetNumQuestLogEntries) or 0
    for i = 1, count do
        local info = call(C_QuestLog.GetInfo, i)
        if info and info.isHeader then
            out[#out + 1] = { header = info.title }
        elseif info and info.questID and not info.isHidden then
            local isComplete = call(C_QuestLog.IsComplete, info.questID) and true or false
            local done, total = 0, 0
            for _, o in ipairs(call(C_QuestLog.GetQuestObjectives, info.questID) or {}) do
                total = total + 1
                if o.finished then done = done + 1 end
            end
            out[#out + 1] = {
                questID = info.questID, title = info.title, level = info.level,
                complete = isComplete, done = done, total = total,
            }
            quests = quests + 1
            if isComplete then complete = complete + 1 end
        end
    end
    return out, quests, complete
end

function Q.InLog(questID)
    return questID ~= nil and call(C_QuestLog.GetLogIndexForQuestID, questID) ~= nil
end

---------------------------------------------------------------------------
-- Detalle de una misión
---------------------------------------------------------------------------

local function QuestTexts(questID)
    local index = call(C_QuestLog.GetLogIndexForQuestID, questID)
    if not index then return nil end
    local desc, objectives = call(GetQuestLogQuestText, index)
    if not desc and C_QuestLog.SetSelectedQuest then
        local previous = call(C_QuestLog.GetSelectedQuest)
        call(C_QuestLog.SetSelectedQuest, questID)
        desc, objectives = call(GetQuestLogQuestText)
        if previous then call(C_QuestLog.SetSelectedQuest, previous) end
    end
    return desc, objectives
end

local function Shorten(text, max)
    if type(text) ~= "string" then return nil end
    text = text:gsub("%s+", " ")
    if #text <= max then return text end
    local cut = text:sub(1, max):gsub("%s%S*$", "")
    return cut .. "…"
end

local function QuestTitle(db, q)
    return call(C_QuestLog.GetTitleForQuestID, q) or Get(db and db.Quest, q, "name") or ("misión " .. q)
end

-- Dónde conseguir un objeto: { { what, spot }, ... } (hasta MAX_SOURCES).
local function ItemSources(db, itemID, preferZone)
    local name = ItemName(db, itemID)
    local out = {}
    local function push(what, spot)
        if #out < MAX_SOURCES then out[#out + 1] = { what = what, spot = spot } end
    end
    for _, npcID in ipairs(Get(db.Item, itemID, "npcDrops") or {}) do
        push(("%s: lo suelta %s"):format(name, Get(db.Npc, npcID, "name") or "?"), BestSpot(Get(db.Npc, npcID, "spawns"), preferZone))
    end
    for _, objID in ipairs(Get(db.Item, itemID, "objectDrops") or {}) do
        push(("%s: está en %s"):format(name, Get(db.Object, objID, "name") or "?"), BestSpot(Get(db.Object, objID, "spawns"), preferZone))
    end
    for _, npcID in ipairs(Get(db.Item, itemID, "vendors") or {}) do
        push(("%s: lo vende %s"):format(name, Get(db.Npc, npcID, "name") or "?"), BestSpot(Get(db.Npc, npcID, "spawns"), preferZone))
    end
    if #out == 0 then out[1] = { what = name } end
    return out
end

-- La misión previa que te falta; de varias alternativas, la que puedes hacer.
local function UnmetPre(db, q)
    local single = Get(db.Quest, q, "preQuestSingle")
    if type(single) == "table" and #single > 0 then
        local pick
        for _, p in ipairs(single) do
            if Done(p) then return nil end
            if Q.InLog(p) then return p end
            if not pick and ns.Important and ns.Important.CanDo(p) then pick = p end
        end
        return pick or single[1]
    end
    local group = Get(db.Quest, q, "preQuestGroup")
    for _, p in ipairs(type(group) == "table" and group or {}) do
        if not Done(p) then return p end
    end
end

-- Cadena de misiones previas, de la primera que tienes que hacer a la última.
local function Chain(db, q)
    local chain, seen, current = {}, { [q] = true }, q
    for _ = 1, 10 do
        local pre = UnmetPre(db, current)
        if not pre or seen[pre] then break end
        seen[pre] = true
        table.insert(chain, 1, pre)
        if Q.InLog(pre) then break end
        current = pre
    end
    return chain
end

-- Escribe quién da una misión (o dónde se consigue el objeto que la empieza)
-- y devuelve el destino para la flecha.
local function StarterLines(db, q, qTitle, add, preferZone)
    local s = ns.Important and ns.Important.StarterOf(q)
    if s and s.isItem then
        add("• La empieza un objeto: " .. s.name)
        local starters = Get(db.Quest, q, "startedBy") or {}
        local itemID = type(starters[3]) == "table" and starters[3][1]
        local dest
        if itemID then
            for _, w in ipairs(ItemSources(db, itemID, preferZone)) do
                add("    " .. w.what)
                add("        " .. SpotText(w.spot))
                if not dest and w.spot and w.spot.x then
                    dest = { zone = w.spot.zone, x = w.spot.x, y = w.spot.y, title = "Conseguir " .. s.name .. " («" .. qTitle .. "»)" }
                end
            end
        end
        return dest
    elseif s then
        add("• " .. s.name)
        add("    " .. SpotText(s.spot))
        if s.spot and s.spot.x then
            return { zone = s.spot.zone, x = s.spot.x, y = s.spot.y, title = "Coger «" .. qTitle .. "» (" .. s.name .. ")" }
        end
    else
        add("|cff9d9d9dNo sé quién la da.|r")
    end
end

-- Devuelve { lines = { ... }, objective = destino, turnIn = destino, starter = destino }
-- destino = { zone, x, y, title } para la flecha.
function Q.Detail(questID)
    local db = DB()
    local info = { lines = {} }
    local L = info.lines
    local function add(text) L[#L + 1] = text or "" end

    local title = call(C_QuestLog.GetTitleForQuestID, questID) or Get(db and db.Quest, questID, "name") or ("Misión " .. questID)
    local level = Get(db and db.Quest, questID, "questLevel")
    local zone = Get(db and db.Quest, questID, "zoneOrSort")
    local preferZone = (type(zone) == "number" and zone > 0) and zone or nil
    info.title = title

    if not (level and level > 0) then
        local index = call(C_QuestLog.GetLogIndexForQuestID, questID)
        local logInfo = index and call(C_QuestLog.GetInfo, index)
        level = logInfo and logInfo.level or level
    end
    add(("|cffffd200%s|r %s"):format(title, Q.LevelText(questID, level)))
    local _, tagText = Q.Tag(questID)
    if tagText then add("|cffff9933" .. tagText .. "|r") end
    if preferZone then add("|cff9d9d9d" .. Q.ZoneName(preferZone) .. "|r") end
    add("")

    -- Si tiene rumbo puesto: cómo llegar.
    local route = ns.Nav and ns.Nav.RouteLines(questID)
    if route then
        for _, line in ipairs(route) do add(line) end
        add("")
    end

    -- Si aún no la tienes: requisitos, cadena previa y quién la da.
    info.inLog = Q.InLog(questID)
    if not info.inLog then
        add("|cffff9933Todavía no la tienes en tu registro.|r")
        local minLevel = Get(db and db.Quest, questID, "requiredLevel")
        if minLevel then add(("Se coge desde el nivel %d."):format(minLevel)) end
        if db then
            local chain = Chain(db, questID)
            if #chain > 0 then
                add("")
                add(#chain == 1 and "|cffff9933Antes tienes que hacer esta misión:|r"
                    or ("|cffff9933Antes tienes que hacer estas %d misiones, en orden:|r"):format(#chain))
                for i, p in ipairs(chain) do
                    add(("  %d. «%s»%s"):format(i, QuestTitle(db, p), Q.InLog(p) and " |cffffd200(ya la tienes)|r" or ""))
                end
                local first = chain[1]
                local firstTitle = QuestTitle(db, first)
                add("")
                add("|cffffd200Empieza por «" .. firstTitle .. "»|r")
                if Q.InLog(first) then
                    add("Ya la tienes en el registro: búscala en la pestaña Misiones.")
                else
                    local firstLevel = Get(db.Quest, first, "requiredLevel")
                    if firstLevel then add(("Se coge desde el nivel %d."):format(firstLevel)) end
                    info.starter = StarterLines(db, first, firstTitle, add, preferZone)
                    if info.starter then info.starter.questID = first end
                    local texts = Get(db.Quest, first, "objectivesText")
                    if type(texts) == "table" and #texts > 0 then
                        add("Qué hay que hacer: " .. Shorten(table.concat(texts, " "), 300))
                    end
                end
            end
            add("")
            add("|cffffd200Quién da «" .. title .. "»|r")
            local dest = StarterLines(db, questID, title, add, preferZone)
            if #chain == 0 then info.starter = dest end
        end
        add("")
    end

    -- Estado y objetivos (del juego, con tu progreso).
    local isComplete = call(C_QuestLog.IsComplete, questID)
    if isComplete then
        add("|cff40ff40¡Completada! Solo te falta entregarla.|r")
        add("")
    end
    local desc, summary = QuestTexts(questID)
    if (not summary or summary == "") and db then
        local texts = Get(db.Quest, questID, "objectivesText")
        if type(texts) == "table" and #texts > 0 then summary = table.concat(texts, " ") end
    end
    if summary and summary ~= "" then
        add("|cffffd200Qué hay que hacer|r")
        add(Shorten(summary, 400))
        add("")
    end
    local objectives = call(C_QuestLog.GetQuestObjectives, questID) or {}
    if #objectives > 0 then
        add("|cffffd200Tu progreso|r")
        for _, o in ipairs(objectives) do
            local color = o.finished and "|cff40ff40" or "|cffffffff"
            add(color .. "• " .. (o.text or "?") .. "|r")
        end
        add("")
    end

    -- Dónde (QuestieDB).
    if not db then
        add("|cffff9933No tengo los datos de Questie, así que no sé dónde están los objetivos.|r")
    elseif not isComplete then
        local where = {}
        local data = Get(db.Quest, questID, "objectives") or {}
        -- 1: criaturas, 2: objetos del mundo, 3: objetos, 5: muertes que cuentan
        for _, c in ipairs(data[1] or {}) do
            local spot = BestSpot(Get(db.Npc, c[1], "spawns"), preferZone)
            where[#where + 1] = { what = "Matar/hablar: " .. (Get(db.Npc, c[1], "name") or c[2] or "?"), spot = spot }
        end
        for _, o in ipairs(data[2] or {}) do
            local spot = BestSpot(Get(db.Object, o[1], "spawns"), preferZone)
            where[#where + 1] = { what = "Usar: " .. (Get(db.Object, o[1], "name") or o[2] or "?"), spot = spot }
        end
        for _, it in ipairs(data[3] or {}) do
            for _, w in ipairs(ItemSources(db, it[1], preferZone)) do where[#where + 1] = w end
        end
        for _, k in ipairs(data[5] or {}) do
            local npcID = k[2] or (type(k[1]) == "table" and k[1][1])
            if npcID then
                where[#where + 1] = { what = "Matar: " .. (Get(db.Npc, npcID, "name") or k[3] or "?"), spot = BestSpot(Get(db.Npc, npcID, "spawns"), preferZone) }
            end
        end
        local trigger = Get(db.Quest, questID, "triggerEnd")
        if type(trigger) == "table" then
            where[#where + 1] = { what = "Explorar: " .. (trigger[1] or "?"), spot = BestSpot(trigger[2], preferZone) }
        end

        add("|cffffd200Dónde hacerla|r")
        if #where == 0 then
            add("|cff9d9d9dNo tengo ubicaciones para los objetivos de esta misión.|r")
        end
        for _, w in ipairs(where) do
            add("• " .. w.what)
            add("    " .. SpotText(w.spot))
            if not info.objective and w.spot and w.spot.x then
                info.objective = { zone = w.spot.zone, x = w.spot.x, y = w.spot.y, title = title .. ": " .. w.what }
            end
        end
        add("")
    end

    -- Entrega.
    if db then
        add("|cffffd200Dónde entregarla|r")
        local finished = Get(db.Quest, questID, "finishedBy") or {}
        local any = false
        for _, npcID in ipairs(finished[1] or {}) do
            local spot = BestSpot(Get(db.Npc, npcID, "spawns"), preferZone)
            local name = Get(db.Npc, npcID, "name") or "?"
            local role = Get(db.Npc, npcID, "subName")
            add("• " .. name .. (role and (" |cff9d9d9d<" .. role .. ">|r") or ""))
            add("    " .. SpotText(spot))
            if not info.turnIn and spot and spot.x then
                info.turnIn = { zone = spot.zone, x = spot.x, y = spot.y, title = "Entregar: " .. title .. " (" .. name .. ")" }
            end
            any = true
        end
        for _, objID in ipairs(finished[2] or {}) do
            local spot = BestSpot(Get(db.Object, objID, "spawns"), preferZone)
            add("• " .. (Get(db.Object, objID, "name") or "?"))
            add("    " .. SpotText(spot))
            if not info.turnIn and spot and spot.x then
                info.turnIn = { zone = spot.zone, x = spot.x, y = spot.y, title = "Entregar: " .. title }
            end
            any = true
        end
        if not any then add("|cff9d9d9dNo sé quién la recibe.|r") end
        add("")
    end

    -- Recompensas (si ya se han leído los datos de la pestaña Importante).
    local rewards = ns.Important and ns.Important.RewardsOf(questID)
    if rewards and #rewards > 0 then
        add("|cffffd200Recompensas|r")
        for _, itemID in ipairs(rewards) do
            local _, link = call(C_Item.GetItemInfo, itemID)
            if not link then call(C_Item.RequestLoadItemDataByID, itemID) end
            add("• " .. (link or ItemName(db, itemID)))
        end
        add("")
    end

    -- Historia.
    local story = Shorten(desc, 500)
    if story then
        add("|cffffd200La historia|r")
        add("|cffd0d0d0" .. story .. "|r")
    end
    return info
end

Q.UiMapID = UiMapID
Q.BestSpot = BestSpot
Q.SpotText = SpotText
Q.DB = DB

-- ¿Se puede navegar hasta este destino?
function Q.CanGo(dest)
    return dest ~= nil and dest.x ~= nil and UiMapID(dest.zone) ~= nil
end

for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" }) do
    ns.On(event, function()
        if ns.UI and ns.UI.IsShowing("misiones") then ns.RequestRefresh() end
    end)
end
