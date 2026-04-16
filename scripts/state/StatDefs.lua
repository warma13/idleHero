-- ============================================================================
-- state/StatDefs.lua - 属性注册表 (单一数据源)
-- ============================================================================
-- P1 重构: 10个独立属性 → 4核心属性 (STR/DEX/INT/WIL)
-- 集中管理: 核心属性定义(含通用效果+职业效果)、装备战力权重、tier缩放
-- ============================================================================

local StatDefs = {}

-- 当前职业 (多职业扩展时由存档/选择决定)
StatDefs.CURRENT_CLASS = "warlock"

-- ========================================================================
-- 核心属性定义 (4个, 替代旧 10 个独立加点属性)
-- ========================================================================
-- key          : 属性ID (与 allocatedPoints 键名一致)
-- label        : UI 显示名
-- effects      : 通用效果列表 (所有职业共享)
-- classEffects : 职业专属效果 { [className] = effects[] }
-- fmtFn        : 格式化函数 (UI 展示用)
--
-- effect 字段:
--   target   : 目标属性ID (如 "def", "dodge", "crit")
--   perPoint : 每点加成值
--   scale    : true = 乘以 attrScale (绝对值属性如护甲), nil = 不缩放
--   desc     : 格式化描述 (printf 格式)
--   descMul  : 显示时乘数 (如 ×100 显示为百分比), 默认 1
-- ========================================================================

---@class CoreStatEffect
---@field target string
---@field perPoint number
---@field scale? boolean
---@field desc string
---@field descMul? number

---@class CoreStatDef
---@field key string
---@field label string
---@field effects CoreStatEffect[]
---@field classEffects? table<string, CoreStatEffect[]>
---@field fmtFn fun(): string

---@type CoreStatDef[]
StatDefs.CORE_STATS = {
    {
        key = "STR", label = "力量",
        effects = {
            { target = "def", perPoint = 1.0, scale = true, desc = "护甲 +%d", descMul = 1 },
        },
        classEffects = {
            warlock = {
                { target = "hpPct", perPoint = 0.001, desc = "生命 +%.1f%%", descMul = 100 },
            },
        },
        fmtFn = function()
            local GS = require("GameState")
            local pts = GS.player.allocatedPoints.STR or 0
            if pts == 0 then return "0pt" end
            return tostring(pts) .. "pt"
        end,
    },
    {
        key = "DEX", label = "敏捷",
        effects = {
            { target = "dodge", perPoint = 0.00025, desc = "闪避 +%.2f%%", descMul = 100 },
        },
        classEffects = {
            warlock = {
                { target = "crit", perPoint = 0.0002, desc = "暴击率 +%.2f%%", descMul = 100 },
            },
        },
        fmtFn = function()
            local GS = require("GameState")
            local pts = GS.player.allocatedPoints.DEX or 0
            if pts == 0 then return "0pt" end
            return tostring(pts) .. "pt"
        end,
    },
    {
        key = "INT", label = "智力",
        effects = {
            { target = "allResist", perPoint = 0.0005, desc = "全抗 +%.2f%%", descMul = 100 },
        },
        classEffects = {
            warlock = {
                { target = "skillDmg", perPoint = 0.001, desc = "技能伤害 +%.1f%%", descMul = 100 },
            },
        },
        fmtFn = function()
            local GS = require("GameState")
            local pts = GS.player.allocatedPoints.INT or 0
            if pts == 0 then return "0pt" end
            return tostring(pts) .. "pt"
        end,
    },
    {
        key = "WIL", label = "意志",
        effects = {
            { target = "healPct", perPoint = 0.001, desc = "治疗 +%.1f%%", descMul = 100 },
            { target = "overkill", perPoint = 0.0025, desc = "超杀 +%.1f%%", descMul = 100 },
        },
        classEffects = {
            warlock = {
                { target = "cdr", perPoint = 0.001, desc = "CDR +%.1f%%", descMul = 100 },
            },
        },
        fmtFn = function()
            local GS = require("GameState")
            local pts = GS.player.allocatedPoints.WIL or 0
            if pts == 0 then return "0pt" end
            return tostring(pts) .. "pt"
        end,
    },
}

-- 向后兼容别名 (外部模块引用 POINT_STATS)
StatDefs.POINT_STATS = StatDefs.CORE_STATS

-- 闪避 / 全抗 硬顶
StatDefs.DODGE_CAP = 0.30
StatDefs.ALL_RESIST_CAP = 0.40

-- 超杀伤害触发阈值 (敌人 HP 低于此比例时生效)
StatDefs.OVERKILL_HP_THRESHOLD = 0.30

-- 快查表: key → CoreStatDef
StatDefs._byKey = {}
for _, def in ipairs(StatDefs.CORE_STATS) do
    StatDefs._byKey[def.key] = def
end

-- ========================================================================
-- 装备属性战力权重 (ItemPower 归一化后乘)
-- 包含所有可能出现在装备上的属性
-- ========================================================================

StatDefs.EQUIP_IMPORTANCE = {
    atk = 1.0, spd = 1.0,
    crit = 0.9, critDmg = 0.9,
    elemDmg = 0.9, reactionDmg = 0.8, skillDmg = 0.7,
    fireDmg = 0.9, iceDmg = 0.9, poisonDmg = 0.9, arcaneDmg = 0.9, waterDmg = 0.9,
    hp = 0.7, def = 0.7, hpPct = 0.7, skillCdReduce = 0.7,
    hpRegen = 0.6, lifeSteal = 0.8, shldPct = 0.6,
    luck = 0.5,
    fireRes = 0.4, iceRes = 0.4, poisonRes = 0.4, arcaneRes = 0.4, waterRes = 0.4,
}

-- ========================================================================
-- 装备属性 tier 缩放特例 (非核心属性的特殊缩放)
-- ========================================================================

StatDefs.STAT_TIER_OVERRIDES = {
    luck = function(ch) return 1.5 ^ ch end,
}

-- ========================================================================
-- 工具函数
-- ========================================================================

--- 生成 allocatedPoints 初始值表 { STR=0, DEX=0, INT=0, WIL=0 }
---@return table<string, number>
function StatDefs.MakeAllocatedPoints()
    local t = {}
    for _, def in ipairs(StatDefs.CORE_STATS) do
        t[def.key] = 0
    end
    return t
end

--- 获取属性的 tier 缩放值
---@param statKey string 属性ID
---@param chapter number 当前章节
---@param defaultTierMul number 通用 tierMul
---@return number
function StatDefs.GetTierMul(statKey, chapter, defaultTierMul)
    local fn = StatDefs.STAT_TIER_OVERRIDES[statKey]
    if fn then return fn(chapter) end
    return defaultTierMul
end

--- 获取装备属性战力权重
---@param statKey string 属性ID
---@return number
function StatDefs.GetImportance(statKey)
    return StatDefs.EQUIP_IMPORTANCE[statKey] or 0.5
end

--- 计算核心属性对指定目标属性的加成总和
--- 遍历所有 CORE_STATS 的 effects + classEffects, 汇总 target 匹配项
---@param targetStat string 目标属性ID (如 "def", "dodge", "crit")
---@param attrScale number 章节属性缩放值 (仅 scale=true 的效果需要)
---@param allocatedPoints table 已分配点数表
---@return number 加成总和
function StatDefs.CalcCoreBonus(targetStat, attrScale, allocatedPoints)
    local cls = StatDefs.CURRENT_CLASS
    local total = 0
    for _, attr in ipairs(StatDefs.CORE_STATS) do
        local pts = allocatedPoints[attr.key] or 0
        if pts > 0 then
            -- 通用效果
            for _, eff in ipairs(attr.effects) do
                if eff.target == targetStat then
                    local val = pts * eff.perPoint
                    if eff.scale then val = val * attrScale end
                    total = total + val
                end
            end
            -- 职业专属效果
            if attr.classEffects and attr.classEffects[cls] then
                for _, eff in ipairs(attr.classEffects[cls]) do
                    if eff.target == targetStat then
                        local val = pts * eff.perPoint
                        if eff.scale then val = val * attrScale end
                        total = total + val
                    end
                end
            end
        end
    end
    return total
end

return StatDefs
