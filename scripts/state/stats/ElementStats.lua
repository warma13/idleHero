-- ============================================================================
-- state/stats/ElementStats.lua — 元素属性: 武器元素, 元素增伤, 反应增伤, Stubs
-- ============================================================================

local M = {}

---@param GS table GameState
---@param ctx table { Config, equipSum, getTitleBonus }
function M.Install(GS, ctx)
    local Config = ctx.Config
    local equipSum      = ctx.equipSum
    local getTitleBonus = ctx.getTitleBonus

    --- 获取当前武器元素 (v4.0: 武器元素系统已移除, 固定返回 fire)
    GS.GetWeaponElement = function()
        return "fire"
    end

    --- 元素增伤倍率
    GS.GetElemDmg = function()
        local weaponElem = GS.GetWeaponElement()
        local ELEM_TO_STAT = {
            fire = "fireDmg", ice = "iceDmg", poison = "poisonDmg",
            arcane = "arcaneDmg", water = "waterDmg",
        }
        local specificKey = ELEM_TO_STAT[weaponElem]
        local specific = specificKey and equipSum(specificKey) or 0
        local allElem = equipSum("elemDmg")
        return specific + allElem + getTitleBonus("allElemDmg")
    end

    --- 获取指定元素的增伤数值 (面板展示)
    GS.GetSpecificElemDmg = function(elemStatKey)
        local specific = equipSum(elemStatKey)
        local allElem = equipSum("elemDmg")
        return specific + allElem + getTitleBonus("allElemDmg")
    end

    --- 反应增伤倍率 (装备)
    GS.GetReactionDmgFromEquip = function()
        return equipSum("reactionDmg")
    end

    -- ========================================================================
    -- 元素增幅技能参数查询
    -- ========================================================================

    GS.GetElementDurationBonus = function()
        local lv = GS.GetSkillLevel("elem_affinity")
        return lv * 0.5
    end

    -- v3.0 STUBs (旧机制移除, 保持向后兼容)
    GS.GetReactionDmgBonus    = function() return 1.0 end
    GS.GetElementMarkBonus    = function() return 0 end
    GS.GetDualAttachChance    = function() return 0 end
    GS.GetElementSpreadChance = function() return 0 end
    GS.GetConvergenceBonus    = function() return 0 end
end

return M
