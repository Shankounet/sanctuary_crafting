--- Métadonnées bancs (partagées client/server)

BenchTypes = {
    scrap = true,
    medical = true,
    weapons = true,
    survival = true,
}

---@param category string
---@return boolean
function IsValidBenchCategory(category)
    return BenchTypes[category] == true
end

---@param category string
---@return number|nil hash
function GetBenchModel(category)
    return Config.BenchModels[category]
end
