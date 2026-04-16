-- ============================================================================
-- state/stats/UtilityStats.lua — 功能属性: Range, Luck, Tenacity, Power(IP)
-- ============================================================================

local M = {}

---@param GS table GameState
---@param ctx table { Config, equipSum, getTitleBonus }
function M.Install(GS, ctx)
    local Config = ctx.Config
    local equipSum      = ctx.equipSum
    local getTitleBonus = ctx.getTitleBonus

    --- 原始范围增量 (递减前)
    GS.GetRangeRawBonus = function()
        return equipSum("range")
    end

    --- 攻击范围 (渐近线递减)
    GS.GetRange = function()
        local rawBonus = GS.GetRangeRawBonus()
        if rawBonus <= 0 then return Config.PLAYER.baseRange end
        local dr = Config.RANGE_DR
        return Config.PLAYER.baseRange + dr.maxBonus * rawBonus / (rawBonus + dr.K)
    end

    --- 范围倍率因子
    GS.GetRangeFactor = function()
        return GS.GetRange() / Config.PLAYER.baseRange
    end

    --- 幸运值
    GS.GetLuck = function()
        return equipSum("luck")
             + GS.GetPotionBuff("luck")
             + getTitleBonus("luck")
    end

    -- ========================================================================
    -- 韧性(TEN) - 通用减益抗性
    -- ========================================================================

    GS.GetDebuffResist = function()
        local resist = getTitleBonus("debuffResist")
        return math.min(Config.TENACITY.maxResist, resist)
    end

    GS.GetSlowResist = GS.GetDebuffResist

    -- ========================================================================
    -- 总装备 IP
    -- ========================================================================

    GS.GetPower = function()
        local total = 0
        for _, slotCfg in ipairs(Config.EQUIP_SLOTS) do
            local item = GS.equipment[slotCfg.id]
            if item then
                total = total + (item.itemPower or 0)
            end
        end
        return total
    end
end

return M
