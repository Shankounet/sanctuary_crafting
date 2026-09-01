BenchTypes = {
    scrap = true,
    medical = true,
    weapons = true,
    survival = true,
    mechanic = true, -- station v2 example type
}

---@param category string
---@return boolean
function IsValidBenchCategory(category)
    return BenchTypes[category] == true
end

---@param category string
---@return number|nil
function GetBenchModel(category)
    return Config.BenchModels and Config.BenchModels[category]
end
