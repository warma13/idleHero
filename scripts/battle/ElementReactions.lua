-- ============================================================================
-- battle/ElementReactions.lua - v3.0 STUB (元素反应已移除)
-- D4模型不使用元素反应系统，此文件保留为空壳兼容旧 require
-- ============================================================================

local ElementReactions = {}

--- STUB: 不再附着元素或触发反应，直接返回原始伤害
function ElementReactions.AttachSkillElement(enemy, element, dmg, attachGrade)
    return nil, dmg
end

--- STUB: 不再处理反应效果
function ElementReactions.ApplyOffensiveReactionEffects(bs, target, reaction, finalDmg, fromX, fromY)
    -- no-op
end

--- STUB: 灼烧DoT已移除
function ElementReactions.UpdateFireBurnDots(dt, bs)
    -- no-op
end

--- STUB: 冰碎加成已移除
function ElementReactions.GetIceShatterBonus(target)
    return 0
end

return ElementReactions
