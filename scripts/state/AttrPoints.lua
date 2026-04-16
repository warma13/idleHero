-- ============================================================================
-- state/AttrPoints.lua - 属性加点系统 (Install 模式注入 GameState)
-- ============================================================================

local Config = require("Config")

local M = {}

function M.Install(GS)

    --- 获取已分配的属性点总数
    function GS.GetTotalAllocatedPoints()
        local total = 0
        for _, v in pairs(GS.player.allocatedPoints) do
            total = total + v
        end
        return total
    end

    --- 计算重置属性点的魂晶消耗
    function GS.GetResetAttrCost()
        return GS.GetTotalAllocatedPoints() * Config.RESET_ATTR_UNIT_COST
    end

    --- 重置属性点 (全部回收)
    --- @return boolean success, string|nil reason
    function GS.ResetAttributePoints()
        local allocated = GS.GetTotalAllocatedPoints()
        if allocated <= 0 then return false, "没有已分配的属性点" end
        local cost = GS.GetResetAttrCost()
        local cur = GS.GetSoulCrystal()
        if cur < cost then
            return false, "魂晶不足 (" .. cur .. "/" .. cost .. ")"
        end
        -- 扣除魂晶
        GS.materials.soulCrystal = GS.materials.soulCrystal - cost
        -- 回收点数
        local p = GS.player
        for stat, pts in pairs(p.allocatedPoints) do
            p.freePoints = p.freePoints + pts
            p.allocatedPoints[stat] = 0
        end
        -- 重置HP到满血 (因为VIT清零会降低上限)
        GS.ResetHP()
        print("[GameState] Reset attribute points, returned " .. allocated .. " pts, cost " .. cost .. " soul crystals")
        return true, nil
    end

    --- 分配属性点
    function GS.AllocatePoint(stat)
        local p = GS.player
        if p.freePoints <= 0 then return false end
        if not p.allocatedPoints[stat] then return false end
        p.allocatedPoints[stat] = p.allocatedPoints[stat] + 1
        p.freePoints = p.freePoints - 1
        return true
    end

    --- 批量加点 (一次加 count 点，实际加的数量受 freePoints 限制)
    ---@param stat string
    ---@param count integer
    ---@return integer actualCount 实际加了多少点
    function GS.AllocatePoints(stat, count)
        local p = GS.player
        if not p.allocatedPoints[stat] then return 0 end
        local actual = math.min(count, p.freePoints)
        if actual <= 0 then return 0 end
        p.allocatedPoints[stat] = p.allocatedPoints[stat] + actual
        p.freePoints = p.freePoints - actual
        return actual
    end

    --- 减少 1 点属性 (消耗 2 魂晶)
    ---@param stat string
    ---@return boolean success
    ---@return string|nil errMsg
    function GS.DeallocatePoint(stat)
        local p = GS.player
        if not p.allocatedPoints[stat] then return false, "无效属性" end
        if (p.allocatedPoints[stat] or 0) <= 0 then return false, "该属性无已分配点数" end
        local cost = 2
        local cur = GS.GetSoulCrystal()
        if cur < cost then return false, "魂晶不足 (" .. cur .. "/" .. cost .. ")" end
        GS.materials.soulCrystal = GS.materials.soulCrystal - cost
        p.allocatedPoints[stat] = p.allocatedPoints[stat] - 1
        p.freePoints = p.freePoints + 1
        return true
    end

    --- 批量减点 (一次减 count 点，每点消耗 2 魂晶)
    ---@param stat string
    ---@param count integer
    ---@return integer actualCount 实际减了多少点
    ---@return string|nil errMsg
    function GS.DeallocatePoints(stat, count)
        local p = GS.player
        if not p.allocatedPoints[stat] then return 0, "无效属性" end
        local allocated = p.allocatedPoints[stat] or 0
        if allocated <= 0 then return 0, "该属性无已分配点数" end
        local maxByPts = allocated
        local maxByCrystal = math.floor(GS.GetSoulCrystal() / 2)
        local actual = math.min(count, maxByPts, maxByCrystal)
        if actual <= 0 then return 0, "魂晶不足" end
        GS.materials.soulCrystal = GS.materials.soulCrystal - actual * 2
        p.allocatedPoints[stat] = p.allocatedPoints[stat] - actual
        p.freePoints = p.freePoints + actual
        return actual
    end
end

return M
