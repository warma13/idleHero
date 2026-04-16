-- ============================================================================
-- battle/skills/LightningSkills.lua - 闪电系 + 奥术技能施放
-- spark, arcane_strike, charged_bolts, chain_lightning, teleport,
-- lightning_spear, thunderstorm, energy_pulse, thunder_storm
-- ============================================================================

local GameState      = require("GameState")
local CombatUtils    = require("battle.CombatUtils")
local H              = require("battle.skills.Helpers")
local ShieldManager  = require("state.ShieldManager")

local function Register(SkillCaster)

-- ============================================================================
-- 电花 (spark) — 基础闪电: 对同一目标连续4段
-- 强化: 暴击叠加 | 闪烁: 每段生成法力 | 闪耀: +2段
-- ============================================================================
function SkillCaster._Cast_spark(bs, skillCfg, lv, p)
    local element = "lightning"
    local dmgPerHit = skillCfg.effect(lv) / 100
    local hitCount = skillCfg.hitCount or 4
    if H.HasEnhance("spark_glinting") then
        hitCount = hitCount + 2
    end

    local hasManaGen = H.HasEnhance("spark_flickering")
    local manaPerHit = hasManaGen and 1 or 0

    -- 强化电花: 每次施放暴击率+2%, 最多叠加至8%
    if H.HasEnhance("spark_enhanced") then
        GameState._sparkCritStacks = math.min((GameState._sparkCritStacks or 0) + 0.02, 0.08)
    end

    local range = 200 * GameState.GetRangeFactor()
    local target = H.FindNearestEnemy(bs.enemies, p.x, p.y, range)
    if not target then return end
    CombatUtils.PlaySfx("spark", 0.5)

    local manaGained = 0
    for i = 1, hitCount do
        if target.dead then break end
        local bonuses = {}
        H.HitEnemySkill(bs, target, dmgPerHit, element, bonuses, p.x, p.y, CombatUtils.KNOCKBACK_SKILL * 0.5)
        -- 闪烁: 每段生成1点法力 (最多4点/次)
        if hasManaGen and manaGained < 4 then
            local maxMana = GameState.GetMaxMana()
            GameState.playerMana = math.min(maxMana, GameState.playerMana + manaPerHit)
            manaGained = manaGained + 1
        end
    end

    -- 神秘传送: 4秒内电花额外命中2个敌人
    if (GameState._teleportMysticalTimer or 0) > 0 then
        local extraTargets = H.GetAliveEnemiesInRange(bs.enemies, p.x, p.y, range)
        local extraHit = 0
        for _, e in ipairs(extraTargets) do
            if e ~= target and not e.dead and extraHit < 2 then
                H.HitEnemySkill(bs, e, dmgPerHit, element, {}, p.x, p.y, CombatUtils.KNOCKBACK_SKILL * 0.5)
                extraHit = extraHit + 1
            end
        end
    end

    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_NORMAL)
    table.insert(bs.skillEffects, {
        type = "spark", x = p.x, y = p.y,
        targetX = target.x, targetY = target.y,
        hitCount = hitCount,
        life = 0.4, maxLife = 0.4,
    })
end

-- ============================================================================
-- 电弧打击 (arcane_strike) — 基础闪电: 每10次释放击晕2秒
-- 强化: 间隔缩至7次/眩晕3秒 | 闪烁: 生成法力 | 闪耀: 攻速加成
-- ============================================================================
function SkillCaster._Cast_arcane_strike(bs, skillCfg, lv, p)
    local element = "lightning"
    local range = 100 * GameState.GetRangeFactor()
    local dmgScale = skillCfg.effect(lv) / 100

    local hasEnhanced = H.HasEnhance("arcane_strike_enhanced")
    local hasManaGen  = H.HasEnhance("arcane_strike_flickering")
    local hasAtkSpd   = H.HasEnhance("arcane_strike_glinting")

    -- 眩晕计数器
    local stunInterval = hasEnhanced and 7 or (skillCfg.stunInterval or 10)
    local stunDur      = hasEnhanced and 3.0 or (skillCfg.stunDuration or 2.0)
    GameState._arcaneStrikeCastCount = (GameState._arcaneStrikeCastCount or 0) + 1
    local shouldStun = (GameState._arcaneStrikeCastCount % stunInterval == 0)

    CombatUtils.PlaySfx("arcaneStrike", 0.6)
    local hitAny = false
    for _, e in ipairs(bs.enemies) do
        if not e.dead then
            local dx, dy = e.x - p.x, e.y - p.y
            if math.sqrt(dx * dx + dy * dy) <= range then
                local bonuses = {}
                H.HitEnemySkill(bs, e, dmgScale, element, bonuses, p.x, p.y, 0)
                -- 每N次释放触发眩晕 (Boss免疫)
                if shouldStun and not e.dead and not e.isBoss then
                    H.ApplyStun(e, stunDur)
                end
                hitAny = true
            end
        end
    end

    -- 闪烁: 命中时生成3点法力
    if hasManaGen and hitAny then
        local maxMana = GameState.GetMaxMana()
        GameState.playerMana = math.min(maxMana, GameState.playerMana + 3)
    end
    -- 闪耀: 命中时10%攻速加成3秒
    if hasAtkSpd and hitAny then
        GameState._arcaneStrikeAtkSpdTimer = 3.0
    end

    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_SKILL)
    table.insert(bs.skillEffects, {
        type = "arcane_strike", x = p.x, y = p.y,
        radius = range, life = 0.3, maxLife = 0.3,
    })
end

-- ============================================================================
-- 电荷弹 (charged_bolts) — 散射弹幕, 多弹体独立判定
-- 基础: 5弹散射, 20%眩晕0.5s
-- 强化: +2弹+30%眩晕 | 闪烁: 对眩晕+40%+眩晕回蓝 | 闪耀: 3+命中同目标触发过载
-- ============================================================================
function SkillCaster._Cast_charged_bolts(bs, skillCfg, lv, p)
    local element = "lightning"
    local dmgPerBolt = skillCfg.effect(lv) / 100

    local hasEnhanced = H.HasEnhance("charged_bolts_enhanced")
    local hasFlicker  = H.HasEnhance("charged_bolts_flickering")
    local hasGlinting = H.HasEnhance("charged_bolts_glinting")

    -- 弹体数量: 基础5, 强化+2
    local boltCount = (skillCfg.boltCount or 5) + (hasEnhanced and 2 or 0)
    -- 眩晕概率: 基础20%, 强化30%
    local stunChance = hasEnhanced and 0.30 or (skillCfg.stunChance or 0.20)
    local stunDur = skillCfg.stunDuration or 0.5

    local skillRange = 200 * GameState.GetRangeFactor()
    local alive = H.GetAliveEnemiesInRange(bs.enemies, p.x, p.y, skillRange)
    if #alive == 0 then return end

    CombatUtils.PlaySfx("chargedBolts", 0.6)

    -- 记录每个敌人被命中次数 (闪耀过载用)
    local hitCounts = {}  -- hitCounts[enemy] = count
    local stunTriggered = 0

    -- 每枚弹体独立选择目标: 随机散射到存活敌人
    local boltTargets = {}  -- 存放每枚弹体的目标引用
    for i = 1, boltCount do
        local target = alive[math.random(#alive)]
        boltTargets[i] = target

        local xSources = {}
        -- 闪烁: 对已眩晕敌人+40%
        if hasFlicker and target.stunTimer and target.stunTimer > 0 then
            xSources[#xSources + 1] = 0.40
        end

        H.HitEnemySkill(bs, target, dmgPerBolt, element, {}, p.x, p.y,
            CombatUtils.KNOCKBACK_SKILL * 0.5, xSources)

        -- 眩晕判定 (Boss免疫)
        if not target.dead and not target.isBoss and math.random() < stunChance then
            H.ApplyStun(target, stunDur)
            stunTriggered = stunTriggered + 1
        end

        -- 统计命中次数
        hitCounts[target] = (hitCounts[target] or 0) + 1
    end

    -- 闪烁: 每次眩晕敌人回复2法力
    if hasFlicker and stunTriggered > 0 then
        GameState.AddMana(2 * stunTriggered)
    end

    -- 闪耀: 3+弹命中同目标触发电荷过载
    if hasGlinting then
        for e, count in pairs(hitCounts) do
            if count >= 3 and not e.dead then
                -- 过载: 对目标额外60%武器伤害
                H.HitEnemySkill(bs, e, 0.60, element, {}, p.x, p.y, 0)
                -- 过载溅射: 对周围敌人30%武器伤害
                local splashRadius = 80
                for _, e2 in ipairs(bs.enemies) do
                    if not e2.dead and e2 ~= e then
                        local dx, dy = e2.x - e.x, e2.y - e.y
                        if math.sqrt(dx * dx + dy * dy) <= splashRadius then
                            H.HitEnemySkill(bs, e2, 0.30, element, {}, e.x, e.y, 0)
                        end
                    end
                end
                -- 过载特效
                table.insert(bs.skillEffects, {
                    type = "charged_bolts_overload", x = e.x, y = e.y,
                    radius = splashRadius, life = 0.3, maxLife = 0.3,
                })
            end
        end
    end

    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_BLAST)
    -- 收集弹体目标坐标 (供弹道特效用)
    local boltTargetData = {}
    for i = 1, boltCount do
        local t = boltTargets[i]
        if t then
            boltTargetData[i] = { x = t.x, y = t.y }
        end
    end
    table.insert(bs.skillEffects, {
        type = "charged_bolts", x = p.x, y = p.y,
        boltCount = boltCount,
        boltTargets = boltTargetData,
        life = 0.5, maxLife = 0.5,
    })
end

-- ============================================================================
-- 连锁闪电 (chain_lightning) — 弹跳链电, 越弹越强
-- 基础: 6次弹跳, 每跳+10%
-- 强化: +2弹跳+3%暴击/跳 | 闪烁: 对眩晕双倍+延长+击杀多跳 | 闪耀: 递增→20%+末尾雷暴AOE
-- ============================================================================
function SkillCaster._Cast_chain_lightning(bs, skillCfg, lv, p)
    local element = "lightning"
    local baseDmgScale = skillCfg.effect(lv) / 100

    local hasEnhanced = H.HasEnhance("chain_lightning_enhanced")
    local hasFlicker  = H.HasEnhance("chain_lightning_flickering")
    local hasGlinting = H.HasEnhance("chain_lightning_glinting")

    -- 弹跳次数: 基础6, 强化+2
    local bounces = (skillCfg.bounceCount or 6) + (hasEnhanced and 2 or 0)
    -- 每次弹跳递增: 基础+10%, 闪耀升至+20%
    local rampPct = hasGlinting and 0.20 or (skillCfg.bounceRampPct or 0.10)
    -- 每次弹跳暴击: 强化+3%/跳
    local critPerBounce = hasEnhanced and 0.03 or 0

    local skillRange = 250 * GameState.GetRangeFactor()
    local alive = H.GetAliveEnemiesInRange(bs.enemies, p.x, p.y, skillRange)
    if #alive == 0 then return end

    CombatUtils.PlaySfx("chainLightning", 0.6)

    -- 选择范围内最近的存活敌人作为第一个目标
    local lastTarget = H.FindNearestEnemy(bs.enemies, p.x, p.y, skillRange) or alive[1]
    local lastTargetForEffect = lastTarget  -- 记录最后弹跳目标(闪耀雷暴用)
    -- 记录弹跳链路径 (供特效渲染)
    local chainPath = { { x = p.x, y = p.y } } -- 起点=玩家

    local totalBounces = bounces
    local i = 1
    while i <= totalBounces do
        if not lastTarget or lastTarget.dead then
            -- 目标死亡, 重新选一个附近的存活敌人 (弹跳范围内)
            local bounceRange = 150
            local nearbyAlive = H.GetAliveEnemiesInRange(bs.enemies, chainPath[#chainPath].x, chainPath[#chainPath].y, bounceRange)
            if #nearbyAlive == 0 then break end
            lastTarget = nearbyAlive[math.random(#nearbyAlive)]
        end

        -- 伤害递增
        local rampMul = 1.0 + rampPct * (i - 1)
        local thisDmg = baseDmgScale * rampMul

        -- 构建额外伤害源
        local xSources = {}

        -- 闪烁: 弹跳到眩晕敌人时双倍伤害
        local isStunned = lastTarget.stunTimer and lastTarget.stunTimer > 0
        if hasFlicker and isStunned then
            xSources[#xSources + 1] = 1.00  -- +100% = 双倍
        end

        -- 强化: 每次弹跳+3%暴击 (通过临时修改暴击率)
        local savedCrit = nil
        if critPerBounce > 0 then
            savedCrit = GameState._tempCritBonus or 0
            GameState._tempCritBonus = savedCrit + critPerBounce * (i - 1)
        end

        local _, isCrit = H.HitEnemySkill(bs, lastTarget, thisDmg, element, {}, p.x, p.y,
            CombatUtils.KNOCKBACK_SKILL * 0.3, xSources)

        -- 恢复暴击率
        if savedCrit ~= nil then
            GameState._tempCritBonus = savedCrit
        end

        -- 闪烁: 命中眩晕敌人时延长眩晕0.5秒
        if hasFlicker and isStunned and not lastTarget.dead then
            H.ApplyStun(lastTarget, lastTarget.stunTimer + 0.5)
        end

        -- 闪烁: 击杀敌人时额外弹跳2次
        if hasFlicker and lastTarget.dead then
            totalBounces = totalBounces + 2
        end

        lastTargetForEffect = lastTarget
        -- 记录弹跳路径节点
        chainPath[#chainPath + 1] = { x = lastTarget.x, y = lastTarget.y }

        -- 寻找下一个弹跳目标: 弹跳范围内最近的其他敌人
        local bounceSearchRange = 150
        local nextTarget = nil
        local nextDist = math.huge
        for _, e in ipairs(bs.enemies) do
            if not e.dead and e ~= lastTarget then
                local dx, dy = e.x - lastTarget.x, e.y - lastTarget.y
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist <= bounceSearchRange and dist < nextDist then
                    nextTarget = e
                    nextDist = dist
                end
            end
        end
        -- 若无其他目标, 在同一目标上继续弹跳
        lastTarget = nextTarget or lastTarget

        i = i + 1
    end

    -- 闪耀: 最后一次弹跳触发雷暴AOE
    if hasGlinting and lastTargetForEffect and not lastTargetForEffect.dead then
        local thunderRadius = 90
        local thunderDmg = 0.50  -- 50%武器伤害
        for _, e in ipairs(bs.enemies) do
            if not e.dead then
                local dx, dy = e.x - lastTargetForEffect.x, e.y - lastTargetForEffect.y
                if math.sqrt(dx * dx + dy * dy) <= thunderRadius then
                    H.HitEnemySkill(bs, e, thunderDmg, element, {},
                        lastTargetForEffect.x, lastTargetForEffect.y, CombatUtils.KNOCKBACK_SKILL)
                end
            end
        end
        table.insert(bs.skillEffects, {
            type = "chain_lightning_thunder",
            x = lastTargetForEffect.x, y = lastTargetForEffect.y,
            radius = thunderRadius, life = 0.4, maxLife = 0.4,
        })
    end

    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_SKILL)
    table.insert(bs.skillEffects, {
        type = "chain_lightning",
        x = p.x, y = p.y,
        life = 0.6, maxLife = 0.6,
        bounces = totalBounces,
        chainPath = chainPath,
    })
end

-- ============================================================================
-- 传送 (teleport) — 位移 + 闪电伤害
-- ============================================================================
function SkillCaster._Cast_teleport(bs, skillCfg, lv, p)
    local element = "lightning"
    local dmgScale = skillCfg.effect(lv) / 100
    local radius = 80
    local teleportRange = 250  -- 传送最大搜索距离

    local hasEnhanced  = H.HasEnhance("teleport_enhanced")
    local hasMystical   = H.HasEnhance("teleport_mystical")
    local hasShimmering = H.HasEnhance("teleport_shimmering")

    -- ── 筛选传送范围内的敌人 ──
    local inRange = {}
    for _, e in ipairs(bs.enemies) do
        if not e.dead then
            local dx, dy = e.x - p.x, e.y - p.y
            if math.sqrt(dx * dx + dy * dy) <= teleportRange then
                inRange[#inRange + 1] = e
            end
        end
    end

    -- 在范围子集中找最优聚集点；无目标则原地释放
    local bestX, bestY
    if #inRange > 0 then
        bestX, bestY = H.FindBestAoeCenter(inRange, radius, p.x, p.y)
    else
        bestX, bestY = p.x, p.y
    end

    local hitCount = 0
    for _, e in ipairs(inRange) do
        local dx, dy = e.x - bestX, e.y - bestY
        if math.sqrt(dx * dx + dy * dy) <= radius then
            hitCount = hitCount + 1
            H.HitEnemySkill(bs, e, dmgScale, element, {}, bestX, bestY, CombatUtils.KNOCKBACK_SKILL)
        end
    end

    -- ── 位移：根据血量风险评估落点（仅范围内有敌人时位移） ──
    if #inRange > 0 then
        local margin = 30
        local hpRatio = GameState.playerHP / math.max(1, GameState.GetMaxHP())
        local safeThreshold = hasShimmering and 0.25 or 0.50
        local critThreshold = hasShimmering and 0.10 or 0.25

        local destX, destY = bestX, bestY
        if hpRatio < safeThreshold then
            local dx, dy = p.x - bestX, p.y - bestY
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < 1 then dx, dy, dist = 0, -1, 1 end
            local nx, ny = dx / dist, dy / dist
            if hpRatio < critThreshold then
                destX = bestX + nx * radius * 1.5
                destY = bestY + ny * radius * 1.5
            else
                destX = bestX + nx * radius * 0.8
                destY = bestY + ny * radius * 0.8
            end
        end
        p.x = math.max(margin, math.min(bs.areaW - margin, destX))
        p.y = math.max(margin, math.min(bs.areaH - margin, destY))
    end

    -- 强化传送: 每命中1个敌人CD-0.5秒(最多-3秒)
    if hasEnhanced and hitCount > 0 then
        local cdReduce = math.min(hitCount * 0.5, 3.0)
        if p.skillTimers and p.skillTimers["teleport"] then
            p.skillTimers["teleport"] = math.max(0, p.skillTimers["teleport"] - cdReduce)
        end
    end

    -- 神秘传送: 4秒内爆裂电花额外命中2个敌人 (标记给spark/电花使用)
    if hasMystical then
        GameState._teleportMysticalTimer = 4.0
    end

    -- 闪光传送: 获得30%伤害减免3秒
    if hasShimmering then
        GameState._teleportDmgReduceTimer = 3.0
    end

    CombatUtils.PlaySfx("teleport", 0.6)
    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_SKILL)
    table.insert(bs.skillEffects, {
        type = "teleport", x = bestX, y = bestY,
        radius = radius, life = 0.4, maxLife = 0.4,
    })
end

-- ============================================================================
-- 闪电矛 (lightning_spear) — 追踪闪电持续攻击
-- ============================================================================
function SkillCaster._Cast_lightning_spear(bs, skillCfg, lv, p)
    local element = "lightning"
    local dmgScale = skillCfg.effect(lv) / 100
    local duration = 6.0
    if H.HasEnhance("lightning_spear_greater") then duration = duration + 2.0 end

    table.insert(GameState.spirits, {
        x = p.x, y = p.y - 20,
        timer = duration,
        atkCD = 0,
        atkInterval = 0.8,
        dmgScale = dmgScale,
        atkRange = 250,
        element = "lightning",
        orbitAngle = math.random() * math.pi * 2,
        source = "lightning_spear",
    })

    CombatUtils.PlaySfx("lightningSpear", 0.6)
    table.insert(bs.skillEffects, {
        type = "lightning_spear", x = p.x, y = p.y,
        life = 0.4, maxLife = 0.4,
    })
end

-- ============================================================================
-- 雷暴 (thunderstorm) — 闪电持续区域
-- ============================================================================
function SkillCaster._Cast_thunderstorm(bs, skillCfg, lv, p)
    local duration = 6.0
    local tickDmg = skillCfg.effect(lv) / 100
    local radius = 100
    if H.HasEnhance("thunderstorm_enhanced") then radius = math.floor(radius * 1.25) end

    local bestX, bestY = H.FindBestAoeCenter(bs.enemies, radius, p.x, p.y)

    table.insert(bs.fireZones, {
        x = bestX, y = bestY,
        radius = radius,
        duration = duration, maxDuration = duration,
        dmgPct = tickDmg, tickRate = 1.0, tickCD = 0,
        element = "lightning", source = "thunderstorm",
        bonusDmg = H.HasEnhance("thunderstorm_destructive") and 0.20 or 0,
        endStun = H.HasEnhance("thunderstorm_greater") and 1.5 or nil,
    })

    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_STORM)
    CombatUtils.PlaySfx("thunderStorm", 0.6)
    table.insert(bs.skillEffects, {
        type = "thunderstorm", x = bestX, y = bestY,
        radius = radius, life = 1.0, maxLife = 1.0,
    })
end

-- ============================================================================
-- 能量脉冲 (energy_pulse) — 全方向能量波
-- ============================================================================
function SkillCaster._Cast_energy_pulse(bs, skillCfg, lv, p)
    local element = "lightning"
    local dmgScale = skillCfg.effect(lv) / 100
    local radius = 130

    local kbMul = CombatUtils.KNOCKBACK_SKILL * 1.5
    if H.HasEnhance("energy_pulse_enhanced") then kbMul = kbMul * 1.5 end

    for _, e in ipairs(bs.enemies) do
        if not e.dead then
            local dx, dy = e.x - p.x, e.y - p.y
            if math.sqrt(dx * dx + dy * dy) <= radius then
                local bonuses = {}
                if H.HasEnhance("energy_pulse_destructive") then
                    if e.hp and e.maxHP and e.maxHP > 0 and e.hp / e.maxHP < 0.30 then
                        bonuses.destructive = 0.40
                    end
                end
                local _, isCrit = H.HitEnemySkill(bs, e, dmgScale, element, bonuses, p.x, p.y, kbMul)
                if H.HasEnhance("energy_pulse_greater") and isCrit then
                    local shield = math.floor(GameState.GetMaxHP() * 0.05)
                    ShieldManager.Add("energy_pulse", shield)
                end
            end
        end
    end

    CombatUtils.PlaySfx("energyPulse", 0.6)
    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_BLAST)
    table.insert(bs.skillEffects, {
        type = "energy_pulse", x = p.x, y = p.y,
        radius = radius, life = 0.6, maxLife = 0.6,
    })
end

-- ============================================================================
-- 雷霆风暴 (thunder_storm) — 持续闪电风暴
-- ============================================================================
function SkillCaster._Cast_thunder_storm(bs, skillCfg, lv, p)
    local element = "lightning"
    local dmgScale = skillCfg.effect(lv) / 100
    local duration = 8.0
    if H.HasEnhance("thunder_storm_prime") then duration = duration + 2.0 end

    for _, e in ipairs(bs.enemies) do
        if not e.dead then
            H.HitEnemySkill(bs, e, dmgScale * 0.5, element, {}, bs.areaW * 0.5, e.y, CombatUtils.KNOCKBACK_SKILL)
        end
    end

    table.insert(bs.fireZones, {
        x = bs.areaW * 0.5, y = bs.areaH * 0.5,
        radius = math.floor(math.min(bs.areaW, bs.areaH) * 0.45),
        duration = duration, maxDuration = duration,
        dmgPct = dmgScale * 0.3, tickRate = 1.0, tickCD = 0,
        element = "lightning", source = "thunder_storm",
    })

    -- 至尊雷霆风暴: 持续期间闪电技能CD-20%
    if H.HasEnhance("thunder_storm_supreme") then
        GameState._thunderStormSupremeTimer = duration
    end

    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_STORM * 2)
    CombatUtils.PlaySfx("thunderStorm", 0.8)
    table.insert(bs.skillEffects, {
        type = "thunder_storm",
        life = 1.5, maxLife = 1.5,
        areaW = bs.areaW, areaH = bs.areaH,
    })
end

end -- Register

return { Register = Register }
