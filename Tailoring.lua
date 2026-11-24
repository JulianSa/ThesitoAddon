-- Thesito Addon: bolsas que puedes coser como Sastre.
-- Los datos de las recetas (qué fabrican, materiales, nivel de Sastrería,
-- instructor o receta, de dónde sale la receta) vienen de la API pública de
-- SkillUpForever (SkillUpForever.API), con datos de esta misma versión de
-- Forever. Si conoces la receta y cuántos materiales tienes lo dice el juego.

local _, ns = ...
local T = {}
ns.Tailor = T

local call = ns.call
local TAILORING = 197
local AHEAD = 25 -- recetas de hasta 25 puntos por encima de tu Sastrería

-- Bolsas especiales (subclase de contenedor): qué cabe en ellas.
local SPECIAL = {
    [1] = "solo para fragmentos de alma",
    [2] = "solo para hierbas",
    [3] = "solo para materiales de encantamiento (¡te sirve como Encantador!)",
    [4] = "solo para piezas de ingeniería",
    [5] = "solo para gemas",
    [6] = "solo para minerales",
}

local slotsCache = {}
T.pending = false

local function API()
    return SkillUpForever and SkillUpForever.API
end

-- Tu nivel de Sastrería, o nil si no eres sastre.
function T.Skill()
    if not (GetProfessions and GetProfessionInfo) then return nil end
    local list = { n = select("#", GetProfessions()), GetProfessions() }
    for i = 1, list.n do
        local index = list[i]
        if index then
            local _, _, rank, _, _, _, skillLine = GetProfessionInfo(index)
            if skillLine == TAILORING then return rank end
        end
    end
end

local function Known(recipeID)
    if IsPlayerSpell and call(IsPlayerSpell, recipeID) then return true end
    if C_SpellBook and C_SpellBook.IsSpellKnown and call(C_SpellBook.IsSpellKnown, recipeID) then return true end
    return false
end

local function Count(itemID)
    if C_Item and C_Item.GetItemCount then return call(C_Item.GetItemCount, itemID, true) or 0 end
    return call(GetItemCount, itemID, true) or 0
end

function T.ItemName(itemID)
    return (C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)) or ("objeto " .. itemID)
end

-- Las recetas de bolsas: { skill, smallest, hidden, list = { ... } } o nil, motivo.
function T.Bags()
    local api = API()
    if not api then
        return nil, "Para esta sección necesito el addon SkillUpForever activado (trae los datos de las recetas)."
    end
    local skill = T.Skill()
    if not skill then return nil, "notailor" end
    local ids, reason = api.Recipes(TAILORING)
    if not ids then
        return nil, reason == "loading" and "Cargando los datos de SkillUpForever…" or "SkillUpForever no tiene recetas de Sastrería."
    end

    local sizes = ns.Bags.EquippedBags()
    local smallest = math.huge
    for i = 2, #sizes do smallest = math.min(smallest, sizes[i]) end

    local out = { skill = skill, smallest = smallest, hidden = 0, list = {} }
    T.pending = false
    for _, recipeID in ipairs(ids) do
        local recipe = api.Recipe(recipeID)
        local itemID = recipe and recipe.output and recipe.output.itemID
        local _, _, _, _, icon, classID, subclassID = call(C_Item.GetItemInfoInstant, itemID or 0)
        if itemID and classID == 1 then
            local slots = slotsCache[itemID] or ns.Bags.SlotsForItemID(itemID)
            slotsCache[itemID] = slots
            if not slots then
                T.pending = true
                call(C_Item.RequestLoadItemDataByID, itemID)
            end
            local req = api.RecipeRequirement(recipeID)
            local bands = api.RecipeSkill(recipeID)
            local e = {
                recipeID = recipeID, itemID = itemID, icon = icon, slots = slots,
                special = subclassID and subclassID ~= 0 and (SPECIAL[subclassID] or "bolsa especial") or nil,
                learned = Known(recipeID), req = req, bands = bands, reagents = recipe.reagents or {},
                -- Si no se sabe el nivel (dato provisional 1), usamos cuándo empieza a dar puntos.
                need = (req and req.skill)
                    or (bands and bands.orange and bands.orange > 1 and bands.orange)
                    or (bands and bands.yellow) or 1,
            }
            local can = e.learned and skill >= e.need
            for _, r in ipairs(e.reagents) do
                r.have = Count(r.itemID)
                if r.have < r.quantity then can = false end
            end
            e.canCraft = can
            local useful = e.special or not slots or slots > smallest
            if useful and (e.learned or e.need <= skill + AHEAD) then
                out.list[#out.list + 1] = e
            else
                out.hidden = out.hidden + 1
            end
        end
    end
    table.sort(out.list, function(a, b)
        if a.need ~= b.need then return a.need < b.need end
        return (a.slots or 0) > (b.slots or 0)
    end)
    return out
end

-- Estado corto para la columna de la derecha.
function T.Status(e, skill)
    if e.canCraft then return "|cff40ff40¡puedes coserla!|r" end
    if e.learned then return "|cffffd200la sabes · faltan materiales|r" end
    if skill < e.need then return ("|cff9d9d9dcon Sastrería %d|r"):format(e.need) end
    if e.req and e.req.source == "trainer" then return "|cff40ff40apréndela en el instructor|r" end
    return "|cff80c0ffnecesitas la receta|r"
end

-- Explicación completa para el tooltip.
function T.Tip(e, skill)
    local t = {}
    if e.special then t[#t + 1] = "Bolsa especial: " .. e.special .. "." end
    if e.learned then
        t[#t + 1] = "|cff40ff40Ya sabes coserla.|r"
    elseif e.req and e.req.source == "trainer" then
        t[#t + 1] = ("Se aprende en el instructor de Sastrería con %d de habilidad%s."):format(
            e.need, e.req.trainerFee and (" por " .. ns.Money(e.req.trainerFee)) or "")
    else
        t[#t + 1] = ("Hace falta la receta y %d de Sastrería."):format(e.need)
        local api = API()
        local s = api and api.RecipeSources(e.recipeID)
        if s then
            for _, v in ipairs(s.vendors or {}) do
                if v.usable ~= false then t[#t + 1] = ("• La vende %s (%s)."):format(v.name or "?", v.zone or "?") end
            end
            for _, q in ipairs(s.quests or {}) do
                if q.usable ~= false then t[#t + 1] = ("• Recompensa de la misión «%s»."):format(q.title or "?") end
            end
            for i, d in ipairs(s.drops or {}) do
                if i <= 3 then t[#t + 1] = ("• La suelta %s (%s), %.1f %%."):format(d.name or "?", d.zone or "?", d.chance or 0) end
            end
            if s.world then t[#t + 1] = "• También cae al azar de enemigos de su nivel." end
        end
    end
    t[#t + 1] = ("Tu Sastrería: %d."):format(skill)
    t[#t + 1] = " "
    t[#t + 1] = "Materiales (lo que tienes, contando el banco):"
    for _, r in ipairs(e.reagents) do
        local color = r.have >= r.quantity and "|cff40ff40" or "|cffff6060"
        t[#t + 1] = ("%s• %d × %s (tienes %d)|r"):format(color, r.quantity, T.ItemName(r.itemID), r.have)
    end
    if e.bands and e.bands.grey then
        t[#t + 1] = " "
        t[#t + 1] = ("Te da puntos de Sastrería hasta el %d."):format(e.bands.grey)
    end
    t[#t + 1] = " "
    if e.learned then
        t[#t + 1] = "Clic: abre tu ventana de Sastrería para coserla."
    elseif e.req and e.req.source == "trainer" then
        t[#t + 1] = "Clic: rumbo al instructor de Sastrería más cercano."
    else
        t[#t + 1] = "Clic: rumbo a quien vende la receta (si la vende alguien)."
    end
    return table.concat(t, "\n")
end

-- Al hacer clic en una bolsa.
function T.Go(e)
    if e.learned then
        local opened = C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill and call(C_TradeSkillUI.OpenTradeSkill, TAILORING)
        if not opened then ns.Print("ábrela desde tu libro de hechizos (Profesiones → Sastrería).") end
        return
    end
    if e.req and e.req.source == "trainer" then
        ns.Nav.GoTailorTrainer()
        return
    end
    local api = API()
    local s = api and api.RecipeSources(e.recipeID)
    local db = ns.Quests.DB()
    for _, v in ipairs(s and s.vendors or {}) do
        if v.usable ~= false and v.npcID and db then
            local spot = ns.Quests.BestSpot(db.Npc.Get(v.npcID, "spawns"))
            if spot and spot.x then
                ns.Nav.Go({ zone = spot.zone, x = spot.x, y = spot.y, title = "Comprar la receta de " .. T.ItemName(e.itemID) .. " (" .. (v.name or "?") .. ")" })
                return
            end
        end
    end
    ns.Print("esa receta no la vende nadie a tu alcance: pasa el ratón por encima para ver de dónde sale.")
end

for _, event in ipairs({ "BAG_UPDATE_DELAYED", "SKILL_LINES_CHANGED", "TRADE_SKILL_LIST_UPDATE", "LEARNED_SPELL_IN_TAB", "NEW_RECIPE_LEARNED" }) do
    ns.On(event, function()
        if ns.UI and ns.UI.IsShowing("importante") then ns.RequestRefresh() end
    end)
end

ns.On("GET_ITEM_INFO_RECEIVED", function()
    if T.pending and ns.UI and ns.UI.IsShowing("importante") then ns.RequestRefresh() end
end)
