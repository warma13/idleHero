-- ============================================================================
-- battle/BuffManager.lua - Buff/Debuff 管理调度入口
-- 通用 Buff + 套装效果聚合; 具体套装逻辑已拆分至 buffs/ 子模块
-- ============================================================================

local GameState = require("GameState")

local BuffManager = {}

-- ============================================================================
-- 子模块加载 & 函数重新导出
-- ============================================================================

local NewSets  = require("battle.buffs.NewSets")
local T13Sets  = require("battle.buffs.T13Sets")

-- 将子模块的所有函数挂载到 BuffManager 上，保持外部调用兼容
for k, v in pairs(NewSets)  do BuffManager[k] = v end
for k, v in pairs(T13Sets)  do BuffManager[k] = v end

-- Frenzy/Atk/Berserk buff tick 已迁移至 state/BuffRuntime.lua（通过 GameState.Update*Buff 调用）

-- ============================================================================
-- 统一获取所有套装提供的额外减伤率
-- ============================================================================

function BuffManager.GetTotalSetDmgReduce()
    local total = 0
    -- 铁壁要塞6件: 护盾破碎后减伤
    total = total + BuffManager.GetIronBastionDmgReduce()
    -- 极寒之心6件: 寒冰化身减伤
    total = total + BuffManager.GetIceAvatarDmgReduce()
    return math.min(total, 0.80)  -- 上限80%减伤
end

-- ============================================================================
-- 统一获取所有套装提供的额外攻速加成
-- ============================================================================

function BuffManager.GetTotalSetAtkSpeedBonus()
    local total = 0
    -- 迅捷猎手6件: 连击风暴攻速
    total = total + BuffManager.GetSwiftHunterAtkSpeedBonus()
    -- 裂变之力6件: 脉冲后攻速
    total = total + BuffManager.GetFissionForceAtkSpeedBonus()
    return total
end

return BuffManager
