-- ============================================================================
-- WorldTierConfig.lua - 世界层级统一配置 (Single Source of Truth)
--
-- 职责: 世界层级定义、倍率、抗性穿透、解锁条件
-- 依赖: 无 (纯数据+查询, 零外部依赖)
-- 设计文档: docs/数值/怪物家族系统设计.md §十
-- ============================================================================

local M = {}

-- ============================================================================
-- 世界层级定义
-- ============================================================================

---@class WorldTierDef
---@field id       number   层级编号 (1-4)
---@field name     string   显示名称
---@field levelCap number   怪物等级上限
---@field hpMul    number   怪物 HP 倍率
---@field atkMul   number   怪物 ATK 倍率
---@field expMul   number   经验倍率
---@field goldMul  number   金币倍率
---@field resistPen number  抗性穿透 (0~1, 如 0.15 = 15%)
---@field dropQualityBonus number 掉落品质加成 (预留)

---@type WorldTierDef[]
local TIERS = {
    {
        id        = 1,
        name      = "冒险",
        levelCap  = 50,
        hpMul     = 1.0,
        atkMul    = 1.0,
        expMul    = 1.0,
        goldMul   = 1.0,
        resistPen = 0.00,
        dropQualityBonus = 0,
    },
    {
        id        = 2,
        name      = "坚忍",
        levelCap  = 70,
        hpMul     = 2.0,
        atkMul    = 1.35,
        expMul    = 1.20,
        goldMul   = 1.15,
        resistPen = 0.05,
        dropQualityBonus = 1,
    },
    {
        id        = 3,
        name      = "噩梦",
        levelCap  = 85,
        hpMul     = 8.5,
        atkMul    = 1.77,
        expMul    = 1.50,
        goldMul   = 1.30,
        resistPen = 0.10,
        dropQualityBonus = 2,
    },
    {
        id        = 4,
        name      = "折磨",
        levelCap  = 100,
        hpMul     = 35.0,
        atkMul    = 2.35,
        expMul    = 2.00,
        goldMul   = 1.50,
        resistPen = 0.15,
        dropQualityBonus = 3,
    },
}

-- 快速索引 (tier id → def)
local TIER_MAP = {}
for _, t in ipairs(TIERS) do
    TIER_MAP[t.id] = t
end

-- ============================================================================
-- 尖塔试炼解锁条件
-- ============================================================================

---@class SpireUnlockDef
---@field spireId      number  试炼编号 (1-3)
---@field unlocksWT    number  通关后解锁的世界层级
---@field requiredLevel number 前置玩家等级
---@field requiredChapter number|nil 前置章节通关 (nil=无)
---@field requiredWT   number|nil 前置世界层级 (nil=无)
---@field monsterLevel number  试炼怪物固定等级
---@field bossLevel    number  试炼 Boss 固定等级
---@field usesWTMul    number  使用目标世界层级的倍率

---@type SpireUnlockDef[]
M.SPIRE_UNLOCKS = {
    {
        spireId       = 1,
        unlocksWT     = 2,
        requiredLevel = 30,
        requiredChapter = 9,
        requiredWT    = nil,
        monsterLevel  = 35,
        bossLevel     = 38,
        usesWTMul     = 2,
    },
    {
        spireId       = 2,
        unlocksWT     = 3,
        requiredLevel = 50,
        requiredChapter = nil,
        requiredWT    = 2,
        monsterLevel  = 55,
        bossLevel     = 60,
        usesWTMul     = 3,
    },
    {
        spireId       = 3,
        unlocksWT     = 4,
        requiredLevel = 70,
        requiredChapter = nil,
        requiredWT    = 3,
        monsterLevel  = 75,
        bossLevel     = 80,
        usesWTMul     = 4,
    },
}

-- ============================================================================
-- 查询接口
-- ============================================================================

--- 获取世界层级定义
---@param tierId number 层级编号 (1-4)
---@return WorldTierDef
function M.Get(tierId)
    return TIER_MAP[tierId] or TIER_MAP[1]
end

--- 获取所有层级定义 (只读)
---@return WorldTierDef[]
function M.GetAll()
    return TIERS
end

--- 获取等级上限
---@param tierId number
---@return number
function M.GetLevelCap(tierId)
    local t = TIER_MAP[tierId]
    return t and t.levelCap or 50
end

--- 获取 HP 倍率
---@param tierId number
---@return number
function M.GetHPMul(tierId)
    local t = TIER_MAP[tierId]
    return t and t.hpMul or 1.0
end

--- 获取 ATK 倍率
---@param tierId number
---@return number
function M.GetATKMul(tierId)
    local t = TIER_MAP[tierId]
    return t and t.atkMul or 1.0
end

--- 获取抗性穿透
---@param tierId number
---@return number (0~0.15)
function M.GetResistPenetration(tierId)
    local t = TIER_MAP[tierId]
    return t and t.resistPen or 0
end

--- 获取经验倍率
---@param tierId number
---@return number
function M.GetExpMul(tierId)
    local t = TIER_MAP[tierId]
    return t and t.expMul or 1.0
end

--- 获取金币倍率
---@param tierId number
---@return number
function M.GetGoldMul(tierId)
    local t = TIER_MAP[tierId]
    return t and t.goldMul or 1.0
end

--- 获取尖塔试炼解锁定义
---@param spireId number (1-3)
---@return SpireUnlockDef|nil
function M.GetSpireUnlock(spireId)
    return M.SPIRE_UNLOCKS[spireId]
end

--- 检查玩家是否满足尖塔试炼的前置条件
---@param spireId number
---@param playerLevel number
---@param maxChapter number
---@param currentWT number
---@return boolean canEnter
---@return string|nil reason 不满足时的原因
function M.CanEnterSpire(spireId, playerLevel, maxChapter, currentWT)
    local def = M.SPIRE_UNLOCKS[spireId]
    if not def then return false, "无效的试炼编号" end
    if playerLevel < def.requiredLevel then
        return false, "需要等级 " .. def.requiredLevel
    end
    if def.requiredChapter and maxChapter < def.requiredChapter then
        return false, "需要通关第 " .. def.requiredChapter .. " 章"
    end
    if def.requiredWT and currentWT < def.requiredWT then
        return false, "需要先解锁世界层级 " .. def.requiredWT
    end
    return true
end

--- 最大世界层级编号
M.MAX_TIER = #TIERS

return M
