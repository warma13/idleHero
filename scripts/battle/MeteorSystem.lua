-- ============================================================================
-- battle/MeteorSystem.lua - 陨石延迟落地 + 风暴冲击 + 元素区域
-- ============================================================================

local Config            = require("Config")
local GameState         = require("GameState")
local Particles         = require("battle.Particles")
local CombatUtils       = require("battle.CombatUtils")
local DamageFormula     = require("battle.DamageFormula")

local MeteorSystem = {}

-- ============================================================================
-- 陨石延迟落地处理
-- ============================================================================

function MeteorSystem.UpdatePendingMeteors(dt, bs)
    for i = #bs.pendingMeteors, 1, -1 do
        local m = bs.pendingMeteors[i]
        m.delay = m.delay - dt
        if m.delay <= 0 then
            table.remove(bs.pendingMeteors, i)
            MeteorSystem.StormImpact(bs, m)
        end
    end
end

-- ============================================================================
-- 风暴冲击 (陨石落地伤害 + 元素附着)
-- ============================================================================

function MeteorSystem.StormImpact(bs, meteor)
    local hitCount = 0
    local shockLv = GameState.GetSkillLevel("shockwave")
    local totemLv = GameState.GetSkillLevel("elem_totem")
    local stormElem = meteor.element or "poison"

    for _, e in ipairs(bs.enemies) do
        if not e.dead then
            local dx, dy = e.x - meteor.x, e.y - meteor.y
            if math.sqrt(dx * dx + dy * dy) <= meteor.radius then
                -- 六桶管线
                local ctx = DamageFormula.BuildContext({
                    target     = e,
                    bs         = bs,
                    multiplier = meteor.dmgScale,
                    damageTag  = "skill",
                    element    = stormElem,
                    forceCrit  = false,
                })
                local finalDmg = DamageFormula.Calculate(ctx)
                local EnemySys = require("battle.EnemySystem")
                finalDmg = EnemySys.ApplyDamageReduction(e, finalDmg)
                EnemySys.ApplyDamage(e, finalDmg, bs)
                -- 风暴吸血 (技能效率)
                GameState.LifeStealHeal(finalDmg, Config.LIFESTEAL.efficiency.skill)
                -- 冲击波: 增强击退 + 减速
                local kbMul = CombatUtils.KNOCKBACK_SKILL * 1.5
                if shockLv > 0 then
                    kbMul = kbMul * (1 + shockLv * 0.5)
                    e.slowTimer = 2.0
                    e.slowFactor = 1.0 - (0.20 + shockLv * 0.10)
                end
                -- 冰霜凝滞: 冰系陨石命中额外减速
                if stormElem == "ice" then
                    local frostSlowLv = GameState.GetSkillLevel("frost_slow")
                    if frostSlowLv > 0 then
                        local slowPct = (20 + frostSlowLv * 10) / 100
                        e.slowTimer = math.max(e.slowTimer or 0, 2.0)
                        e.slowFactor = math.min(e.slowFactor or 1.0, 1.0 - slowPct)
                    end
                end

                CombatUtils.ApplyKnockback(e, meteor.x, meteor.y, kbMul)
                hitCount = hitCount + 1
                local stormColor = Config.ELEMENTS.colors[meteor.element or "poison"] or { 80, 200, 60 }
                Particles.SpawnDmgText(bs.particles, e.x, e.y - (e.radius or 16) - 10, finalDmg, false, true, stormColor)
            end
        end
    end

    -- 元素图腾: 风暴落点留持续元素区域（冰系陨石不生成火圈）
    if totemLv > 0 and stormElem ~= "ice" then
        local duration = 1 + totemLv
        table.insert(bs.fireZones, {
            x = meteor.x, y = meteor.y,
            radius = meteor.radius,
            duration = duration,
            maxDuration = duration,
            dmgPct = 0.4,
            tickRate = 0.5,
            tickCD = 0,
            element = stormElem,
            source = "elem_totem",
        })
    end

    -- 冰晶凝聚: 冰系陨石落点生成冰晶持续伤害区域
    if stormElem == "ice" then
        local crystalLv = GameState.GetSkillLevel("frost_crystal")
        if crystalLv > 0 then
            local duration = 2 + crystalLv
            table.insert(bs.fireZones, {
                x = meteor.x, y = meteor.y,
                radius = math.floor(meteor.radius * 0.7),
                duration = duration,
                maxDuration = duration,
                dmgPct = 0.25,
                tickRate = 0.5,
                tickCD = 0,
                element = "ice",
                source = "frost_crystal",
            })
        end
    end

    -- 陨星余震: 奥术陨星落点产生持续脉冲区域
    if stormElem == "arcane" and meteor.aftershockLv and meteor.aftershockLv > 0 then
        local afterDur = 1 + meteor.aftershockLv
        table.insert(bs.fireZones, {
            x = meteor.x, y = meteor.y,
            radius = math.floor(meteor.radius * 0.8),
            duration = afterDur,
            maxDuration = afterDur,
            dmgPct = 0.3,
            tickRate = 0.5,
            tickCD = 0,
            element = "arcane",
            source = "meteor_aftershock",
        })
    end

    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_STORM)
    if stormElem == "ice" then
        CombatUtils.PlaySfx("frostImpact", 0.8)
        Particles.SpawnFrostExplosion(bs.particles, meteor.x, meteor.y, meteor.radius)
    else
        CombatUtils.PlaySfx("stormImpact", 0.8)
        Particles.SpawnMeteorExplosion(bs.particles, meteor.x, meteor.y, meteor.radius)
    end
end

-- ============================================================================
-- 元素区域 (图腾/毁灭领域) 持续伤害
-- ============================================================================

function MeteorSystem.UpdateFireZones(dt, bs)
    local totalAtk = GameState.GetTotalAtk()
    for i = #bs.fireZones, 1, -1 do
        local zone = bs.fireZones[i]
        -- 跟随玩家位置 (深度冻结等)
        if zone.followPlayer then
            local p = bs.playerBattle
            if p then
                zone.x = p.x
                zone.y = p.y
            end
        end
        zone.duration = zone.duration - dt
        if zone.duration <= 0 then
            -- 冰晶碎裂: 冰晶区消散时发射小冰晶
            if zone.source == "frost_crystal" then
                local shatterLv = GameState.GetSkillLevel("frost_shatter")
                if shatterLv > 0 then
                    local shardCount = 2 + shatterLv
                    local shardDmg = math.floor(totalAtk * 0.3)
                    local iceColor = Config.ELEMENTS.colors["ice"] or { 100, 200, 255 }
                    for si = 1, shardCount do
                        local angle = (si - 1) * (math.pi * 2 / shardCount)
                        local speed = 120
                        local shard = {
                            x = zone.x, y = zone.y,
                            vx = math.cos(angle) * speed,
                            vy = math.sin(angle) * speed,
                            dmg = shardDmg,
                            radius = 6,
                            life = 1.5,
                            element = "ice",
                            source = "frost_shard",
                            pierced = {},
                        }
                        if not bs.frostShards then bs.frostShards = {} end
                        table.insert(bs.frostShards, shard)
                    end
                    Particles.SpawnFrostExplosion(bs.particles, zone.x, zone.y, zone.radius * 0.6)
                    CombatUtils.PlaySfx("frostImpact", 0.4)
                end
            end
            table.remove(bs.fireZones, i)
        else
            zone.tickCD = zone.tickCD - dt
            -- per-enemy ICD: 递减所有敌人的命中计时器
            if zone.enemyHitTimers then
                for k, v in pairs(zone.enemyHitTimers) do
                    zone.enemyHitTimers[k] = v - dt
                end
            end
            if zone.tickCD <= 0 then
                zone.tickCD = zone.tickRate
                local tickBaseDmg = math.floor(totalAtk * zone.dmgPct)
                local zoneElem = zone.element or "poison"
                for _, e in ipairs(bs.enemies) do
                    if not e.dead then
                        local dx, dy = e.x - zone.x, e.y - zone.y
                        if math.sqrt(dx * dx + dy * dy) <= zone.radius then
                            -- per-enemy ICD 检查
                            if zone.perEnemyICD and zone.enemyHitTimers then
                                local lastHit = zone.enemyHitTimers[e] or -1
                                if lastHit > 0 then
                                    goto continue_enemy
                                end
                                zone.enemyHitTimers[e] = zone.perEnemyICD
                            end
                            -- 冻伤施加
                            if zone.frostbitePct and zone.frostbitePct > 0 then
                                local H = require("battle.skills.Helpers")
                                H.ApplyFrostbite(e, zone.frostbitePct)
                            end
                            -- tick 伤害 (dmgPct > 0 时才造成伤害)
                            if tickBaseDmg > 0 then
                                local hitDmg = tickBaseDmg
                                -- 冻结敌人额外伤害 (暴风雪强化)
                                if zone.frozenBonus and zone.frozenBonus > 0 and e.isFrozen then
                                    hitDmg = math.floor(hitDmg * (1 + zone.frozenBonus))
                                end
                                -- 六桶管线 (tick 伤害)
                                local ctx = DamageFormula.BuildContext({
                                    target    = e,
                                    bs        = bs,
                                    baseDmg   = hitDmg,
                                    damageTag = "skill",
                                    element   = zoneElem,
                                    forceCrit = false,
                                    luckyHitChance = zone.luckyHitChance,
                                })
                                local finalDmg = DamageFormula.Calculate(ctx)
                                local EnemySys = require("battle.EnemySystem")
                                finalDmg = EnemySys.ApplyDamageReduction(e, finalDmg)
                                EnemySys.ApplyDamage(e, finalDmg, bs)
                                -- 区域吸血 (fireZone效率)
                                GameState.LifeStealHeal(finalDmg, Config.LIFESTEAL.efficiency.fireZone)
                                local zoneColor = Config.ELEMENTS.colors[zoneElem] or { 200, 200, 200 }
                                Particles.SpawnDmgText(bs.particles, e.x, e.y - 10, finalDmg, false, false, zoneColor)
                            end
                            ::continue_enemy::
                        end
                    end
                end
            end
        end
    end
end

-- ============================================================================
-- 冰晶碎片飞行 + 碰撞伤害
-- ============================================================================

function MeteorSystem.UpdateFrostShards(dt, bs)
    if not bs.frostShards then return end
    local iceColor = Config.ELEMENTS.colors["ice"] or { 100, 200, 255 }
    for i = #bs.frostShards, 1, -1 do
        local s = bs.frostShards[i]
        s.x = s.x + s.vx * dt
        s.y = s.y + s.vy * dt
        s.life = s.life - dt

        -- 超出边界或寿命结束
        if s.life <= 0 or s.x < -20 or s.x > (bs.areaW or 400) + 20
           or s.y < -20 or s.y > (bs.areaH or 600) + 20 then
            table.remove(bs.frostShards, i)
        else
            -- 碰撞检测
            for _, e in ipairs(bs.enemies) do
                if not e.dead and not s.pierced[e] then
                    local dx, dy = e.x - s.x, e.y - s.y
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist <= (e.radius or 14) + s.radius then
                        s.pierced[e] = true
                        if s.onHit then
                            -- 自定义命中处理 (ice_shards 等)
                            s.onHit(s, e, bs)
                        else
                            -- 默认伤害 (frost_shatter 碎片)
                            local ctx = DamageFormula.BuildContext({
                                target    = e,
                                bs        = bs,
                                baseDmg   = s.dmg,
                                damageTag = "skill",
                                element   = "ice",
                                forceCrit = false,
                            })
                            local finalDmg = DamageFormula.Calculate(ctx)
                            local EnemySys = require("battle.EnemySystem")
                            finalDmg = EnemySys.ApplyDamageReduction(e, finalDmg)
                            EnemySys.ApplyDamage(e, finalDmg, bs)
                            GameState.LifeStealHeal(finalDmg, Config.LIFESTEAL.efficiency.fireZone)
                            Particles.SpawnDmgText(bs.particles, e.x, e.y - 10, finalDmg, false, false, iceColor)
                        end
                        -- 碎片命中后消失
                        table.remove(bs.frostShards, i)
                        break
                    end
                end
            end
        end
    end
end

-- ============================================================================
-- 毒池持续伤害区域 (poison_rain 技能生成)
-- ============================================================================

function MeteorSystem.UpdatePoisonPools(dt, bs)
    if not bs.poisonPools then return end
    local totalAtk = GameState.GetTotalAtk()
    local poisonColor = Config.ELEMENTS.colors["poison"] or { 80, 200, 60 }

    for i = #bs.poisonPools, 1, -1 do
        local pool = bs.poisonPools[i]
        pool.timer = pool.timer - dt
        if pool.timer <= 0 then
            table.remove(bs.poisonPools, i)
        else
            pool.tickCD = (pool.tickCD or 0) - dt
            if pool.tickCD <= 0 then
                pool.tickCD = 1.0
                local tickBaseDmg = pool.dmgPerSec or math.floor(totalAtk * 0.3)
                local poolElem = pool.element or "poison"
                for _, e in ipairs(bs.enemies) do
                    if not e.dead then
                        local dx, dy = e.x - pool.x, e.y - pool.y
                        if math.sqrt(dx * dx + dy * dy) <= pool.radius then
                            -- 六桶管线 (tick 伤害, baseDmg 预计算, 不暴击)
                            local ctx = DamageFormula.BuildContext({
                                target    = e,
                                bs        = bs,
                                baseDmg   = tickBaseDmg,
                                damageTag = "skill",
                                element   = poolElem,
                                forceCrit = false,
                            })
                            local finalDmg = DamageFormula.Calculate(ctx)
                            local EnemySys = require("battle.EnemySystem")
                            finalDmg = EnemySys.ApplyDamageReduction(e, finalDmg)
                            EnemySys.ApplyDamage(e, finalDmg, bs)
                            GameState.LifeStealHeal(finalDmg, Config.LIFESTEAL.efficiency.fireZone)
                            Particles.SpawnDmgText(bs.particles, e.x, e.y - 10, finalDmg, false, false, poisonColor)
                            -- 毒池减速天赋
                            if pool.slowRate and pool.slowRate > 0 then
                                e.slowTimer = math.max(e.slowTimer or 0, 1.5)
                                e.slowFactor = math.min(e.slowFactor or 1.0, 1.0 - pool.slowRate)
                            end
                        end
                    end
                end
            end
        end
    end
end

-- ============================================================================
-- 冰晶弹幕延迟波次处理
-- ============================================================================

function MeteorSystem.UpdatePendingBarrageWaves(dt, bs)
    if not bs.pendingBarrageWaves then return end
    local SkillCaster = require("battle.SkillCaster")

    for i = #bs.pendingBarrageWaves, 1, -1 do
        local wave = bs.pendingBarrageWaves[i]
        wave.delay = wave.delay - dt
        if wave.delay <= 0 then
            table.remove(bs.pendingBarrageWaves, i)
            SkillCaster._IceBarrageWave(
                bs, wave.skillCfg, wave.lv, bs.playerBattle,
                wave.attachGrade, wave.freezeLv, wave.shatterBonusLv
            )
        end
    end
end

return MeteorSystem
