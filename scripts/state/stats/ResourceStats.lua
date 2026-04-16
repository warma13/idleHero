-- ============================================================================
-- state/stats/ResourceStats.lua — 资源属性: Mana, ManaRegen, CDR, SkillDmg
-- ============================================================================

local M = {}

---@param GS table GameState
---@param ctx table { Config, equipSum, getCoreAttrBonus }
function M.Install(GS, ctx)
    local Config = ctx.Config
    local equipSum         = ctx.equipSum
    local getCoreAttrBonus = ctx.getCoreAttrBonus

    --- 法力上限
    GS.GetMaxMana = function()
        local p = GS.player
        local mc = Config.MANA
        return mc.base + p.level * mc.perLevel
    end

    --- 每秒法力回复量 (D4 完整公式)
    GS.GetManaRegen = function()
        local mc = Config.MANA
        local base = mc.regenBase
        local manaRegenSpeed = equipSum("manaRegenSpeed")
        local resourceGen = equipSum("resourceGen")
        local wilPts = GS.player.allocatedPoints.WIL or 0
        local willResourceGen = wilPts * mc.willRegenPer

        local result = base * (1 + manaRegenSpeed) ^ 2
                           * (1 + resourceGen)
                           * (1 + willResourceGen)
        -- 强化寒冰甲
        if GS.iceArmorActive and GS._hasIceArmorEnhanced then
            result = result * 1.30
        end
        -- 巫师暴风雪
        if GS.blizzardActive and GS._hasBlizzardWizard then
            local maxMana = GS.GetMaxMana()
            local bonusRegen = math.floor(maxMana / 20)
            result = result + bonusRegen
        end
        return result
    end

    --- 技能冷却倍率 (渐近线递减)
    GS.GetSkillCdMul = function()
        local totalCDR = 0
        local lv = GS.GetSkillLevel("mana_affinity")
        totalCDR = totalCDR + lv * 0.04
        totalCDR = totalCDR + equipSum("skillCdReduce")
        local mulBonus = GS.GetSetBonusStatsMul()
        totalCDR = totalCDR + (mulBonus.skillCdReduce or 0)
        totalCDR = totalCDR + getCoreAttrBonus("cdr")
        -- 关键被动: 维尔精通 — CDR+10%
        if GS.GetSkillLevel("kp_vyr_mastery") > 0 then
            totalCDR = totalCDR + 0.10
        end
        if totalCDR <= 0 then return 1.0 end
        local dr = Config.CDR_DR
        return 1.0 - dr.maxCDR * totalCDR / (totalCDR + dr.K)
    end

    --- 技能伤害加成
    GS.GetSkillDmg = function()
        local total = equipSum("skillDmg")
        local mulBonus = GS.GetSetBonusStatsMul()
        total = total + (mulBonus.skillDmg or 0)
        local setStats = GS.GetSetBonusStats()
        total = total + (setStats.skillDmg or 0)
        total = total + getCoreAttrBonus("skillDmg")
        -- 关键被动: 维尔精通 — 技能伤害+15%
        if GS.GetSkillLevel("kp_vyr_mastery") > 0 then
            total = total + 0.15
        end
        return total
    end
end

return M
