-- Thesito Addon: ventana de bolsas propia, con secciones.
-- Sustituye a la ventana de bolsas del juego: se abre y se cierra cuando el
-- juego abre o cierra sus bolsas (tecla B, vendedor, banco, buzón...), y las
-- del juego se quedan escondidas. Las casillas usan la plantilla de casilla
-- de bolsa del propio juego, así que el clic derecho (usar, equipar, vender),
-- arrastrar, partir montones o enlazar en el chat funcionan como siempre.
-- Las secciones y la explicación de cada objeto son las de la pestaña Bolsas.

local _, ns = ...
local W = {}
ns.BagWindow = W

local call = ns.call

local BUTTON, GAP, COLUMNS, PAD = 37, 4, 10, 12
local HEADER_H, TOP, FOOTER = 20, 58, 34
local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
local EMPTY_TEXTURE = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"

-- Addons de bolsas que ya cambian la ventana: si hay alguno, por defecto no
-- usamos la nuestra (se puede forzar con la casilla de la pestaña Bolsas).
local OTHER_BAG_ADDONS = { "Bagnon", "Baganator", "AdiBags", "BetterBags", "ArkInventory", "Combuctor", "ForeverBags", "PrimeBags" }

local function OtherBagAddon()
    for _, name in ipairs(OTHER_BAG_ADDONS) do
        local loaded
        if C_AddOns and C_AddOns.IsAddOnLoaded then
            loaded = call(C_AddOns.IsAddOnLoaded, name)
        elseif IsAddOnLoaded then
            loaded = call(IsAddOnLoaded, name)
        end
        if loaded then return name end
    end
end

function W.Enabled()
    if not ns.db then return false end
    if ns.db.ownBags == nil then return not OtherBagAddon() end
    return ns.db.ownBags and true or false
end

---------------------------------------------------------------------------
-- Ventana
---------------------------------------------------------------------------

local frame, content, search, slotsText, moneyText
local bagParents, slotButtons, headers = {}, {}, {}
local pending, afterCombat = false, false
local protectedButtons = false -- si las casillas del juego son protegidas, no se mueven en combate
local Layout

function W.RequestLayout()
    if pending or not (frame and frame:IsShown()) then return end
    pending = true
    C_Timer.After(0.05, function() Layout() end)
end

local function SavePosition()
    local point, _, relPoint, x, y = frame:GetPoint(1)
    ns.db.bagWindowPos = { point, relPoint, x, y }
end

local function ApplyPosition()
    frame:ClearAllPoints()
    local p = ns.db.bagWindowPos
    if p then
        frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -90, 110)
    end
end

-- Las casillas cuelgan de un marco por bolsa cuyo ID es el de la bolsa: así
-- la plantilla del juego sabe de qué bolsa es cada casilla.
local function BagParent(bag)
    local p = bagParents[bag]
    if not p then
        p = CreateFrame("Frame", nil, content)
        p:SetID(bag)
        p:SetAllPoints(content)
        bagParents[bag] = p
    end
    return p
end

local function ItemName(info)
    return type(info.hyperlink) == "string" and info.hyperlink:match("%[(.-)%]") or nil
end

-- Añade a la ayuda del juego lo que dice Thesito de ese objeto. El juego
-- rehace la ayuda cada poco mientras tienes el ratón encima, así que la
-- línea se añade cada vez que se construye la ayuda de un objeto.
local function AddThesitoLine(tooltip)
    local owner = tooltip and tooltip.GetOwner and tooltip:GetOwner()
    local e = type(owner) == "table" and owner.thesitoEntry
    if e and e.note and e.note ~= "" then
        tooltip:AddLine(" ")
        tooltip:AddLine("|cff9482c9Thesito:|r " .. e.note, 1, 1, 1, true)
    end
end

local postCall = false
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    postCall = pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tooltip)
        if tooltip == GameTooltip then AddThesitoLine(tooltip) end
    end)
end

local function OnEnterSlot(b)
    if b.thesitoFree then
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        GameTooltip:SetText(("Casillas vacías: %d"):format(b.thesitoFree))
        GameTooltip:AddLine("Suelta aquí un objeto para guardarlo en la primera casilla libre.", 1, 1, 1, true)
        GameTooltip:Show()
        return
    end
    if not postCall and GameTooltip:IsOwned(b) then
        AddThesitoLine(GameTooltip)
        GameTooltip:Show()
    end
end

local buttonCount = 0
local function SlotButton(bag, slot)
    slotButtons[bag] = slotButtons[bag] or {}
    local b = slotButtons[bag][slot]
    if b then return b end
    buttonCount = buttonCount + 1
    local name = "ThesitoBagSlot" .. buttonCount
    local ok, made = pcall(CreateFrame, "ItemButton", name, BagParent(bag), "ContainerFrameItemButtonTemplate")
    b = ok and made or CreateFrame("Button", name, BagParent(bag), "ContainerFrameItemButtonTemplate")
    b:SetID(slot)
    if b.SetBagID then call(b.SetBagID, b, bag) end
    -- La plantilla espera estar dentro de una ventana de bolsas del juego:
    -- sus eventos y su OnShow los llevamos nosotros.
    b:SetScript("OnEvent", nil)
    b:SetScript("OnShow", nil)
    b:SetSize(BUTTON, BUTTON)
    if b.NewItemTexture then b.NewItemTexture:Hide() end
    if b.BattlepayItemTexture then b.BattlepayItemTexture:Hide() end
    b:HookScript("OnEnter", OnEnterSlot)
    if b.IsProtected and b:IsProtected() then protectedButtons = true end
    slotButtons[bag][slot] = b
    return b
end

-- Crea de antemano todas las casillas (fuera de combate), por si abres las
-- bolsas en mitad de un combate.
local function PrecreateButtons()
    if InCombatLockdown() or not frame then return end
    for bag = 0, LAST_BAG do
        local n = call(C_Container.GetContainerNumSlots, bag) or 0
        for slot = 1, n do
            local b = SlotButton(bag, slot)
            if not frame:IsShown() then b:Hide() end
        end
    end
end

local function SetQuestMark(b, bag, slot)
    local mark = b.IconQuestTexture or (b:GetName() and _G[b:GetName() .. "IconQuestTexture"])
    if not mark then return end
    local q = call(C_Container.GetContainerItemQuestInfo, bag, slot)
    if q and q.questID and not q.isActive then
        mark:SetTexture(TEXTURE_ITEM_QUEST_BANG)
        mark:Show()
    elseif q and (q.questID or q.isQuestItem) then
        mark:SetTexture(TEXTURE_ITEM_QUEST_BORDER)
        mark:Show()
    else
        mark:Hide()
    end
end

local function UpdateSlot(b, bag, slot, info, e)
    b.thesitoEntry, b.thesitoFree = e, nil
    if SetItemButtonTexture then SetItemButtonTexture(b, info and info.iconFileID or EMPTY_TEXTURE) end
    if SetItemButtonCount then SetItemButtonCount(b, info and info.stackCount or 0) end
    if SetItemButtonQuality then call(SetItemButtonQuality, b, info and info.quality, info and info.hyperlink) end
    if SetItemButtonDesaturated then SetItemButtonDesaturated(b, info and info.isLocked or false) end
    if info then
        SetQuestMark(b, bag, slot)
    else
        local mark = b.IconQuestTexture
        if mark then mark:Hide() end
    end
    -- La moneda de "basura" marca lo que Thesito te dice que vendas o tires.
    if b.JunkIcon then b.JunkIcon:SetShown(e ~= nil and e.group == "tirar") end
    if b.Cooldown then
        if info then
            local start, duration, enable = call(C_Container.GetContainerItemCooldown, bag, slot)
            if CooldownFrame_Set then CooldownFrame_Set(b.Cooldown, start or 0, duration or 0, enable) end
        else
            b.Cooldown:Hide()
        end
    end
end

local function Header(i)
    local h = headers[i]
    if h then return h end
    h = CreateFrame("Button", nil, content)
    h:SetHeight(HEADER_H - 2)
    h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h.text:SetPoint("LEFT", 2, 0)
    h.line = h:CreateTexture(nil, "ARTWORK")
    h.line:SetHeight(1)
    h.line:SetPoint("BOTTOMLEFT", 0, 0)
    h.line:SetPoint("BOTTOMRIGHT", 0, 0)
    h.line:SetColorTexture(1, 0.82, 0, 0.45)
    h:SetScript("OnClick", function(self)
        if not self.key then return end
        ns.db.bagCollapsed = ns.db.bagCollapsed or {}
        ns.db.bagCollapsed[self.key] = not ns.db.bagCollapsed[self.key] or nil
        Layout()
    end)
    h:SetScript("OnEnter", function(self)
        if not self.key then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Clic para plegar o desplegar la sección.", 1, 1, 1)
        GameTooltip:Show()
    end)
    h:SetScript("OnLeave", GameTooltip_Hide)
    headers[i] = h
    return h
end

local function Less(a, b)
    local ka, kb = a.key, b.key
    if ka.rank ~= kb.rank then return ka.rank < kb.rank end
    if ka.class ~= kb.class then return ka.class < kb.class end
    if ka.sub ~= kb.sub then return ka.sub < kb.sub end
    if ka.quality ~= kb.quality then return ka.quality > kb.quality end
    if ka.name ~= kb.name then return ka.name < kb.name end
    if a.info.itemID ~= b.info.itemID then return a.info.itemID < b.info.itemID end
    if a.bag ~= b.bag then return a.bag < b.bag end
    return a.slot < b.slot
end

Layout = function()
    pending = false
    if not (frame and frame:IsShown()) then return end
    if protectedButtons and InCombatLockdown() then
        afterCombat = true
        return
    end

    local list = ns.Bags.Analyze()
    local keys = ns.Bags.SortKeys(list)
    local byItem = {}
    for _, e in ipairs(list) do byItem[e.itemID] = e end

    local sectionsDef = ns.Bags.SORT_SECTIONS
    local sections = {}
    for i = 1, #sectionsDef do sections[i] = {} end

    local used, total, free, firstFree = 0, 0, 0, nil
    for bag = 0, LAST_BAG do
        local n = call(C_Container.GetContainerNumSlots, bag) or 0
        local _, family = call(C_Container.GetContainerNumFreeSlots, bag)
        for slot = 1, n do
            total = total + 1
            local info = call(C_Container.GetContainerItemInfo, bag, slot)
            if info and info.itemID then
                used = used + 1
                local key = keys[info.itemID] or keys.default
                local into = sections[key.section] or sections[#sections]
                into[#into + 1] = { bag = bag, slot = slot, info = info, key = key, e = byItem[info.itemID] }
            else
                free = free + 1
                if not firstFree and (not family or family == 0) then firstFree = { bag = bag, slot = slot } end
            end
        end
    end

    for _, bySlot in pairs(slotButtons) do
        for _, b in pairs(bySlot) do b:Hide() end
    end
    for _, h in pairs(headers) do h:Hide() end

    local query = strtrim(search:GetText() or ""):lower()
    local width = COLUMNS * BUTTON + (COLUMNS - 1) * GAP
    local collapsed = ns.db.bagCollapsed or {}
    local y, hi = 0, 0

    local function PlaceHeader(key, title, count)
        hi = hi + 1
        local h = Header(hi)
        h.key = key
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        h:SetWidth(width)
        local sign = key and (collapsed[key] and "|cff9d9d9d+|r " or "|cff9d9d9d-|r ") or ""
        h.text:SetText(("%s%s |cff9d9d9d(%d)|r"):format(sign, title, count))
        h:Show()
        y = y + HEADER_H
    end

    local function PlaceButton(b, i)
        local col, row = (i - 1) % COLUMNS, math.floor((i - 1) / COLUMNS)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", content, "TOPLEFT", col * (BUTTON + GAP), -(y + row * (BUTTON + GAP)))
        b:Show()
    end

    for s, items in ipairs(sections) do
        if #items > 0 then
            table.sort(items, Less)
            local def = sectionsDef[s]
            local key = def.title
            PlaceHeader(key, def.title:sub(1, 1):upper() .. def.title:sub(2), #items)
            if not collapsed[key] then
                for i, it in ipairs(items) do
                    local b = SlotButton(it.bag, it.slot)
                    UpdateSlot(b, it.bag, it.slot, it.info, it.e)
                    local name = query ~= "" and (ItemName(it.info) or ""):lower()
                    b:SetAlpha((query == "" or name:find(query, 1, true)) and 1 or 0.25)
                    PlaceButton(b, i)
                end
                y = y + math.ceil(#items / COLUMNS) * (BUTTON + GAP)
            end
            y = y + 6
        end
    end

    -- Casillas vacías: una sola, con cuántas hay. Al soltar ahí un objeto va a
    -- la primera casilla libre (de una bolsa normal).
    PlaceHeader(nil, "Casillas vacías", free)
    if firstFree then
        local b = SlotButton(firstFree.bag, firstFree.slot)
        UpdateSlot(b, firstFree.bag, firstFree.slot, nil, nil)
        b.thesitoFree = free
        if SetItemButtonCount then SetItemButtonCount(b, free) end
        b:SetAlpha(1)
        PlaceButton(b, 1)
        y = y + BUTTON + GAP
    end

    content:SetSize(width, math.max(1, y))
    frame:SetSize(width + PAD * 2, TOP + y + FOOTER)
    slotsText:SetText(("|cffffd200Casillas:|r %d de %d ocupadas"):format(used, total))
    moneyText:SetText(ns.Money(GetMoney and GetMoney() or 0))
end

local function Create()
    if frame then return end
    frame = CreateFrame("Frame", "ThesitoBagsFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    if frame.TitleText then frame.TitleText:SetText("Bolsas de " .. (UnitName("player") or "?")) end
    tinsert(UISpecialFrames, "ThesitoBagsFrame")
    frame:Hide()

    search = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
    search:SetHeight(20)
    search:SetPoint("TOPLEFT", PAD + 6, -30)
    search:SetPoint("TOPRIGHT", -PAD - 92, -30)
    search:SetAutoFocus(false)
    search:HookScript("OnTextChanged", function() W.RequestLayout() end)

    local analysis = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    analysis:SetSize(84, 20)
    analysis:SetPoint("TOPRIGHT", -PAD, -30)
    analysis:SetNormalFontObject(GameFontNormalSmall)
    analysis:SetHighlightFontObject(GameFontHighlightSmall)
    analysis:SetText("Análisis")
    analysis:SetScript("OnClick", function() ns.UI.Open("bolsas") end)
    analysis:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Abre la pestaña Bolsas de Thesito: qué vender, desencantar o guardar, y por qué.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    analysis:SetScript("OnLeave", GameTooltip_Hide)

    content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", PAD, -TOP)
    content:SetSize(1, 1)

    slotsText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    slotsText:SetPoint("BOTTOMLEFT", PAD + 2, 12)
    moneyText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    moneyText:SetPoint("BOTTOMRIGHT", -PAD - 2, 12)

    -- Al cerrar la nuestra (X o Esc), cerramos también las del juego para que
    -- la tecla B siga funcionando como siempre.
    frame:SetScript("OnHide", function()
        search:ClearFocus()
        if W.BlizzardBagsOpen() and CloseAllBags then CloseAllBags() end
    end)
    frame:SetScript("OnShow", function() Layout() end)
    ApplyPosition()
end

function W.Show()
    Create()
    if not frame:IsShown() then frame:Show() end
end

function W.Hide()
    if frame and frame:IsShown() then frame:Hide() end
end

function W.ResetPosition()
    ns.db.bagWindowPos = nil
    if frame then ApplyPosition() end
end

---------------------------------------------------------------------------
-- Sustituir a las bolsas del juego
-- Las ventanas de bolsas del juego se siguen abriendo y cerrando como siempre,
-- pero dentro de un marco diminuto y transparente (visible para el juego: si
-- fuera un marco escondido, el juego dejaría de avisar cuando se abren). La
-- nuestra se muestra mientras alguna de ellas (de tus bolsas, no del banco)
-- esté abierta.
---------------------------------------------------------------------------

local tinyParent
local originalParent = {}

local function InventoryBag(bag)
    return type(bag) == "number" and bag >= 0 and bag <= LAST_BAG
end

local function BlizzardFrames()
    local list = {}
    if _G.ContainerFrameCombinedBags then list[#list + 1] = _G.ContainerFrameCombinedBags end
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local f = _G["ContainerFrame" .. i]
        if f then list[#list + 1] = f end
    end
    return list
end

local function IsInventoryFrame(f)
    return f == _G.ContainerFrameCombinedBags or InventoryBag(f:GetID())
end

function W.BlizzardBagsOpen()
    for _, f in ipairs(BlizzardFrames()) do
        if f:IsShown() and IsInventoryFrame(f) then return true end
    end
    return false
end

local function Sync()
    if not W.Enabled() then return end
    if W.BlizzardBagsOpen() then W.Show() else W.Hide() end
end

-- Al abrir todas las bolsas el juego abre una tras otra: esperamos a que
-- termine (un instante) antes de mirar.
local syncPending = false
local function SyncSoon()
    if syncPending then return end
    syncPending = true
    C_Timer.After(0, function()
        syncPending = false
        Sync()
    end)
end

local function Adopt(f)
    if not tinyParent then return end
    if W.Enabled() and IsInventoryFrame(f) then
        if f:GetParent() ~= tinyParent then f:SetParent(tinyParent) end
    elseif f:GetParent() == tinyParent then
        f:SetParent(originalParent[f] or UIParent)
    end
end

function W.SetEnabled(on)
    ns.db.ownBags = on and true or false
    for _, f in ipairs(BlizzardFrames()) do Adopt(f) end
    if on then
        Sync()
        local other = OtherBagAddon()
        if other then
            ns.Print(("tienes %s activado y la ventana de bolsas de Thesito a la vez: desactiva %s en AddOns para que no se pisen."):format(other, other))
        end
    else
        W.Hide()
    end
    ns.RequestRefresh()
end

function W.Toggle()
    if ToggleAllBags then ToggleAllBags() end
end

ns.On("PLAYER_LOGIN", function()
    -- Visible para el juego, pero tan pequeño y transparente que no se ve ni
    -- se puede pulsar.
    tinyParent = CreateFrame("Frame", nil, UIParent)
    tinyParent:SetSize(1, 1)
    tinyParent:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
    tinyParent:SetScale(0.001)
    tinyParent:SetAlpha(0)
    -- Con la nuestra activa, el juego usa una sola ventana para todas tus
    -- bolsas (como viene por defecto; Bagnon la cambia a una por bolsa).
    if W.Enabled() and C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("combinedBags") == "0" then
        pcall(C_CVar.SetCVar, "combinedBags", "1")
    end
    for _, f in ipairs(BlizzardFrames()) do
        originalParent[f] = f:GetParent()
        Adopt(f) -- ahora, con todo cerrado, para no provocar avisos al abrir
        f:HookScript("OnShow", function(self)
            Adopt(self) -- la del banco vuelve a su sitio; las de tus bolsas, al marco diminuto
            SyncSoon()
        end)
        f:HookScript("OnHide", SyncSoon)
    end
    -- Por si algún camino no avisa: también al usar las funciones de abrir y
    -- cerrar bolsas del juego (tecla B, iconos de la barra de bolsas...).
    for _, fn in ipairs({ "ToggleAllBags", "OpenAllBags", "CloseAllBags", "ToggleBackpack", "OpenBackpack",
        "CloseBackpack", "ToggleBag", "OpenBag", "CloseBag" }) do
        if type(_G[fn]) == "function" then hooksecurefunc(fn, SyncSoon) end
    end
    if ns.db.ownBags == nil then
        local other = OtherBagAddon()
        if other then
            ns.Print(("uso tu %s para las bolsas. Si lo desactivas, se activa sola la ventana de bolsas de Thesito, con secciones."):format(other))
        end
    end
end)

local function Prepare()
    if not W.Enabled() or InCombatLockdown() then return end
    Create()
    PrecreateButtons()
end
ns.On("PLAYER_ENTERING_WORLD", Prepare)
ns.On("BAG_CONTAINER_UPDATE", Prepare) -- cambias una bolsa por otra

ns.On("PLAYER_REGEN_ENABLED", function()
    if afterCombat then
        afterCombat = false
        Prepare()
        W.RequestLayout()
    end
end)

for _, event in ipairs({
    "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN", "PLAYER_MONEY",
    "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "SKILL_LINES_CHANGED",
    "GET_ITEM_INFO_RECEIVED",
}) do
    ns.On(event, function() W.RequestLayout() end)
end
