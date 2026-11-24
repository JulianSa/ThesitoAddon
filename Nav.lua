-- Thesito Addon: cómo llegar.
-- Planifica el camino por etapas: zepelín o barco si el destino está en otro
-- continente, vuelo si está lejos y conoces los puntos de vuelo, y a pie el
-- resto. La línea morada (mapa del mundo y minimapa) y la flecha de TomTom
-- apuntan siempre al SIGUIENTE paso; al aterrizar o cambiar de continente se
-- vuelve a calcular. Las posiciones se calculan con HereBeDragons (viene con
-- TomTom), igual que los marcadores de TomTom.

local _, ns = ...
local N = {}
ns.Nav = N

local call = ns.call
local LINE_COLOR = { 0.75, 0.45, 1, 0.9 } -- morado de las Sombras
local FAR = 1200       -- yardas: a partir de aquí miramos si compensa volar
local FLY_RATIO = 0.6  -- volar compensa si lo que andas es menos del 60 % del camino directo
local ARRIVED = 5      -- yardas: has llegado

-- Destino activo:
-- { zone, x, y, title, questID, kind,      el destino (zona de Questie, x/y en %)
--   wx, wy, instance,                       el destino en coordenadas del mundo
--   leg, lx, ly, linst, steps, uid }        el paso actual, sus coordenadas, los consejos y la flecha
local target

local function HBD()
    return LibStub and LibStub("HereBeDragons-2.0", true)
end

function N.Target() return target end

local function Dist(ax, ay, bx, by)
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

-- Zona de Questie + x/y en % -> coordenadas del mundo (x, y, continente).
local function WorldOf(zone, x, y)
    local hbd = HBD()
    local map = ns.Quests.UiMapID(zone)
    if not (hbd and map and x and y) then return nil end
    return call(hbd.GetWorldCoordinatesFromZone, hbd, x / 100, y / 100, map)
end

-- Tu posición en coordenadas del mundo (nada en mazmorras).
local function Player(hbd)
    local x, y, instance = call(hbd.GetPlayerWorldPosition, hbd)
    if not x or (issecretvalue and (issecretvalue(x) or issecretvalue(y))) then return nil end
    return x, y, instance
end

local CONTINENTS = { [0] = "los Reinos del Este", [1] = "Kalimdor" }
local function ContinentName(instance) return CONTINENTS[instance] or "otra parte del mundo" end

---------------------------------------------------------------------------
-- Zepelines y barcos entre continentes (zona = área de Questie, x/y en %)
---------------------------------------------------------------------------

local TRANSPORTS = {
    { name = "zepelín Orgrimmar - Entrañas", faction = "Horde",
      a = { zone = 14, x = 50.8, y = 13.6, label = "la torre del zepelín junto a Orgrimmar (Durotar)" },
      b = { zone = 85, x = 60.7, y = 58.8, label = "la torre del zepelín de Claros de Tirisfal, junto a Entrañas" } },
    { name = "zepelín Orgrimmar - Grom'gol", faction = "Horde",
      a = { zone = 14, x = 50.6, y = 12.7, label = "la torre del zepelín junto a Orgrimmar (Durotar)" },
      b = { zone = 33, x = 31.6, y = 29.1, label = "el Campamento Grom'gol (Vega de Tuercespina)" } },
    { name = "barco Trinquete - Bahía del Botín",
      a = { zone = 17, x = 63.7, y = 38.6, label = "el muelle de Trinquete (Los Baldíos)" },
      b = { zone = 33, x = 25.8, y = 73.1, label = "el muelle de Bahía del Botín (Vega de Tuercespina)" } },
    { name = "barco Theramore - Menethil", faction = "Alliance",
      a = { zone = 15, x = 71.6, y = 56.4, label = "el muelle de Theramore (Marjal Revolcafango)" },
      b = { zone = 11, x = 5.0, y = 63.4, label = "el puerto de Menethil (Los Humedales)" } },
    { name = "barco Auberdine - Menethil", faction = "Alliance",
      a = { zone = 148, x = 32.4, y = 43.8, label = "el muelle de Auberdine (Costa Oscura)" },
      b = { zone = 11, x = 4.6, y = 57.1, label = "el puerto de Menethil (Los Humedales)" } },
}

local function BestTransport(px, py, pinst)
    local faction = UnitFactionGroup("player")
    local best
    for _, t in ipairs(TRANSPORTS) do
        if not t.faction or t.faction == faction then
            for _, dir in ipairs({ { t.a, t.b }, { t.b, t.a } }) do
                local from, to = dir[1], dir[2]
                local fx, fy, fi = WorldOf(from.zone, from.x, from.y)
                local tx, ty, ti = WorldOf(to.zone, to.x, to.y)
                if fx and tx and fi == pinst and ti == target.instance then
                    local cost = Dist(px, py, fx, fy) + Dist(tx, ty, target.wx, target.wy)
                    if not best or cost < best.cost then
                        best = { t = t, from = from, to = to, cost = cost, fx = fx, fy = fy }
                    end
                end
            end
        end
    end
    return best
end

---------------------------------------------------------------------------
-- Maestros de vuelo (de QuestieDB) y los puntos de vuelo que conoces
---------------------------------------------------------------------------

local flightMasters      -- { { name, zone, x, y, wx, wy, instance }, ... }
local tailorTrainers     -- igual, instructores de Sastrería
local fmStatus = "idle"  -- idle | loading | ready

local function LoadFlightMasters()
    if fmStatus ~= "idle" then return end
    local db = ns.Quests.DB()
    local flag = db and db.Enum and db.Enum.npcFlags and db.Enum.npcFlags.FLIGHT_MASTER
    if not (flag and HBD()) then return end
    fmStatus = "loading"
    local faction = UnitFactionGroup("player") == "Alliance" and "A" or "H"
    local list, trainers = {}, {}

    -- Un PNJ amistoso con su posición, o nil.
    local function Entry(id)
        local friendly = db.Npc.Get(id, "friendlyToFaction")
        if not (type(friendly) == "string" and friendly:find(faction, 1, true)) then return nil end
        local spot = ns.Quests.BestSpot(db.Npc.Get(id, "spawns"))
        if not (spot and spot.x) then return nil end
        local wx, wy, instance = WorldOf(spot.zone, spot.x, spot.y)
        if not wx then return nil end
        return { name = db.Npc.Get(id, "name") or "?", zone = spot.zone, x = spot.x, y = spot.y, wx = wx, wy = wy, instance = instance }
    end

    local work = coroutine.create(function()
        for i, id in ipairs(db.Npc.GetAllIds()) do
            local flags = db.Npc.Get(id, "npcFlags")
            if type(flags) == "number" and bit.band(flags, flag) ~= 0 then
                list[#list + 1] = Entry(id)
            end
            local sub = db.Npc.Get(id, "subName")
            if type(sub) == "string" then
                local low = sub:lower()
                if (low:find("tailor", 1, true) and low:find("trainer", 1, true))
                    or (low:find("sastr", 1, true) and low:find("instructor", 1, true)) then
                    trainers[#trainers + 1] = Entry(id)
                end
            end
            if i % 500 == 0 then coroutine.yield() end
        end
    end)
    local ticker
    ticker = C_Timer.NewTicker(0.01, function()
        local ok, err = coroutine.resume(work)
        if not ok or coroutine.status(work) == "dead" then
            ticker:Cancel()
            fmStatus = "ready"
            flightMasters, tailorTrainers = list, trainers
            if not ok then
                geterrorhandler()(err)
            elseif target then
                N.Replan()
            end
        end
    end)
end

-- Al abrir un mapa de vuelo apuntamos los puntos que conoces.
local function RecordTaxi()
    local hbd = HBD()
    local mapID = GetTaxiMapID and call(GetTaxiMapID)
    if not (hbd and mapID and ns.db) then return end
    ns.db.taxi = ns.db.taxi or {}
    local function add(x, y)
        local wx, wy, instance = call(hbd.GetWorldCoordinatesFromZone, hbd, x, y, mapID)
        if not wx then return end
        for _, k in ipairs(ns.db.taxi) do
            if k[3] == instance and Dist(k[1], k[2], wx, wy) < 60 then return end
        end
        ns.db.taxi[#ns.db.taxi + 1] = { wx, wy, instance }
    end
    if C_TaxiMap and C_TaxiMap.GetAllTaxiNodes then
        local unreachable = Enum and Enum.FlightPathState and Enum.FlightPathState.Unreachable
        for _, node in ipairs(call(C_TaxiMap.GetAllTaxiNodes, mapID) or {}) do
            if node.position and node.state ~= unreachable then add(node.position.x, node.position.y) end
        end
    elseif NumTaxiNodes then
        for i = 1, (call(NumTaxiNodes) or 0) do
            local kind = call(TaxiNodeGetType, i)
            if kind == "CURRENT" or kind == "REACHABLE" then add(call(TaxiNodePosition, i)) end
        end
    end
end

local function KnownFlightMaster(fm)
    for _, k in ipairs(ns.db.taxi or {}) do
        if k[3] == fm.instance and Dist(k[1], k[2], fm.wx, fm.wy) < 100 then return true end
    end
    return false
end

local function FlightAdvice(px, py, pinst, tx, ty)
    if not flightMasters then return nil end
    local direct = Dist(px, py, tx, ty)
    if direct < FAR then return nil end
    local useKnown = ns.db.taxi and #ns.db.taxi > 0
    local fromFM, toFM, dFrom, dTo
    for _, fm in ipairs(flightMasters) do
        if fm.instance == pinst and (not useKnown or KnownFlightMaster(fm)) then
            local d1 = Dist(px, py, fm.wx, fm.wy)
            if not fromFM or d1 < dFrom then fromFM, dFrom = fm, d1 end
            local d2 = Dist(fm.wx, fm.wy, tx, ty)
            if not toFM or d2 < dTo then toFM, dTo = fm, d2 end
        end
    end
    if not (fromFM and toFM) or fromFM == toFM then return nil end
    if dFrom + dTo > direct * FLY_RATIO then return nil end
    return { from = fromFM, to = toFM, direct = direct, known = useKnown }
end

local function FMText(fm)
    return ("%s (%s %.0f, %.0f)"):format(fm.name, ns.Quests.ZoneName(fm.zone), fm.x, fm.y)
end

---------------------------------------------------------------------------
-- El plan: consejos y siguiente paso
---------------------------------------------------------------------------

local function Plan()
    local hbd = HBD()
    local px, py, pinst
    if hbd then px, py, pinst = Player(hbd) end
    if not (px and target.wx) then
        return { "Sigue la flecha hacia el destino." }, nil
    end

    -- Otro continente: zepelín o barco.
    if pinst ~= target.instance then
        local best = BestTransport(px, py, pinst)
        if not best then
            return { ("El destino está en %s: necesitas un barco o un zepelín para llegar."):format(ContinentName(target.instance)) }, nil
        end
        local steps = { ("El destino está en %s y tú estás en %s."):format(ContinentName(target.instance), ContinentName(pinst)) }
        local n, leg = 1, nil
        local fly = FlightAdvice(px, py, pinst, best.fx, best.fy)
        if fly then
            steps[#steps + 1] = ("%d. Vuela desde %s hasta %s."):format(n, FMText(fly.from), FMText(fly.to))
            n = n + 1
            leg = { zone = fly.from.zone, x = fly.from.x, y = fly.from.y, title = "Maestro de vuelo " .. fly.from.name }
        else
            leg = { zone = best.from.zone, x = best.from.x, y = best.from.y, title = best.t.name }
        end
        steps[#steps + 1] = ("%d. Coge el %s en %s."):format(n, best.t.name, best.from.label)
        steps[#steps + 1] = ("%d. Bájate en %s y desde allí te vuelvo a guiar."):format(n + 1, best.to.label)
        return steps, leg
    end

    -- Mismo continente y lejos: ¿volar?
    local fly = FlightAdvice(px, py, pinst, target.wx, target.wy)
    if fly then
        return {
            ("Está lejos (unas %d yardas en línea recta)."):format(math.floor(fly.direct)),
            ("1. Ve al maestro de vuelo %s."):format(FMText(fly.from)),
            ("2. Vuela hasta %s%s."):format(FMText(fly.to), fly.known and "" or " (si ya conoces ese punto de vuelo)"),
            "3. Al aterrizar, la línea te lleva al destino.",
        }, { zone = fly.from.zone, x = fly.from.x, y = fly.from.y, title = "Maestro de vuelo " .. fly.from.name }
    end

    return { "Sigue la línea: puedes ir andando o en montura." }, nil
end

local function RemoveWaypoint()
    if target and target.uid and TomTom and TomTom.RemoveWaypoint then
        call(TomTom.RemoveWaypoint, TomTom, target.uid)
    end
    if target then target.uid = nil end
end

local function SetWaypoint(point, title)
    RemoveWaypoint()
    local map = ns.Quests.UiMapID(point.zone)
    if not map then return end
    if TomTom and TomTom.AddWaypoint then
        target.uid = call(TomTom.AddWaypoint, TomTom, map, point.x / 100, point.y / 100,
            { title = title, from = "Thesito Addon", crazy = true, persistent = false })
    elseif C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        call(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(map, point.x / 100, point.y / 100))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            call(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
        end
    end
end

local function SameLeg(a, b)
    if a == nil or b == nil then return a == b end
    return a.zone == b.zone and a.x == b.x and a.y == b.y
end

-- Recalcula el camino. Si cambia el siguiente paso, mueve la línea y la
-- flecha y te lo cuenta en el chat.
function N.Replan()
    if not target then return end
    local steps, leg = Plan()
    target.steps = steps
    if target.planned and SameLeg(leg, target.leg) then return end
    target.planned = true
    target.leg = leg
    local point = leg or target
    target.lx, target.ly, target.linst = WorldOf(point.zone, point.x, point.y)
    SetWaypoint(point, leg and leg.title or target.title)
    ns.Print("rumbo a " .. target.title .. ":")
    for _, s in ipairs(steps) do ns.Print("   " .. s) end
    ns.RequestRefresh()
end

-- Líneas para la ficha de la misión.
function N.RouteLines(questID)
    if not (target and target.steps and (target.questID == questID or target.forQuest == questID)) then return nil end
    local lines = { "|cffc080ffCómo llegar|r  |cff9d9d9d(" .. target.title .. ")|r" }
    for _, s in ipairs(target.steps) do lines[#lines + 1] = s end
    return lines
end

---------------------------------------------------------------------------
-- Líneas en el minimapa y en el mapa del mundo
---------------------------------------------------------------------------

local miniLine, miniDot, mapHolder, mapLine, mapLine2

local function MakeMinimapParts()
    if miniLine or not Minimap then return end
    miniLine = Minimap:CreateLine(nil, "OVERLAY")
    miniLine:SetThickness(3)
    miniLine:SetColorTexture(LINE_COLOR[1], LINE_COLOR[2], LINE_COLOR[3], LINE_COLOR[4])
    miniLine:Hide()
    miniDot = Minimap:CreateTexture(nil, "OVERLAY")
    miniDot:SetSize(8, 8)
    miniDot:SetColorTexture(LINE_COLOR[1], LINE_COLOR[2], LINE_COLOR[3], 1)
    miniDot:Hide()
end

local function HideLines()
    if miniLine then miniLine:Hide() end
    if miniDot then miniDot:Hide() end
    if mapLine then mapLine:Hide() end
    if mapLine2 then mapLine2:Hide() end
end

local function UpdateMinimap(hbd)
    MakeMinimapParts()
    if not miniLine then return end
    local px, py, instance = Player(hbd)
    if not (px and target.lx) or instance ~= target.linst then
        miniLine:Hide()
        miniDot:Hide()
        return
    end
    local dx, dy = px - target.lx, py - target.ly
    if dx * dx + dy * dy < ARRIVED * ARRIVED then
        miniLine:Hide()
        miniDot:Hide()
        return
    end
    if GetCVar("rotateMinimap") == "1" then
        local facing = GetPlayerFacing and GetPlayerFacing()
        if not facing or (issecretvalue and issecretvalue(facing)) then
            miniLine:Hide()
            miniDot:Hide()
            return
        end
        local s, c = math.sin(facing), math.cos(facing)
        dx, dy = dx * c - dy * s, dx * s + dy * c
    end
    local radius = (C_Minimap and C_Minimap.GetViewRadius and call(C_Minimap.GetViewRadius)) or 200
    local half = Minimap:GetWidth() / 2
    local ox, oy = dx / radius * half, -dy / radius * half
    local len = math.sqrt(ox * ox + oy * oy)
    local maxLen = half * 0.9
    local inside = len <= maxLen
    if not inside then ox, oy = ox / len * maxLen, oy / len * maxLen end
    miniLine:SetStartPoint("CENTER", Minimap, 0, 0)
    miniLine:SetEndPoint("CENTER", Minimap, ox, oy)
    miniLine:Show()
    if inside then
        miniDot:ClearAllPoints()
        miniDot:SetPoint("CENTER", Minimap, "CENTER", ox, oy)
        miniDot:Show()
    else
        miniDot:Hide()
    end
end

local function WorldCanvas()
    return WorldMapFrame and WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
end

-- Punto del mundo -> posición en el mapa que estás mirando (teniendo en
-- cuenta en qué continente está; así funciona también el mapa de Azeroth).
local function OnMap(hbd, x, y, instance, mapID)
    if hbd.GetZoneCoordinatesFromWorldInstance then
        return call(hbd.GetZoneCoordinatesFromWorldInstance, hbd, x, y, instance, mapID, true)
    end
    return call(hbd.GetZoneCoordinatesFromWorld, hbd, x, y, mapID, true)
end

local function DrawMapLine(line, canvas, ax, ay, bx, by, thickness)
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    line:SetThickness(thickness)
    line:SetStartPoint("TOPLEFT", canvas, ax * w, -ay * h)
    line:SetEndPoint("TOPLEFT", canvas, bx * w, -by * h)
    line:Show()
end

local function UpdateWorldMap(hbd)
    local canvas = WorldCanvas()
    if not (canvas and WorldMapFrame:IsShown()) then
        if mapLine then mapLine:Hide() end
        if mapLine2 then mapLine2:Hide() end
        return
    end
    if not mapHolder then
        mapHolder = CreateFrame("Frame", nil, canvas)
        mapHolder:SetAllPoints(canvas)
        mapHolder:SetFrameLevel(canvas:GetFrameLevel() + 2000)
        mapLine = mapHolder:CreateLine(nil, "OVERLAY")
        mapLine:SetColorTexture(LINE_COLOR[1], LINE_COLOR[2], LINE_COLOR[3], LINE_COLOR[4])
        mapLine2 = mapHolder:CreateLine(nil, "OVERLAY")
        mapLine2:SetColorTexture(LINE_COLOR[1], LINE_COLOR[2], LINE_COLOR[3], 0.35)
    end
    mapLine:Hide()
    mapLine2:Hide()
    local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    local px, py, instance = Player(hbd)
    if not (mapID and px and target.lx) then return end
    local scale = canvas:GetScale() or 1

    -- Tú -> siguiente paso (línea fuerte).
    local ax, ay = OnMap(hbd, px, py, instance, mapID)
    local bx, by = OnMap(hbd, target.lx, target.ly, target.linst, mapID)
    if ax and bx then DrawMapLine(mapLine, canvas, ax, ay, bx, by, math.max(2, 4 / scale)) end

    -- Siguiente paso -> destino final (línea suave), si hay escala por medio.
    if target.leg and target.wx then
        local cx, cy = OnMap(hbd, target.wx, target.wy, target.instance, mapID)
        if bx and cx then DrawMapLine(mapLine2, canvas, bx, by, cx, cy, math.max(1.5, 3 / scale)) end
    end
end

local ticker = CreateFrame("Frame")
local elapsedSince = 0
ticker:Hide()
ticker:SetScript("OnUpdate", function(_, elapsed)
    elapsedSince = elapsedSince + elapsed
    if elapsedSince < 0.05 then return end
    elapsedSince = 0
    local hbd = HBD()
    if not (target and hbd) then
        HideLines()
        return
    end
    UpdateMinimap(hbd)
    UpdateWorldMap(hbd)
end)

---------------------------------------------------------------------------
-- Poner y quitar el destino
---------------------------------------------------------------------------

function N.Clear(silent)
    RemoveWaypoint()
    target = nil
    HideLines()
    ticker:Hide()
    if not silent then ns.Print("rumbo quitado.") end
    ns.RequestRefresh()
end

-- dest = { zone (área de Questie), x, y (0-100), title, questID, kind }
function N.Go(dest)
    if not (dest and dest.x) then return false end
    if not ns.Quests.UiMapID(dest.zone) then
        ns.Print("no sé situar esa zona en el mapa.")
        return false
    end
    N.Clear(true)
    target = dest
    target.wx, target.wy, target.instance = WorldOf(dest.zone, dest.x, dest.y)
    LoadFlightMasters()
    ticker:Show()
    N.Replan()
    return true
end

-- Rumbo al instructor de Sastrería más cercano.
function N.GoTailorTrainer()
    if fmStatus ~= "ready" then
        LoadFlightMasters()
        ns.Print("todavía estoy buscando los instructores; prueba otra vez en unos segundos.")
        return
    end
    local hbd = HBD()
    local px, py, pinst
    if hbd then px, py, pinst = Player(hbd) end
    local best, bestDistance
    for _, t in ipairs(tailorTrainers or {}) do
        local d = (px and t.instance == pinst) and Dist(px, py, t.wx, t.wy) or math.huge
        if not best or d < bestDistance then best, bestDistance = t, d end
    end
    if not best then
        ns.Print("no encuentro instructores de Sastrería en la base de datos de Questie.")
        return
    end
    N.Go({ zone = best.zone, x = best.x, y = best.y, title = "Instructor de Sastrería " .. best.name })
end

---------------------------------------------------------------------------
-- Eventos
---------------------------------------------------------------------------

ns.On("TAXIMAP_OPENED", RecordTaxi)

-- Al aterrizar, cambiar de zona o de continente: recalcular.
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "PLAYER_CONTROL_GAINED" }) do
    ns.On(event, function()
        if target then C_Timer.After(1, N.Replan) end
    end)
end

-- Objetivos hechos -> rumbo a la entrega; entregada o abandonada -> fin.
ns.On("QUEST_LOG_UPDATE", function()
    if not (target and target.questID and target.kind == "objetivo") then return end
    if call(C_QuestLog.IsComplete, target.questID) then
        local detail = ns.Quests.Detail(target.questID)
        if detail.turnIn then
            ns.Print("¡objetivos completados! Te llevo a la entrega.")
            detail.turnIn.questID, detail.turnIn.kind = target.questID, "entrega"
            N.Go(detail.turnIn)
        end
    end
end)

ns.On("QUEST_TURNED_IN", function(questID)
    if target and target.questID == questID then N.Clear(true) end
end)

ns.On("QUEST_REMOVED", function(questID)
    if target and target.questID == questID then N.Clear(true) end
end)

-- Cargamos la lista de maestros de vuelo poco después de entrar.
ns.On("PLAYER_LOGIN", function()
    C_Timer.After(8, LoadFlightMasters)
end)
