-- ============================================================================
-- battle/BulletSystem.lua - 碎裂弹体系统 (已废弃)
-- 通用分支已移除, 此模块保留空壳供 BattleSystem.Update 调用
-- ============================================================================

local BulletSystem = {}

local SALVO_DELAY = 0.12

--- 生成圆周分裂弹 — 已废弃 (shatter 技能已移除)
function BulletSystem.SpawnSplitBullets(bs, x, y)
    -- no-op
end

--- 更新连射待发轮次 — 已废弃
function BulletSystem.UpdatePendingSalvos(dt, bs)
    -- 清空残留数据 (存档迁移可能遗留)
    if bs.pendingSalvos and #bs.pendingSalvos > 0 then
        bs.pendingSalvos = {}
    end
end

--- 更新所有碎裂弹体 — 已废弃
function BulletSystem.UpdateBullets(dt, bs, areaW, areaH)
    -- 清空残留数据
    if bs.bullets and #bs.bullets > 0 then
        bs.bullets = {}
    end
end

BulletSystem.SALVO_DELAY = SALVO_DELAY

return BulletSystem
