-- ============================================================================
-- DynamicLevel.lua - 动态怪物等级 & 成长曲线 (Single Source of Truth)
--
-- 职责: 怪物等级计算、HP/ATK 成长公式、角色倍率
-- 依赖: WorldTierConfig (等级上限查询)
-- 设计文档: docs/数值/怪物家族系统设计.md §七、§十一
-- ============================================================================

local WorldTierConfig = require("WorldTierConfig")

local M = {}

-- ============================================================================
-- 成长曲线常量
-- ============================================================================

M.HP_GROWTH_BASE  = 1.085   -- HP 指数底数: 1.085^(lv-1)
M.ATK_GROWTH_BASE = 1.070   -- ATK 指数底数: 1.070^(lv-1)

-- ============================================================================
-- 角色倍率 (怪物扮演的战斗角色)
-- ============================================================================

---@class RoleMulDef
---@field hpMul  number  HP 倍率
---@field atkMul number  ATK 倍率

---@type table<string, RoleMulDef>
M.ROLE_MULS = {
    normal      = { hpMul = 1,  atkMul = 1   },   -- 普通小怪
    elite       = { hpMul = 5,  atkMul = 1.5 },   -- 精英
    champion    = { hpMul = 15, atkMul = 1.8 },   -- 冠军
    miniboss    = { hpMul = 30, atkMul = 2.0 },   -- 小 Boss
    dungeon_boss = { hpMul = 75, atkMul = 2.5 },  -- 地下城/章节 Boss
}

-- ============================================================================
-- 等级计算
-- ============================================================================

--- D4 式动态怪物等级: clamp(playerLevel, areaFloor, worldTierCap)
---@param playerLevel number 玩家等级
---@param areaFloor   number 区域最低等级 (章节下限)
---@param worldTierId number 当前世界层级 (1-4)
---@return number monsterLevel
function M.CalcMonsterLevel(playerLevel, areaFloor, worldTierId)
    local cap = WorldTierConfig.GetLevelCap(worldTierId)
    return math.min(math.max(playerLevel, areaFloor), cap)
end

--- 深渊模式怪物等级: playerLevel + floor(layer/5), 上限 = worldTierCap + 20
---@param playerLevel number
---@param layer       number 深渊层数
---@param worldTierId number
---@return number monsterLevel
function M.CalcAbyssLevel(playerLevel, layer, worldTierId)
    local base = playerLevel + math.floor(layer / 5)
    local cap  = WorldTierConfig.GetLevelCap(worldTierId) + 20
    return math.min(base, cap)
end

--- 尖塔试炼怪物等级 (固定值, 从 WorldTierConfig 读取)
---@param spireId number (1-3)
---@param isBoss  boolean
---@return number monsterLevel
function M.CalcSpireLevel(spireId, isBoss)
    local def = WorldTierConfig.GetSpireUnlock(spireId)
    if not def then return 1 end
    return isBoss and def.bossLevel or def.monsterLevel
end

-- ============================================================================
-- 成长公式
-- ============================================================================

--- HP 等级成长系数: 1.085^(level-1)
---@param level number 怪物等级
---@return number
function M.GrowthHP(level)
    if level <= 1 then return 1.0 end
    return M.HP_GROWTH_BASE ^ (level - 1)
end

--- ATK 等级成长系数: 1.070^(level-1)
---@param level number 怪物等级
---@return number
function M.GrowthATK(level)
    if level <= 1 then return 1.0 end
    return M.ATK_GROWTH_BASE ^ (level - 1)
end

-- ============================================================================
-- 怪物最终属性计算
-- ============================================================================

--- 计算怪物最终 HP
---@param raceBaseHP  number 种族基准 HP (S=55, A=85, B=110, C=240, D=400)
---@param level       number 怪物等级
---@param tierHPMul   number 世界层级/模式 HP 倍率
---@param roleMul     number 角色倍率 (normal=1, elite=5, boss=75...)
---@return number hp
function M.CalcHP(raceBaseHP, level, tierHPMul, roleMul)
    return math.floor(raceBaseHP * M.GrowthHP(level) * tierHPMul * roleMul)
end

--- 计算怪物最终 ATK
---@param raceBaseATK number 种族基准 ATK
---@param level       number 怪物等级
---@param tierATKMul  number 世界层级/模式 ATK 倍率
---@param roleMul     number 角色倍率
---@return number atk
function M.CalcATK(raceBaseATK, level, tierATKMul, roleMul)
    return math.floor(raceBaseATK * M.GrowthATK(level) * tierATKMul * roleMul)
end

--- 便捷: 用角色名获取角色倍率
---@param roleName string "normal"|"elite"|"champion"|"miniboss"|"dungeon_boss"
---@return RoleMulDef
function M.GetRoleMul(roleName)
    return M.ROLE_MULS[roleName] or M.ROLE_MULS.normal
end

-- ============================================================================
-- 深渊专属倍率
-- ============================================================================

--- 深渊 HP 层倍率: 1.0 + layer × 0.15
---@param layer number
---@return number
function M.AbyssHPMul(layer)
    return 1.0 + layer * 0.15
end

--- 深渊 ATK 层倍率: 1.0 + layer × 0.08
---@param layer number
---@return number
function M.AbyssATKMul(layer)
    return 1.0 + layer * 0.08
end

return M
