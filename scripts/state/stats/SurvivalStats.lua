-- ============================================================================
-- state/stats/SurvivalStats.lua — 生存属性: HP, DEF, HPRegen, Heal%, Shield%, LifeSteal, Dodge
-- ============================================================================

local M = {}

---@param GS table GameState
---@param ctx table { Config, StatDefs, equipSum, getCoreAttrBonus, getTitleBonus }
function M.Install(GS, ctx)
    local Config = ctx.Config
    local StatDefs = ctx.StatDefs
    local equipSum         = ctx.equipSum
    local getCoreAttrBonus = ctx.getCoreAttrBonus
    local getTitleBonus    = ctx.getTitleBonus

    --- 最大生命值 = (基础 + 等级 + 装备) × (1 + STR职业hpPct + 装备hpPct + 称号 + 套装 + 药水)
    GS.GetMaxHP = function()
        local p = GS.player
        local base = Config.PLAYER.baseHP
                  + p.level * Config.PLAYER.hpPerLevel
                  + math.floor(equipSum("hp"))
        local hpPctBonus = getCoreAttrBonus("hpPct") + equipSum("hpPct") + getTitleBonus("hp")
        local mulBonus = GS.GetSetBonusStatsMul()
        local hpMul = 1.0 + (mulBonus.hp or 0) + hpPctBonus
        local hpPotionBuff = GS.GetPotionBuff("hp")
        if hpPotionBuff > 0 then
            hpMul = hpMul + hpPotionBuff
        end
        return math.floor(base * hpMul)
    end

    --- 总防御力
    GS.GetTotalDEF = function()
        local p = GS.player
        local base = Config.PLAYER.baseDEF
             + p.level * Config.PLAYER.defPerLevel
             + getCoreAttrBonus("def")
             + equipSum("def")
        local mulPool = 0
        local mulBonus = GS.GetSetBonusStatsMul()
        mulPool = mulPool + (mulBonus.def or 0)
        mulPool = mulPool + getTitleBonus("def")
        return math.floor(base * (1 + mulPool))
    end

    --- 玩家受伤DEF伤害保留率 (0~1)
    ---@param monsterLevel number|nil
    GS.GetDEFMul = function(monsterLevel)
        local def = GS.GetTotalDEF()
        if GS.corrosionStacks > 0 and GS.corrosionDefReduce > 0 then
            local reducePct = GS.corrosionStacks * GS.corrosionDefReduce
            def = math.max(0, def * (1 - reducePct))
        end
        local lvl = monsterLevel or GS.player.level or 1
        local DF = require("DefenseFormula")
        return DF.PlayerDefMul(def, lvl)
    end

    --- 每秒回血量
    GS.GetHPRegen = function()
        return equipSum("hpRegen")
    end

    --- 治疗倍率
    GS.GetHealMul = function()
        return 1.0 + getCoreAttrBonus("healPct") + equipSum("healPct")
    end

    --- 护盾倍率
    GS.GetShieldMul = function()
        return 1.0 + equipSum("shldPct")
    end

    --- 吸血百分比
    GS.GetLifeSteal = function()
        return equipSum("lifeSteal")
    end

    --- 闪避概率 (cap 30%)
    GS.GetDodgeChance = function()
        local dodge = getCoreAttrBonus("dodge")
        return math.min(StatDefs.DODGE_CAP, dodge)
    end

    --- 全元素抗性加成 (cap 40%)
    GS.GetAllResist = function()
        local allRes = getCoreAttrBonus("allResist")
        return math.min(StatDefs.ALL_RESIST_CAP, allRes)
    end

    --- 超杀伤害加成
    GS.GetOverkillDmg = function()
        return getCoreAttrBonus("overkill")
    end
end

return M
