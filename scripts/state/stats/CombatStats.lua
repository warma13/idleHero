-- ============================================================================
-- state/stats/CombatStats.lua — 战斗属性: ATK, SPD, CRT, CDM, DPS
-- ============================================================================

local M = {}

---@param GS table GameState
---@param ctx table { Config, SM, equipSum, getCoreAttrBonus, getTitleBonus }
function M.Install(GS, ctx)
    local Config = ctx.Config
    local SM     = ctx.SM
    local equipSum        = ctx.equipSum
    local getCoreAttrBonus = ctx.getCoreAttrBonus
    local getTitleBonus    = ctx.getTitleBonus

    -- ========================================================================
    -- ATK
    -- ========================================================================

    --- 总攻击力 = (基础 + 装备) × 修饰器
    GS.GetTotalAtk = function()
        local p = GS.player
        local base = p.baseAtk + equipSum("atk")
        return math.floor(SM.Apply("atk", base))
    end

    --- 攻击药水伤害增幅倍率 (1.0 = 无增幅, 1.05 = +5%)
    GS.GetAtkPotionMul = function()
        local v = GS.GetPotionBuff("atk")
        if v > 0 then return 1 + v end
        return 1.0
    end

    -- ========================================================================
    -- SPD (双池攻速)
    -- ========================================================================

    --- 第一类攻速加成 (面板): 装备 + 套装被动 + 速射技能
    GS.GetAtkSpeedPool1 = function()
        local total = equipSum("spd")
        local mulBonus = GS.GetSetBonusStatsMul()
        total = total + (mulBonus.atkSpeed or 0)
        total = total + GS.GetSkillLevel("normal_speed") * 0.08
        return math.min(Config.ATK_SPEED_CAP1, total)
    end

    --- 第二类攻速加成 (触发): SM.Apply("atkSpd2") 汇总
    GS.GetAtkSpeedPool2 = function()
        local raw = SM.Apply("atkSpd2", 0)
        return math.max(-Config.ATK_SPEED_CAP2, math.min(Config.ATK_SPEED_CAP2, raw))
    end

    --- 原始攻速 (面板展示用, 不含触发)
    GS.GetAtkSpeedRaw = function()
        local p = GS.player
        return p.atkSpeed * (1 + GS.GetAtkSpeedPool1())
    end

    --- 攻击速度 (双池公式)
    --- 总攻速 = (1 + 第一类 + 第二类) × 武器攻速
    GS.GetAtkSpeed = function()
        local p = GS.player
        local pool1 = GS.GetAtkSpeedPool1()
        local pool2 = GS.GetAtkSpeedPool2()
        local effective = (1 + pool1 + pool2) * p.atkSpeed
        return math.max(0.15, effective)
    end

    -- ========================================================================
    -- CRT / CDM
    -- ========================================================================

    --- 暴击率 (DEX 职业效果 + 装备 + 技能 + 称号)
    GS.GetCritRateRaw = function()
        local p = GS.player
        local base = p.critRate + getCoreAttrBonus("crit") + equipSum("crit")
        base = base + GS.GetSkillLevel("arcane_sense") * 0.03
        base = base + getTitleBonus("crit")
        return base
    end

    --- 实际暴击率 (上限100%)
    GS.GetCritRate = function()
        local rate = GS.GetCritRateRaw()
        rate = SM.Apply("crit", rate)
        return math.max(0, math.min(1.0, rate))
    end

    --- 暴击率溢出部分
    GS.GetCritOverflow = function()
        return math.max(0, GS.GetCritRateRaw() - 1.0)
    end

    --- 暴击伤害倍率
    GS.GetCritDmg = function()
        local p = GS.player
        local base = p.critDmg + equipSum("critDmg")
        base = base + GS.GetCritOverflow() * Config.CRIT_OVERFLOW_RATIO
        local mulBonus = GS.GetSetBonusStatsMul()
        base = base + (mulBonus.critDmg or 0) + getTitleBonus("critDmg")
        return base
    end

    -- ========================================================================
    -- DPS
    -- ========================================================================

    GS.GetDPS = function()
        local atk = GS.GetTotalAtk()
        local spd = GS.GetAtkSpeed()
        local crit = GS.GetCritRate()
        local critDmg = GS.GetCritDmg()
        return math.floor(atk * spd * (1 + crit * (critDmg - 1)))
    end

    -- ========================================================================
    -- 永久修饰器注册
    -- ========================================================================

    SM.Register({
        id = "skill_base_atk_boost", stat = "atk", type = "pctPool",
        valueFn = function() return GS.GetSkillLevel("base_atk_boost") * 0.08 end,
    })

    SM.Register({
        id = "title_atk", stat = "atk", type = "pctPool",
        valueFn = function() return getTitleBonus("atk") end,
    })

    -- 强化电花: 暴击率叠加 (+2%/次, 最多8%)
    SM.Register({
        id = "spark_enhanced_crit", stat = "crit", type = "pctPool",
        valueFn = function() return GS._sparkCritStacks or 0 end,
        conditionFn = function() return (GS._sparkCritStacks or 0) > 0 end,
    })

    -- 闪耀奥术打击: 攻速加成 (10%, 3秒)
    SM.Register({
        id = "arcane_strike_glinting_atkspd", stat = "atkSpd2", type = "flatAdd",
        valueFn = function() return 0.10 end,
        conditionFn = function() return (GS._arcaneStrikeAtkSpdTimer or 0) > 0 end,
    })

    -- 强化闪电矛: 暴击率叠加 (+5%/crit, 最多25%)
    SM.Register({
        id = "lightning_spear_enhanced_crit", stat = "crit", type = "pctPool",
        valueFn = function() return GS._lsEnhancedCritStacks or 0 end,
        conditionFn = function() return (GS._lsEnhancedCritStacks or 0) > 0 end,
    })
end

return M
