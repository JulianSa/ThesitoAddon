-- Thesito Addon: talentos.
-- En Forever los talentos son un árbol moderno (C_Traits): un único árbol de
-- clase con tres grupos (Disciplina, Sagrado, Magia sombría). Leemos lo que
-- tienes del propio juego y lo comparamos con la ruta de Data.lua.

local _, ns = ...
local T = {}
ns.Talents = T

local call = ns.call

local function ConfigID()
    local id = C_ClassTalents and call(C_ClassTalents.GetActiveConfigID)
    if id then return id end
    if C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup then
        local group = call(C_SpecializationInfo.GetActiveSpecGroup)
        if group then return call(C_SpecializationInfo.GetCombatConfigIDForSpecGroup, group) end
    end
end

-- Lee tu árbol: { config, tree, nodes, bySpell, trees, spentTotal, unspent } o nil.
function T.Read()
    if not C_Traits then return nil end
    local config = ConfigID()
    if not config then return nil end
    local info = call(C_Traits.GetConfigInfo, config)
    local tree = info and info.treeIDs and info.treeIDs[1]
    if not tree then return nil end
    local ids = call(C_Traits.GetTreeNodes, tree)
    if type(ids) ~= "table" or #ids == 0 then return nil end

    local state = { config = config, tree = tree, nodes = {}, bySpell = {}, byName = {}, trees = {}, spentTotal = 0, unspent = 0 }

    for _, nodeID in ipairs(ids) do
        local n = call(C_Traits.GetNodeInfo, config, nodeID)
        if n and n.ID and n.ID ~= 0 then
            local entryID = (n.activeEntry and n.activeEntry.entryID) or (n.entryIDs and n.entryIDs[1])
            local entry = entryID and call(C_Traits.GetEntryInfo, config, entryID)
            local def = entry and entry.definitionID and call(C_Traits.GetDefinitionInfo, entry.definitionID)
            local rank = n.ranksPurchased
            if type(rank) ~= "number" then rank = n.currentRank or n.activeRank or 0 end
            local node = {
                id = nodeID,
                spell = def and def.spellID,
                icon = def and def.overrideIcon,
                rank = rank,
                max = n.maxRanks or 0,
                canBuy = n.canPurchaseRank,
                x = n.posX, y = n.posY,       -- posición en la ventana de talentos
                groups = n.groupIDs,          -- rama (Disciplina, Sagrado...)
                edges = n.visibleEdges,       -- flechas de requisito
            }
            state.nodes[nodeID] = node
            state.spentTotal = state.spentTotal + rank
            if node.spell then state.bySpell[node.spell] = node end
            local name = (def and def.overrideName ~= "" and def.overrideName) or ns.SpellName(node.spell)
            if type(name) == "string" then state.byName[name:lower()] = node end
        end
    end

    -- Puntos por rama, con el nombre que da el juego.
    local groups = call(C_Traits.GetGroupDisplayInfoByTreeID, tree)
    if type(groups) == "table" and #groups > 0 then
        local groupIDs = {}
        for _, g in ipairs(groups) do groupIDs[#groupIDs + 1] = g.groupID end
        local spent = {}
        for _, gi in ipairs(call(C_Traits.GetGroupCurrencyInfo, config, groupIDs) or {}) do
            local c = gi.currencyInfos and gi.currencyInfos[1]
            if c then spent[gi.traitNodeGroupID] = c.spent end
        end
        for _, g in ipairs(groups) do
            state.trees[#state.trees + 1] = { groupID = g.groupID, name = g.displayName or "?", order = g.orderIndex or 0, spent = spent[g.groupID] or 0 }
        end
        table.sort(state.trees, function(a, b) return a.order < b.order end)
    end

    -- Puntos sin gastar.
    for _, c in ipairs(call(C_Traits.GetTreeCurrencyInfo, config, tree, false) or {}) do
        if type(c.quantity) == "number" then state.unspent = state.unspent + c.quantity end
    end

    return state
end

-- El talento del árbol que corresponde a un paso: por ID y, si no está, por nombre.
local function Lookup(state, step)
    if not state then return nil end
    return (step.spell and state.bySpell[step.spell]) or (step.name and state.byName[step.name:lower()])
end

---------------------------------------------------------------------------
-- Rutas de tu clase
---------------------------------------------------------------------------

local FIRST_LEVEL = 10

function T.Routes()
    return ns.Routes[ns.class or ""] or {}
end

-- La ruta activa: la que elegiste con "Cambiar ruta" o, si no, la que más se
-- parece a los talentos que ya tienes.
function T.ActiveRoute(state)
    local routes = T.Routes()
    if #routes == 0 then return nil end
    for _, r in ipairs(routes) do
        if r.key == (ns.db and ns.db.routeKey) then return r end
    end
    local best, bestScore = routes[1], 0
    for _, r in ipairs(routes) do
        local score = 0
        for _, step in ipairs(r.steps) do
            local node = Lookup(state, step)
            if node then score = score + math.min(node.rank, step.rank) end
        end
        if score > bestScore then best, bestScore = r, score end
    end
    return best
end

function T.CycleRoute()
    local routes = T.Routes()
    if #routes < 2 then return end
    local current = T.ActiveRoute(T.Read())
    for i, r in ipairs(routes) do
        if r == current then
            local nextRoute = routes[i % #routes + 1]
            ns.db.routeKey = nextRoute.key
            ns.Print("ruta de talentos: " .. nextRoute.title)
            break
        end
    end
    ns.RequestRefresh()
end

-- Compara tu árbol con la ruta.
-- Cada paso: { spell, name, target, have, done, missing, isNext, from, to }
-- from/to = niveles en que te llegan los puntos que faltan (según tus puntos reales).
function T.Status(state, route)
    route = route or T.ActiveRoute(state)
    local s = { steps = {}, missing = 0, offPlan = {}, route = route }
    if not route then return s end
    local planned = {}
    local used = state and state.spentTotal or 0
    for i, step in ipairs(route.steps) do
        local node = Lookup(state, step)
        -- Si en el juego el talento tiene menos rangos que en la guía, mandan los del juego.
        local target = (node and node.max > 0) and math.min(step.rank, node.max) or step.rank
        local have = node and math.min(node.rank, target) or 0
        local row = { index = i, spell = (node and node.spell) or step.spell, name = step.name, target = target, node = node, have = have }
        row.done = node ~= nil and node.rank >= target
        if state and not node then
            row.missing = true
            s.missing = s.missing + 1
        end
        if not row.done and not row.missing then
            local left = target - have
            row.from = FIRST_LEVEL + used
            row.to = row.from + left - 1
            used = used + left
            if not s.next then
                s.next = row
                row.isNext = true
            end
        end
        if node then planned[node] = math.max(planned[node] or 0, target) end
        s.steps[i] = row
    end
    if state then
        for _, node in pairs(state.nodes) do
            local extra = node.rank - (planned[node] or 0)
            if extra > 0 and node.spell then
                s.offPlan[#s.offPlan + 1] = { spell = node.spell, node = node, extra = extra }
            end
        end
        table.sort(s.offPlan, function(a, b) return (ns.SpellName(a.spell) or "") < (ns.SpellName(b.spell) or "") end)
    end
    return s
end

-- Línea para el chat con el siguiente talento.
function T.NextLine()
    local state = T.Read()
    if not state then return nil end
    local s = T.Status(state)
    if not s.route then return nil end
    if not s.next then return "has completado la ruta." end
    local r = s.next
    local icon = ns.SpellIcon(r.spell)
    local text = ("%s|cffffffff%s|r (%d/%d)"):format(icon and ("|T" .. icon .. ":16|t ") or "", ns.SpellName(r.spell) or r.name or "?", r.have + 1, r.target)
    if state.unspent > 0 then
        text = text .. (" — tienes %d punto(s) sin gastar."):format(state.unspent)
    end
    return text
end

---------------------------------------------------------------------------
-- Brillo sobre el siguiente talento en la ventana de talentos del juego (N)
---------------------------------------------------------------------------

local glow
local hooked = false

local function TalentsFrame()
    return PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
end

local function MakeGlow(parent)
    local g = CreateFrame("Frame", nil, parent)
    g:EnableMouse(false)
    local tex = g:CreateTexture(nil, "OVERLAY")
    tex:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    tex:SetBlendMode("ADD")
    tex:SetVertexColor(1, 0.82, 0)
    tex:SetAllPoints()
    local label = g:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOM", g, "TOP", 0, -8)
    label:SetText("Siguiente")
    local anim = g:CreateAnimationGroup()
    anim:SetLooping("BOUNCE")
    local alpha = anim:CreateAnimation("Alpha")
    alpha:SetFromAlpha(1)
    alpha:SetToAlpha(0.3)
    alpha:SetDuration(0.7)
    g.anim = anim
    return g
end

function T.UpdateGlow(tries)
    local f = TalentsFrame()
    if not (ns.ready and f and f:IsShown()) then
        if glow then glow:Hide() end
        return
    end
    local s = T.Status(T.Read())
    local nodeID = s.next and s.next.node and s.next.node.id
    local button = nodeID and f.GetTalentButtonByNodeID and call(f.GetTalentButtonByNodeID, f, nodeID)
    if not button then
        if glow then glow:Hide() end
        -- La ventana coloca sus botones justo después de abrirse: reintentamos.
        tries = (tries or 0) + 1
        if nodeID and tries <= 10 then
            C_Timer.After(0.15, function() T.UpdateGlow(tries) end)
        end
        return
    end
    glow = glow or MakeGlow(f)
    glow:SetParent(f)
    glow:ClearAllPoints()
    local w, h = button:GetSize()
    glow:SetSize((w or 40) * 1.8, (h or 40) * 1.8)
    glow:SetPoint("CENTER", button, "CENTER")
    glow:SetFrameLevel((button:GetFrameLevel() or 1) + 10)
    glow:Show()
    glow.anim:Play()
end

local function Hook()
    local f = TalentsFrame()
    if hooked or not f then return end
    hooked = true
    f:HookScript("OnShow", function() T.UpdateGlow() end)
end

ns.On("ADDON_LOADED", function(name)
    if name == "Blizzard_PlayerSpells" then Hook() end
end)

ns.On("PLAYER_LOGIN", function()
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_PlayerSpells") then Hook() end
end)
