-- ============================================================================
-- state/StatCalc.lua — 属性计算编排层 (薄入口)
-- ============================================================================
-- 职责: 初始化共享上下文 (ctx), 依次安装各子模块
-- 子模块位于 state/stats/ 目录:
--   CombatStats   — ATK, SPD, CRT, CDM, DPS
--   SurvivalStats — HP, DEF, HPRegen, Heal%, Shield%, LifeSteal, Dodge, Resist
--   ResourceStats — Mana, ManaRegen, CDR, SkillDmg
--   ElementStats  — 武器元素, 元素增伤, 反应增伤
--   UtilityStats  — Range, Luck, Tenacity, Power(IP)
--   SetBonus      — 套装件数统计, stats/statsMul 查询
--   StatFormat    — 属性/装备/时间/大数字格式化
-- ============================================================================

local StatCalc = {}

function StatCalc.Install(GameState)
    local Config   = require("Config")
    local StatDefs = require("state.StatDefs")
    local SM       = require("state.StatModifiers")

    -- ====================================================================
    -- 共享辅助函数
    -- ====================================================================

    -- 称号加成 (延迟加载, 避免循环依赖)
    local TitleSystem_ = nil
    local function getTitleBonus(statKey)
        if not TitleSystem_ then
            local ok, ts = pcall(require, "TitleSystem")
            if ok then TitleSystem_ = ts end
        end
        if TitleSystem_ then return TitleSystem_.GetBonus(statKey) end
        return 0
    end

    --- 装备属性求和辅助 (遍历主属性+词缀+宝石)
    local function equipSum(stat)
        local total = 0
        for _, item in pairs(GameState.equipment) do
            if item then
                -- 主属性 (固有, 不占词缀格)
                if item.mainStatId == stat and item.mainStatValue then
                    total = total + item.mainStatValue
                end
                if item.affixes then
                    for _, aff in ipairs(item.affixes) do
                        if aff.id == stat then
                            total = total + (aff.value or 0)
                        end
                    end
                end
                if item.gems and item.sockets then
                    local gemStats = GameState.GetGemStats(item)
                    if gemStats[stat] then
                        total = total + gemStats[stat]
                    end
                end
            end
        end
        return total
    end

    -- 暴露给其他子模块 (Combat.lua 等需要)
    GameState._equipSum = equipSum

    --- 获取最高通关章节
    local function getMaxChapter()
        return (GameState.records and GameState.records.maxChapter)
            or (GameState.stage and GameState.stage.chapter)
            or 1
    end

    --- 查询核心属性对指定目标属性的加成总和
    ---@param targetStat string
    ---@return number
    local function getCoreAttrBonus(targetStat)
        local attrScale = Config.GetAttrScale(getMaxChapter())
        return StatDefs.CalcCoreBonus(targetStat, attrScale, GameState.player.allocatedPoints)
    end

    -- ====================================================================
    -- 共享上下文 — 传递给所有子模块
    -- ====================================================================

    local ctx = {
        Config          = Config,
        StatDefs        = StatDefs,
        SM              = SM,
        equipSum        = equipSum,
        getCoreAttrBonus = getCoreAttrBonus,
        getTitleBonus   = getTitleBonus,
    }

    -- ====================================================================
    -- 按依赖顺序安装子模块
    -- SetBonus 必须最先 (其他模块调用 GetSetBonusStats/Mul)
    -- ====================================================================

    require("state.stats.SetBonus").Install(GameState, ctx)
    require("state.stats.CombatStats").Install(GameState, ctx)
    require("state.stats.SurvivalStats").Install(GameState, ctx)
    require("state.stats.ResourceStats").Install(GameState, ctx)
    require("state.stats.ElementStats").Install(GameState, ctx)
    require("state.stats.UtilityStats").Install(GameState, ctx)
    require("state.stats.StatFormat").Install(GameState, ctx)
end

return StatCalc
