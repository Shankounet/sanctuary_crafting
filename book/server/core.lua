--[[
    book/server/core.lua — discoveries / objectives / pins / notes / artisans / orders / history / prefs
    Server-authoritative. No GPS. No other players' exact skills/inventories/licenses.
]]

SurvivalBook = SurvivalBook or {}

local discoveredCache = {} -- [ident] = { [item]=true }
local pinCache = {}        -- [ident] = { recipeId, ... }
local notifCooldown = {}     -- [src] = lastMs

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
    -- Prefer ox_inventory label when available
    local ok, data = pcall(function()
        return exports.ox_inventory:Items(item)
    end)
    if ok and type(data) == 'table' and data.label then
        return data.label
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
    MySQL.insert.await(
        'INSERT INTO sanctuary_book_history (identifier, event_type, payload) VALUES (?,?,?)',
        { ident, eventType, jenc(payload) }
    )
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
        'SELECT item FROM sanctuary_book_discovered_resources WHERE identifier = ?', { id }
    ) or {}
    for i = 1, #rows do
        discoveredCache[id][rows[i].item] = true
    end
end

function SurvivalBook.HasDiscoveredResource(src, item)
    if not item then return false end
    local id = BookDB.Ident(src)
    if not id then return false end
    if not discoveredCache[id] then SurvivalBook.LoadDiscoveries(src) end
    return discoveredCache[id] and discoveredCache[id][item] == true
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

    local lab = label or itemLabel(item)
    MySQL.insert.await(
        'INSERT IGNORE INTO sanctuary_book_discovered_resources (identifier, item, label) VALUES (?,?,?)',
        { id, item, lab }
    )
    discoveredCache[id][item] = true
    SurvivalBook.PushHistory(id, 'resource_discovered', { item = item, label = lab, reason = reason })
    TriggerClientEvent('sanctuary_crafting:book:resourceDiscovered', src, item, lab)
    TriggerEvent('sanctuary_crafting:book:resourceDiscovered', src, item, lab)
    SurvivalBook.Notify(src, 'book_resource_discovered', 'success', { lab or item })
    return true
end

function SurvivalBook.ListResources(src)
    local id = BookDB.Ident(src)
    if not id then return {} end
    local rows = MySQL.query.await(
        'SELECT item, label, UNIX_TIMESTAMP(discovered_at) AS ts FROM sanctuary_book_discovered_resources WHERE identifier = ? ORDER BY discovered_at DESC',
        { id }
    ) or {}
    local out = {}
    for i = 1, #rows do
        out[i] = { item = rows[i].item, label = rows[i].label or rows[i].item, discoveredAt = rows[i].ts }
    end
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
    local maxO = (Config.Book and Config.Book.MaxObjectives) or 24
    local count = MySQL.scalar.await(
        'SELECT COUNT(*) FROM sanctuary_book_objectives WHERE identifier = ? AND done = 0', { id }
    ) or 0
    if count >= maxO then return nil, 'book_objectives_full' end
    local insertId = MySQL.insert.await(
        'INSERT INTO sanctuary_book_objectives (identifier, kind, title, payload, done) VALUES (?,?,?,?,0)',
        { id, kind, title, jenc(payload or {}) }
    )
    SurvivalBook.PushHistory(id, 'objective_added', { id = insertId, title = title, kind = kind })
    return { id = insertId, title = title, kind = kind, done = false, payload = payload or {} }
end

function SurvivalBook.AddObjectiveFromRecipe(src, recipeId)
    local recipe = Config.RecipeById and Config.RecipeById[recipeId]
    if not recipe then return nil, 'craft_invalid' end
    return SurvivalBook.AddObjective(src, recipe.label or recipeId, 'recipe', { recipeId = recipeId })
end

function SurvivalBook.ListObjectives(src)
    local id = BookDB.Ident(src)
    if not id then return {} end
    local rows = MySQL.query.await(
        'SELECT id, kind, title, payload, done, UNIX_TIMESTAMP(created_at) AS ts FROM sanctuary_book_objectives WHERE identifier = ? ORDER BY done ASC, id DESC',
        { id }
    ) or {}
    local out = {}
    for i = 1, #rows do
        out[i] = {
            id = rows[i].id, kind = rows[i].kind, title = rows[i].title,
            payload = jdec(rows[i].payload, {}), done = rows[i].done == 1,
            createdAt = rows[i].ts,
        }
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
function SurvivalBook.ListNotes(src)
    if not BookDB.Mod('Notes') then return {} end
    local id = BookDB.Ident(src)
    if not id then return {} end
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
    return out
end

function SurvivalBook.SaveNote(src, data)
    if not BookDB.Mod('Notes') then return nil, 'book_notes_disabled' end
    local id = BookDB.Ident(src)
    if not id or type(data) ~= 'table' then return nil, 'craft_invalid' end
    local title = tostring(data.title or 'Note'):sub(1, 128)
    local body = tostring(data.body or ''):sub(1, 8000)
    local checklist = type(data.checklist) == 'table' and data.checklist or {}
    if data.id then
        MySQL.update.await(
            'UPDATE sanctuary_book_notes SET title=?, body=?, checklist=? WHERE id=? AND identifier=?',
            { title, body, jenc(checklist), tonumber(data.id), id }
        )
        return { id = tonumber(data.id), title = title, body = body, checklist = checklist }
    end
    local maxN = (Config.Book and Config.Book.MaxNotes) or 64
    local count = MySQL.scalar.await('SELECT COUNT(*) FROM sanctuary_book_notes WHERE identifier = ?', { id }) or 0
    if count >= maxN then return nil, 'book_notes_full' end
    local nid = MySQL.insert.await(
        'INSERT INTO sanctuary_book_notes (identifier, title, body, checklist) VALUES (?,?,?,?)',
        { id, title, body, jenc(checklist) }
    )
    return { id = nid, title = title, body = body, checklist = checklist }
end

function SurvivalBook.DeleteNote(src, noteId)
    local id = BookDB.Ident(src)
    if not id then return false end
    MySQL.query.await('DELETE FROM sanctuary_book_notes WHERE id = ? AND identifier = ?', { tonumber(noteId), id })
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
    TriggerClientEvent('sanctuary_crafting:book:artisanMet', src, contactId, displayName)
    TriggerEvent('sanctuary_crafting:book:artisanMet', src, contactId, displayName)
    SurvivalBook.Notify(src, 'book_artisan_met', 'inform', { displayName })
    return true
end

function SurvivalBook.ListArtisans(src)
    local id = BookDB.Ident(src)
    if not id then return {} end
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
    return out
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
    local count = MySQL.scalar.await(
        "SELECT COUNT(*) FROM sanctuary_book_orders WHERE owner = ? AND status = 'open'", { id }
    ) or 0
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
    return { orderUid = uid, status = 'open', items = items, recipeId = recipeId, targetContact = data.targetContact, note = data.note }
end

function SurvivalBook.ListOrders(src)
    local id = BookDB.Ident(src)
    if not id then return {} end
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
            teleport = false, -- always false
        }
    end
    return out
end

function SurvivalBook.SetOrderStatus(src, orderUid, status)
    local id = BookDB.Ident(src)
    if not id then return false end
    if not ({ open=true, fulfilled=true, cancelled=true })[status] then return false end
    MySQL.update.await(
        'UPDATE sanctuary_book_orders SET status = ? WHERE order_uid = ? AND owner = ?',
        { status, orderUid, id }
    )
    return true
end

--------------------------------------------------------------------------------
-- History / Discoveries timeline
--------------------------------------------------------------------------------
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

AddEventHandler('playerDropped', function()
    local src = source
    notifCooldown[src] = nil
end)

AddEventHandler('esx:playerLoaded', function(playerId)
    local src = type(playerId) == 'number' and playerId or source
    SurvivalBook.LoadDiscoveries(src)
    SurvivalBook.LoadPins(src)
end)

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, sid in ipairs(GetPlayers()) do
        local src = tonumber(sid)
        if src then
            SurvivalBook.LoadDiscoveries(src)
            SurvivalBook.LoadPins(src)
        end
    end
end)
