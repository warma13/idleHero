-- ============================================================================
-- state/equip/Materials.lua — 材料管理 & 背包容量
-- v5.0: D4 多材料体系 (iron/crystal/wraith/eternal/abyssHeart/riftEcho)
-- ============================================================================

local M = {}

---@param GS table GameState
---@param ctx table { Config }
function M.Install(GS, ctx)
    local Config = ctx.Config

    -- ================================================================
    -- 通用材料 API (替代旧版 AddStone/GetStone)
    -- ================================================================

    --- 增加指定材料
    ---@param matId string 材料ID (iron/crystal/wraith/eternal/abyssHeart/riftEcho)
    ---@param amount number 数量
    function GS.AddMaterial(matId, amount)
        if not matId or not amount or amount == 0 then return end
        GS.materials[matId] = (GS.materials[matId] or 0) + amount
    end

    --- 获取指定材料数量
    ---@param matId string 材料ID
    ---@return number
    function GS.GetMaterial(matId)
        return GS.materials[matId] or 0
    end

    --- 批量增加材料 (从材料表)
    ---@param matTable table { [materialId] = amount }
    function GS.AddMaterials(matTable)
        if not matTable then return end
        for matId, amount in pairs(matTable) do
            if amount > 0 then
                GS.materials[matId] = (GS.materials[matId] or 0) + amount
            end
        end
    end

    --- 检查是否有足够的材料
    ---@param matTable table { [materialId] = amount }
    ---@return boolean ok
    ---@return string|nil reason 不足时返回缺少的材料描述
    function GS.HasMaterials(matTable)
        if not matTable then return true, nil end
        for matId, needed in pairs(matTable) do
            local have = GS.materials[matId] or 0
            if have < needed then
                local matDef = Config.MATERIAL_MAP[matId]
                local matName = matDef and matDef.name or matId
                return false, matName .. "不足 (" .. have .. "/" .. needed .. ")"
            end
        end
        return true, nil
    end

    --- 批量扣除材料
    ---@param matTable table { [materialId] = amount }
    ---@return boolean ok
    ---@return string|nil reason
    function GS.SpendMaterials(matTable)
        local ok, reason = GS.HasMaterials(matTable)
        if not ok then return false, reason end
        for matId, amount in pairs(matTable) do
            GS.materials[matId] = (GS.materials[matId] or 0) - amount
        end
        return true, nil
    end

    -- ================================================================
    -- 旧版兼容 API (转发到通用材料 API)
    -- ================================================================

    function GS.AddStone(amount)
        -- 旧版强化石 → 映射到 iron
        GS.AddMaterial("iron", amount)
    end

    function GS.GetStone()
        -- 返回 iron 数量作为兼容值
        return GS.GetMaterial("iron")
    end

    -- ================================================================
    -- 魂晶 (保持独立, 不属于 D4 材料体系)
    -- ================================================================

    function GS.AddSoulCrystal(amount)
        GS.materials.soulCrystal = GS.materials.soulCrystal + (amount or 1)
    end

    function GS.GetSoulCrystal()
        return GS.materials.soulCrystal or 0
    end

    -- ================================================================
    -- 背包容量
    -- ================================================================

    function GS.GetInventorySize()
        return Config.INVENTORY_SIZE + (GS.expandCount or 0) * Config.INVENTORY_EXPAND_SLOTS
    end

    function GS.GetExpandCost()
        local n = (GS.expandCount or 0) + 1
        return Config.EXPAND_BASE_COST + (n - 1) * Config.EXPAND_COST_INCREMENT
    end

    function GS.ExpandInventory()
        local curSize = GS.GetInventorySize()
        if curSize >= Config.INVENTORY_MAX_SIZE then
            return false, "背包已达上限 " .. Config.INVENTORY_MAX_SIZE .. " 格"
        end
        local cost = GS.GetExpandCost()
        local cur = GS.GetSoulCrystal()
        if cur < cost then
            return false, "魂晶不足 (" .. cur .. "/" .. cost .. ")"
        end
        GS.materials.soulCrystal = GS.materials.soulCrystal - cost
        GS.expandCount = (GS.expandCount or 0) + 1
        print("[GameState] Inventory expanded to " .. GS.GetInventorySize() .. " slots (cost " .. cost .. " soul crystals)")
        return true, nil
    end
end

return M
