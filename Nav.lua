-- Thesito Addon: cómo llegar.
-- Busca el camino más rápido combinando: a pie, vuelos entre los puntos de
-- vuelo que conoces y zepelines o barcos. Lo escribe paso a paso y lo dibuja
-- entero en el mapa del mundo (morado a pie, dorado en vuelo, azul en
-- zepelín o barco). La línea del minimapa y la flecha de TomTom apuntan al
-- SIGUIENTE paso; al llegar a él, aterrizar o cambiar de zona se vuelve a
-- calcular. Las posiciones se calculan con HereBeDragons (viene con TomTom).
-- Si tienes SendaFH con su navegación (SendaFH_Nav), los tramos a pie van
-- por los caminos y los pasos en vez de en línea recta (ver más abajo).

local _, ns = ...
local N = {}
ns.Nav = N

local call = ns.call
local LINE_COLOR = { 0.75, 0.45, 1, 0.9 } -- morado de las Sombras
local ROUTE_COLORS = {
    walk = { 0.75, 0.45, 1, 0.9 },  -- a pie
    fly  = { 1, 0.82, 0.2, 0.9 },   -- en vuelo
    ride = { 0.35, 0.8, 1, 0.9 },   -- zepelín o barco
}
local ARRIVED = 5      -- yardas: has llegado

-- Para comparar caminos (en segundos, aproximado).
local WALK_SPEED = 7     -- yardas por segundo corriendo
local MOUNT_SPEED = 11   -- con montura (desde el nivel 40)
local TERRAIN = 1.3      -- a pie no se va en línea recta
local FLY_SPEED = 30     -- vuelos
local FLY_DETOUR = 1.2   -- los vuelos dan algo de rodeo
local FLY_EXTRA = 30     -- hablar con el maestro, despegar y aterrizar
local RIDE_TIME = 240    -- esperar el zepelín o el barco y el viaje
local NEAR = 40          -- yardas: ya estás en esa parada

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
-- Zepelines y barcos (zona = área de Questie, x/y en %; posiciones
-- aproximadas). name = dónde está ese muelle o torre.
---------------------------------------------------------------------------

local TRANSPORTS = {
    { kind = "zepelín", faction = "Horde",
      a = { zone = 14, x = 50.8, y = 13.6, name = "Orgrimmar", label = "la torre del zepelín junto a Orgrimmar (Durotar)" },
      b = { zone = 85, x = 60.7, y = 58.8, name = "Entrañas", label = "la torre del zepelín de Claros de Tirisfal, junto a Entrañas" } },
    { kind = "zepelín", faction = "Horde",
      a = { zone = 14, x = 50.6, y = 12.7, name = "Orgrimmar", label = "la torre del zepelín junto a Orgrimmar (Durotar)" },
      b = { zone = 33, x = 31.6, y = 29.1, name = "Grom'gol", label = "la torre del zepelín del Campamento Grom'gol (Vega de Tuercespina)" } },
    { kind = "zepelín", faction = "Horde",
      a = { zone = 85, x = 61.9, y = 59.0, name = "Entrañas", label = "la torre del zepelín de Claros de Tirisfal, junto a Entrañas" },
      b = { zone = 33, x = 31.4, y = 30.2, name = "Grom'gol", label = "la torre del zepelín del Campamento Grom'gol (Vega de Tuercespina)" } },
    { kind = "barco",
      a = { zone = 17, x = 63.7, y = 38.6, name = "Trinquete", label = "el muelle de Trinquete (Los Baldíos)" },
      b = { zone = 33, x = 25.8, y = 73.1, name = "Bahía del Botín", label = "el muelle de Bahía del Botín (Vega de Tuercespina)" } },
    { kind = "barco", faction = "Alliance",
      a = { zone = 15, x = 71.6, y = 56.4, name = "Theramore", label = "el muelle de Theramore (Marjal Revolcafango)" },
      b = { zone = 11, x = 5.0, y = 63.4, name = "Menethil", label = "el puerto de Menethil (Los Humedales)" } },
    { kind = "barco", faction = "Alliance",
      a = { zone = 148, x = 32.4, y = 43.8, name = "Auberdine", label = "el muelle de Auberdine (Costa Oscura)" },
      b = { zone = 11, x = 4.6, y = 57.1, name = "Menethil", label = "el puerto de Menethil (Los Humedales)" } },
}

-- Posición en el mundo de un muelle o torre (se guarda al calcularla).
local function DockPos(side)
    if not side.wx then
        side.wx, side.wy, side.instance = WorldOf(side.zone, side.x, side.y)
    end
    return side.wx, side.wy, side.instance
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

local function FMText(fm)
    return ("%s (%s %.0f, %.0f)"):format(fm.name, ns.Quests.ZoneName(fm.zone), fm.x, fm.y)
end

---------------------------------------------------------------------------
-- Caminos a pie por donde se puede pasar (si tienes SendaFH)
-- SendaFH_Nav (parte de SendaFH, de Forever Hispano, GPL-3.0; su cálculo de
-- rutas parte del de Shortest Path Forever, de Cillian Berragan) trae mapas
-- del terreno de Forever y busca caminos a pie por los caminos, las puertas
-- y los pasos, sin subir montañas ni cruzar el mar. Thesito no lleva esos
-- mapas ni ese código: si SendaFH_Nav está instalado, le pide el camino de
-- cada tramo a pie (SendaFH_NavEngine.Find); si no, los tramos van en línea
-- recta como antes.
---------------------------------------------------------------------------

local WALK_STYLE = "roads"   -- prefiere los caminos y evita las cuestas
local STRAY = 40             -- yardas: si te apartas más del camino, se busca otro desde donde estés
local ASK_AGAIN = 3          -- segundos entre dos búsquedas del tramo en que estás
local FAIL_AGAIN = 20        -- segundos antes de volver a probar un tramo que no se encontró
local LOOK_AHEAD = 60        -- yardas: la flecha apunta a la curva del camino que hay a esta distancia
local engineTried = false
local walks = {}             -- tramos a pie ya pedidos (salvo el tuyo): [clave] = entrada

local function WalkEngine()
    if not ns.IsOn("walkPaths") then return nil end
    local P = _G.SendaFH_NavEngine
    if type(P) == "table" and type(P.Find) == "function" then return P end
    -- SendaFH lo carga cuando lo necesita; si aún no lo ha hecho, lo cargamos
    -- nosotros una vez (nunca en combate: son unos cuantos megas).
    if engineTried or (InCombatLockdown and InCombatLockdown()) then return nil end
    engineTried = true
    local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if load then pcall(load, "SendaFH_Nav") end
    P = _G.SendaFH_NavEngine
    if type(P) == "table" and type(P.Find) == "function" then return P end
    return nil
end

-- ¿Se pueden buscar caminos a pie en ese continente?
local function WalkReady(instance)
    local P = WalkEngine()
    if not (P and instance) then return false end
    if P.Available then return call(P.Available, instance) and true or false end
    return true
end

-- Pide el camino a pie de (ax, ay) a (bx, by). La respuesta llega unos
-- fotogramas después: entry.status pasa de "pending" a "ok" (con xs, ys: los
-- puntos del camino, en coordenadas de HereBeDragons) o a "fail".
local function AskWalk(instance, ax, ay, bx, by)
    local entry = { status = "fail", when = GetTime(), instance = instance, bx = bx, by = by }
    local P = WalkEngine()
    if not (P and WalkReady(instance)) then return entry end
    -- El motor usa las coordenadas de UnitPosition (x al norte, y al oeste):
    -- las de HereBeDragons al revés.
    local ok, job = pcall(P.Find, instance, { x = ay, y = ax }, { x = by, y = bx }, function(points, reason)
        if entry.cancelled then return end
        local raw = {}
        for _, p in ipairs(type(points) == "table" and points or {}) do
            if type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" then
                raw[#raw + 1] = p
            end
        end
        entry.when, entry.job = GetTime(), nil
        if #raw < 2 then
            entry.status, entry.reason = "fail", tostring(reason)
            return
        end
        -- Sin puntos casi repetidos (menos de 3 yardas), pero con el último.
        local xs, ys = { raw[1].y }, { raw[1].x }
        for i = 2, #raw do
            local x, y = raw[i].y, raw[i].x
            local n = #xs
            if i == #raw or Dist(xs[n], ys[n], x, y) >= 3 then
                xs[n + 1], ys[n + 1] = x, y
            end
        end
        entry.xs, entry.ys, entry.status, entry.previous = xs, ys, "ok", nil
        local yards = 0
        for i = 2, #xs do yards = yards + Dist(xs[i - 1], ys[i - 1], xs[i], ys[i]) end
        entry.yards = yards
    end, { profile = UnitFactionGroup("player"), style = WALK_STYLE })
    if ok then entry.status, entry.job = "pending", job end
    return entry
end

local function DropWalk(entry)
    if not entry then return end
    entry.cancelled = true
    local P = _G.SendaFH_NavEngine
    if entry.job and P and P.Cancel then pcall(P.Cancel, entry.job) end
    entry.job = nil
end

-- Al quitar o cambiar el rumbo: fuera las búsquedas pendientes.
local function ForgetWalks()
    for _, e in pairs(walks) do DropWalk(e) end
    walks = {}
    if target then
        DropWalk(target.here)
        target.here = nil
    end
end

-- El camino que se puede usar ya: el que ha llegado o, mientras llega el
-- nuevo, el anterior.
local function Usable(entry)
    if not (entry and ns.IsOn("walkPaths")) then return nil end
    if entry.status == "ok" then return entry end
    return entry.previous
end

-- Tu sitio en el camino: el tramo (entre los puntos i e i+1) y el punto más
-- cercano en él. Busca cerca de donde ibas, o en todo el camino si full.
local function Project(e, x, y, full)
    local xs, ys = e.xs, e.ys
    local first, last = 1, #xs - 1
    if not full and e.progress then
        first, last = math.max(1, e.progress - 3), math.min(#xs - 1, e.progress + 60)
    end
    local bestI, bestD, bestX, bestY = first, math.huge, xs[first], ys[first]
    for i = first, last do
        local ax, ay = xs[i], ys[i]
        local dx, dy = xs[i + 1] - ax, ys[i + 1] - ay
        local len2 = dx * dx + dy * dy
        local t = len2 > 0 and ((x - ax) * dx + (y - ay) * dy) / len2 or 0
        if t < 0 then t = 0 elseif t > 1 then t = 1 end
        local qx, qy = ax + dx * t, ay + dy * t
        local d = Dist(x, y, qx, qy)
        if d < bestD then bestI, bestD, bestX, bestY = i, d, qx, qy end
    end
    e.progress, e.qx, e.qy, e.off = bestI, bestX, bestY, bestD
    return bestD
end

-- Clave de un tramo a pie entre dos paradas (redondeada a 8 yardas).
local function WalkKey(instance, ax, ay, bx, by)
    local r = function(v) return math.floor(v / 8 + 0.5) end
    return ("%s:%d:%d:%d:%d"):format(tostring(instance), r(ax), r(ay), r(bx), r(by))
end

-- Pide (si hace falta) los caminos de todos los tramos a pie de la ruta: el
-- tuyo (de ti a la primera parada) se guarda en target.here y se vuelve a
-- pedir si te apartas de él; los demás, en walks.
local function UpdateWalks(px, py, pinst)
    local route = target and target.route
    if not (route and px and ns.IsOn("walkPaths")) then return end
    -- En vuelo o montado en el zepelín o el barco no se anda.
    if (UnitOnTaxi and UnitOnTaxi("player")) or (target.leg and target.leg.arrival) then return end
    local now = GetTime()
    for i, p in ipairs(route) do
        if p.how == "walk" and p.instance then
            if i == 1 then
                local e = target.here
                if e and (e.instance ~= p.instance or Dist(e.bx, e.by, p.wx, p.wy) > 5) then
                    DropWalk(e)
                    e, target.here = nil, nil
                end
                local ask = false
                if p.instance ~= pinst then
                    ask = false
                elseif not e then
                    ask = true
                elseif e.status == "ok" then
                    ask = Project(e, px, py, true) > STRAY and now - e.when >= ASK_AGAIN
                elseif e.status == "fail" then
                    ask = now - e.when >= FAIL_AGAIN
                end
                if ask and WalkReady(pinst) then
                    local fresh = AskWalk(pinst, px, py, p.wx, p.wy)
                    -- Mientras llega el nuevo, se sigue viendo el anterior.
                    fresh.previous = Usable(e)
                    DropWalk(e)
                    target.here = fresh
                end
            else
                local from = route[i - 1]
                if from.instance == p.instance then
                    local key = WalkKey(p.instance, from.wx, from.wy, p.wx, p.wy)
                    local e = walks[key]
                    if e and e.status == "fail" and now - e.when >= FAIL_AGAIN then e = nil end
                    if not e and WalkReady(p.instance) then
                        e = AskWalk(p.instance, from.wx, from.wy, p.wx, p.wy)
                        walks[key] = e
                    end
                    p.walk = e
                end
            end
        end
    end
    local first = route[1]
    if target.here and not (first and first.how == "walk") then
        DropWalk(target.here)
        target.here = nil
    end
end

-- Cuántos tramos a pie tienen ya su camino (para /thesito mapa).
local function WalkCounts()
    local ready, total = 0, 0
    for i, p in ipairs(target and target.route or {}) do
        if p.how == "walk" then
            total = total + 1
            if Usable(i == 1 and target.here or p.walk) then ready = ready + 1 end
        end
    end
    return ready, total
end

---------------------------------------------------------------------------
-- El plan: el camino más rápido y el siguiente paso
-- Paradas posibles: tú, el destino, los maestros de vuelo que conoces y los
-- muelles y torres de zepelín. Entre dos paradas del mismo continente se
-- puede ir a pie; entre dos maestros de vuelo, volando; entre los dos lados
-- de un zepelín o barco, en él. Gana el camino que tarda menos (Dijkstra).
---------------------------------------------------------------------------

-- Continentes donde has abierto algún mapa de vuelo (sabemos qué vuelos tienes).
local function TaxiContinents()
    local set = {}
    for _, k in ipairs(ns.db.taxi or {}) do set[k[3]] = true end
    return set
end

local function Stops(px, py, pinst)
    local stops = {
        { kind = "start", wx = px, wy = py, instance = pinst },
        { kind = "goal", wx = target.wx, wy = target.wy, instance = target.instance },
    }
    local recorded = TaxiContinents()
    for _, fm in ipairs(flightMasters or {}) do
        -- Si nunca has abierto un mapa de vuelo en ese continente, no sabemos
        -- cuáles tienes: los damos por buenos y lo avisamos.
        local assumed = not recorded[fm.instance]
        if assumed or KnownFlightMaster(fm) then
            stops[#stops + 1] = { kind = "fm", fm = fm, wx = fm.wx, wy = fm.wy, instance = fm.instance, assumed = assumed }
        end
    end
    local faction = UnitFactionGroup("player")
    for _, t in ipairs(TRANSPORTS) do
        if not t.faction or t.faction == faction then
            local ax, ay, ai = DockPos(t.a)
            local bx, by, bi = DockPos(t.b)
            if ax and bx then
                local a = { kind = "dock", t = t, side = t.a, wx = ax, wy = ay, instance = ai }
                local b = { kind = "dock", t = t, side = t.b, wx = bx, wy = by, instance = bi }
                a.pair, b.pair = b, a
                stops[#stops + 1] = a
                stops[#stops + 1] = b
            end
        end
    end
    return stops
end

-- Cuánto se tarda de una parada a otra y cómo (o nil si no se puede).
local function Leg(a, b, speed)
    if a.kind == "dock" and a.pair == b then return RIDE_TIME, "ride" end
    if a.instance ~= b.instance then return nil end
    local d = Dist(a.wx, a.wy, b.wx, b.wy)
    local cost, how = d * TERRAIN / speed, "walk"
    if a.kind == "fm" and b.kind == "fm" then
        local fly = d * FLY_DETOUR / FLY_SPEED + FLY_EXTRA
        if fly < cost then cost, how = fly, "fly" end
    end
    return cost, how
end

-- Camino más rápido de tu posición al destino: { { stop, how }, ... }, segundos.
local function BestPath(stops)
    local speed = (UnitLevel("player") or 1) >= 40 and MOUNT_SPEED or WALK_SPEED
    local n = #stops
    local time, prev, how, done = {}, {}, {}, {}
    for i = 1, n do time[i] = math.huge end
    time[1] = 0
    for _ = 1, n do
        local u, best = nil, math.huge
        for i = 1, n do
            if not done[i] and time[i] < best then u, best = i, time[i] end
        end
        if not u or u == 2 then break end
        done[u] = true
        for v = 2, n do
            if not done[v] then
                local cost, h = Leg(stops[u], stops[v], speed)
                if cost and best + cost < time[v] then time[v], prev[v], how[v] = best + cost, u, h end
            end
        end
    end
    if time[2] == math.huge then return nil end
    local path, i = {}, 2
    while i do
        table.insert(path, 1, { stop = stops[i], how = how[i] })
        i = prev[i]
    end
    return path, time[2]
end

-- arrival: es donde te deja el zepelín o el barco (vas montado en él).
local function StopPoint(stop, arrival)
    if stop.kind == "fm" then
        return { zone = stop.fm.zone, x = stop.fm.x, y = stop.fm.y, title = "Maestro de vuelo " .. stop.fm.name }
    elseif stop.kind == "dock" then
        local title = arrival and ("Bajar del " .. stop.t.kind .. " en " .. stop.side.name)
            or (stop.t.kind .. " a " .. stop.pair.side.name)
        return { zone = stop.side.zone, x = stop.side.x, y = stop.side.y, title = title, arrival = arrival }
    end
end

-- Los pasos en palabras.
local function Describe(path, total)
    local steps, n, assumed = {}, 0, false
    local minutes = math.max(1, math.floor(total / 60 + 0.5))
    local function step(text)
        n = n + 1
        steps[#steps + 1] = ("%d. %s"):format(n, text)
    end
    if #path == 2 then
        local d = Dist(path[1].stop.wx, path[1].stop.wy, path[2].stop.wx, path[2].stop.wy)
        if WalkReady(path[2].stop.instance) then
            steps[1] = ("Ve a pie o en montura siguiendo la línea, que va por el camino: unas %d yardas en línea recta (unos %d min)."):format(math.floor(d), minutes)
        else
            steps[1] = ("Ve a pie o en montura: unas %d yardas en línea recta (unos %d min)."):format(math.floor(d), minutes)
            if d > 1500 then steps[2] = "Ve por los caminos: la línea va en línea recta y no esquiva montañas." end
        end
        return steps
    end
    steps[1] = ("Unos %d minutos de viaje:"):format(minutes)
    for i = 2, #path do
        local from, to, how = path[i - 1].stop, path[i].stop, path[i].how
        local nextHow = path[i + 1] and path[i + 1].how
        local d = Dist(from.wx, from.wy, to.wx, to.wy)
        if how == "walk" then
            if to.kind == "goal" then
                step(("Desde ahí, a pie hasta el destino (unas %d yardas)."):format(math.floor(d)))
                if d > 1500 and not WalkReady(to.instance) then
                    steps[#steps + 1] = "    Ve por los caminos: la línea va en línea recta."
                end
            elseif d > NEAR then
                if to.kind == "fm" and nextHow == "fly" then
                    step("Ve al maestro de vuelo " .. FMText(to.fm) .. ".")
                elseif to.kind == "dock" then
                    step(("Ve a %s y espera el %s a %s."):format(to.side.label, to.t.kind, to.pair.side.name))
                else
                    step("Ve a " .. (to.fm and FMText(to.fm) or "la siguiente parada") .. ".")
                end
            end
        elseif how == "fly" then
            local maybe = (from.assumed or to.assumed) and " (si ya tienes ese punto de vuelo)" or ""
            assumed = assumed or maybe ~= ""
            step("Vuela hasta " .. FMText(to.fm) .. maybe .. ".")
        elseif how == "ride" then
            step(("Sube al %s a %s y bájate en %s."):format(to.t.kind, to.side.name, to.side.label))
        end
    end
    if assumed then
        steps[#steps + 1] = "|cff9d9d9dNo sé qué vuelos tienes en este continente: abre una vez el mapa de vuelo en cualquier maestro de vuelo y lo apunto.|r"
    end
    return steps
end

-- Devuelve los pasos, el siguiente punto al que ir (o nil: el destino) y la
-- ruta para dibujarla { { wx, wy, instance, how }, ... }.
local function Plan()
    local hbd = HBD()
    local px, py, pinst
    if hbd then px, py, pinst = Player(hbd) end
    if not (px and target.wx) then
        return { "Sigue la flecha hacia el destino." }, nil, nil
    end
    local path, total = BestPath(Stops(px, py, pinst))
    if not path then
        return { ("El destino está en %s y no encuentro zepelín ni barco para llegar desde %s."):format(
            ContinentName(target.instance), ContinentName(pinst)) }, nil, nil
    end
    local route = {}
    for i = 2, #path do
        local s = path[i].stop
        route[#route + 1] = { wx = s.wx, wy = s.wy, instance = s.instance, how = path[i].how, stop = s.kind ~= "goal" }
    end
    -- Siguiente paso: la primera parada a la que aún no has llegado.
    local leg
    for i = 2, #path - 1 do
        local s = path[i].stop
        if not (s.instance == pinst and Dist(px, py, s.wx, s.wy) <= NEAR) then
            leg = StopPoint(s, path[i].how == "ride")
            break
        end
    end
    return Describe(path, total), leg, route
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

-- El mapa del continente (para poner la flecha en un punto del mundo).
local continentMaps = {}
local function ContinentMap(instance)
    if continentMaps[instance] == nil then
        local hbd = HBD()
        local kind = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
        local found = false
        for id, data in pairs(hbd and hbd.mapData or {}) do
            if data.instance == instance and data.mapType == kind then
                found = id
                break
            end
        end
        continentMaps[instance] = found
    end
    return continentMaps[instance] or nil
end

-- La flecha de TomTom en un punto del mundo (una curva del camino). Sin
-- mensajes: cambia a menudo mientras andas.
local function SetWaypointWorld(instance, wx, wy, title)
    local hbd = HBD()
    local map = ContinentMap(instance)
    if not (hbd and map and TomTom and TomTom.AddWaypoint) then return false end
    local x, y = call(hbd.GetZoneCoordinatesFromWorld, hbd, wx, wy, map)
    if not x then return false end
    -- Primero la nueva y luego fuera la vieja: si no se pudiera poner, la
    -- flecha sigue donde estaba.
    local old = target.uid
    local uid = call(TomTom.AddWaypoint, TomTom, map, x, y,
        { title = title, from = "Thesito Addon", crazy = true, persistent = false, silent = true })
    if not uid then return false end
    if old and TomTom.RemoveWaypoint then call(TomTom.RemoveWaypoint, TomTom, old) end
    target.uid = uid
    return true
end

-- Si el tramo en que estás tiene camino, la flecha apunta a la curva del
-- camino que hay unas LOOK_AHEAD yardas por delante (y no en línea recta a
-- la parada, por encima de la montaña). Cerca del final, a la parada.
local function FollowArrow()
    local e = target and Usable(target.here)
    local first = target and target.route and target.route[1]
    local onLeg = e and e.progress and first and target.lx and target.linst == e.instance
        and Dist(first.wx, first.wy, target.lx, target.ly) <= 5
    local want, j = nil, nil
    if onLeg then
        local xs, ys = e.xs, e.ys
        local along, lastX, lastY = 0, e.qx, e.qy
        for k = e.progress + 1, #xs do
            along = along + Dist(lastX, lastY, xs[k], ys[k])
            lastX, lastY = xs[k], ys[k]
            if along >= LOOK_AHEAD then
                j = k
                break
            end
        end
        if j and j < #xs then want = tostring(e) .. ":" .. j end
    end
    if want == target.arrowOn then return end
    local now = GetTime()
    if want and now - (target.arrowAt or 0) < 2 then return end
    local point = target.leg or target
    local title = target.leg and target.leg.title or target.title
    if want and SetWaypointWorld(e.instance, e.xs[j], e.ys[j], title .. " (por el camino)") then
        target.arrowOn, target.arrowAt = want, now
    elseif target.arrowOn then
        -- Sin camino o ya cerca: la flecha vuelve a la parada.
        SetWaypoint(point, title)
        target.arrowOn, target.arrowAt = nil, now
    end
end

local function SameLeg(a, b)
    if a == nil or b == nil then return a == b end
    return a.zone == b.zone and a.x == b.x and a.y == b.y
end

local ARRIVAL_NEAR = 200   -- yardas: el zepelín o el barco ya está llegando
local RIDE_WAIT = 480      -- segundos: como mucho esperamos esto (espera + viaje)

-- ¿Estás a menos de radius yardas del paso al que vas?
local function NearLeg(radius)
    local hbd = HBD()
    if not (hbd and target and target.leg and target.lx) then return false end
    local px, py, instance = Player(hbd)
    return px ~= nil and instance == target.linst and Dist(px, py, target.lx, target.ly) <= radius
end

-- Recalcula el camino. Si cambia el siguiente paso, mueve la línea y la
-- flecha y te lo cuenta (solo a ti, en tu ventana de chat).
function N.Replan()
    if not target then return end
    -- En pleno vuelo, o montado en el zepelín o el barco: esperamos a llegar.
    if UnitOnTaxi and UnitOnTaxi("player") then return end
    if target.leg and target.leg.arrival and GetTime() - (target.legSince or 0) < RIDE_WAIT
        and not NearLeg(ARRIVAL_NEAR) then
        return
    end
    local steps, leg, route = Plan()
    target.steps = steps
    target.route = route
    local hbd = HBD()
    if hbd then UpdateWalks(Player(hbd)) end
    if target.planned and SameLeg(leg, target.leg) then return end
    target.planned = true
    target.leg = leg
    target.legSince = GetTime()
    local point = leg or target
    target.lx, target.ly, target.linst = WorldOf(point.zone, point.x, point.y)
    SetWaypoint(point, leg and leg.title or target.title)
    target.arrowOn = nil
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

local miniLine, miniDot, mapHolder
local miniPath = {}   -- trozos del camino en el minimapa
-- Tramos (borde oscuro y color) y paradas de la ruta en el mapa del mundo.
local mapEdges, mapLines, mapDots = {}, {}, {}
-- Lo último que pasó al dibujar en el mapa del mundo (para /thesito mapa).
local mapState = {}
local mapErrorShown = false
-- Lo que hay dibujado en el mapa del mundo: si no cambia, solo se mueve el
-- trozo que sale de ti (los caminos tienen muchos puntos).
local drawnSig

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

local function HideMapRoute()
    for _, edge in ipairs(mapEdges) do edge:Hide() end
    for _, line in ipairs(mapLines) do line:Hide() end
    for _, dot in ipairs(mapDots) do dot:Hide() end
end

local function HideMiniPath(from)
    for i = from or 1, #miniPath do miniPath[i]:Hide() end
end

local function HideLines()
    if miniLine then miniLine:Hide() end
    if miniDot then miniDot:Hide() end
    HideMiniPath()
    HideMapRoute()
    drawnSig = nil
end

local function MiniPathLine(i)
    local line = miniPath[i]
    if not line then
        line = Minimap:CreateLine(nil, "OVERLAY")
        line:SetThickness(3)
        line:SetColorTexture(LINE_COLOR[1], LINE_COLOR[2], LINE_COLOR[3], LINE_COLOR[4])
        miniPath[i] = line
    end
    return line
end

-- Del segmento de a (dentro del círculo) a b (fuera): dónde corta el borde.
local function ClipToCircle(ax, ay, bx, by, r)
    local dx, dy = bx - ax, by - ay
    local A = dx * dx + dy * dy
    if A == 0 then return ax, ay end
    local B = 2 * (ax * dx + ay * dy)
    local C = ax * ax + ay * ay - r * r
    local disc = B * B - 4 * A * C
    if disc < 0 then return ax, ay end
    local t = (-B + math.sqrt(disc)) / (2 * A)
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    return ax + dx * t, ay + dy * t
end

local function UpdateMinimap(hbd)
    MakeMinimapParts()
    if not miniLine then return end
    local px, py, instance = Player(hbd)
    if not (px and target.lx) or instance ~= target.linst then
        miniLine:Hide()
        miniDot:Hide()
        HideMiniPath()
        return
    end
    local tdx, tdy = px - target.lx, py - target.ly
    if tdx * tdx + tdy * tdy < ARRIVED * ARRIVED then
        miniLine:Hide()
        miniDot:Hide()
        HideMiniPath()
        return
    end
    local s, c
    if GetCVar("rotateMinimap") == "1" then
        local facing = GetPlayerFacing and GetPlayerFacing()
        if not facing or (issecretvalue and issecretvalue(facing)) then
            miniLine:Hide()
            miniDot:Hide()
            HideMiniPath()
            return
        end
        s, c = math.sin(facing), math.cos(facing)
    end
    local radius = (C_Minimap and C_Minimap.GetViewRadius and call(C_Minimap.GetViewRadius)) or 200
    local half = Minimap:GetWidth() / 2
    local maxLen = half * 0.9
    -- Punto del mundo -> desplazamiento en el minimapa desde el centro (tú).
    local function Off(wx, wy)
        local dx, dy = px - wx, py - wy
        if s then dx, dy = dx * c - dy * s, dx * s + dy * c end
        return dx / radius * half, -dy / radius * half
    end

    -- Con camino: la línea va por él, curva a curva, hasta el borde.
    local e = Usable(target.here)
    local first = target.route and target.route[1]
    if e and e.qx and first and e.instance == instance and Dist(first.wx, first.wy, target.lx, target.ly) <= 5 then
        miniLine:Hide()
        local n, ax, ay = 0, 0, 0
        local inside = true
        local k = e.progress
        while inside and k <= #e.xs do
            local bx, by
            if k == e.progress then bx, by = Off(e.qx, e.qy) else bx, by = Off(e.xs[k], e.ys[k]) end
            if bx * bx + by * by > maxLen * maxLen then
                bx, by = ClipToCircle(ax, ay, bx, by, maxLen)
                inside = false
            end
            if bx ~= ax or by ~= ay then
                n = n + 1
                local line = MiniPathLine(n)
                line:SetStartPoint("CENTER", Minimap, ax, ay)
                line:SetEndPoint("CENTER", Minimap, bx, by)
                line:Show()
            end
            ax, ay = bx, by
            k = k + 1
        end
        HideMiniPath(n + 1)
        if inside then
            miniDot:ClearAllPoints()
            miniDot:SetPoint("CENTER", Minimap, "CENTER", ax, ay)
            miniDot:Show()
        else
            miniDot:Hide()
        end
        return
    end

    -- Sin camino: en línea recta a la parada.
    HideMiniPath()
    local ox, oy = Off(target.lx, target.ly)
    local len = math.sqrt(ox * ox + oy * oy)
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
    if not WorldMapFrame then return nil end
    if WorldMapFrame.GetCanvas then
        local canvas = call(WorldMapFrame.GetCanvas, WorldMapFrame)
        if canvas then return canvas end
    end
    return WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
end

-- Punto del mundo -> posición en el mapa que estás mirando (teniendo en
-- cuenta en qué continente está; así funciona también el mapa de Azeroth).
local function OnMap(hbd, x, y, instance, mapID)
    if hbd.GetZoneCoordinatesFromWorldInstance then
        return call(hbd.GetZoneCoordinatesFromWorldInstance, hbd, x, y, instance, mapID, true)
    end
    return call(hbd.GetZoneCoordinatesFromWorld, hbd, x, y, mapID, true)
end

-- En el mapa del mundo los tramos son texturas normales deformadas (se
-- mueven sus cuatro esquinas), no objetos «línea»: así es como dibuja
-- Questie sus rutas en el mapa de Forever, y las líneas no se veían.
local WHITE = "Interface\\Buttons\\WHITE8x8"
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local function MapTexture(pool, i, layer, sublevel, file)
    local tex = pool[i]
    if not tex then
        tex = mapHolder:CreateTexture(nil, layer, nil, sublevel)
        tex:SetTexture(file)
        if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false) end
        if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
        pool[i] = tex
    end
    return tex
end

-- Un tramo de «width» unidades del mapa de ancho, de (x1, y1) a (x2, y2)
-- (unidades del mapa, y hacia abajo). La textura ocupa la caja del tramo y
-- sus esquinas se mueven a las del tramo inclinado.
local function DrawSegment(tex, x1, y1, x2, y2, width)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then
        tex:Hide()
        return false
    end
    local nx, ny = dy / len * width / 2, -dx / len * width / 2
    local slx, sly, srx, sry = x1 + nx, y1 + ny, x1 - nx, y1 - ny   -- inicio: izquierda, derecha
    local elx, ely, erx, ery = x2 + nx, y2 + ny, x2 - nx, y2 - ny   -- final: izquierda, derecha
    local minX, maxX = math.min(slx, srx, elx, erx), math.max(slx, srx, elx, erx)
    local minY, maxY = math.min(sly, sry, ely, ery), math.max(sly, sry, ely, ery)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", mapHolder, "TOPLEFT", minX, -minY)
    tex:SetPoint("BOTTOMRIGHT", mapHolder, "TOPLEFT", maxX, -maxY)
    tex:SetVertexOffset(UPPER_LEFT_VERTEX or 1, slx - minX, minY - sly)
    tex:SetVertexOffset(UPPER_RIGHT_VERTEX or 3, elx - maxX, minY - ely)
    tex:SetVertexOffset(LOWER_LEFT_VERTEX or 2, srx - minX, maxY - sry)
    tex:SetVertexOffset(LOWER_RIGHT_VERTEX or 4, erx - maxX, maxY - ery)
    tex:Show()
    return true
end

-- Nivel de la capa de la ruta. En Forever el lienzo del mapa dice estar a
-- nivel 3, pero el dibujo del mapa va mucho más arriba (hacia 2000): justo
-- encima del lienzo la ruta quedaba tapada. Como las rutas de Questie: 2015,
-- encima del dibujo y debajo de sus iconos; y si alguna capa del tamaño del
-- mapa va aún más alta, por encima de ella.
local MAP_ROUTE_LEVEL = 2015
local levelMap, levelAt, levelValue, levelTop

local function RouteLevel(canvas, mapID)
    local now = GetTime()
    if levelValue and levelMap == mapID and now < levelAt then return levelValue, levelTop end
    local cw, ch = canvas:GetWidth(), canvas:GetHeight()
    local top = 0
    for _, child in ipairs({ canvas:GetChildren() }) do
        if child ~= mapHolder and child:IsShown()
            and child:GetWidth() >= cw * 0.9 and child:GetHeight() >= ch * 0.9 then
            top = math.max(top, child:GetFrameLevel())
        end
    end
    levelMap, levelAt, levelTop = mapID, now + 2, top
    levelValue = math.min(math.max(canvas:GetFrameLevel() + 15, MAP_ROUTE_LEVEL, top + 1), 9000)
    return levelValue, levelTop
end

local function DrawDot(tex, x, y, size, r, g, b, a)
    tex:SetSize(size, size)
    tex:SetVertexColor(r, g, b, a)
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", mapHolder, "TOPLEFT", x, -y)
    tex:Show()
end

-- La ruta entera: de ti a cada parada y al destino, cada tramo de su color
-- (morado a pie, dorado en vuelo, azul en zepelín o barco) con un borde
-- oscuro, y un punto blanco en cada parada. Los tramos a pie que tienen
-- camino van por él, curva a curva. Los tramos de otro continente no salen
-- en este mapa.
local function UpdateWorldMap(hbd)
    local canvas = WorldCanvas()
    if not (canvas and WorldMapFrame:IsShown()) then
        HideMapRoute()
        drawnSig = nil
        return
    end
    if not mapHolder or mapHolder:GetParent() ~= canvas then
        mapHolder = mapHolder or CreateFrame("Frame", nil, canvas)
        mapHolder:SetParent(canvas)
        mapHolder:ClearAllPoints()
        mapHolder:SetAllPoints(canvas)
    end
    local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    if issecretvalue and mapID and issecretvalue(mapID) then mapID = nil end
    local level, top = RouteLevel(canvas, mapID)
    if mapHolder:GetFrameLevel() ~= level then mapHolder:SetFrameLevel(level) end
    mapHolder:Show()

    local px, py, instance = Player(hbd)
    local scale = canvas:GetScale() or 1
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    local s = mapState
    s.when, s.mapID, s.w, s.h, s.scale, s.top = GetTime(), mapID, w, h, scale, top
    s.canvasLevel, s.level, s.you, s.err = canvas:GetFrameLevel(), mapHolder:GetFrameLevel(), nil, nil
    s.route = target.route and #target.route or 0
    if not (mapID and px and target.wx) then
        HideMapRoute()
        drawnSig = nil
        s.segments, s.dots = 0, 0
        return
    end
    local route = target.route or { { wx = target.wx, wy = target.wy, instance = target.instance, how = "walk" } }
    local first = route[1]
    local here = Usable(target.here)
    if here and not (here.qx and first and first.how == "walk") then here = nil end

    -- Punto del mundo -> unidades del lienzo (nada si es de otro continente).
    local function At(wx, wy, inst)
        local mx, my = OnMap(hbd, wx, wy, inst, mapID)
        if mx then return mx * w, my * h end
    end
    local function Seg(n, ax, ay, bx, by, width, c)
        local edge = MapTexture(mapEdges, n, "ARTWORK", 0, WHITE)
        edge:SetVertexColor(0, 0, 0, 0.6)
        DrawSegment(edge, ax, ay, bx, by, width + 2 / scale)
        local line = MapTexture(mapLines, n, "OVERLAY", 0, WHITE)
        line:SetVertexColor(c[1], c[2], c[3], 1)
        DrawSegment(line, ax, ay, bx, by, width)
    end
    local function Polyline(n, e, from, width, c)
        local ax, ay = At(e.xs[from], e.ys[from], e.instance)
        for k = from + 1, #e.xs do
            local bx, by = At(e.xs[k], e.ys[k], e.instance)
            if ax and bx then
                n = n + 1
                Seg(n, ax, ay, bx, by, width, c)
            end
            ax, ay = bx, by
        end
        return n
    end

    -- Lo fijo (todo menos el trozo que sale de ti): solo cuando cambia algo.
    local parts = { mapID, math.floor(w), math.floor(h), math.floor(scale * 1000), tostring(route),
        tostring(here), here and here.progress or 0 }
    for _, p in ipairs(route) do parts[#parts + 1] = tostring(Usable(p.walk)) end
    local sig = table.concat(parts, "|")
    if sig ~= drawnSig then
        HideMapRoute()
        drawnSig = sig
        local n, dots = 2, 0   -- los trozos 1 y 2 son los que salen de ti (abajo)
        for i, p in ipairs(route) do
            local c = ROUTE_COLORS[p.how] or ROUTE_COLORS.walk
            local width = (i == 1 and 4 or 3) / scale
            local e = (i > 1 and p.how == "walk") and Usable(p.walk) or nil
            if i == 1 then
                if here then n = Polyline(n, here, here.progress + 1, width, c) end
            elseif e then
                n = Polyline(n, e, 1, width, c)
            else
                local prev = route[i - 1]
                local ax, ay = At(prev.wx, prev.wy, prev.instance)
                local bx, by = At(p.wx, p.wy, p.instance)
                if ax and bx then
                    n = n + 1
                    Seg(n, ax, ay, bx, by, width, c)
                end
            end
            if p.stop then
                local bx, by = At(p.wx, p.wy, p.instance)
                if bx then
                    dots = dots + 1
                    local size = 10 / scale
                    DrawDot(MapTexture(mapDots, dots * 2 - 1, "OVERLAY", 6, DISC), bx, by, size + 3 / scale, 0, 0, 0, 0.8)
                    DrawDot(MapTexture(mapDots, dots * 2, "OVERLAY", 7, DISC), bx, by, size, 1, 1, 1, 1)
                end
            end
        end
        s.segments, s.dots = n - 2, dots
    end

    -- Lo que se mueve contigo: de ti al camino y a su siguiente curva, o
    -- (sin camino) de ti a la primera parada en línea recta.
    local drawn = 0
    local ax, ay = At(px, py, instance)
    if ax then s.you = ("%.2f, %.2f"):format(ax / w, ay / h) end
    if ax and first then
        local c = ROUTE_COLORS[first.how] or ROUTE_COLORS.walk
        local width = 4 / scale
        if here then
            local qx, qy = At(here.qx, here.qy, here.instance)
            local nx, ny = At(here.xs[here.progress + 1], here.ys[here.progress + 1], here.instance)
            if qx then
                drawn = 1
                Seg(1, ax, ay, qx, qy, width, c)
                if nx then
                    drawn = 2
                    Seg(2, qx, qy, nx, ny, width, c)
                end
            end
        else
            local bx, by = At(first.wx, first.wy, first.instance)
            if bx then
                drawn = 1
                Seg(1, ax, ay, bx, by, width, c)
            end
        end
    end
    for k = drawn + 1, 2 do
        if mapEdges[k] then mapEdges[k]:Hide() end
        if mapLines[k] then mapLines[k]:Hide() end
    end
    s.moving = drawn
    s.shown = (mapLines[1] and mapLines[1]:IsVisible()) or (mapLines[3] and mapLines[3]:IsVisible()) or false
end

-- /thesito mapa: qué pasó la última vez que se dibujó la ruta en el mapa.
function N.MapReport()
    if not target then return "no tienes ningún rumbo puesto." end
    local s = mapState
    if not s.when then return "abre el mapa (M) con el rumbo puesto y vuelve a escribir /thesito mapa." end
    local ready, total = WalkCounts()
    local engine = _G.SendaFH_NavEngine and "sí" or (ns.IsOn("walkPaths") and "no está" or "apagado en Opciones")
    local here = target.here
    return ("hace %d s: mapa %s, lienzo %dx%d, escala %.2f, nivel %s/%s/%s; tú en %s; %d paradas, %d tramos y %d puntos dibujados%s; caminos a pie %d de %d (SendaFH_Nav: %s%s)%s."):format(
        GetTime() - s.when, tostring(s.mapID), s.w or 0, s.h or 0, s.scale or 0,
        tostring(s.canvasLevel), tostring(s.top), tostring(s.level), s.you or "otro mapa",
        s.route or 0, (s.segments or 0) + (s.moving or 0), s.dots or 0,
        ((s.segments or 0) + (s.moving or 0)) > 0 and (s.shown and ", visibles" or ", NO visibles") or "",
        ready, total, engine,
        here and ("; el tuyo: " .. tostring(here.status) .. (here.reason and (" " .. here.reason) or "")) or "",
        s.err and (" | error: " .. s.err) or "")
end

-- ¿Has llegado a la parada a la que ibas? Entonces toca el siguiente paso.
local function ReachedLeg()
    return target.leg ~= nil and NearLeg(target.leg.arrival and ARRIVAL_NEAR or NEAR)
end

local ticker = CreateFrame("Frame")
local elapsedSince, sinceCheck = 0, 0
ticker:Hide()
ticker:SetScript("OnUpdate", function(_, elapsed)
    elapsedSince = elapsedSince + elapsed
    if elapsedSince < 0.05 then return end
    sinceCheck = sinceCheck + elapsedSince
    elapsedSince = 0
    local hbd = HBD()
    if not (target and hbd) then
        HideLines()
        return
    end
    if sinceCheck >= 1 then
        sinceCheck = 0
        if ReachedLeg() then N.Replan() end
        if not target then return end
        -- Caminos a pie: pedir los que falten (o otro si te has apartado) y
        -- llevar la flecha por el camino.
        pcall(UpdateWalks, Player(hbd))
        pcall(FollowArrow)
    end
    -- Tu sitio en el camino del tramo en que estás.
    local here = Usable(target.here)
    if here then
        local px, py, pinst = Player(hbd)
        if px and pinst == here.instance then pcall(Project, here, px, py) end
    end
    pcall(UpdateMinimap, hbd)
    -- Si el mapa grande falla, que no se lleve por delante lo demás: se
    -- apunta el error para /thesito mapa y se avisa una sola vez.
    local ok, err = pcall(UpdateWorldMap, hbd)
    if not ok then
        mapState.err = tostring(err)
        pcall(HideMapRoute)
        if not mapErrorShown then
            mapErrorShown = true
            ns.Print("no he podido dibujar la ruta en el mapa grande; escribe /thesito mapa para ver por qué.")
        end
    end
end)

---------------------------------------------------------------------------
-- Poner y quitar el destino
---------------------------------------------------------------------------

function N.Clear(silent)
    RemoveWaypoint()
    ForgetWalks()
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
