--[[
    systems/batch.lua — SAME clamp helper for interactive craft AND queue
    MAX = min(mats, tools, energy, queue, recipe.batchMax or maxQuantity, Config.Batch.MaxBatch)
    Hard cap 50/100. No negative / overflow.
]]

CraftBatch = CraftBatch or {}

local HARD_CAP = 100

local function floorPos(n, fallback)
    n = tonumber(n)
    if not n or n ~= n or n < 0 then return fallback or 0 end
    if n > 1e9 then return 1e9 end
    return math.floor(n)
end

function CraftBatch.HardCap()
    local cfg = Config.Batch or {}
    local cap = floorPos(cfg.HardCap or cfg.MaxBatch or 50, 50)
    if cap < 1 then cap = 1 end
    if cap > HARD_CAP then cap = HARD_CAP end
    return cap
end

function CraftBatch.ConfiguredMax()
    local cfg = Config.Batch or {}
    if cfg.Enabled == false then return 1 end
    local maxB = floorPos(cfg.MaxBatch or 50, 50)
    local hard = CraftBatch.HardCap()
    if maxB < 1 then maxB = 1 end
    if maxB > hard then maxB = hard end
    return maxB
end

function CraftBatch.RecipeCap(recipe)
    if not recipe then return CraftBatch.ConfiguredMax() end
    local a = recipe.batchMax
    local b = recipe.maxQuantity
    local cap = CraftBatch.ConfiguredMax()
    if type(a) == 'number' then cap = math.min(cap, floorPos(a, cap)) end
    if type(b) == 'number' then cap = math.min(cap, floorPos(b, cap)) end
    if cap < 1 then cap = 1 end
    return cap
end

local function matsMax(src, recipe)
    local ings = recipe and recipe.ingredients
    if type(ings) ~= 'table' or #ings == 0 then return CraftBatch.ConfiguredMax() end
    local maxN = CraftBatch.ConfiguredMax()
    for i = 1, #ings do
        local need = floorPos(ings[i].count or 1, 1)
        if need < 1 then need = 1 end
        local have = 0
        if GetResourceState('ox_inventory') == 'started' then
            have = floorPos(exports.ox_inventory:GetItemCount(src, ings[i].item) or 0, 0)
        end
        local can = math.floor(have / need)
        if can < maxN then maxN = can end
    end
    return math.max(0, maxN)
end

local function toolsMax(src, recipe)
    if not Tools or not Tools.HasRecipe then return CraftBatch.ConfiguredMax() end
    if Tools.HasRecipe(src, recipe) then return CraftBatch.ConfiguredMax() end
    return 0
end

local function energyMax(bench, recipe)
    if not recipe or not recipe.powerCost or recipe.powerCost <= 0 then
        return CraftBatch.ConfiguredMax()
    end
    if CraftingPower and CraftingPower.CanRunRecipe and not CraftingPower.CanRunRecipe(bench, recipe) then
        return 0
    end
    return CraftBatch.ConfiguredMax()
end

local function queueMax(src, bench)
    if not Config.Queue or not Config.Queue.Enabled then
        return CraftBatch.ConfiguredMax()
    end
    local playerMax = floorPos(Config.Queue.MaxQueuePerPlayer or 5, 5)
    local benchCap = playerMax
    if bench then
        local extra = 0
        if StationRuntime and StationRuntime.Modifiers then
            extra = floorPos(StationRuntime.Modifiers(bench).queueSize or 0, 0)
        end
        if type(bench.queueSize) == 'number' then
            benchCap = floorPos(bench.queueSize, playerMax) + extra
        else
            benchCap = playerMax + extra
        end
    end
    local used = 0
    if CraftQueue and CraftQueue.CountForBench then
        used = CraftQueue.CountForBench(src, bench and bench.key)
    elseif CraftQueue and CraftQueue.List then
        used = #(CraftQueue.List(src) or {})
    end
    local free = math.max(0, math.min(playerMax, benchCap) - used)
    -- queue slot is 1 job, not batch units — batch itself is unbounded by slots
    if free <= 0 then return 0 end
    return CraftBatch.ConfiguredMax()
end

--- Limits used by MAX preset (and server clamp).
--- opts.queued: apply bench queue-slot cap (interactive crafts ignore it).
function CraftBatch.Limits(src, recipe, bench, opts)
    opts = opts or {}
    local recipeCap = CraftBatch.RecipeCap(recipe)
    local mats = matsMax(src, recipe)
    local tools = toolsMax(src, recipe)
    local energy = energyMax(bench, recipe)
    local queue = CraftBatch.ConfiguredMax()
    if opts.queued then
        queue = queueMax(src, bench)
    end
    local hard = CraftBatch.HardCap()
    local maxN = math.min(recipeCap, mats, tools, energy, queue, hard)
    if maxN < 0 then maxN = 0 end
    return {
        recipe = recipeCap,
        mats = mats,
        tools = tools,
        energy = energy,
        queue = queue,
        hard = hard,
        max = maxN,
    }
end

--- Clamp requested batch. Returns integer >= 1 (or 0 if nothing is possible).
function CraftBatch.Clamp(src, recipe, bench, batch, opts)
    local lim = CraftBatch.Limits(src, recipe, bench, opts)
    local n = floorPos(batch or 1, 1)
    if n < 1 then n = 1 end
    if n > lim.max then n = lim.max end
    if n < 1 then return 0, lim end
    return n, lim
end

function CraftBatch.SafeMul(a, b)
    a = floorPos(a, 0)
    b = floorPos(b, 0)
    if a <= 0 or b <= 0 then return 0 end
    if b > 0 and a > math.floor(1000000 / b) then
        return 1000000
    end
    return a * b
end
