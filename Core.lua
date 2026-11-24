-- Thesito Addon: núcleo (eventos, guardado, comandos, botón del minimapa).

local ADDON, ns = ...

local PREFIX = "|cff9482c9Thesito Addon|r: "

function ns.Print(msg)
    print(PREFIX .. msg)
end

-- Llama a una función del juego sin romper nada si no existe o falla.
-- Devuelve todos sus resultados (o nada si falla).
local function results(ok, ...)
    if ok then return ... end
end

function ns.call(fn, ...)
    if type(fn) ~= "function" then return nil end
    return results(pcall(fn, ...))
end

function ns.SpellName(id)
    if not id then return nil end
    if C_Spell and C_Spell.GetSpellName then return (ns.call(C_Spell.GetSpellName, id)) end
    return (ns.call(GetSpellInfo, id))
end

function ns.SpellIcon(id)
    if not id then return nil end
    if C_Spell and C_Spell.GetSpellTexture then return (ns.call(C_Spell.GetSpellTexture, id)) end
    return (ns.call(GetSpellTexture, id))
end

-- Opciones: lo que se puede apagar en la pestaña Opciones (todo encendido
-- mientras no se diga lo contrario).
function ns.IsOn(key)
    return not (ns.db and ns.db.off and ns.db.off[key])
end

function ns.SetOn(key, on)
    if not ns.db then return end
    ns.db.off = ns.db.off or {}
    ns.db.off[key] = (not on) or nil
end

-- Dinero con los iconos de oro, plata y cobre.
local COIN = "|TInterface\\MoneyFrame\\UI-%sIcon:12:12:2:0|t"
function ns.Money(copper)
    copper = math.floor(tonumber(copper) or 0)
    local fn = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    if fn then
        local ok, text = pcall(fn, copper)
        if ok and type(text) == "string" and text ~= "" then return text end
    end
    local gold, silver, bronze = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. COIN:format("Gold") end
    if silver > 0 or gold > 0 then parts[#parts + 1] = silver .. COIN:format("Silver") end
    parts[#parts + 1] = bronze .. COIN:format("Copper")
    return table.concat(parts, " ")
end

---------------------------------------------------------------------------
-- Eventos
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
local handlers = {}

-- Registra una función para un evento. Si el evento no existe en este
-- cliente, se ignora en silencio.
function ns.On(event, fn)
    if not handlers[event] then
        if not pcall(events.RegisterEvent, events, event) then return false end
        handlers[event] = {}
    end
    table.insert(handlers[event], fn)
    return true
end

events:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event] or {}) do
        if securecallfunction then
            securecallfunction(fn, ...)
        else
            fn(...)
        end
    end
end)

-- Refresco agrupado: muchos eventos seguidos = un solo repintado.
local refreshPending = false
function ns.RequestRefresh()
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(0.15, function()
        refreshPending = false
        if ns.UI then ns.UI.Refresh() end
        if ns.Talents then ns.Talents.UpdateGlow() end
    end)
end

ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    ThesitoAddonDB = ThesitoAddonDB or {}
    ns.db = ThesitoAddonDB
    ns.db.trainer = ns.db.trainer or {}
    if ns.db.minimapAngle == nil then ns.db.minimapAngle = 200 end
end)

-- Tu clase: ns.class es el nombre en inglés (PRIEST, WARRIOR, PALADIN...),
-- ns.className el que ves en el juego.
ns.On("PLAYER_LOGIN", function()
    local className, class = UnitClass("player")
    ns.class, ns.className = class, className
    ns.ready = true
    ns.CreateMinimapButton()
    local extra = ""
    if not (ns.Routes[class] and ns.ClassAdvice[class]) then
        extra = (" (para %s aún no tengo ruta de talentos ni consejos de instructor; lo demás funciona)"):format(className or "tu clase")
    end
    ns.Print("listo. Botón del minimapa o /thesito para abrir la ventana." .. extra)
end)

for _, event in ipairs({
    "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB",
    "TRAIT_NODE_CHANGED", "TRAIT_CONFIG_UPDATED", "TRAIT_TREE_CURRENCY_INFO_UPDATED",
    "PLAYER_TALENT_UPDATE",
}) do
    ns.On(event, function()
        if ns.ready then ns.RequestRefresh() end
    end)
end

-- Al subir de nivel: qué talento poner y qué hay nuevo en el instructor.
ns.On("PLAYER_LEVEL_UP", function(level)
    if not (ns.ready and ns.IsOn("levelUp")) then return end
    C_Timer.After(2, function()
        ns.Print(("|cffffd200¡Nivel %d!|r"):format(level))
        if ns.IsOn("tab:talentos") then
            local talent = ns.Talents.NextLine()
            if talent then ns.Print("Talento: " .. talent) end
        end
        if ns.IsOn("tab:entrenador") then ns.Print(ns.Trainer.LevelUpLine(level)) end
        ns.RequestRefresh()
    end)
end)

---------------------------------------------------------------------------
-- Comandos y atajo de teclado
---------------------------------------------------------------------------

SLASH_THESITOADDON1 = "/thesito"
SLASH_THESITOADDON2 = "/thesitoaddon"
SlashCmdList.THESITOADDON = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "debug" then
        ns.Debug()
    elseif msg == "centrar" then
        ns.UI.ResetPosition()
    elseif msg == "talentos" then
        ns.UI.Open("talentos")
    elseif msg == "instructor" or msg == "entrenador" then
        ns.UI.Open("entrenador")
    elseif msg == "bolsas" then
        ns.UI.Open("bolsas")
    elseif msg == "misiones" then
        ns.UI.Open("misiones")
    elseif msg == "importante" then
        ns.UI.Open("importante")
    elseif msg == "creditos" or msg == "créditos" then
        ns.UI.Open("creditos")
    elseif msg == "opciones" or msg == "config" then
        ns.UI.Open("opciones")
    elseif msg == "rumbo" or msg == "quitar" then
        ns.Nav.Clear()
    elseif msg == "ordenar" then
        ns.Bags.Sort()
    elseif msg == "mochila" then
        ns.BagWindow.Toggle()
    elseif msg == "centrar bolsas" then
        ns.BagWindow.ResetPosition()
    else
        ns.UI.Toggle()
    end
end

BINDING_HEADER_THESITOADDON = "Thesito Addon"
BINDING_NAME_THESITOADDON_TOGGLE = "Abrir o cerrar la ventana"
function ThesitoAddon_Toggle()
    if ns.UI then ns.UI.Toggle() end
end

-- /thesito debug: datos para revisar si algo no cuadra. Se escriben en el
-- chat y se guardan también en ns.db.lastDebug (en el archivo de datos de
-- Thesito, que el juego escribe al hacer /reload o al salir), con más detalle.
function ns.Debug()
    local saved = {}
    local function Out(msg)
        ns.Print(msg)
        saved[#saved + 1] = msg
    end
    local state = ns.Talents.Read()
    if state then
        local nodes = 0
        for _ in pairs(state.nodes) do nodes = nodes + 1 end
        Out(("talentos: config %s, árbol %s, %d nodos, %d gastados, %d sin gastar."):format(
            tostring(state.config), tostring(state.tree), nodes, state.spentTotal, state.unspent))
        local s = ns.Talents.Status(state)
        Out(("ruta: %d pasos, %d no encontrados en tu árbol, %d talentos fuera de la ruta."):format(
            #s.steps, s.missing, #s.offPlan))
    else
        Out("talentos: no he podido leer el árbol todavía.")
    end
    local completed = C_QuestLog.GetAllCompletedQuestIDs and ns.call(C_QuestLog.GetAllCompletedQuestIDs)
    Out(("misiones: el juego dice que has completado %s."):format(completed and #completed or "?"))
    if ns.Bags and ns.Bags.ProfessionReport then
        Out("profesiones: " .. ns.Bags.ProfessionReport())
        local users = ns.Bags.ReagentUsers(11083) -- Polvo de alma
        local list = {}
        for skill in pairs(users or {}) do list[#list + 1] = tostring(skill) end
        Out(("materiales: %s. Polvo de alma lo usa: %s."):format(ns.Bags.reagentStatus,
            #list > 0 and table.concat(list, ", ") or "nadie"))
    end
    local count = 0
    for _ in pairs(ns.db.trainer) do count = count + 1 end
    Out(("instructor: %d hechizos guardados."):format(count))
    if ns.db.trainerRaw then Out("primer hechizo leído (crudo): " .. ns.db.trainerRaw) end
    -- Detalle que no se escribe en el chat (no cabría): solo se guarda.
    if ns.Bags and ns.Bags.DebugLines then
        for _, line in ipairs(ns.Bags.DebugLines()) do saved[#saved + 1] = line end
    end
    ns.db.lastDebug = { when = date and date("%Y-%m-%d %H:%M:%S") or "?", lines = saved }
    ns.Print("|cff9d9d9d(guardado con más detalle; haz /reload para que se escriba en el archivo)|r")
end

---------------------------------------------------------------------------
-- Botón del minimapa (arrástralo para moverlo alrededor del mapa)
---------------------------------------------------------------------------

local function PlaceMinimapButton(button)
    local angle = math.rad(ns.db.minimapAngle or 200)
    local radius = (Minimap:GetWidth() / 2) + 6
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function ns.CreateMinimapButton()
    if ns.minimapButton or not Minimap then return end
    local b = CreateFrame("Button", "ThesitoAddonMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("TOPLEFT", 7, -5)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetTexture("Interface\\Icons\\ClassIcon_" .. (ns.class or "Priest"):sub(1, 1) .. (ns.class or "Priest"):sub(2):lower())
    icon:SetPoint("TOPLEFT", 7, -6)

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    b:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            ns.UI.Open("entrenador")
        else
            ns.UI.Toggle()
        end
    end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            ns.db.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
            PlaceMinimapButton(self)
        end)
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Thesito Addon")
        GameTooltip:AddLine("Clic: abrir o cerrar", 1, 1, 1)
        GameTooltip:AddLine("Clic derecho: instructor", 1, 1, 1)
        GameTooltip:AddLine("Arrastra para moverlo", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)

    PlaceMinimapButton(b)
    if ns.db.hideMinimap then b:Hide() end
    ns.minimapButton = b
end
