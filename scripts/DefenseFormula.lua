-- ============================================================================
-- DefenseFormula.lua - 护甲与抗性减伤公式模块
--
-- 职责: 统一管理 DEF/Resist 减伤计算，K 常数随怪物等级缩放
-- 依赖: WorldTierConfig (抗性穿透查询)
-- 设计文档: docs/数值/怪物家族系统设计.md §九
-- ============================================================================

local WorldTierConfig = require("WorldTierConfig")

local M = {}

-- ============================================================================
-- 常数定义
-- ============================================================================

-- 玩家 DEF K 常数 (怪物打玩家时, K 越大 → 玩家同等 DEF 减伤越低)
M.PLAYER_DEF_K_BASE       = 200    -- 基础 K
M.PLAYER_DEF_K_PER_LEVEL  = 0.04   -- 每级增长率 (4%)

-- 怪物 DEF K 常数 (玩家打怪物时, K 越大 → 怪物同等 DEF 减伤越低)
M.ENEMY_DEF_K_BASE        = 100    -- 基础 K
M.ENEMY_DEF_K_PER_LEVEL   = 0.03   -- 每级增长率 (3%)

-- ============================================================================
-- K 常数计算
-- ============================================================================

--- 计算玩家侧 DEF 减免常数 K (怪物攻击玩家时使用)
--- K 随怪物等级增长 → 玩家需要不断提升 DEF 才能维持减伤率
---@param monsterLevel number 怪物等级 (≥1)
---@return number K_player
function M.CalcPlayerDefK(monsterLevel)
    local lv = math.max(1, monsterLevel)
    return M.PLAYER_DEF_K_BASE * (1 + M.PLAYER_DEF_K_PER_LEVEL * (lv - 1))
end

--- 计算怪物侧 DEF 减免常数 K (玩家攻击怪物时使用)
--- K 随怪物等级增长 → 高等级怪的固定 DEF "更厚"
---@param monsterLevel number 怪物等级 (≥1)
---@return number K_enemy
function M.CalcEnemyDefK(monsterLevel)
    local lv = math.max(1, monsterLevel)
    return M.ENEMY_DEF_K_BASE * (1 + M.ENEMY_DEF_K_PER_LEVEL * (lv - 1))
end

-- ============================================================================
-- 减伤率计算 (核心公式)
-- ============================================================================

--- DEF 减伤倍率 (伤害保留率, 越低 = 减伤越多)
--- 公式: 保留率 = K / (DEF + K), 即 1 - DEF/(DEF+K)
---@param def number 防御值 (已扣减 debuff 后, ≥0)
---@param K   number 减免常数
---@return number damageMul 伤害保留率 (0~1)
function M.DefMul(def, K)
    if def <= 0 then return 1.0 end
    if K <= 0 then return 0.0 end
    return K / (def + K)
end

--- 玩家 DEF 减伤倍率 (怪物打玩家)
---@param playerDef    number 玩家总 DEF
---@param monsterLevel number 怪物等级
---@return number damageMul 伤害保留率 (0~1)
function M.PlayerDefMul(playerDef, monsterLevel)
    return M.DefMul(playerDef, M.CalcPlayerDefK(monsterLevel))
end

--- 怪物 DEF 减伤倍率 (玩家打怪物)
---@param enemyDef     number 怪物 DEF (种族模板固定值)
---@param monsterLevel number 怪物等级
---@return number damageMul 伤害保留率 (0~1)
function M.EnemyDefMul(enemyDef, monsterLevel)
    return M.DefMul(enemyDef, M.CalcEnemyDefK(monsterLevel))
end

-- ============================================================================
-- 元素抗性
-- ============================================================================

--- 抗性减伤倍率 (三段曲线, 与 Config.ResistMul 一致)
--- 负抗 → 增伤; 0~75% → 线性; 75%+ → 渐近线递减
---@param resist number 有效抗性值
---@return number damageMul 伤害倍率 (>0)
function M.ResistMul(resist)
    if resist < 0 then
        return 1 - resist / 2          -- 负抗 = 增伤
    elseif resist < 0.75 then
        return 1 - resist              -- 线性减伤
    else
        return 1 / (1 + resist / 4)    -- 渐近线递减
    end
end

--- 计算有效抗性 (面板抗性 - 世界层级穿透)
---@param faceResist  number 面板抗性 (0~1 范围, 如 0.40 = 40%)
---@param worldTierId number 当前世界层级 (1-4)
---@return number effectiveResist 有效抗性 (可为负数)
function M.CalcEffectiveResist(faceResist, worldTierId)
    local pen = WorldTierConfig.GetResistPenetration(worldTierId)
    return faceResist - pen
end

--- 带世界层级穿透的抗性减伤倍率 (一步到位)
---@param faceResist  number 面板抗性
---@param worldTierId number 当前世界层级 (1-4)
---@return number damageMul 伤害倍率
function M.ResistMulWithPen(faceResist, worldTierId)
    return M.ResistMul(M.CalcEffectiveResist(faceResist, worldTierId))
end

-- ============================================================================
-- 总减伤聚合 (独立相乘)
-- ============================================================================

--- 多层减伤独立相乘
--- 总伤害保留率 = defMul × resistMul × dodgeMul × miscMul × ...
---@param ... number 各层伤害保留率
---@return number totalMul 最终伤害保留率
function M.CombineDamageMul(...)
    local result = 1.0
    for i = 1, select("#", ...) do
        result = result * select(i, ...)
    end
    return result
end

return M
