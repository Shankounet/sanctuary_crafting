--[[
    systems/signature.lua — none | batch | individual
    Default batch: shared LOT + craftedBy RP + date + station + quality.
    STOP unique craftUID on stackable consumables (splits ox stacks).
]]

CraftSignature = CraftSignature or {}

local seq = 0

local PREFIX = {
    medical = 'MED', medecin = 'MED', armurier = 'ARM', weapons = 'ARM',
    munition = 'MUN', forgeron = 'FRG', fonderie_forgeron = 'FND',
    manche_forgeron = 'MCH', reparation_forgeron = 'REP',
    ingenieur = 'ING', mecano = 'MEC', mechanic = 'MEC',
    cuisine = 'CUI', agriculture = 'AGR', boucherie = 'BCH',
    survie = 'SRV', survival = 'SRV', tailleur = 'TLR',
    construction = 'CST', decoration = 'DEC', schema = 'SCH',
    accessoires = 'ACC', scrap = 'SCP',
}

local function rpName(src)
    local xPlayer = ESX and ESX.GetPlayerFromId and ESX.GetPlayerFromId(src)
    if xPlayer then
        if xPlayer.getName then
            local n = xPlayer.getName()
            if type(n) == 'string' and n ~= '' then return n end
        end
        local fn = xPlayer.get and xPlayer.get('firstName')
        local ln = xPlayer.get and xPlayer.get('lastName')
        if type(fn) == 'string' and fn ~= '' then
            return (fn .. ' ' .. (type(ln) == 'string' and ln or '')):gsub('%s+$', '')
        end
    end
    return GetPlayerName(src) or 'Inconnu'
end

local function prefixOf(recipe, bench)
    local key = (bench and (bench.station or bench.category)) or (recipe and (recipe.station or recipe.category)) or 'NG'
    return PREFIX[key] or string.upper(string.sub(tostring(key), 1, 3))
end

local function newLot(recipe, bench)
    seq = (seq % 9999) + 1
    local d = os.date('%y%m%d')
    return ('%s-%s-%04d'):format(prefixOf(recipe, bench), d, seq)
end

local function isStackable(item)
    if OxItemCatalog and OxItemCatalog.IsStackable then
        return OxItemCatalog.IsStackable(item)
    end
    return true
end

function CraftSignature.Mode(recipe)
    local cfg = Config.Signature or {}
    if cfg.Enabled == false then return 'none' end
    if not recipe then return cfg.DefaultMode or 'batch' end
    if type(recipe.signatureMode) == 'string' and recipe.signatureMode ~= '' then
        local m = recipe.signatureMode
        if m == 'none' or m == 'batch' or m == 'individual' then return m end
    end
    if recipe.trackCrafter == false and recipe.trackLot == false then
        return 'none'
    end
    if recipe.trackCrafter == 'individual' or recipe.individualSignature == true then
        return 'individual'
    end
    if recipe.trackLot == false and recipe.trackCrafter == false then
        return 'none'
    end
    return cfg.DefaultMode or 'batch'
end

local function describe(meta)
    local bits = {}
    if meta.lot then bits[#bits + 1] = 'LOT ' .. meta.lot end
    if meta.quality then bits[#bits + 1] = tostring(meta.quality) end
    if meta.craftedBy then bits[#bits + 1] = meta.craftedBy end
    if meta.craftedDate then bits[#bits + 1] = meta.craftedDate end
    if meta.station then bits[#bits + 1] = meta.station end
    if #bits == 0 then return nil end
    return table.concat(bits, ' · ')
end

function CraftSignature.Build(src, recipe, bench, quality, craftId)
    local mode = CraftSignature.Mode(recipe)
    local item = recipe and recipe.result and recipe.result.item
    local stackable = item and isStackable(item) ~= false
    local meta = {}
    local dateStr = os.date('%Y-%m-%d')
    local stationLabel = (bench and (bench.label or bench.station or bench.category)) or (recipe and (recipe.station or recipe.category))

    if quality then meta.quality = quality end

    if mode == 'none' then
        return meta, mode
    end

    local trackCrafter = recipe.trackCrafter ~= false
    local trackLot = recipe.trackLot ~= false
    if trackLot then
        meta.lot = newLot(recipe, bench)
    end
    if trackCrafter then
        meta.craftedBy = rpName(src)
    end
    meta.craftedDate = dateStr
    if stationLabel then meta.station = stationLabel end

    if mode == 'individual' and not stackable then
        meta.craftUID = craftId
    end

    local desc = describe(meta)
    if desc then meta.description = desc end
    return meta, mode
end

function CraftSignature.GiveResult(src, recipe, bench, quality, craftId, count)
    count = math.max(1, math.floor(tonumber(count) or 1))
    local item = recipe.result.item
    local mode = CraftSignature.Mode(recipe)
    local stackable = isStackable(item) ~= false

    if mode == 'individual' and not stackable then
        local given = 0
        for i = 1, count do
            local meta = CraftSignature.Build(src, recipe, bench, quality, (craftId or 'c') .. ':' .. i)
            if not Validation.CanCarry(src, item, 1) then
                break
            end
            local added = exports.ox_inventory:AddItem(src, item, 1, meta)
            if not added then break end
            given = given + 1
        end
        return given == count, given
    end

    local meta = CraftSignature.Build(src, recipe, bench, quality, craftId)
    if not Validation.CanCarry(src, item, count) then
        return false, 0
    end
    local added = exports.ox_inventory:AddItem(src, item, count, meta)
    if not added then return false, 0 end
    return true, count, meta
end
