-- ============================================================================
-- battle/skills/IceSkills.lua - 冰系技能施放
-- frost_bolt, ice_shards, ice_armor, frost_nova, blizzard, frozen_orb,
-- deep_freeze
-- ============================================================================

local GameState      = require("GameState")
local CombatUtils    = require("battle.CombatUtils")
local H              = require("battle.skills.Helpers")
local ShieldManager  = require("state.ShieldManager")

local function Register(SkillCaster)

-- ============================================================================
-- 冰霜弹 (frost_bolt) — 基础冰系单体 + 冻伤
-- ============================================================================
function SkillCaster._Cast_frost_bolt(bs, skillCfg, lv, p)
    local element = "ice"
    local range = 200 * GameState.GetRangeFactor()
    local dmgScale = skillCfg.effect(lv) / 100
    local target = H.FindNearestEnemy(bs.enemies, p.x, p.y, range)

    if target then
        CombatUtils.PlaySfx("frostBolt", 0.5)
        local bonuses = {}
        local dmg, isCrit = H.HitEnemySkill(bs, target, dmgScale, element, bonuses, p.x, p.y, CombatUtils.KNOCKBACK_SKILL)
        if not target.dead then
            local fbPct = skillCfg.frostbitePct or 15
            H.ApplyFrostbite(target, fbPct)
            if H.HasEnhance("frost_bolt_vuln") then
                H.ApplyVulnerable(target, 3.0)
            end
            if H.HasEnhance("frost_bolt_shatter") then
                local hasFrostbite = (target.frostbite or 0) > 0
                local isFrozen = target.isFrozen
                local aoeChance = isFrozen and 1.0 or (hasFrostbite and 0.15 or 0)
                if aoeChance > 0 and math.random() < aoeChance then
                    local aoeRange = 80
                    for _, e in ipairs(bs.enemies) do
                        if not e.dead and e ~= target then
                            local adx = e.x - target.x
                            local ady = e.y - target.y
                            if adx * adx + ady * ady <= aoeRange * aoeRange then
                                H.HitEnemySkill(bs, e, dmgScale * 0.5, element, {}, e.x, e.y, 0)
                            end
                        end
                    end
                end
            end
            if H.HasEnhance("frost_bolt_cdr") then
                local hasFrostbite = (target.frostbite or 0) > 0
                if hasFrostbite or target.isFrozen then
                    local manaGain = 4
                    local maxMana = GameState.GetMaxMana()
                    GameState.playerMana = math.min(maxMana, GameState.playerMana + manaGain)
                end
            end
        end
    end

    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_NORMAL)
    table.insert(bs.skillEffects, {
        type = "frost_bolt", x = p.x, y = p.y,
        targetX = target and target.x or p.x,
        targetY = target and target.y or p.y,
        radius = 20, life = 0.3, maxLife = 0.3,
    })
end

-- ============================================================================
-- 冰碎片 (ice_shards) — 射出5枚弹道碎片，横向排列飞向敌人，到达射程消失
-- 基础: 对冻结敌人伤害+50% [x]乘伤
-- 强化: 50%弹射, 冻结目标100%弹射
-- 强效: 有屏障时, 冻结加伤无条件生效
-- 毁灭: 5发全中同一敌人→易伤2秒
-- ============================================================================
function SkillCaster._Cast_ice_shards(bs, skillCfg, lv, p)
    local alive = H.GetAliveEnemies(bs.enemies)
    if #alive == 0 then return end

    local shardCount    = skillCfg.hitCount or 5
    local dmgPerShard   = skillCfg.effect(lv) / 100

    -- 选择最近目标确定飞行方向
    local target = H.FindNearestEnemy(bs.enemies, p.x, p.y, 9999)
    if not target then target = alive[1] end

    -- 方向向量
    local dx = target.x - p.x
    local dy = target.y - p.y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 1 then dx, dy, dist = 1, 0, 1 end
    local dirX, dirY = dx / dist, dy / dist

    -- 垂直方向 (横向排列)
    local perpX, perpY = -dirY, dirX

    -- 弹道参数
    local speed    = 300
    local maxRange = 220 * GameState.GetRangeFactor()
    local life     = maxRange / speed
    local spacing  = 14  -- 碎片间距(像素)

    -- 增强/强效/毁灭 状态
    local hasEnhanced    = H.HasEnhance("ice_shards_enhanced")
    local hasGreater     = H.HasEnhance("ice_shards_greater")
    local hasDestructive = H.HasEnhance("ice_shards_destructive")
    local hasBarrier     = ShieldManager.GetTotal() > 0
    local alwaysFrozenBonus = hasGreater and hasBarrier

    -- 毁灭追踪器: 所有碎片共享, 5发全中同一敌人→易伤
    local hitTracker = hasDestructive and { counts = {}, total = shardCount } or nil

    -- 生成5枚碎片, 横向排列
    if not bs.frostShards then bs.frostShards = {} end

    for i = 1, shardCount do
        local offset = (i - 1 - (shardCount - 1) / 2) * spacing
        local startX = p.x + perpX * offset
        local startY = p.y + perpY * offset

        local shard = {
            x = startX, y = startY,
            vx = dirX * speed, vy = dirY * speed,
            dmg = 0,       -- 伤害由 onHit 处理
            radius = 7,
            life = life,
            element = "ice",
            source = "ice_shards",
            pierced = {},
            onHit = function(s, e, bs2)
                -- 冻结加伤 (+50% x伤)
                local xSources = {}
                if e.isFrozen or alwaysFrozenBonus then
                    xSources[#xSources + 1] = 0.50
                end

                H.HitEnemySkill(bs2, e, dmgPerShard, "ice", {},
                    s.x, s.y, CombatUtils.KNOCKBACK_SKILL * 0.5, xSources)

                if not e.dead then
                    H.ApplyChill(e, 0.20, 1.5)
                end

                -- 毁灭: 累计命中, 达到 shardCount 则施加易伤
                if hitTracker then
                    hitTracker.counts[e] = (hitTracker.counts[e] or 0) + 1
                    if hitTracker.counts[e] >= hitTracker.total and not e.dead then
                        H.ApplyVulnerable(e, 2.0)
                    end
                end

                -- 强化: 弹射
                if hasEnhanced and not e.dead then
                    local bounceChance = e.isFrozen and 1.0 or 0.50
                    if math.random() < bounceChance then
                        local bounceTarget, bounceDist = nil, math.huge
                        for _, other in ipairs(bs2.enemies) do
                            if not other.dead and other ~= e then
                                local bdx, bdy = other.x - e.x, other.y - e.y
                                local bd = math.sqrt(bdx * bdx + bdy * bdy)
                                if bd < bounceDist then
                                    bounceTarget = other
                                    bounceDist = bd
                                end
                            end
                        end
                        if bounceTarget then
                            local bXSources = {}
                            if bounceTarget.isFrozen or alwaysFrozenBonus then
                                bXSources[#bXSources + 1] = 0.50
                            end
                            H.HitEnemySkill(bs2, bounceTarget, dmgPerShard, "ice", {},
                                bounceTarget.x, bounceTarget.y,
                                CombatUtils.KNOCKBACK_SKILL * 0.3, bXSources)
                            if not bounceTarget.dead then
                                H.ApplyChill(bounceTarget, 0.20, 1.5)
                            end
                        end
                    end
                end
            end,
        }
        table.insert(bs.frostShards, shard)
    end

    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_SKILL)
    -- 施放闪光 (短暂, 弹道有独立渲染)
    table.insert(bs.skillEffects, {
        type = "ice_shards", x = p.x, y = p.y,
        life = 0.15, maxLife = 0.15,
        areaW = bs.areaW, areaH = bs.areaH,
    })
end

-- ============================================================================
-- 寒冰甲 (ice_armor) — 冰霜屏障 (D4)
-- 持续6秒, 吸收生命上限 56%~78% 的伤害
-- 强化: 法力回复+30%[x]
-- 神秘: 周期冻伤 + 冻结伤害+15%[x]
-- 微光: 每花费50法力减1秒CD
-- ============================================================================
function SkillCaster._Cast_ice_armor(bs, skillCfg, lv, p)
    local shieldPct = skillCfg.effect(lv) / 100
    local duration = skillCfg.shieldDuration or 6.0

    local maxHP = GameState.GetMaxHP()
    local shieldValue = math.floor(maxHP * shieldPct)

    ShieldManager.Add("ice_armor", shieldValue)
    GameState.shieldTimer = duration

    -- 标记寒冰甲激活状态 (供增强效果检测)
    GameState.iceArmorActive = true
    GameState.iceArmorFrostbiteTimer = 0  -- 神秘: 冻伤周期计时
    GameState._hasIceArmorEnhanced = H.HasEnhance("ice_armor_enhanced")
    GameState._hasIceArmorMystical = H.HasEnhance("ice_armor_mystical")
    GameState._hasIceArmorShimmering = H.HasEnhance("ice_armor_shimmering")

    -- 微光: 重置法力消耗追踪
    if GameState._hasIceArmorShimmering then
        GameState.iceArmorManaSpent = 0
    end

    CombatUtils.PlaySfx("iceArmor", 0.6)
    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_SKILL)
    table.insert(bs.skillEffects, {
        type = "ice_armor", x = p.x, y = p.y,
        life = 0.5, maxLife = 0.5,
        radius = 60,
    })
end

-- ============================================================================
-- 冰霜新星 (frost_nova) — 范围冻结
-- ============================================================================
function SkillCaster._Cast_frost_nova(bs, skillCfg, lv, p)
    local element = "ice"
    local freezeDur = skillCfg.effect(lv)
    if H.HasEnhance("frost_nova_enhanced") then freezeDur = freezeDur + 1.0 end
    local dmgScale = (skillCfg.damageCoeff and skillCfg.damageCoeff(lv) or 60) / 100
    local radius = 120

    for _, e in ipairs(bs.enemies) do
        if not e.dead then
            local dx, dy = e.x - p.x, e.y - p.y
            if math.sqrt(dx * dx + dy * dy) <= radius then
                H.HitEnemySkill(bs, e, dmgScale, element, {}, p.x, p.y, CombatUtils.KNOCKBACK_SKILL)
                if not e.dead then
                    H.ApplyFreeze(e, freezeDur)
                    if H.HasEnhance("frost_nova_mystical") then
                        H.ApplyVulnerable(e, 3.0)
                    end
                end
            end
        end
    end

    -- 闪光冰霜新星: 释放后获得20%移动速度4秒
    if H.HasEnhance("frost_nova_shimmering") then
        GameState._frostNovaSpeedTimer = 4.0
    end

    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_BLAST)
    CombatUtils.PlaySfx("frostNova", 0.6)
    table.insert(bs.skillEffects, {
        type = "frost_nova", x = p.x, y = p.y,
        radius = radius, life = 0.6, maxLife = 0.6,
    })
end

-- ============================================================================
-- 暴风雪 (blizzard) — 脱手持续伤害区域 + 冻伤
-- 每1秒tick造成[250]%霜噬伤害, 同一敌人内置CD 0.5秒, 持续8秒冻伤18%
-- ============================================================================
function SkillCaster._Cast_blizzard(bs, skillCfg, lv, p)
    local dmgPct = skillCfg.effect(lv) / 100          -- 250%~350% 每tick伤害
    local duration = skillCfg.frostbiteDuration or 8   -- 持续时间
    local fbPct = (skillCfg.frostbitePct or 0.18) * 100 -- 冻伤百分比 (18%)
    local radius = 100

    -- 法师暴风雪: 持续时间延长4秒
    if H.HasEnhance("blizzard_mage") then
        duration = duration + 4
    end

    -- 强化暴风雪: 对被冻结敌人伤害+40%
    local frozenBonus = H.HasEnhance("blizzard_enhanced") and 0.40 or 0

    -- 只在释放范围内的敌人中索敌
    local castRange = skillCfg.castRange or 250
    local inRangeEnemies = {}
    for _, e in ipairs(bs.enemies) do
        if not e.dead then
            local dx, dy = e.x - p.x, e.y - p.y
            if math.sqrt(dx * dx + dy * dy) <= castRange then
                inRangeEnemies[#inRangeEnemies + 1] = e
            end
        end
    end
    if #inRangeEnemies == 0 then return end  -- 范围内无敌人则不释放

    local bestX, bestY = H.FindBestAoeCenter(inRangeEnemies, radius, p.x, p.y)

    -- 创建持续伤害+冻伤区域 (脱手技: 每1秒tick, 同一敌人ICD 0.5秒)
    table.insert(bs.fireZones, {
        x = bestX, y = bestY,
        radius = radius,
        duration = duration, maxDuration = duration,
        dmgPct = dmgPct, tickRate = 1.0, tickCD = 0,
        element = "ice", source = "blizzard",
        frostbitePct = fbPct,           -- 每tick施加冻伤量
        frozenBonus = frozenBonus,      -- 冻结敌人额外伤害
        perEnemyICD = 0.5,              -- 同一敌人内置CD
        enemyHitTimers = {},            -- 敌人命中时间戳记录
        luckyHitChance = skillCfg.luckyHitChance,
    })

    -- 激活暴风雪状态 (用于巫师暴风雪法力回复加成)
    GameState.blizzardActive = true
    GameState.blizzardTimer = duration
    GameState._hasBlizzardWizard = H.HasEnhance("blizzard_wizard")

    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_SKILL)
    CombatUtils.PlaySfx("frostWarn", 0.5)
    table.insert(bs.skillEffects, {
        type = "blizzard", x = bestX, y = bestY,
        radius = radius, life = 1.0, maxLife = 1.0,
    })
end

-- ============================================================================
-- 冰封球 (frozen_orb) — 滚动冰球 + 爆炸
-- ============================================================================
function SkillCaster._Cast_frozen_orb(bs, skillCfg, lv, p)
    local element = "ice"
    local dmgScale = skillCfg.effect(lv) / 100
    local radius = 100

    local bestX, bestY = H.FindBestAoeCenter(bs.enemies, radius, p.x, p.y)

    for _, e in ipairs(bs.enemies) do
        if not e.dead then
            local dx, dy = e.x - bestX, e.y - bestY
            if math.sqrt(dx * dx + dy * dy) <= radius then
                H.HitEnemySkill(bs, e, dmgScale, element, {}, bestX, bestY, CombatUtils.KNOCKBACK_SKILL)
                if not e.dead then
                    H.ApplyChill(e, 0.30, 2.0)
                    if H.HasEnhance("frozen_orb_destructive") then
                        H.ApplyFreeze(e, 2.0)
                    end
                end
            end
        end
    end

    -- 强化冰封球: 移速+30% (3秒)
    local hasOrbEnhanced = H.HasEnhance("frozen_orb_enhanced")
    if hasOrbEnhanced then
        GameState._frozenOrbSpeedTimer = 3.0
    end

    if H.HasEnhance("frozen_orb_greater") then
        -- 强化冰封球: greater 区域持续时间+1秒
        local zoneDur = hasOrbEnhanced and 5.0 or 4.0
        table.insert(bs.fireZones, {
            x = bestX, y = bestY,
            radius = radius,
            duration = zoneDur, maxDuration = zoneDur,
            dmgPct = 0.15, tickRate = 0.5, tickCD = 0,
            element = "ice", source = "frozen_orb_greater",
        })
    end

    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_BLAST)
    CombatUtils.PlaySfx("frozenOrb", 0.7)
    table.insert(bs.skillEffects, {
        type = "frozen_orb", x = bestX, y = bestY,
        radius = radius, life = 0.8, maxLife = 0.8,
    })
end

-- ============================================================================
-- 深度冻结 (deep_freeze) — CC免疫4秒 + 跟随玩家AOE持续伤害 + 冻伤 + 结束爆炸
-- ============================================================================
function SkillCaster._Cast_deep_freeze(bs, skillCfg, lv, p)
    local duration   = skillCfg.duration or 4.0
    local radius     = skillCfg.aoeRadius or 120
    local tickDmgPct = skillCfg.tickDmgPct(lv)         -- 每tick伤害%
    local burstPct   = skillCfg.effect(lv) / 100        -- 结束爆炸伤害%
    local fbPerSec   = skillCfg.frostbitePctPerSec       -- 冻伤%/秒 (常量)
    local tickRate   = skillCfg.tickRate or 1.0

    -- 至尊深度冻结: 免疫期间每2秒回复10法力 (标记, BuffRuntime 执行)
    if H.HasEnhance("deep_freeze_supreme") then
        GameState._deepFreezeSupreme = true
        GameState._deepFreezeManaTick = 0
    else
        GameState._deepFreezeSupreme = false
    end

    -- 1) 激活 CC 免疫 (BuffRuntime 管理计时)
    GameState.ActivateDeepFreeze(duration, burstPct, radius, bs)

    -- 2) 创建跟随玩家的持续伤害区域
    table.insert(bs.fireZones, {
        x = p.x, y = p.y,
        radius = radius,
        duration = duration, maxDuration = duration,
        dmgPct = tickDmgPct,
        tickRate = tickRate, tickCD = 0,
        element = "ice", source = "deep_freeze",
        frostbitePct = fbPerSec,           -- 每tick施加冻伤
        followPlayer = true,               -- 跟随玩家位置
        luckyHitChance = skillCfg.luckyHitChance,
        -- 结束爆炸参数 (MeteorSystem 消散时触发)
        burstDmgPct = burstPct,
    })

    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_STORM)
    CombatUtils.PlaySfx("frostWarn", 0.8)
    table.insert(bs.skillEffects, {
        type = "deep_freeze",
        life = 1.0, maxLife = 1.0,
        areaW = bs.areaW, areaH = bs.areaH,
    })
end

end -- Register

return { Register = Register }
