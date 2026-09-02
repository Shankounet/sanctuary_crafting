--[[
    book/server/core.lua — discoveries / objectives / pins / notes / artisans / orders / history / prefs
    Server-authoritative. No GPS. No other players' exact skills/inventories/licenses.
]]

SurvivalBook = SurvivalBook or {}

local discoveredCache = {} -- [ident] = { [item]=ts }
local pinCache = {}        -- [ident] = { recipeId, ... }
local artisanCache = {}    -- [ident] = { contact, ... }
local orderCache = {}      -- [ident] = { order, ... }
local noteCache = {}       -- [ident] = { note, ... }
local objectiveCache = {}  -- [ident] = { sql objective rows, ... }
local historyCount = {}    -- [ident] = number
local notifCooldown = {}     -- [src] = lastMs

local function craftHistoryOn()
    local ch = Config.CraftHistory
    if ch == true then return true end
    if type(ch) == 'table' then return ch.Enabled == true end
    return false
end

local function jdec(s, fb)
    if not s or s == '' then return fb end
    local ok, d = pcall(json.decode, s)
    if ok and d ~= nil then return d end
    return fb
end

local function jenc(t)
    return json.encode(t or {})
end

local function itemLabel(item)
    if not item then return nil end
    if OxItemCatalog and OxItemCatalog.Label then
        return OxItemCatalog.Label(item)
    end
    return item
end

function SurvivalBook.Notify(src, key, nType, args)
    if not BookDB.Mod('Notifications') then return end
    local cd = (Config.Book.Notifications and Config.Book.Notifications.CooldownMs) or 8000
    local now = GetGameTimer()
    local last = notifCooldown[src] or 0
    if now - last < cd then return end
    notifCooldown[src] = now
    local desc = key
    if type(args) == 'table' and #args > 0 then
        desc = _(key, table.unpack(args))
    else
        desc = _(key)
    end
    TriggerClientEvent('ox_lib:notify', src, { type = nType or 'inform', description = desc })
end

function SurvivalBook.PushHistory(ident, eventType, payload)
    if not BookDB.Mod('History') and not BookDB.Mod('Discoveries') then return end
    if eventType == 'craft_completed' and not craftHistoryOn() then
        return
    end
    MySQL.insert.await(
        'INSERT INTO sanctuary_book_history (identifier, event_type, payload) VALUES (?,?,?)',
        { ident, eventType, jenc(payload) }
    )
    historyCount[ident] = (historyCount[ident] or 0) + 1
    local maxH = (Config.Book and Config.Book.MaxHistory) or 120
    MySQL.query.await([[
        DELETE FROM sanctuary_book_history WHERE identifier = ? AND id NOT IN (
            SELECT id FROM (
                SELECT id FROM sanctuary_book_history WHERE identifier = ? ORDER BY id DESC LIMIT ?
            ) t
        )
    ]], { ident, ident, maxH })
end

--------------------------------------------------------------------------------
-- Prefs
--------------------------------------------------------------------------------
function SurvivalBook.GetPrefs(src)
    local id = BookDB.Ident(src)
    if not id then return {} end
    local row = MySQL.single.await('SELECT prefs FROM sanctuary_book_player WHERE identifier = ?', { id })
    return jdec(row and row.prefs, {})
end

function SurvivalBook.SetPrefs(src, prefs)
    local id = BookDB.Ident(src)
    if not id or type(prefs) ~= 'table' then return false end
    MySQL.query.await(
        'INSERT INTO sanctuary_book_player (identifier, prefs) VALUES (?,?) ON DUPLICATE KEY UPDATE prefs = VALUES(prefs)',
        { id, jenc(prefs) }
    )
    return true
end

--------------------------------------------------------------------------------
-- Discoveries / Resources
--------------------------------------------------------------------------------
function SurvivalBook.LoadDiscoveries(src)
    local id = BookDB.Ident(src)
    if not id then return end
    discoveredCache[id] = {}
    local rows = MySQL.query.await(
        'SELECT item, UNIX_TIMESTAMP(discovered_at) AS ts FROM sanctuary_book_discovered_resources WHERE identifier = ?', { id }
    ) or {}
    for i = 1, #rows do
        discoveredCache[id][rows[i].item] = tonumber(rows[i].ts) or 0
    end
end

function SurvivalBook.HasDiscoveredResource(src, item)
    if not item then return false end
    local id = BookDB.Ident(src)
    if not id then return false end
    if not discoveredCache[id] then SurvivalBook.LoadDiscoveries(src) end
    return discoveredCache[id] and discoveredCache[id][item] ~= nil
end

function SurvivalBook.DiscoverResource(src, item, label, reason)
    if not BookDB.Mod('Resources') and not BookDB.Mod('Discoveries') then
        return false, 'book_disabled'
    end
    if type(item) ~= 'string' or item == '' then return false, 'craft_invalid' end
    local id = BookDB.Ident(src)
    if not id then return false, 'craft_invalid' end
    if not discoveredCache[id] then SurvivalBook.LoadDiscoveries(src) end
    if discoveredCache[id][item] then return true, 'already' end

    local lab = itemLabel(item)
    MySQL.insert.await(
        'INSERT IGNORE INTO sanctuary_book_discovered_resources (identifier, item) VALUES (?,?)',
        { id, item }
    )
    discoveredCache[id][item] = os.time()
    SurvivalBook.PushHistory(id, 'resource_discovered', { item = item, label = lab, reason = reason })
    TriggerClientEvent('sanctuary_crafting:book:resourceDiscovered', src, item, lab)
    TriggerEvent('sanctuary_crafting:book:resourceDiscovered', src, item, lab)
    SurvivalBook.Notify(src, 'book_resource_discovered', 'success', { lab or item })
    return true
end

function SurvivalBook.ListResources(src)
    local id = BookDB.Ident(src)
    if not id then return {} end
    if not discoveredCache[id] then SurvivalBook.LoadDiscoveries(src) end
    local out = {}
    for item, ts in pairs(discoveredCache[id] or {}) do
        out[#out + 1] = { item = item, label = itemLabel(item), discoveredAt = ts }
    end
    table.sort(out, function(a, b) return (a.discoveredAt or 0) > (b.discoveredAt or 0) end)
    return out
end

--- Mask unknown resources as ???
function SurvivalBook.MaskItem(src, item)
    local unknown = (Config.Book.Resources and Config.Book.Resources.UnknownLabel) or '???'
    if SurvivalBook.HasDiscoveredResource(src, item) then
        return { item = item, label = itemLabel(item), known = true }
    end
    return { item = item, label = unknown, known = false }
end

--------------------------------------------------------------------------------
-- Objectives
--------------------------------------------------------------------------------
function SurvivalBook.AddObjective(src, title, kind, payload)
    if not BookDB.Mod('Objectives') then return nil, 'book_objectives_disabled' end
    local id = BookDB.Ident(src)
    if not id or type(title) ~= 'string' or title == '' then return nil, 'craft_invalid' end
    title = title:sub(1, 128)
    kind = kind or 'manual'
    if kind == 'gather' or kind == 'skill' or kind == 'blueprint' then
        kind = 'manual'
    end
    local maxO = (Config.Book and Config.Book.MaxObjectives) or 24
    if not objectiveCache[id] then SurvivalBook.LoadObjectives(src) end
    local count = 0
    for _, o in ipairs(objectiveCache[id] or {}) do
        if not o.done then count = count + 1 end
    end
    if count >= maxO then return nil, 'book_objectives_full' end
    local insertId = MySQL.insert.await(
        'INSERT INTO sanctuary_book_objectives (identifier, kind, title, payload, done) VALUES (?,?,?,?,0)',
        { id, kind, title, jenc(payload or {}) }
    )
    local obj = { id = insertId, title = title, kind = kind, done = false, payload = payload or {}, createdAt = os.time() }
    objectiveCache[id][#objectiveCache[id] + 1] = obj
    SurvivalBook.PushHistory(id, 'objective_added', { id = insertId, title = title, kind = kind })
    return obj
end

--- Live gather/skill/blueprint children — RAM only, never persisted.
function SurvivalBook.LiveObjectiveChildren(src, recipeId, parentId)
    local recipe = Config.RecipeById and Config.RecipeById[recipeId]
    if not recipe then return {} end
    local function invCount(item)
        if GetResourceState('ox_inventory') ~= 'started' then return 0 end
        return exports.ox_inventory:GetItemCount(src, item) or 0
    end
    local children = {}
    local ings = recipe.ingredients or {}
    if type(recipe.steps) == 'table' and #recipe.steps > 0 then
        ings = {}
        for _, step in ipairs(recipe.steps) do
            for _, ing in ipairs(step.ingredients or {}) do
                ings[#ings + 1] = ing
            end
        end
    end
    for i = 1, #ings do
        local ing = ings[i]
        if ing and ing.item then
            local need = ing.count or 1
            local owned = invCount(ing.item)
            local lab = (OxItemCatalog and OxItemCatalog.Label and OxItemCatalog.Label(ing.item)) or ing.item
            children[#children + 1] = {
                id = nil, kind = 'gather', live = true,
                title = string.format('Récupérer %s', lab),
                payload = { recipeId = recipeId, item = ing.item, need = need, count = need, parentObjectiveId = parentId },
                done = owned >= need, liveDone = owned >= need,
                need = need, owned = owned, remaining = math.max(0, need - owned),
            }
        end
    end
    if recipe.requireLevel then
        local cat = CraftingSkills and CraftingSkills.LevelCategoryForRecipe and CraftingSkills.LevelCategoryForRecipe(recipe)
        local cur = 0
        if CraftingSkills and CraftingSkills.GetLevel then
            cur = CraftingSkills.GetLevel(cat, src) or 0
        end
        local need = tonumber(recipe.requireLevel) or 0
        children[#children + 1] = {
            id = nil, kind = 'skill', live = true,
            title = string.format('Atteindre le niveau %s', tostring(need)),
            payload = { recipeId = recipeId, category = cat, requireLevel = need, parentObjectiveId = parentId },
            done = cur >= need, liveDone = cur >= need,
            need = need, owned = cur, playerSkillLevel = cur,
        }
    end
    local bpId = recipe.requireBlueprint or recipe.blueprintId
    if bpId then
        local has = true
        if Blueprints and Blueprints.Has then
            has = Blueprints.Has(src, bpId) == true
        end
        children[#children + 1] = {
            id = nil, kind = 'blueprint', live = true,
            title = 'Obtenir le plan technique',
            payload = { recipeId = recipeId, blueprintId = bpId, parentObjectiveId = parentId },
            done = has, liveDone = has, owned = has and 1 or 0, need = 1,
        }
    end
    return children
end

function SurvivalBook.AddObjectiveFromRecipe(src, recipeId, opts)
    local recipe = Config.RecipeById and Config.RecipeById[recipeId]
    if not recipe then return nil, 'craft_invalid' end
    opts = type(opts) == 'table' and opts or {}
    -- idempotent: reuse open recipe objective (parent only — no gather/skill/blueprint SQL)
    local existing = SurvivalBook.ListObjectives(src, { skipLive = true }) or {}
    for _, o in ipairs(existing) do
        if not o.done and o.kind == 'recipe' and o.payload and o.payload.recipeId == recipeId then
            o.already = true
            o.subObjectives = SurvivalBook.LiveObjectiveChildren(src, recipeId, o.id)
            o.children = o.subObjectives
            return o
        end
    end
    local facing = (OxItemCatalog and OxItemCatalog.RecipeLabel and OxItemCatalog.RecipeLabel(recipe)) or recipe.label or recipeId
    local obj, err = SurvivalBook.AddObjective(src, facing, 'recipe', { recipeId = recipeId })
    if not obj then return nil, err end
    -- withMissing ignored for SQL: shopping / gather reconstructed live
    obj.subObjectives = SurvivalBook.LiveObjectiveChildren(src, recipeId, obj.id)
    obj.children = obj.subObjectives
    return obj
end

function SurvivalBook.LoadObjectives(src)
    local id = BookDB.Ident(src)
    if not id then return end
    local rows = MySQL.query.await(
        'SELECT id, kind, title, payload, done, UNIX_TIMESTAMP(created_at) AS ts FROM sanctuary_book_objectives WHERE identifier = ? ORDER BY done ASC, id DESC',
        { id }
    ) or {}
    local out = {}
    for i = 1, #rows do
        local kind = rows[i].kind
        -- leftover pre-217 derived rows: ignore (migration deletes them)
        if kind ~= 'gather' and kind ~= 'skill' and kind ~= 'blueprint' then
            out[#out + 1] = {
                id = rows[i].id, kind = kind, title = rows[i].title,
                payload = jdec(rows[i].payload, {}), done = rows[i].done == 1,
                createdAt = rows[i].ts,
            }
        end
    end
    objectiveCache[id] = out
end

function SurvivalBook.ListObjectives(src, opts)
    local id = BookDB.Ident(src)
    if not id then return {} end
    opts = type(opts) == 'table' and opts or {}
    if not objectiveCache[id] then SurvivalBook.LoadObjectives(src) end
    local out = {}
    for i, row in ipairs(objectiveCache[id] or {}) do
        out[i] = {
            id = row.id, kind = row.kind, title = row.title,
            payload = row.payload or {}, done = row.done and true or false,
            createdAt = row.createdAt,
        }
    end
    if opts.skipLive then return out end

    -- Reconstruct gather/skill/blueprint LIVE. Do NOT UPDATE SQL on dashboard paint.
    for i = 1, #out do
        local o = out[i]
        if o.kind == 'recipe' and o.payload and o.payload.recipeId then
            local kids = SurvivalBook.LiveObjectiveChildren(src, o.payload.recipeId, o.id)
            o.children = kids
            o.subObjectives = kids
        end
    end
    return out
end

function SurvivalBook.CompleteObjective(src, objId)
    local id = BookDB.Ident(src)
    if not id then return false end
    objId = tonumber(objId)
    if not objId then return false end
    local aff = MySQL.update.await(
        'UPDATE sanctuary_book_objectives SET done = 1 WHERE id = ? AND identifier = ?',
        { objId, id }
    )
    if aff and aff > 0 then
        if objectiveCache[id] then
            for _, o in ipairs(objectiveCache[id]) do
                if o.id == objId then o.done = true break end
            end
        end
        SurvivalBook.PushHistory(id, 'objective_completed', { id = objId })
        TriggerClientEvent('sanctuary_crafting:book:objectiveCompleted', src, objId)
        TriggerEvent('sanctuary_crafting:book:objectiveCompleted', src, objId)
        SurvivalBook.Notify(src, 'book_objective_done', 'success')
        return true
    end
    return false
end

function SurvivalBook.RemoveObjective(src, objId)
    local id = BookDB.Ident(src)
    if not id then return false end
    MySQL.query.await('DELETE FROM sanctuary_book_objectives WHERE id = ? AND identifier = ?', { tonumber(objId), id })
    if objectiveCache[id] then
        local nid = tonumber(objId)
        local kept = {}
        for _, o in ipairs(objectiveCache[id]) do
            if o.id ~= nid then kept[#kept + 1] = o end
        end
        objectiveCache[id] = kept
    end
    return true
end

--------------------------------------------------------------------------------
-- Pins
--------------------------------------------------------------------------------
function SurvivalBook.LoadPins(src)
    local id = BookDB.Ident(src)
    if not id then return end
    pinCache[id] = {}
    local rows = MySQL.query.await(
        'SELECT recipe_id FROM sanctuary_book_pins WHERE identifier = ? ORDER BY sort_order ASC, created_at ASC',
        { id }
    ) or {}
    for i = 1, #rows do pinCache[id][i] = rows[i].recipe_id end
end

function SurvivalBook.ListPins(src)
    local id = BookDB.Ident(src)
    if not id then return {} end
    if not pinCache[id] then SurvivalBook.LoadPins(src) end
    local out = {}
    for i, rid in ipairs(pinCache[id] or {}) do
        local r = Config.RecipeById and Config.RecipeById[rid]
        out[i] = {
            recipeId = rid,
            label = r and r.label or rid,
            category = r and r.category or nil,
        }
    end
    return out
end

function SurvivalBook.PinRecipe(src, recipeId)
    if not BookDB.Mod('Pins') then return false, 'book_pins_disabled' end
    local recipe = Config.RecipeById and Config.RecipeById[recipeId]
    if not recipe then return false, 'craft_invalid' end
    local id = BookDB.Ident(src)
    if not id then return false, 'craft_invalid' end
    if not pinCache[id] then SurvivalBook.LoadPins(src) end
    for _, rid in ipairs(pinCache[id]) do
        if rid == recipeId then return true, 'already' end
    end
    local maxP = (Config.Book and Config.Book.MaxPins) or 8
    if #pinCache[id] >= maxP then return false, 'book_pins_full' end
    MySQL.insert.await(
        'INSERT IGNORE INTO sanctuary_book_pins (identifier, recipe_id, sort_order) VALUES (?,?,?)',
        { id, recipeId, #pinCache[id] + 1 }
    )
    pinCache[id][#pinCache[id] + 1] = recipeId
    if Config.Follow and Config.Follow.AutoObjectives ~= false then
        SurvivalBook.AddObjectiveFromRecipe(src, recipeId, { withMissing = true })
    end
    TriggerClientEvent('sanctuary_crafting:book:pinsUpdated', src, SurvivalBook.ListPins(src))
    return true
end

function SurvivalBook.UnpinRecipe(src, recipeId)
    local id = BookDB.Ident(src)
    if not id then return false end
    MySQL.query.await('DELETE FROM sanctuary_book_pins WHERE identifier = ? AND recipe_id = ?', { id, recipeId })
    SurvivalBook.LoadPins(src)
    TriggerClientEvent('sanctuary_crafting:book:pinsUpdated', src, SurvivalBook.ListPins(src))
    return true
end

--------------------------------------------------------------------------------
-- Notes
--------------------------------------------------------------------------------
function SurvivalBook.LoadNotes(src)
    local id = BookDB.Ident(src)
    if not id then return end
    local rows = MySQL.query.await(
        'SELECT id, title, body, checklist, UNIX_TIMESTAMP(updated_at) AS ts FROM sanctuary_book_notes WHERE identifier = ? ORDER BY updated_at DESC',
        { id }
    ) or {}
    local out = {}
    for i = 1, #rows do
        out[i] = {
            id = rows[i].id, title = rows[i].title, body = rows[i].body,
            checklist = jdec(rows[i].checklist, {}), updatedAt = rows[i].ts,
        }
    end
    noteCache[id] = out
end

function SurvivalBook.ListNotes(src)
    if not BookDB.Mod('Notes') then return {} end
    local id = BookDB.Ident(src)
    if not id then return {} end
    if not noteCache[id] then SurvivalBook.LoadNotes(src) end
    return noteCache[id] or {}
end

function SurvivalBook.SaveNote(src, data)
    if not BookDB.Mod('Notes') then return nil, 'book_notes_disabled' end
    local id = BookDB.Ident(src)
    if not id or type(data) ~= 'table' then return nil, 'craft_invalid' end
    local title = tostring(data.title or 'Note'):sub(1, 128)
    local body = tostring(data.body or ''):sub(1, 8000)
    local checklist = type(data.checklist) == 'table' and data.checklist or {}
    if not noteCache[id] then SurvivalBook.LoadNotes(src) end
    if data.id then
        MySQL.update.await(
            'UPDATE sanctuary_book_notes SET title=?, body=?, checklist=? WHERE id=? AND identifier=?',
            { title, body, jenc(checklist), tonumber(data.id), id }
        )
        local note = { id = tonumber(data.id), title = title, body = body, checklist = checklist, updatedAt = os.time() }
        for i, n in ipairs(noteCache[id] or {}) do
            if n.id == note.id then noteCache[id][i] = note break end
        end
        return note
    end
    local maxN = (Config.Book and Config.Book.MaxNotes) or 64
    if #(noteCache[id] or {}) >= maxN then return nil, 'book_notes_full' end
    local nid = MySQL.insert.await(
        'INSERT INTO sanctuary_book_notes (identifier, title, body, checklist) VALUES (?,?,?,?)',
        { id, title, body, jenc(checklist) }
    )
    local note = { id = nid, title = title, body = body, checklist = checklist, updatedAt = os.time() }
    table.insert(noteCache[id], 1, note)
    return note
end

function SurvivalBook.DeleteNote(src, noteId)
    local id = BookDB.Ident(src)
    if not id then return false end
    MySQL.query.await('DELETE FROM sanctuary_book_notes WHERE id = ? AND identifier = ?', { tonumber(noteId), id })
    if noteCache[id] then
        local nid = tonumber(noteId)
        local kept = {}
        for _, n in ipairs(noteCache[id]) do
            if n.id ~= nid then kept[#kept + 1] = n end
        end
        noteCache[id] = kept
    end
    return true
end

--------------------------------------------------------------------------------
-- Artisans (qualitative tiers only — never exact skill levels of others)
--------------------------------------------------------------------------------
function SurvivalBook.AddArtisanContact(src, contact)
    if not BookDB.Mod('Artisans') then return false, 'book_artisans_disabled' end
    local id = BookDB.Ident(src)
    if not id or type(contact) ~= 'table' then return false, 'craft_invalid' end
    local contactId = tostring(contact.contactId or contact.id or '')
    local displayName = tostring(contact.displayName or contact.name or ''):sub(1, 64)
    if contactId == '' or displayName == '' then return false, 'craft_invalid' end
    -- Never store exact levels/licenses/inventories of others
    local tier = contact.tier -- qualitative: novice|capable|seasoned|master|unknown
    if tier and not ({ novice=true, capable=true, seasoned=true, master=true, unknown=true })[tier] then
        tier = 'unknown'
    end
    local specialty = contact.specialty and tostring(contact.specialty):sub(1, 32) or nil
    local source = contact.source or 'meet'
    local meta = {
        note = contact.note and tostring(contact.note):sub(1, 200) or nil,
        -- intentionally omit levels / inventory / blueprints
    }
    MySQL.query.await([[
        INSERT INTO sanctuary_book_artisans (identifier, contact_id, display_name, specialty, tier, source, meta)
        VALUES (?,?,?,?,?,?,?)
        ON DUPLICATE KEY UPDATE display_name=VALUES(display_name), specialty=VALUES(specialty),
            tier=COALESCE(VALUES(tier), tier), source=VALUES(source), meta=VALUES(meta)
    ]], { id, contactId, displayName, specialty, tier, source, jenc(meta) })
    SurvivalBook.PushHistory(id, 'artisan_met', { contactId = contactId, name = displayName, specialty = specialty, tier = tier })
    artisanCache[id] = nil -- invalidate; next List reloads
    TriggerClientEvent('sanctuary_crafting:book:artisanMet', src, contactId, displayName)
    TriggerEvent('sanctuary_crafting:book:artisanMet', src, contactId, displayName)
    SurvivalBook.Notify(src, 'book_artisan_met', 'inform', { displayName })
    return true
end

function SurvivalBook.LoadArtisans(src)
    local id = BookDB.Ident(src)
    if not id then return end
    local rows = MySQL.query.await(
        'SELECT contact_id, display_name, specialty, tier, source, meta, UNIX_TIMESTAMP(met_at) AS ts FROM sanctuary_book_artisans WHERE identifier = ? ORDER BY met_at DESC',
        { id }
    ) or {}
    local out = {}
    for i = 1, #rows do
        out[i] = {
            contactId = rows[i].contact_id,
            displayName = rows[i].display_name,
            specialty = rows[i].specialty,
            tier = rows[i].tier or 'unknown',
            source = rows[i].source,
            meta = jdec(rows[i].meta, {}),
            metAt = rows[i].ts,
        }
    end
    artisanCache[id] = out
end

function SurvivalBook.ListArtisans(src)
    local id = BookDB.Ident(src)
    if not id then return {} end
    if not artisanCache[id] then SurvivalBook.LoadArtisans(src) end
    return artisanCache[id] or {}
end

function SurvivalBook.NetworkBySpecialty(src)
    if not BookDB.Mod('Network') then return {} end
    local list = SurvivalBook.ListArtisans(src)
    local net = {}
    for i = 1, #list do
        local sp = list[i].specialty or 'general'
        net[sp] = net[sp] or {}
        net[sp][#net[sp] + 1] = list[i]
    end
    return net
end

--------------------------------------------------------------------------------
-- Orders (no item teleport — RP exchange only)
--------------------------------------------------------------------------------
function SurvivalBook.CreateOrder(src, data)
    if not BookDB.Mod('Orders') then return nil, 'book_orders_disabled' end
    local cfg = Config.Book.Orders or {}
    if cfg.AllowTeleport then
        -- hard refuse teleport even if misconfigured
        cfg.AllowTeleport = false
    end
    local id = BookDB.Ident(src)
    if not id or type(data) ~= 'table' then return nil, 'craft_invalid' end
    local maxO = (Config.Book and Config.Book.MaxOrders) or 20
    if not orderCache[id] then SurvivalBook.LoadOrders(src) end
    local count = 0
    for _, o in ipairs(orderCache[id] or {}) do
        if o.status == 'open' then count = count + 1 end
    end
    if count >= maxO then return nil, 'book_orders_full' end
    local uid = GenerateCraftId()
    local items = type(data.items) == 'table' and data.items or {}
    local recipeId = data.recipeId
    if recipeId and not (Config.RecipeById and Config.RecipeById[recipeId]) then
        return nil, 'craft_invalid'
    end
    MySQL.insert.await(
        'INSERT INTO sanctuary_book_orders (order_uid, owner, target_contact, recipe_id, items, status, note) VALUES (?,?,?,?,?,?,?)',
        { uid, id, data.targetContact, recipeId, jenc(items), 'open', data.note and tostring(data.note):sub(1, 255) or nil }
    )
    SurvivalBook.PushHistory(id, 'order_created', { orderUid = uid, recipeId = recipeId })
    local order = { orderUid = uid, status = 'open', items = items, recipeId = recipeId, targetContact = data.targetContact, note = data.note, createdAt = os.time(), teleport = false }
    if orderCache[id] then table.insert(orderCache[id], 1, order) end
    return order
end

function SurvivalBook.LoadOrders(src)
    local id = BookDB.Ident(src)
    if not id then return end
    local rows = MySQL.query.await(
        'SELECT order_uid, target_contact, recipe_id, items, status, note, UNIX_TIMESTAMP(created_at) AS ts FROM sanctuary_book_orders WHERE owner = ? ORDER BY id DESC LIMIT 40',
        { id }
    ) or {}
    local out = {}
    for i = 1, #rows do
        out[i] = {
            orderUid = rows[i].order_uid,
            targetContact = rows[i].target_contact,
            recipeId = rows[i].recipe_id,
            items = jdec(rows[i].items, {}),
            status = rows[i].status,
            note = rows[i].note,
            createdAt = rows[i].ts,
            teleport = false,
        }
    end
    orderCache[id] = out
end

function SurvivalBook.ListOrders(src)
    local id = BookDB.Ident(src)
    if not id then return {} end
    if not orderCache[id] then SurvivalBook.LoadOrders(src) end
    return orderCache[id] or {}
end

function SurvivalBook.SetOrderStatus(src, orderUid, status)
    local id = BookDB.Ident(src)
    if not id then return false end
    if not ({ open=true, fulfilled=true, cancelled=true })[status] then return false end
    MySQL.update.await(
        'UPDATE sanctuary_book_orders SET status = ? WHERE order_uid = ? AND owner = ?',
        { status, orderUid, id }
    )
    if orderCache[id] then
        for _, o in ipairs(orderCache[id]) do
            if o.orderUid == orderUid then o.status = status break end
        end
    end
    return true
end

--------------------------------------------------------------------------------
-- History / Discoveries timeline
--------------------------------------------------------------------------------
function SurvivalBook.LoadHistoryCount(src)
    local id = BookDB.Ident(src)
    if not id then return end
    historyCount[id] = MySQL.scalar.await(
        'SELECT COUNT(*) FROM sanctuary_book_history WHERE identifier = ?', { id }
    ) or 0
end

function SurvivalBook.HistoryCount(src)
    local id = BookDB.Ident(src)
    if not id then return 0 end
    if historyCount[id] == nil then SurvivalBook.LoadHistoryCount(src) end
    return historyCount[id] or 0
end

function SurvivalBook.ListHistory(src, limit)
    local id = BookDB.Ident(src)
    if not id then return {} end
    limit = math.min(tonumber(limit) or 40, 100)
    local rows = MySQL.query.await(
        'SELECT id, event_type, payload, UNIX_TIMESTAMP(created_at) AS ts FROM sanctuary_book_history WHERE identifier = ? ORDER BY id DESC LIMIT ?',
        { id, limit }
    ) or {}
    local out = {}
    for i = 1, #rows do
        out[i] = {
            id = rows[i].id,
            type = rows[i].event_type,
            payload = jdec(rows[i].payload, {}),
            at = rows[i].ts,
        }
    end
    return out
end

function SurvivalBook.WarmCaches(src)
    SurvivalBook.LoadDiscoveries(src)
    SurvivalBook.LoadPins(src)
    SurvivalBook.LoadArtisans(src)
    SurvivalBook.LoadOrders(src)
    SurvivalBook.LoadNotes(src)
    SurvivalBook.LoadObjectives(src)
    SurvivalBook.LoadHistoryCount(src)
end

function SurvivalBook.CacheSizes(src)
    local id = BookDB.Ident(src)
    if not id then
        return { resources = 0, objectivesOpen = 0, objectivesDone = 0, pins = 0, notes = 0, artisans = 0, orders = 0, history = 0 }
    end
    if not discoveredCache[id] then SurvivalBook.LoadDiscoveries(src) end
    if not pinCache[id] then SurvivalBook.LoadPins(src) end
    if not artisanCache[id] then SurvivalBook.LoadArtisans(src) end
    if not orderCache[id] then SurvivalBook.LoadOrders(src) end
    if not noteCache[id] then SurvivalBook.LoadNotes(src) end
    if not objectiveCache[id] then SurvivalBook.LoadObjectives(src) end
    if historyCount[id] == nil then SurvivalBook.LoadHistoryCount(src) end
    local open, done = 0, 0
    for _, o in ipairs(objectiveCache[id] or {}) do
        if o.done then done = done + 1 else open = open + 1 end
    end
    local resources = 0
    for _ in pairs(discoveredCache[id] or {}) do resources = resources + 1 end
    return {
        resources = resources,
        objectivesOpen = open,
        objectivesDone = done,
        pins = #(pinCache[id] or {}),
        notes = #(noteCache[id] or {}),
        artisans = #(artisanCache[id] or {}),
        orders = #(orderCache[id] or {}),
        history = historyCount[id] or 0,
    }
end

AddEventHandler('playerDropped', function()
    local src = source
    notifCooldown[src] = nil
    local id = BookDB.Ident(src)
    if not id then return end
    discoveredCache[id] = nil
    pinCache[id] = nil
    artisanCache[id] = nil
    orderCache[id] = nil
    noteCache[id] = nil
    objectiveCache[id] = nil
    historyCount[id] = nil
end)

AddEventHandler('esx:playerLoaded', function(playerId)
    local src = type(playerId) == 'number' and playerId or source
    SurvivalBook.WarmCaches(src)
end)

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, sid in ipairs(GetPlayers()) do
        local src = tonumber(sid)
        if src then
            SurvivalBook.WarmCaches(src)
        end
    end
end)
