-- Thesito Addon: la ventana (pestañas Talentos, Instructor, Bolsas, Misiones e Importante).

local _, ns = ...
local UI = {}
ns.UI = UI

local WIDTH, HEIGHT, ROW_H = 500, 620, 24
-- Alturas de cada zona (desde arriba de la ventana).
local TABS_Y = -66      -- pestañas
local HEADER_Y = -102   -- texto de cabecera y botones de la derecha
local NEXT_Y = -146     -- caja del siguiente talento
local LIST_TOP = -196   -- lista / árbol
local FOOTER_H = 40     -- barra inferior

local MINUS = "Interface\\Buttons\\UI-MinusButton-Up"
local PLUS = "Interface\\Buttons\\UI-PlusButton-Up"

local ADVICE = {
    esencial = { "|cff40ff40", "Esencial" },
    util = { "|cffffd200", "Útil" },
    saltar = { "|cff9d9d9d", "Saltar" },
    desconocido = { "|cff80c0ff", "Sin consejo" },
}
local ICON_OK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t"

local frame, scrollFrame, content, header, nextBox, showKnown, routeButton, viewButton
local subtitle, clearRoute
local detailScroll, detailChild, detailText
local tabButtons = {}
local questButtons = {}
local rows = {}
local tab = "talentos"
local selected = {} -- misión abierta en cada pestaña (misiones / importante)

---------------------------------------------------------------------------
-- Filas de la lista
---------------------------------------------------------------------------

local function ShowTooltip(self)
    if not (self.spell or self.tip or self.bag or self.itemID) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.bag then
        GameTooltip:SetBagItem(self.bag, self.slot)
    elseif self.itemID then
        GameTooltip:SetItemByID(self.itemID)
    elseif self.spell then
        GameTooltip:SetSpellByID(self.spell)
    else
        GameTooltip:SetText(self.tipTitle or "")
    end
    if self.tip then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(self.tip, 1, 0.82, 0, true)
    end
    GameTooltip:Show()
end

local function GetRow(i)
    if rows[i] then return rows[i] end
    local row = CreateFrame("Button", nil, content)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()

    -- Línea dorada bajo los títulos de sección.
    row.line = row:CreateTexture(nil, "ARTWORK")
    row.line:SetHeight(1)
    row.line:SetPoint("BOTTOMLEFT", 0, 0)
    row.line:SetPoint("BOTTOMRIGHT", 0, 0)
    row.line:SetColorTexture(1, 0.82, 0, 0.6)
    row.line:Hide()

    -- Barrita dorada a la izquierda de las filas normales.
    row.accent = row:CreateTexture(nil, "ARTWORK")
    row.accent:SetWidth(2)
    row.accent:SetPoint("TOPLEFT", 0, -2)
    row.accent:SetPoint("BOTTOMLEFT", 0, 2)
    row.accent:SetColorTexture(1, 0.82, 0, 0.7)
    row.accent:Hide()

    -- Botón ⊟/⊞ de las secciones desplegables.
    row.toggle = row:CreateTexture(nil, "OVERLAY")
    row.toggle:SetSize(16, 16)
    row.toggle:SetPoint("LEFT", 6, 0)
    row.toggle:Hide()

    row.level = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.level:SetPoint("LEFT", 4, 0)
    row.level:SetWidth(58)
    row.level:SetJustifyH("LEFT")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 64, 0)

    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.right:SetPoint("RIGHT", -6, 0)
    row.right:SetJustifyH("RIGHT")

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row:SetScript("OnEnter", ShowTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", function(self)
        if self.onClick then self.onClick() end
    end)
    rows[i] = row
    return row
end

-- Secciones plegadas (se recuerdan por personaje).
local function Collapsed(key)
    return key ~= nil and ns.db.collapsed ~= nil and ns.db.collapsed[key] == true
end

local function ToggleSection(key)
    ns.db.collapsed = ns.db.collapsed or {}
    ns.db.collapsed[key] = not ns.db.collapsed[key] or nil
    UI.Refresh()
end

-- Tipos de fila:
--   normal       icono, nombre y columna derecha
--   isHeader     título de sección: franja oscura, letra grande y línea dorada;
--                con key se puede plegar (⊟/⊞)
--   isNote       aviso: letra pequeña y gris, sangrado
--   spacer       hueco vacío antes de una sección
local function SetRow(i, d)
    local row = GetRow(i)
    local plain = not (d.isHeader or d.isNote or d.spacer)
    if d.isHeader and d.key then
        row.toggle:SetTexture(Collapsed(d.key) and PLUS or MINUS)
        row.toggle:Show()
        d.onClick = function() ToggleSection(d.key) end
        d.tip = d.tip or "Clic para plegar o desplegar esta sección."
    else
        row.toggle:Hide()
    end
    row.accent:SetShown(plain)
    row.level:SetText(plain and d.level or "")
    if plain and d.icon then
        row.icon:SetTexture(d.icon)
        row.icon:Show()
    else
        row.icon:Hide()
    end
    row.name:ClearAllPoints()
    if plain then
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    else
        row.name:SetPoint("LEFT", row, "LEFT", d.isNote and 24 or (d.key and 28 or 8), 0)
    end
    row.name:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
    row.name:SetFontObject(d.isHeader and "GameFontNormalLarge" or d.isNote and "GameFontDisableSmall" or "GameFontHighlight")
    row.name:SetText(d.spacer and "" or (d.name or ""))
    row.right:SetText(d.spacer and "" or (d.right or ""))
    -- Fondo: el que pida la fila, franja oscura en títulos o rayado suave.
    local c = d.bg or (d.isHeader and { 0, 0, 0, 0.45 }) or (plain and i % 2 == 0 and { 1, 1, 1, 0.03 }) or nil
    if c then
        row.bg:SetColorTexture(c[1], c[2], c[3], c[4])
    else
        row.bg:SetColorTexture(0, 0, 0, 0)
    end
    row.line:SetShown(d.isHeader == true)
    local highlight = row:GetHighlightTexture()
    if highlight then highlight:SetAlpha((plain or d.key) and 1 or 0) end
    row.spell, row.tip, row.tipTitle = d.spell, d.tip, d.tipTitle
    row.bag, row.slot = d.bag, d.slot
    row.itemID = d.itemID
    row.onClick = d.onClick
    row:Show()
end

local function LevelText(from, to)
    if not from then return "" end
    if from == to then return "Nv " .. from end
    return ("Nv %d-%d"):format(from, to)
end

---------------------------------------------------------------------------
-- Árbol de talentos dibujado como en el juego, con tu ruta encima
---------------------------------------------------------------------------

local treeFrame
local treeIcons, treeLines, treeHeaders = {}, {}, {}

local TREE_COLORS = {
    done = { 0.25, 1, 0.25 },     -- completado
    next = { 1, 0.82, 0 },        -- siguiente
    later = { 0.75, 0.45, 1 },    -- en la ruta, más adelante
    extra = { 1, 0.55, 0.15 },    -- tienes puntos pero no está en la ruta
    none = { 0.22, 0.22, 0.22 },  -- la ruta no lo usa
}

local function TreeIcon(i)
    if treeIcons[i] then return treeIcons[i] end
    local b = CreateFrame("Button", nil, treeFrame)
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.rank = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.rank:SetPoint("BOTTOMRIGHT", 3, -3)
    b.when = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.when:SetPoint("TOPLEFT", -3, 4)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.spell then GameTooltip:SetSpellByID(self.spell) end
        if self.tip then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(self.tip, 1, 0.82, 0, true)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    treeIcons[i] = b
    return b
end

-- Distancia entre columnas (o filas) vecinas, para convertir posiciones en
-- casillas. Los talentos de una misma columna no siempre tienen exactamente
-- la misma posición, así que primero juntamos los valores casi iguales.
local function GridStep(values)
    table.sort(values)
    local range = (values[#values] or 0) - (values[1] or 0)
    if range <= 0 then return 1 end
    local tolerance = range / 12
    local centers = {}
    local groupStart, sum, count = values[1], 0, 0
    for _, v in ipairs(values) do
        if v - groupStart > tolerance then
            centers[#centers + 1] = sum / count
            groupStart, sum, count = v, 0, 0
        end
        sum, count = sum + v, count + 1
    end
    centers[#centers + 1] = sum / count
    local step = math.huge
    for k = 2, #centers do step = math.min(step, centers[k] - centers[k - 1]) end
    return step ~= math.huge and step or range
end

-- Dibuja los árboles. Devuelve false si el juego no da las posiciones.
local function DrawTree(state, s)
    for _, b in ipairs(treeIcons) do b:Hide() end
    for _, l in ipairs(treeLines) do l:Hide() end
    for _, h in ipairs(treeHeaders) do h:Hide() end
    if not (state and #state.trees > 0) then return false end

    -- Paso de la ruta de cada talento.
    local plan = {}
    for _, row in ipairs(s.steps) do
        if row.node and not plan[row.node] then plan[row.node] = row end
    end

    -- Talentos de cada rama.
    local treeOf, perTree, any = {}, {}, false
    for idx, t in ipairs(state.trees) do treeOf[t.groupID] = idx end
    for _, node in pairs(state.nodes) do
        if node.spell and type(node.x) == "number" and type(node.y) == "number" then
            for _, g in ipairs(node.groups or {}) do
                local t = treeOf[g]
                if t then
                    perTree[t] = perTree[t] or {}
                    table.insert(perTree[t], node)
                    any = true
                    break
                end
            end
        end
    end
    if not any then return false end

    local W, H = treeFrame:GetWidth(), treeFrame:GetHeight()
    if not W or W < 50 then W, H = WIDTH - 24, HEIGHT + LIST_TOP - FOOTER_H - 6 end
    local TOP = 24
    local areaW = W / #state.trees
    local pos = {}
    for t, tree in ipairs(state.trees) do
        local nodes = perTree[t] or {}
        local xs, ys = {}, {}
        local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
        for _, n in ipairs(nodes) do
            xs[#xs + 1], ys[#ys + 1] = n.x, n.y
            minX, maxX = math.min(minX, n.x), math.max(maxX, n.x)
            minY, maxY = math.min(minY, n.y), math.max(maxY, n.y)
        end
        local sx, sy = GridStep(xs), GridStep(ys)
        local cols = #nodes > 0 and math.floor((maxX - minX) / sx + 0.5) + 1 or 1
        local rowsN = #nodes > 0 and math.floor((maxY - minY) / sy + 0.5) + 1 or 1
        local cell = math.min(areaW / cols, (H - TOP) / rowsN)
        local size = math.min(30, cell * 0.72)
        local x0 = (t - 1) * areaW + (areaW - cols * cell) / 2

        local h = treeHeaders[t]
        if not h then
            h = treeFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            treeHeaders[t] = h
        end
        h:ClearAllPoints()
        h:SetPoint("TOP", treeFrame, "TOPLEFT", (t - 0.5) * areaW, -4)
        h:SetText(("%s |cffffffff%d|r"):format(tree.name, tree.spent))
        h:Show()

        for _, n in ipairs(nodes) do
            local col = math.floor((n.x - minX) / sx + 0.5)
            local row = math.floor((n.y - minY) / sy + 0.5)
            pos[n] = { x0 + (col + 0.5) * cell, TOP + (row + 0.5) * cell, size }
        end
    end

    -- Flechas de requisito (debajo de los iconos).
    local li = 0
    for n, p in pairs(pos) do
        for _, e in ipairs(n.edges or {}) do
            local target = e.targetNode and state.nodes[e.targetNode]
            local q = target and pos[target]
            if q then
                li = li + 1
                local l = treeLines[li]
                if not l then
                    l = treeFrame:CreateLine(nil, "BACKGROUND")
                    treeLines[li] = l
                end
                l:SetThickness(2)
                if e.isActive then l:SetColorTexture(1, 0.82, 0, 0.9) else l:SetColorTexture(0.5, 0.5, 0.5, 0.6) end
                l:SetStartPoint("TOPLEFT", treeFrame, p[1], -p[2])
                l:SetEndPoint("TOPLEFT", treeFrame, q[1], -q[2])
                l:Show()
            end
        end
    end

    -- Iconos con el estado de la ruta.
    local bi = 0
    for n, p in pairs(pos) do
        bi = bi + 1
        local b = TreeIcon(bi)
        b:SetSize(p[3], p[3])
        b:ClearAllPoints()
        b:SetPoint("CENTER", treeFrame, "TOPLEFT", p[1], -p[2])
        b.icon:SetTexture(n.icon or ns.SpellIcon(n.spell))
        b.spell = n.spell
        local r = plan[n]
        local kind, when, tip
        if r and r.done then
            kind, tip = "done", ("En tu ruta: completado (%d/%d)."):format(n.rank, r.target)
        elseif r and r.isNext then
            kind, when = "next", "»"
            tip = ("¡Es el siguiente! Ponle un punto (%d/%d)."):format(n.rank + 1, r.target)
        elseif r then
            kind, when = "later", r.from and tostring(r.from) or ""
            tip = ("En tu ruta: llévalo a %d/%d entre los niveles %d y %d."):format(r.target, n.max, r.from or 0, r.to or 0)
        elseif n.rank > 0 then
            kind, tip = "extra", ("No está en tu ruta: tienes %d punto(s)."):format(n.rank)
        else
            kind, tip = "none", "Tu ruta no usa este talento."
        end
        local c = TREE_COLORS[kind]
        b.border:SetColorTexture(c[1], c[2], c[3], 1)
        b.icon:SetDesaturated(kind == "none")
        b.icon:SetAlpha(kind == "none" and 0.6 or 1)
        b.rank:SetText((n.rank > 0 or r) and ("%d/%d"):format(n.rank, n.max) or "")
        b.when:SetText(when or "")
        b.tip = tip
        b:Show()
    end
    return true
end

---------------------------------------------------------------------------
-- Pestaña Talentos
---------------------------------------------------------------------------

local function FillTalents()
    nextBox:Show()
    showKnown:Hide()
    local state = ns.Talents.Read()
    local s = ns.Talents.Status(state)
    local level = UnitLevel("player") or 1

    if not s.route then
        nextBox:Hide()
        header:SetText(("Todavía no tengo ruta de talentos para %s.\n\n"
            .. "Las demás pestañas funcionan igual. Si quieres una ruta para esta clase, pídesela a quien te pasó el addon "
            .. "(se añade en Data.lua)."):format(ns.className or "tu clase"))
        return 0
    end
    if #ns.Talents.Routes() > 1 then routeButton:Show() end
    viewButton:SetText(ns.db.talentView == "lista" and "Ver árbol" or "Ver lista")
    viewButton:Show()
    header:SetPoint("RIGHT", frame, "RIGHT", -130, 0) -- deja sitio a los botones

    local lines = { "|cffffd200Ruta:|r " .. s.route.title }
    if state then
        local parts = {}
        for _, t in ipairs(state.trees) do parts[#parts + 1] = ("%s |cffffffff%d|r"):format(t.name, t.spent) end
        local text = "|cffffd200Tus puntos:|r " .. table.concat(parts, " · ")
        if state.unspent > 0 then text = text .. ("   |cff40ff40%d sin gastar|r"):format(state.unspent) end
        lines[#lines + 1] = text
        if s.missing > 0 then
            lines[#lines + 1] = ("|cffff6060%d talento(s) de la ruta no aparecen en tu árbol (escribe /thesito debug).|r"):format(s.missing)
        end
    else
        lines[#lines + 1] = "|cffff6060No puedo leer tus talentos todavía: abre una vez la ventana de talentos (N).|r"
    end
    header:SetText(table.concat(lines, "\n"))

    -- Caja grande con el siguiente talento.
    local r = s.next
    if state and r then
        nextBox.icon:SetTexture(ns.SpellIcon(r.spell))
        local when
        if state.unspent > 0 then
            when = "|cff40ff40¡Ya puedes ponerlo! Ábrelo con N: lo verás brillando.|r"
        elseif r.from and r.from > level then
            when = ("Te llega al nivel %d."):format(r.from)
        else
            when = "|cffff9933No tienes puntos libres: los tienes en otros talentos.|r"
        end
        nextBox.text:SetText(("Siguiente: |cffffffff%s|r (%d/%d)\n%s"):format(ns.SpellName(r.spell) or r.name or "?", r.have + 1, r.target, when))
        nextBox.spell = r.spell
    else
        nextBox.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
        nextBox.text:SetText(state and "¡Ruta completada!" or "Esperando tus datos de talentos…")
        nextBox.spell = nil
    end

    -- Vista de árbol (como la ventana del juego) o de lista.
    if ns.db.talentView ~= "lista" then
        scrollFrame:Hide()
        treeFrame:Show()
        if DrawTree(state, s) then return 0 end
        treeFrame:Hide() -- el juego no da posiciones: mostramos la lista
        scrollFrame:Show()
    end

    -- Lista de pasos.
    local i = 0
    for _, step in ipairs(s.steps) do
        i = i + 1
        local name = ns.SpellName(step.spell) or step.name or "?"
        local progress = ("%d/%d"):format(step.have, step.target)
        local d = { icon = ns.SpellIcon(step.spell), spell = step.spell }
        if step.missing then
            d.name = "|cff9d9d9d" .. name .. "|r"
            d.right = "|cffff6060no está en tu árbol|r"
        elseif step.done then
            d.level = ICON_OK
            d.name = "|cff9d9d9d" .. name .. "|r"
            d.right = "|cff9d9d9d" .. progress .. "|r"
        else
            d.level = state and LevelText(step.from, step.to) or ""
            d.name = name
            if step.isNext then
                d.right = "|cffffd200siguiente|r  " .. progress
                d.bg = { 1, 0.82, 0, 0.18 }
            elseif state and step.from <= level then
                d.right = "|cff40ff40ya|r  " .. progress
            else
                d.right = progress
            end
        end
        SetRow(i, d)
    end

    if #s.offPlan > 0 then
        i = i + 1
        SetRow(i, { spacer = true })
        i = i + 1
        SetRow(i, { name = "Otros talentos que tienes (no están en la ruta)", isHeader = true, key = "tal:extra" })
        for _, o in ipairs(Collapsed("tal:extra") and {} or s.offPlan) do
            i = i + 1
            SetRow(i, {
                icon = ns.SpellIcon(o.spell), spell = o.spell,
                name = "|cffff9933" .. (ns.SpellName(o.spell) or "?") .. "|r",
                right = ("%d punto(s)"):format(o.extra),
            })
        end
    end
    return i
end

---------------------------------------------------------------------------
-- Pestaña Instructor
---------------------------------------------------------------------------

local function FillTrainer()
    nextBox:Hide()
    showKnown:Show()
    showKnown:SetChecked(ns.db.showKnown and true or false)
    local level = UnitLevel("player") or 1
    local sum, list = ns.Trainer.Summary(level)

    if not sum then
        header:SetText("Todavía no conozco la lista de tu instructor.\n\n"
            .. "Ve al |cffffd200instructor de tu clase|r y háblale una vez. Guardaré todos sus hechizos, "
            .. "también los de niveles futuros si en su ventana tienes marcado el filtro «No disponible».")
        return 0
    end

    header:SetText(table.concat({
        ("|cffffd200Para tu nivel (%d) puedes aprender:|r"):format(level),
        ("%s%d esencial(es)|r %s      %s%d útil(es)|r %s"):format(
            ADVICE.esencial[1], sum.esencial[1], ns.Money(sum.esencial[2]),
            ADVICE.util[1], sum.util[1], ns.Money(sum.util[2])),
        ("%sSi te saltas los grises (%d) ahorras|r %s"):format(ADVICE.saltar[1], sum.saltar[1], ns.Money(sum.saltar[2])),
        ("|cff9d9d9dLista leída del instructor el %s. Pasa el ratón por un hechizo para ver el porqué.|r"):format(
            date("%d/%m a las %H:%M", ns.db.trainerScanned or 0)),
    }, "\n"))

    local i, lastLevel = 0, false
    for _, e in ipairs(list) do
        if ns.db.showKnown or not e.known then
            local key = "tr:" .. tostring(e.level)
            if e.level ~= lastLevel then
                lastLevel = e.level
                i = i + 1
                local text = ("Nivel %s"):format(e.level or "?")
                if e.level and e.level <= level then text = text .. "   |cff40ff40ya disponible|r" end
                SetRow(i, { name = text, isHeader = true, key = key })
            end
        end
        if (ns.db.showKnown or not e.known) and not Collapsed("tr:" .. tostring(e.level)) then
            i = i + 1
            local a = ADVICE[e.advice] or ADVICE.desconocido
            local rank = e.rank and (" |cff9d9d9d(" .. e.rank .. ")|r") or ""
            local name = e.known and ("|cff9d9d9d" .. e.name .. "|r" .. rank .. " " .. ICON_OK) or (e.name .. rank)
            local now = not e.known and e.level and e.level <= level
            SetRow(i, {
                icon = e.icon, spell = e.spell, name = name,
                right = ns.Money(e.cost) .. "   " .. a[1] .. a[2] .. "|r",
                tip = a[1] .. a[2] .. ":|r " .. (e.note or ""), tipTitle = e.name,
                bg = (now and e.advice == "esencial") and { 0.25, 1, 0.25, 0.12 } or nil,
            })
        end
    end
    if i == 0 then
        SetRow(1, { name = "|cff40ff40¡Tienes todo lo de la lista!|r", isNote = true })
        i = 1
    end
    return i
end

---------------------------------------------------------------------------
-- Pestaña Bolsas
---------------------------------------------------------------------------

local function QualityColor(q)
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    return (c and c.hex) or "|cffffffff"
end

local function FillBags()
    nextBox:Hide()
    showKnown:Hide()
    local list, sum = ns.Bags.Analyze()

    local sizes = {}
    for _, n in ipairs(sum.bags) do sizes[#sizes + 1] = tostring(n) end
    header:SetText(table.concat({
        ("|cffffd200Casillas:|r %d de %d ocupadas (%d libres)   |cffffd200Tus bolsas:|r %s"):format(
            sum.used, sum.total, sum.total - sum.used, table.concat(sizes, " · ")),
        ("|cffff6060Puedes liberar %d casilla(s)|r y sacar %s vendiendo lo rojo."):format(sum.freeSlots, ns.Money(sum.freeValue)),
        sum.withQuestie and "|cff9d9d9dUso los datos de Questie para saber de qué misión es cada objeto.|r"
            or "|cffff9933Questie no está cargado: lo de misiones es menos fiable.|r",
        "|cff9d9d9dPasa el ratón por un objeto para ver el porqué.|r",
    }, "\n"))

    local groups = {}
    for _, g in ipairs(ns.Bags.GROUPS) do groups[g.key] = g end

    local i, last = 0, nil
    for _, e in ipairs(list) do
        local g = groups[e.group]
        if e.group ~= last then
            last = e.group
            if i > 0 then
                i = i + 1
                SetRow(i, { spacer = true })
            end
            i = i + 1
            SetRow(i, { name = g.color .. g.title .. "|r", isHeader = true, key = "bag:" .. e.group })
        end
        if not Collapsed("bag:" .. e.group) then
        i = i + 1
        local name = QualityColor(e.quality) .. (e.name or ("Objeto " .. e.itemID)) .. "|r"
        if e.count > 1 then name = name .. " |cffffffffx" .. e.count .. "|r" end
        local right = (e.tag and e.tag ~= "") and (g.color .. e.tag .. "|r") or ""
        if e.value and e.value > 0 then right = right .. "  " .. ns.Money(e.value) end
        SetRow(i, {
            icon = e.icon, name = name, right = right, bag = e.bag, slot = e.slot,
            tip = (e.note and e.note ~= "") and e.note or nil,
        })
        end
    end
    if i == 0 then
        SetRow(1, { name = "Tus bolsas están vacías.", isNote = true })
        i = 1
    end
    return i
end

---------------------------------------------------------------------------
-- Pestaña Misiones
---------------------------------------------------------------------------

local function DifficultyColor(level)
    local c = level and GetQuestDifficultyColor and GetQuestDifficultyColor(level)
    if c and c.r then return ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255) end
    return "|cffffffff"
end

local lastDetail
local function ShowQuestDetail(questID)
    local d = ns.Quests.Detail(questID)
    header:Hide()
    scrollFrame:Hide()
    detailScroll:ClearAllPoints()
    detailScroll:SetPoint("TOPLEFT", 12, HEADER_Y - 30)
    detailScroll:SetPoint("BOTTOMRIGHT", -32, FOOTER_H + 6)
    detailScroll:Show()
    for _, b in pairs(questButtons) do b:Show() end
    detailText:SetText(table.concat(d.lines, "\n"))
    detailChild:SetHeight(detailText:GetStringHeight() + 20)
    if lastDetail ~= questID then
        detailScroll:SetVerticalScroll(0)
        lastDetail = questID
    end

    local function setup(button, dest, kind)
        if dest and ns.Quests.CanGo(dest) then
            dest.questID = dest.questID or questID -- (en una cadena, la primera misión)
            dest.forQuest, dest.kind = questID, kind
            button:Enable()
            button:SetScript("OnClick", function() ns.Nav.Go(dest) end)
        else
            button:Disable()
        end
    end
    setup(questButtons.starter, d.starter, "coger")
    setup(questButtons.objective, d.objective, "objetivo")
    setup(questButtons.turnIn, d.turnIn, "entrega")
    if ns.Nav.Target() then questButtons.clear:Enable() else questButtons.clear:Disable() end
end

local function FillQuests()
    nextBox:Hide()
    showKnown:Hide()
    if selected.misiones and not ns.Quests.InLog(selected.misiones) then selected.misiones = nil end
    if selected.misiones then
        ShowQuestDetail(selected.misiones)
        return 0
    end

    local list, count, complete = ns.Quests.List()
    local nav = ns.Nav.Target()
    local lines = {
        ("|cffffd200Tienes %d misiones|r (%d listas para entregar)."):format(count, complete),
        "Haz clic en una para ver qué hacer, dónde hacerla y dónde entregarla.",
    }
    if nav then lines[#lines + 1] = "|cffc080ffRumbo a:|r " .. nav.title end
    header:SetText(table.concat(lines, "\n"))

    local i, zoneKey = 0, nil
    for _, q in ipairs(list) do
        if q.header then
            zoneKey = "q:" .. q.header
            i = i + 1
            SetRow(i, { name = q.header, isHeader = true, key = zoneKey })
        elseif not Collapsed(zoneKey) then
            i = i + 1
            local right = ""
            if q.complete then
                right = "|cff40ff40¡entregar!|r"
            elseif q.total > 0 then
                right = ("%d/%d"):format(q.done, q.total)
            end
            if nav and nav.questID == q.questID then right = "|cffc080ff» rumbo|r  " .. right end
            local questID = q.questID
            SetRow(i, {
                level = q.level and (DifficultyColor(q.level) .. "[" .. q.level .. "]|r") or "",
                name = q.title or "?", right = right,
                bg = q.complete and { 0.25, 1, 0.25, 0.10 } or nil,
                tipTitle = q.title, tip = "Clic para ver qué hacer y dónde.",
                onClick = function()
                    selected.misiones = questID
                    UI.Refresh()
                end,
            })
        end
    end
    if i == 0 then
        SetRow(1, { name = "No tienes misiones en el registro.", isNote = true })
        i = 1
    end
    return i
end

---------------------------------------------------------------------------
-- Pestaña Importante
---------------------------------------------------------------------------

local function QuestStatus(info, level)
    if info.inLog then return "|cffffd200en tu registro|r" end
    if info.needs then return "|cffff9933antes otra|r" end
    if info.minLevel <= level then return "|cff40ff40disponible|r" end
    return ("|cff9d9d9ddesde nv %d|r"):format(info.minLevel)
end

local function QuestTip(info)
    local t = { ("Misión de nivel %d (se coge desde el nivel %d)."):format(info.level, info.minLevel) }
    local s = info.starter
    if s and s.isItem then
        t[#t + 1] = "La empieza un objeto: " .. s.name .. "."
    elseif s then
        t[#t + 1] = "La da: " .. s.name .. " — " .. ns.Quests.SpotText(s.spot)
    end
    if info.needs then t[#t + 1] = "|cffff9933Antes tienes que hacer «" .. info.needs .. "».|r" end
    if info.rewards and #info.rewards > 0 then t[#t + 1] = "Recompensas: " .. table.concat(info.rewards, ", ") .. "." end
    t[#t + 1] = "Clic: ver toda la información de la misión."
    return table.concat(t, "\n")
end

local function FillImportant()
    nextBox:Hide()
    showKnown:Hide()
    ns.Important.Start()
    local status, progress = ns.Important.Status()
    if status == "nodb" then
        header:SetText("|cffff6060Para esta sección necesito Questie (QuestieDB) activado.|r")
        return 0
    end
    if status ~= "ready" then
        header:SetText(("Preparando los datos de misiones… |cffffffff%d%%|r\n"
            .. "|cff9d9d9dSolo la primera vez que abres esta sección en cada sesión.|r"):format(math.floor(progress * 100)))
        return 0
    end

    local data = ns.Important.Lists()
    if not data then
        header:SetText("|cffff6060No he podido leer los datos de Questie.|r")
        return 0
    end
    if selected.importante then
        ShowQuestDetail(selected.importante)
        return 0
    end
    local level = data.me.level
    local lines = {
        ("|cffffd200Misiones que no te conviene saltarte|r (que ya puedes coger a nivel %d)"):format(level),
        "Haz clic en una para ver toda su información y ponerle rumbo.",
        "|cff9d9d9dSolo misiones de tu raza, clase y facción que no has completado.|r",
    }
    if data.later + data.hard > 0 then
        lines[#lines + 1] = ("|cff9d9d9dOcultas: %d porque aún no tienes nivel para cogerlas y %d por ser de más de 3 niveles por encima del tuyo.|r"):format(data.later, data.hard)
    end
    header:SetText(table.concat(lines, "\n"))

    local i = 0
    local function LevelTag(info)
        return (info.minLevel <= level and "|cff40ff40" or "|cff9d9d9d") .. "[" .. info.minLevel .. "]|r"
    end
    -- Título de sección plegable; devuelve true si está plegada.
    local function Header(title, key)
        if i > 0 then
            i = i + 1
            SetRow(i, { spacer = true })
        end
        i = i + 1
        SetRow(i, { name = title, isHeader = true, key = key })
        return Collapsed(key)
    end
    local function Note(text)
        i = i + 1
        SetRow(i, { name = text, isNote = true })
    end
    local function Section(title, key, list, empty, makeRow)
        if Header(title .. ("  |cff9d9d9d(%d)|r"):format(#list), key) then return end
        if #list == 0 then Note(empty) end
        for _, info in ipairs(list) do
            i = i + 1
            local d = makeRow(info)
            d.level = LevelTag(info)
            d.onClick = function()
                selected.importante = info.questID
                UI.Refresh()
            end
            SetRow(i, d)
        end
    end

    Section("|cff40e0d0Bolsas de más de 10 casillas|r", "imp:bolsas", data.bags, "Ninguna que puedas hacer ahora mismo.", function(info)
        return {
            icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(info.itemID), itemID = info.itemID,
            name = info.name, tip = QuestTip(info),
            right = ("|cff40e0d0%d casillas|r  %s"):format(info.slots, QuestStatus(info, level)),
        }
    end)
    -- Bolsas que puedes coser como Sastre (solo si este personaje es sastre).
    local tailor, why = ns.Tailor.Bags()
    local tailorFolded = false
    if tailor or why ~= "notailor" then
        tailorFolded = Header("|cff40ff40Bolsas que puedes coser (Sastrería" .. (tailor and (" " .. tailor.skill) or "") .. ")|r", "imp:sastre")
    end
    if tailorFolded then
        -- plegada: no se muestra nada más
    elseif not tailor then
        if why ~= "notailor" then Note(why or "?") end
    else
        for _, e in ipairs(tailor.list) do
            i = i + 1
            local name = ns.Tailor.ItemName(e.itemID)
            if e.slots then name = name .. (" |cff40e0d0(%d)|r"):format(e.slots) end
            SetRow(i, {
                level = (tailor.skill >= e.need and "|cff40ff40" or "|cff9d9d9d") .. "[" .. e.need .. "]|r",
                icon = e.icon, itemID = e.itemID, name = name,
                right = ns.Tailor.Status(e, tailor.skill),
                tip = ns.Tailor.Tip(e, tailor.skill),
                onClick = function() ns.Tailor.Go(e) end,
            })
        end
        if #tailor.list == 0 then Note("Ninguna bolsa de Sastrería mejora las tuyas a tu nivel.") end
        if tailor.hidden > 0 then
            Note(("Ocultas %d: no más grandes que tus bolsas o de mucho más nivel de Sastrería."):format(tailor.hidden))
        end
    end

    Section("|cffffffffMisiones de " .. (ns.className or "tu clase"):lower() .. "|r", "imp:clase", data.class, "No te queda ninguna de tu nivel o superior.", function(info)
        return { name = info.name, tipTitle = info.name, tip = QuestTip(info), right = QuestStatus(info, level) }
    end)
    local noGear = not (ns.ClassGear[ns.class or ""] and ns.ClassWeights[ns.class or ""])
    Section("|cffc080ffMejoras para tu equipo|r", "imp:equipo", data.upgrades,
        noGear and ("Todavía no tengo datos de equipo para %s (se añaden en Data.lua)."):format(ns.className or "tu clase")
            or "Ninguna recompensa cercana a tu nivel mejora lo que llevas.", function(info)
        local _, link = ns.call(C_Item.GetItemInfo, info.itemID)
        local slotName = ns.Important.SLOT_NAMES[info.slot] or "equipo"
        return {
            icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(info.itemID), itemID = info.itemID,
            name = (link or "?") .. " |cff9d9d9d(" .. info.name .. ")|r",
            right = ("|cffc080ff+%d|r %s  %s"):format(info.gain, slotName, QuestStatus(info, level)),
            tip = ("Recompensa de «%s». Mejora tu %s: de %d a %d puntos.\n%s"):format(
                info.name, slotName, info.before, info.after, QuestTip(info)),
        }
    end)
    return i
end

function UI.ShowQuest(questID)
    selected.misiones = questID
    UI.Open("misiones")
end

---------------------------------------------------------------------------
-- Ventana
---------------------------------------------------------------------------

local function SavePosition()
    local point, _, relPoint, x, y = frame:GetPoint(1)
    ns.db.pos = { point, relPoint, x, y }
end

local function ApplyPosition()
    frame:ClearAllPoints()
    local p = ns.db.pos
    if p then
        frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        frame:SetPoint("CENTER")
    end
end

local function Create()
    if frame then return end
    frame = CreateFrame("Frame", "ThesitoAddonFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    if frame.TitleText then frame.TitleText:SetText("Thesito Addon") end
    tinsert(UISpecialFrames, "ThesitoAddonFrame")
    frame:Hide()

    -- Cabecera: icono de tu clase, nombre del addon y tu personaje.
    local classIcon = frame:CreateTexture(nil, "ARTWORK")
    classIcon:SetSize(34, 34)
    classIcon:SetPoint("TOPLEFT", 14, -28)
    local cls = ns.class or "PRIEST"
    classIcon:SetTexture("Interface\\Icons\\ClassIcon_" .. cls:sub(1, 1) .. cls:sub(2):lower())
    local iconBorder = frame:CreateTexture(nil, "BORDER")
    iconBorder:SetPoint("TOPLEFT", classIcon, -2, 2)
    iconBorder:SetPoint("BOTTOMRIGHT", classIcon, 2, -2)
    iconBorder:SetColorTexture(1, 0.82, 0, 0.8)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", classIcon, "TOPRIGHT", 10, -1)
    title:SetText("Thesito Addon")
    subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)

    local credits = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    credits:SetSize(90, 22)
    credits:SetPoint("TOPRIGHT", -14, -32)
    credits:SetText("Créditos")
    credits:SetScript("OnClick", function() UI.Open("creditos") end)

    -- Pestañas (con el aspecto de pestaña del juego si está disponible).
    local prev
    for _, def in ipairs({ { "talentos", "Talentos" }, { "entrenador", "Instructor" }, { "bolsas", "Bolsas" },
        { "misiones", "Misiones" }, { "importante", "Importante" } }) do
        local ok, b = pcall(CreateFrame, "Button", nil, frame, "PanelTopTabButtonTemplate")
        if ok and b then
            b.isTab = true
            b:SetText(def[2])
            if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, b, 12, nil, 80) end
        else
            b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
            b:SetSize(88, 24)
            b:SetText(def[2])
        end
        if prev then
            b:SetPoint("LEFT", prev, "RIGHT", b.isTab and -4 or 4, 0)
        else
            b:SetPoint("TOPLEFT", 14, TABS_Y)
        end
        b:SetScript("OnClick", function()
            selected[def[1]] = nil
            UI.Open(def[1])
        end)
        tabButtons[def[1]] = b
        prev = b
    end
    local tabLine = frame:CreateTexture(nil, "ARTWORK")
    tabLine:SetHeight(1)
    tabLine:SetPoint("TOPLEFT", 10, TABS_Y - 28)
    tabLine:SetPoint("TOPRIGHT", -10, TABS_Y - 28)
    tabLine:SetColorTexture(1, 0.82, 0, 0.5)

    -- Botones del detalle de una misión.
    local function QuestButton(key, text, width, x, onClick)
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(width, 22)
        b:SetPoint("TOPLEFT", x, HEADER_Y)
        b:SetText(text)
        if onClick then b:SetScript("OnClick", onClick) end
        b:Hide()
        questButtons[key] = b
    end
    QuestButton("back", "‹ Volver", 70, 14, function()
        selected[tab] = nil
        UI.Refresh()
    end)
    QuestButton("starter", "Quien la da", 104, 88)
    QuestButton("objective", "Al objetivo", 104, 196)
    QuestButton("turnIn", "A la entrega", 104, 304)
    QuestButton("clear", "Quitar", 70, 412, function() ns.Nav.Clear() end)

    -- Texto del detalle (y de los créditos), con barra de desplazamiento.
    detailScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    detailScroll:SetPoint("TOPLEFT", 12, HEADER_Y - 30)
    detailScroll:SetPoint("BOTTOMRIGHT", -32, FOOTER_H + 6)
    detailChild = CreateFrame("Frame", nil, detailScroll)
    detailChild:SetSize(WIDTH - 46, 1)
    detailScroll:SetScrollChild(detailChild)
    detailText = detailChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    detailText:SetPoint("TOPLEFT", 4, -4)
    detailText:SetWidth(WIDTH - 60)
    detailText:SetJustifyH("LEFT")
    detailText:SetJustifyV("TOP")
    detailText:SetSpacing(2)
    detailScroll:Hide()

    -- Casilla "ver aprendidos" (solo en Instructor).
    showKnown = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    showKnown:SetSize(24, 24)
    showKnown:SetPoint("TOPRIGHT", -110, HEADER_Y + 2)
    local label = showKnown:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", showKnown, "RIGHT", 2, 0)
    label:SetText("Ver aprendidos")
    showKnown:SetScript("OnClick", function(self)
        ns.db.showKnown = self:GetChecked() and true or false
        UI.Refresh()
    end)

    -- Botón "Cambiar ruta" (solo en Talentos, si tu clase tiene varias).
    routeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    routeButton:SetSize(110, 22)
    routeButton:SetPoint("TOPRIGHT", -14, HEADER_Y + 2)
    routeButton:SetText("Cambiar ruta")
    routeButton:SetScript("OnClick", function() ns.Talents.CycleRoute() end)
    routeButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Rutas de talentos de tu clase")
        for _, r in ipairs(ns.Talents.Routes()) do GameTooltip:AddLine("• " .. r.title, 1, 1, 1) end
        GameTooltip:AddLine("Al principio se elige sola la que más se parece a tus talentos.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    routeButton:SetScript("OnLeave", GameTooltip_Hide)
    routeButton:Hide()

    -- Botón "Ver árbol / Ver lista" (solo en Talentos).
    viewButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    viewButton:SetSize(110, 20)
    viewButton:SetPoint("TOPRIGHT", -14, HEADER_Y - 20)
    viewButton:SetScript("OnClick", function()
        ns.db.talentView = (ns.db.talentView == "lista") and "arbol" or "lista"
        UI.Refresh()
    end)
    viewButton:Hide()

    -- Zona del árbol de talentos (ocupa el sitio de la lista).
    treeFrame = CreateFrame("Frame", nil, frame)
    treeFrame:SetPoint("TOPLEFT", 12, LIST_TOP)
    treeFrame:SetPoint("BOTTOMRIGHT", -12, FOOTER_H + 6)
    treeFrame:Hide()

    -- Texto de cabecera.
    header = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    header:SetPoint("TOPLEFT", 16, HEADER_Y)
    header:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    header:SetJustifyH("LEFT")
    header:SetJustifyV("TOP")
    header:SetSpacing(3)

    -- Caja del siguiente talento.
    nextBox = CreateFrame("Button", nil, frame)
    nextBox:SetHeight(44)
    nextBox:SetPoint("TOPLEFT", 14, NEXT_Y)
    nextBox:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
    nextBox.bg = nextBox:CreateTexture(nil, "BACKGROUND")
    nextBox.bg:SetAllPoints()
    nextBox.bg:SetColorTexture(0.58, 0.51, 0.79, 0.2)
    nextBox.icon = nextBox:CreateTexture(nil, "ARTWORK")
    nextBox.icon:SetSize(36, 36)
    nextBox.icon:SetPoint("LEFT", 4, 0)
    nextBox.text = nextBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nextBox.text:SetPoint("LEFT", nextBox.icon, "RIGHT", 8, 0)
    nextBox.text:SetPoint("RIGHT", -6, 0)
    nextBox.text:SetJustifyH("LEFT")
    nextBox:SetScript("OnEnter", ShowTooltip)
    nextBox:SetScript("OnLeave", GameTooltip_Hide)

    -- Lista con barra de desplazamiento.
    scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 12, LIST_TOP)
    scrollFrame:SetPoint("BOTTOMRIGHT", -32, FOOTER_H + 6)
    content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(WIDTH - 46, 1)
    scrollFrame:SetScrollChild(content)

    -- Barra inferior: opciones y botón de quitar el rumbo.
    local footerLine = frame:CreateTexture(nil, "ARTWORK")
    footerLine:SetHeight(1)
    footerLine:SetPoint("BOTTOMLEFT", 10, FOOTER_H)
    footerLine:SetPoint("BOTTOMRIGHT", -10, FOOTER_H)
    footerLine:SetColorTexture(1, 0.82, 0, 0.5)

    local function Option(text, x, get, set)
        local c = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        c:SetSize(24, 24)
        c:SetPoint("BOTTOMLEFT", x, 8)
        local label = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", c, "RIGHT", 2, 0)
        label:SetText(text)
        c:SetScript("OnShow", function(self) self:SetChecked(get()) end)
        c:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
        return c
    end
    Option("Botón del minimapa", 12, function() return not ns.db.hideMinimap end, function(on)
        ns.db.hideMinimap = not on or nil
        if ns.minimapButton then ns.minimapButton:SetShown(on) end
    end)
    Option("Abrir con el instructor", 160, function() return ns.db.autoOpenTrainer ~= false end, function(on)
        ns.db.autoOpenTrainer = on
    end)

    clearRoute = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearRoute:SetSize(110, 22)
    clearRoute:SetPoint("BOTTOMRIGHT", -14, 9)
    clearRoute:SetText("Quitar rumbo")
    clearRoute:SetScript("OnClick", function() ns.Nav.Clear() end)

    frame:SetScript("OnShow", function() UI.Refresh() end)
end

---------------------------------------------------------------------------
-- Créditos
---------------------------------------------------------------------------

local CREDITS = {
    "|cffffd200Thesito Addon|r",
    "Hecho por Thesito para jugar a World of Warcraft: Forever, con ayuda de Claude (Anthropic).",
    "",
    "|cffffd200Datos que usa mientras juegas (no se copian: se le piden a estos addons)|r",
    "• |cffffffffQuestie / QuestieDB|r (licencia GPLv3): misiones, PNJ, objetos, zonas y maestros de vuelo.",
    "• |cffffffffSkillUpForever|r (GPLv3): recetas de Sastrería, materiales y de dónde salen las recetas.",
    "• |cffffffffTomTom|r y su librería |cffffffffHereBeDragons|r: la flecha y las posiciones para las líneas del mapa.",
    "",
    "|cffffd200Rutas de talentos|r",
    "• |cffffffffForever Hispano|r (foreverhispano.com): el orden de los talentos de todas las rutas sale de sus guías de clase (revisión 1.1, 07/11/2026). La ruta \"la de Thesito\" mezcla lo que tenía puesto con la suya.",
    "• Los identificadores de cada talento se sacaron del árbol que publica el addon |cffffffffSendaFH|r (GPLv3).",
    "",
    "|cffffd200Consultados para aprender cómo funciona Forever|r",
    "• El código de |cffffffffSendaFH|r, |cffffffffLFGForever|r, |cffffffffBind on Forever Guide|r y |cffffffffSkillUpForever|r, para saber cómo leer los talentos y el instructor. No se ha copiado su código.",
    "• |cffffffffWarcraft Wiki|r (warcraft.wiki.gg): documentación de la API del juego y de los libros de biblioteca.",
    "• |cffffffffWarcraft Tavern|r: guía de los libros de biblioteca de Forever.",
    "",
    "|cffffd200Criterio propio|r",
    "• Los consejos del instructor (esencial, útil, saltar), el valor de cada estadística para las mejoras de equipo y las posiciones de zepelines y barcos son criterio propio: puedes cambiarlos en Data.lua y Nav.lua.",
    "",
    "Gracias a todos ellos. Si algo de esto es tuyo y quieres que se cambie, dilo en GitHub.",
}

local function FillCredits()
    nextBox:Hide()
    showKnown:Hide()
    header:Hide()
    scrollFrame:Hide()
    detailScroll:Show()
    detailScroll:ClearAllPoints()
    detailScroll:SetPoint("TOPLEFT", 12, HEADER_Y)
    detailScroll:SetPoint("BOTTOMRIGHT", -32, FOOTER_H + 6)
    detailText:SetText(table.concat(CREDITS, "\n"))
    detailChild:SetHeight(detailText:GetStringHeight() + 20)
    return 0
end

function UI.Refresh()
    if not (frame and frame:IsShown() and ns.db) then return end
    for name, b in pairs(tabButtons) do
        if b.isTab and PanelTemplates_SelectTab then
            if name == tab then PanelTemplates_SelectTab(b) else PanelTemplates_DeselectTab(b) end
        elseif name == tab then
            b:LockHighlight()
        else
            b:UnlockHighlight()
        end
    end
    subtitle:SetText(("%s · %s · nivel %d"):format(UnitName("player") or "?", ns.className or "?", UnitLevel("player") or 1))
    clearRoute:SetEnabled(ns.Nav.Target() ~= nil)
    header:Show()
    header:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    scrollFrame:Show()
    detailScroll:Hide()
    routeButton:Hide()
    viewButton:Hide()
    treeFrame:Hide()
    for _, b in pairs(questButtons) do b:Hide() end
    local n
    if tab == "talentos" then
        n = FillTalents()
    elseif tab == "bolsas" then
        n = FillBags()
    elseif tab == "misiones" then
        n = FillQuests()
    elseif tab == "importante" then
        n = FillImportant()
    elseif tab == "creditos" then
        n = FillCredits()
    else
        n = FillTrainer()
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    content:SetHeight(math.max(1, n * ROW_H))
end

local function CanOpen()
    if ns.ready then return true end
    ns.Print("espera a terminar de entrar en el juego.")
    return false
end

function UI.Open(which)
    if not CanOpen() then return end
    Create()
    if which then tab = which end
    if not frame:IsShown() then
        ApplyPosition()
        frame:Show()
    end
    UI.Refresh()
end

function UI.Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
    else
        UI.Open()
    end
end

function UI.Close()
    if frame then frame:Hide() end
end

function UI.IsShowing(which)
    return frame ~= nil and frame:IsShown() and tab == which
end

-- Abre la pestaña Instructor junto a la ventana del instructor.
-- Devuelve true si la ventana estaba cerrada (para cerrarla al irte).
function UI.OpenBesideTrainer()
    if not CanOpen() then return false end
    Create()
    tab = "entrenador"
    if frame:IsShown() then
        UI.Refresh()
        return false
    end
    frame:ClearAllPoints()
    if ClassTrainerFrame and ClassTrainerFrame:IsShown() then
        frame:SetPoint("TOPLEFT", ClassTrainerFrame, "TOPRIGHT", 12, 0)
    else
        ApplyPosition()
    end
    frame:Show()
    UI.Refresh()
    return true
end

function UI.ResetPosition()
    ns.db.pos = nil
    if frame then ApplyPosition() end
end
