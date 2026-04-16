-- ============================================================================
-- battle/EnemySystem.lua - 敌人减益/AI/攻击/特殊能力
-- ============================================================================

local Config           = require("Config")
local GameState        = require("GameState")
local StageConfig      = require("StageConfig")
local Particles        = require("battle.Particles")
local CombatUtils      = require("battle.CombatUtils")
local MonsterFamilies  = require("MonsterFamilies")
local EnemyAnim        = require("battle.EnemyAnim")

local EnemySystem = {}

-- 前向声明（定义在文件末尾，但需在 EnemyAttackPlayer 中调用）
local ApplyChargeUpAttack
local ApplyChainLightning
local ApplySandStorm
local ApplyVenomStack

-- ============================================================================
-- 敌人身上的元素附着衰减和反应debuff
-- ============================================================================

--- @param bs table BattleSystem 引用
function EnemySystem.UpdateEnemyDebuffs(dt, bs)
    for _, e in ipairs(bs.enemies) do
        if not e.dead then
            -- 元素附着衰减
            if e.attachedElementTimer and e.attachedElementTimer > 0 then
                e.attachedElementTimer = e.attachedElementTimer - dt
                if e.attachedElementTimer <= 0 then
                    e.attachedElement = nil
                    e.attachedElementTimer = 0
                end
            end
            -- 防御降低衰减
            if e.defReduceTimer and e.defReduceTimer > 0 then
                e.defReduceTimer = e.defReduceTimer - dt
                if e.defReduceTimer <= 0 then
                    e.defReduceRate = 0
                    e.defReduceTimer = 0
                end
            end
            -- 元素削弱衰减
            if e.elemWeakenTimer and e.elemWeakenTimer > 0 then
                e.elemWeakenTimer = e.elemWeakenTimer - dt
                if e.elemWeakenTimer <= 0 then
                    e.elemWeakenRate = 0
                    e.elemWeakenTimer = 0
                end
            end
            -- 攻速降低衰减 (磐岩反震)
            if e._atkSpeedReduceTimer and e._atkSpeedReduceTimer > 0 then
                e._atkSpeedReduceTimer = e._atkSpeedReduceTimer - dt
                if e._atkSpeedReduceTimer <= 0 then
                    e._atkSpeedReduceRate = 0
                    e._atkSpeedReduceTimer = 0
                end
            end
            -- 反应DoT tick
            if e.reactionDot then
                local dot = e.reactionDot
                dot.timer = dot.timer - dt
                if dot.timer <= 0 then
                    e.reactionDot = nil
                else
                    dot.tickCD = dot.tickCD - dt
                    if dot.tickCD <= 0 then
                        dot.tickCD = dot.tickRate
                        EnemySystem.ApplyDamage(e, dot.dmgPerTick, bs)
                        Particles.SpawnDmgText(bs.particles, e.x, e.y - (e.radius or 16) - 5, dot.dmgPerTick, false, false, { 80, 200, 60 })
                    end
                end
            end
        end
    end
end

-- ============================================================================
-- 敌人AI: 靠近玩家 + 近身攻击 (远程怪保持距离)
-- ============================================================================

--- @param bs table BattleSystem 引用
function EnemySystem.UpdateEnemyAI(dt, bs)
    if GameState.playerDead then return end
    local p = bs.playerBattle
    for _, e in ipairs(bs.enemies) do
        if not e.dead then
            -- 处理击退
            local kbSpeed = math.sqrt(e.knockbackVx * e.knockbackVx + e.knockbackVy * e.knockbackVy)
            if kbSpeed > 5 then
                e.x = e.x + e.knockbackVx * dt
                e.y = e.y + e.knockbackVy * dt
                local margin = e.radius or 16
                e.x = math.max(margin, math.min(bs.areaW - margin, e.x))
                e.y = math.max(margin, math.min(bs.areaH - margin, e.y))
                local decay = math.exp(-CombatUtils.KNOCKBACK_DECAY * dt)
                e.knockbackVx = e.knockbackVx * decay
                e.knockbackVy = e.knockbackVy * decay
            else
                e.knockbackVx = 0
                e.knockbackVy = 0
                -- 眩晕处理: 眩晕期间跳过移动和攻击
                if e.stunTimer and e.stunTimer > 0 then
                    e.stunTimer = e.stunTimer - dt
                    if e.stunTimer <= 0 then e.stunTimer = 0 end
                    goto continue_enemy_ai
                end
                -- 减速处理
                local speedMul = 1.0
                if e.slowTimer and e.slowTimer > 0 then
                    e.slowTimer = e.slowTimer - dt
                    speedMul = e.slowFactor or 1.0
                end
                -- 冻结计时
                if e.frozenTimer and e.frozenTimer > 0 then
                    e.frozenTimer = e.frozenTimer - dt
                    if e.frozenTimer <= 0 then
                        e.isFrozen = false
                        -- 碎冰: 冻结结束时爆炸
                        if e._frozenDmgTaken and e._frozenDmgTaken > 0
                           and GameState.GetSkillLevel("kp_shatter") > 0 then
                            local SkillTreeConfig = require("SkillTreeConfig")
                            local kpCfg = SkillTreeConfig.SKILL_MAP["kp_shatter"]
                            local pct = kpCfg and kpCfg.effect() or 0.45
                            local shatterDmg = math.floor(e._frozenDmgTaken * pct)
                            if shatterDmg > 0 then
                                EnemySystem.ApplyDamage(e, shatterDmg, bs)
                                Particles.SpawnDmgText(bs.particles, e.x,
                                    e.y - (e.radius or 16) - 10,
                                    shatterDmg, false, true, { 150, 220, 255 })
                            end
                        end
                        e._frozenDmgTaken = nil
                    end
                end
                -- 易伤计时
                if e.vulnerableTimer and e.vulnerableTimer > 0 then
                    e.vulnerableTimer = e.vulnerableTimer - dt
                    if e.vulnerableTimer <= 0 then
                        e.isVulnerable = false
                        e.vulnAdd = 0
                        e.vulnXSources = nil
                    end
                end
                -- 冻伤自然衰减 (每秒衰减5%)
                if e.frostbite and e.frostbite > 0 and not (e.isFrozen) then
                    e.frostbite = math.max(0, e.frostbite - 5 * dt)
                end
                -- 冰封领域减速
                if e.frozenFieldSlowTimer and e.frozenFieldSlowTimer > 0 then
                    -- 这个是给玩家的减速，不影响敌人自身
                end

                local dx, dy = p.x - e.x, p.y - e.y
                local dist = math.sqrt(dx * dx + dy * dy)

                -- 远程怪: 保持距离 (atkRange=120)，太近时后退
                if e.isRanged then
                    local preferDist = 120
                    e.atkRange = preferDist
                    if dist > preferDist + 20 then
                        -- 靠近到射程
                        local nx, ny = dx / dist, dy / dist
                        e.x = e.x + nx * e.speed * speedMul * dt
                        e.y = e.y + ny * e.speed * speedMul * dt
                    elseif dist < preferDist - 30 then
                        -- 太近，后退
                        local nx, ny = dx / dist, dy / dist
                        e.x = e.x - nx * e.speed * speedMul * 0.6 * dt
                        e.y = e.y - ny * e.speed * speedMul * 0.6 * dt
                    end
                    -- 在射程范围内攻击
                    if dist <= preferDist + 20 then
                        local atkDt = dt * (1 - (e._atkSpeedReduceRate or 0))
                        e.atkTimer = e.atkTimer + atkDt
                        if e.atkTimer >= e.atkCd then
                            e.atkTimer = 0
                            EnemySystem.EnemyAttackPlayer(bs, e)
                        end
                    end
                else
                    -- 近战怪: 原有逻辑
                    if dist > e.atkRange then
                        local nx, ny = dx / dist, dy / dist
                        e.x = e.x + nx * e.speed * speedMul * dt
                        e.y = e.y + ny * e.speed * speedMul * dt
                    else
                        local atkDt = dt * (1 - (e._atkSpeedReduceRate or 0))
                        e.atkTimer = e.atkTimer + atkDt
                        if e.atkTimer >= e.atkCd then
                            e.atkTimer = 0
                            EnemySystem.EnemyAttackPlayer(bs, e)
                        end
                    end
                end

                -- 边界限制
                local margin = e.radius or 16
                e.x = math.max(margin, math.min(bs.areaW - margin, e.x))
                e.y = math.max(margin, math.min(bs.areaH - margin, e.y))
                ::continue_enemy_ai::
            end
        end
    end
end

-- ============================================================================
-- 敌人特殊能力 (每帧更新)
-- ============================================================================

function EnemySystem.UpdateEnemyAbilities(dt, bs)
    if GameState.playerDead then return end
    local p = bs.playerBattle
    if not p then return end

    for _, e in ipairs(bs.enemies) do
        if not e.dead then
            -- ── 新模板系统 Boss 跳过旧逻辑 ──
            if e.phases then goto continue_abilities end

            -- ── 狼群增伤 (packBonus) ──
            if e.packBonus and e.packBonus > 0 then
                local count = 0
                for _, e2 in ipairs(bs.enemies) do
                    if not e2.dead and e2.templateId == e.templateId then
                        count = count + 1
                    end
                end
                e._packActive = (count >= (e.packThreshold or 3))
            end

            -- ── HP 回复 (hpRegen) ──
            if e.hpRegenPct and e.hpRegenPct > 0 and e.hpRegenInterval and e.hpRegenInterval > 0 then
                e.hpRegenTimer = (e.hpRegenTimer or 0) + dt
                if e.hpRegenTimer >= e.hpRegenInterval then
                    e.hpRegenTimer = e.hpRegenTimer - e.hpRegenInterval
                    local heal = math.floor(e.maxHp * e.hpRegenPct)
                    if e.hp < e.maxHp then
                        e.hp = math.min(e.maxHp, e.hp + heal)
                        Particles.SpawnDmgText(bs.particles, e.x, e.y - (e.radius or 16) - 10, heal, false, false, { 100, 255, 100 })
                    end
                end
            end

            -- ── 治疗光环 (healAura): 周围敌人定时回血 ──
            if e.healAura then
                e.healAuraTimer = (e.healAuraTimer or 0) + dt
                if e.healAuraTimer >= e.healAura.interval then
                    e.healAuraTimer = e.healAuraTimer - e.healAura.interval
                    local healRadius = e.healAura.radius or 100
                    for _, e2 in ipairs(bs.enemies) do
                        if not e2.dead and e2 ~= e then
                            local dx2 = e2.x - e.x
                            local dy2 = e2.y - e.y
                            if math.sqrt(dx2 * dx2 + dy2 * dy2) <= healRadius then
                                -- 检测减疗debuff
                                local healMul = 1.0
                                if e2._antiHealTimer and e2._antiHealTimer > 0 then
                                    healMul = 1.0 - (e2._antiHealRate or 0)
                                end
                                local heal = math.floor(e2.maxHp * (e.healAura.pct or 0.05) * healMul)
                                if heal > 0 and e2.hp < e2.maxHp then
                                    e2.hp = math.min(e2.maxHp, e2.hp + heal)
                                    Particles.SpawnDmgText(bs.particles, e2.x, e2.y - (e2.radius or 16) - 10, heal, false, false, { 100, 255, 100 })
                                end
                            end
                        end
                    end
                end
            end

            -- ── 点燃DoT tick (igniteDot) ──
            if e.igniteDot then
                local dot = e.igniteDot
                dot.timer = dot.timer - dt
                if dot.timer <= 0 then
                    e.igniteDot = nil
                else
                    dot.tickCD = dot.tickCD - dt
                    if dot.tickCD <= 0 then
                        dot.tickCD = dot.tickRate
                        EnemySystem.ApplyDamage(e, dot.dmgPerTick, bs)
                        Particles.SpawnDmgText(bs.particles, e.x, e.y - (e.radius or 16) - 5, dot.dmgPerTick, false, false, { 255, 140, 30 })
                    end
                end
            end

            -- ── 敌人减疗debuff衰减 (_antiHealTimer) ──
            if e._antiHealTimer and e._antiHealTimer > 0 then
                e._antiHealTimer = e._antiHealTimer - dt
                if e._antiHealTimer <= 0 then
                    e._antiHealRate = 0
                    e._antiHealTimer = 0
                end
            end

            -- ── 冰晶再生 (iceRegen): HP<阈值时每秒回复 ──
            if e.iceRegen then
                local hpPct = e.hp / e.maxHp
                if hpPct <= e.iceRegen.hpThreshold then
                    e._iceRegenTimer = (e._iceRegenTimer or 0) + dt
                    if e._iceRegenTimer >= 1.0 then
                        e._iceRegenTimer = e._iceRegenTimer - 1.0
                        local heal = math.floor(e.maxHp * e.iceRegen.regenPct)
                        e.hp = math.min(e.maxHp, e.hp + heal)
                        Particles.SpawnDmgText(bs.particles, e.x, e.y - (e.radius or 16) - 10, heal, false, false, { 120, 200, 255 })
                    end
                end
            end

            -- ── 狂暴 (enrage): HP<30%时ATK+50%, 速度+30% ──
            if e.isBoss and not e.enraged then
                local hpPct = e.hp / e.maxHp
                if hpPct <= 0.3 then
                    e.enraged = true
                    e.atk = math.floor(e.atk * 1.5)
                    e.speed = math.floor(e.speed * 1.3)
                    Particles.SpawnReactionText(bs.particles, e.x, e.y - (e.radius or 16) - 20, "狂暴!", { 255, 80, 80 })
                    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_CRIT)
                end
            end

            -- ── 冰棱弹幕 (barrage) ──
            if e.barrage then
                e.barrageTimer = (e.barrageTimer or 0) - dt
                if e.barrageTimer <= 0 then
                    e.barrageTimer = e.barrage.interval
                    EnemySystem.CastBarrage(bs, e)
                end
            end

            -- ── 召唤 (summon): Boss定时召唤小怪 (优先同家族) ──
            if e.summon then
                e.summonTimer = (e.summonTimer or 0) - dt
                if e.summonTimer <= 0 then
                    e.summonTimer = e.summon.interval
                    local gs = GameState.stage
                    local scaleMul = StageConfig.GetScaleMul(gs.chapter, gs.stage)
                    -- 优先用 Boss 同家族的 swarm 成员
                    local sTemplate = nil
                    local summonTplId = e.summon.monsterId
                    if e.familyId then
                        local familyDef = MonsterFamilies.Get(e.familyId)
                        if familyDef and familyDef.members and familyDef.members.swarm then
                            sTemplate = MonsterFamilies.Resolve(e.familyId, "swarm", gs.chapter, nil, nil)
                            summonTplId = e.familyId .. "_swarm"
                        end
                    end
                    if not sTemplate then
                        sTemplate = StageConfig.MONSTERS[e.summon.monsterId]
                    end
                    if sTemplate then
                        for _ = 1, (e.summon.count or 1) do
                            local sHp = math.floor(sTemplate.hp * scaleMul)
                            local sAtk = math.floor(sTemplate.atk * scaleMul)
                            local sx = e.x + math.random(-40, 40)
                            local sy = e.y + math.random(-40, 40)
                            sx = math.max(30, math.min(bs.areaW - 30, sx))
                            sy = math.max(30, math.min(bs.areaH - 30, sy))
                            table.insert(bs.enemies, {
                                x = sx, y = sy,
                                hp = sHp, maxHp = sHp, atk = sAtk,
                                speed = sTemplate.speed, radius = sTemplate.radius or 16,
                                expDrop = math.floor((sTemplate.expDrop or 3) * scaleMul),
                                goldMin = sTemplate.goldDrop and math.floor(sTemplate.goldDrop[1] * math.sqrt(scaleMul)) or 0,
                                goldMax = sTemplate.goldDrop and math.floor(sTemplate.goldDrop[2] * math.sqrt(scaleMul)) or 0,
                                color = { sTemplate.color[1], sTemplate.color[2], sTemplate.color[3] },
                                image = sTemplate.image, isBoss = false, dead = false,
                                def = math.floor((sTemplate.def or 0) * scaleMul), atkTimer = 0,
                                atkCd = sTemplate.atkInterval or 2.0, atkRange = sTemplate.atkRange or 35,
                                name = sTemplate.name, knockbackVx = 0, knockbackVy = 0,
                                weight = sTemplate.weight or 1.0,
                                element = sTemplate.element or "physical",
                                antiHeal = sTemplate.antiHeal or false,
                                slowOnHit = sTemplate.slowOnHit or 0, slowDuration = sTemplate.slowDuration or 0,
                                attachedElement = nil, attachedElementTimer = 0,
                                defReduceRate = 0, defReduceTimer = 0,
                                elemWeakenRate = 0, elemWeakenTimer = 0,
                                reactionDot = nil,
                                templateId = summonTplId,
                                _isSummon = true,
                                defPierce = sTemplate.defPierce or 0,
                                packBonus = sTemplate.packBonus or 0, packThreshold = sTemplate.packThreshold or 0,
                                isRanged = sTemplate.isRanged or false, deathExplode = sTemplate.deathExplode,
                                hpRegenPct = sTemplate.hpRegen or 0, hpRegenInterval = sTemplate.hpRegenInterval or 0,
                                hpRegenTimer = 0, enraged = false,
                                resist = sTemplate.resist, lifesteal = sTemplate.lifesteal or 0,
                                healAura = sTemplate.healAura, healAuraTimer = 0,
                                firstStrikeMul = sTemplate.firstStrikeMul, firstStrikeDone = false,
                                igniteDot = nil,
                                chargeUp = sTemplate.chargeUp, chargeUpStacks = 0,
                                chainLightning = sTemplate.chainLightning,
                                sandStorm = sTemplate.sandStorm,
                                venomStack = sTemplate.venomStack,
                                sporeCloud = sTemplate.sporeCloud,
                                burnStack = sTemplate.burnStack,
                                scorchOnHit = sTemplate.scorchOnHit,
                                burnAura = sTemplate.burnAura,
                                burnAuraTimer = sTemplate.burnAura and sTemplate.burnAura.interval or 0,
                            })
                            EnemyAnim.InitAnim(bs.enemies[#bs.enemies])
                        end
                        Particles.SpawnReactionText(bs.particles, e.x, e.y - (e.radius or 16) - 20, "召唤!", { 180, 140, 255 })
                    end
                end
            end

            -- ── 冰甲 (iceArmor): HP低于阈值时触发 ──
            if e.iceArmor then
                -- CD 倒计时
                if e.iceArmorCdTimer > 0 then
                    e.iceArmorCdTimer = e.iceArmorCdTimer - dt
                end
                -- 激活中倒计时
                if e.iceArmorActive then
                    e.iceArmorTimer = e.iceArmorTimer - dt
                    if e.iceArmorTimer <= 0 then
                        e.iceArmorActive = false
                        e.iceArmorCdTimer = e.iceArmor.cd
                    end
                else
                    -- 检测触发条件
                    local hpPct = e.hp / e.maxHp
                    if hpPct <= e.iceArmor.hpThreshold and e.iceArmorCdTimer <= 0 then
                        e.iceArmorActive = true
                        e.iceArmorTimer = e.iceArmor.duration
                        Particles.SpawnReactionText(bs.particles, e.x, e.y - (e.radius or 16) - 20, "冰甲!", { 100, 200, 255 })
                        -- 冰甲激活视觉特效
                        table.insert(bs.bossSkillEffects, {
                            type = "iceArmor",
                            element = e.element or "ice",
                            enemyRef = e,
                            life = e.iceArmor.duration, maxLife = e.iceArmor.duration,
                        })
                    end
                end
            end

            -- ── 龙息 (dragonBreath) ──
            if e.dragonBreath then
                e.breathTimer = (e.breathTimer or 0) - dt
                if e.breathTimer <= 0 then
                    e.breathTimer = e.dragonBreath.interval
                    EnemySystem.CastDragonBreath(bs, e)
                end
            end

            -- ── 冰封领域 (frozenField): HP低于阈值时触发全场减速 ──
            if e.frozenField then
                if e.frozenFieldCdTimer > 0 then
                    e.frozenFieldCdTimer = e.frozenFieldCdTimer - dt
                end
                if e.frozenFieldActive then
                    e.frozenFieldTimer = e.frozenFieldTimer - dt
                    -- 持续减速玩家
                    GameState.ApplySlowDebuff(e.frozenField.slowRate, 0.5)
                    if e.frozenFieldTimer <= 0 then
                        e.frozenFieldActive = false
                        e.frozenFieldCdTimer = e.frozenField.cd
                    end
                else
                    local hpPct = e.hp / e.maxHp
                    if hpPct <= e.frozenField.hpThreshold and e.frozenFieldCdTimer <= 0 then
                        e.frozenFieldActive = true
                        e.frozenFieldTimer = e.frozenField.duration
                        Particles.SpawnReactionText(bs.particles, e.x, e.y - (e.radius or 16) - 20, "冰封领域!", { 80, 160, 255 })
                        CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_SKILL)
                        -- 冰封领域视觉特效
                        table.insert(bs.bossSkillEffects, {
                            type = "frozenField",
                            element = e.element or "ice",
                            enemyRef = e,
                            radius = 80,
                            life = e.frozenField.duration, maxLife = e.frozenField.duration,
                        })
                    end
                end
            end

            ::continue_abilities::
        end
    end
end

-- ============================================================================
-- Boss 技能: 冰棱弹幕 (向周围发射多个冰棱)
-- ============================================================================

function EnemySystem.CastBarrage(bs, enemy)
    if GameState.playerDead then return end
    local cfg = enemy.barrage
    local count = cfg.count or 6
    local dmg = math.floor(enemy.atk * (cfg.dmgMul or 0.5))
    local p = bs.playerBattle

    Particles.SpawnReactionText(bs.particles, enemy.x, enemy.y - (enemy.radius or 16) - 20, "冰棱弹幕!", { 140, 200, 255 })
    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_NORMAL)

    -- 弹幕视觉特效: 每颗冰棱从boss飞向玩家
    local elem = cfg.element or "ice"
    for i = 1, count do
        local angle = (i / count) * math.pi * 2
        table.insert(bs.bossSkillEffects, {
            type = "barrage",
            element = elem,
            srcX = enemy.x, srcY = enemy.y,
            tgtX = p.x + math.cos(angle) * 20, tgtY = p.y + math.sin(angle) * 20,
            delay = (i - 1) * 0.15,
            life = 0.15 * count + 0.3, maxLife = 0.15 * count + 0.3,
        })
    end

    -- 每个冰棱对玩家造成伤害 (间隔 0.15s)
    for i = 1, count do
        local delay = (i - 1) * 0.15
        table.insert(bs.delayedActions, {
            timer = delay,
            callback = function()
                if GameState.playerDead then return end
                local rawDmg = GameState.CalcElementDamage(dmg, cfg.element or "ice")
                local actualDmg, isDodged = GameState.DamagePlayer(rawDmg)
                if isDodged then
                    Particles.SpawnDodgeText(bs.particles, p.x, p.y - 25)
                    return
                end
                local elemColor = Config.ELEMENTS.colors[cfg.element or "ice"]
                Particles.SpawnDmgText(bs.particles, p.x + math.random(-15, 15), p.y - 25, actualDmg, false, false, elemColor)
                -- 冰棱附着
                GameState.ApplyElementAndReact(cfg.element or "ice", 0)
            end,
        })
    end
end

-- ============================================================================
-- Boss 技能: 龙息 (锥形冰息，高伤害)
-- ============================================================================

function EnemySystem.CastDragonBreath(bs, enemy)
    if GameState.playerDead then return end
    local cfg = enemy.dragonBreath
    local dmg = math.floor(enemy.atk * (cfg.dmgMul or 2.0))
    local p = bs.playerBattle

    Particles.SpawnReactionText(bs.particles, enemy.x, enemy.y - (enemy.radius or 16) - 20, "龙息!", { 100, 180, 255 })
    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_STORM)

    -- 龙息视觉特效: 从boss到玩家的锥形喷射
    table.insert(bs.bossSkillEffects, {
        type = "dragonBreath",
        element = cfg.element or "ice",
        srcX = enemy.x, srcY = enemy.y,
        tgtX = p.x, tgtY = p.y,
        life = 1.0, maxLife = 1.0,
    })

    -- 延迟 0.5s 后命中 (给玩家一个视觉预警)
    table.insert(bs.delayedActions, {
        timer = 0.5,
        callback = function()
            if GameState.playerDead then return end
            local rawDmg = GameState.CalcElementDamage(dmg, cfg.element or "ice")
            local actualDmg, isDodged = GameState.DamagePlayer(rawDmg)
            if isDodged then
                Particles.SpawnDodgeText(bs.particles, p.x, p.y - 30)
                return
            end
            local elemColor = Config.ELEMENTS.colors[cfg.element or "ice"]
            Particles.SpawnDmgText(bs.particles, p.x, p.y - 30, actualDmg, true, false, elemColor)
            GameState.ApplySlowDebuff(0.5, 2.0) -- 龙息附带减速
            GameState.ApplyElementAndReact(cfg.element or "ice", 0)
            CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_STORM)
            bs.playerHitFlash = 0.5
        end,
    })
end

-- ============================================================================
-- 死亡爆炸 (deathExplode)
-- ============================================================================

function EnemySystem.OnEnemyDeath(bs, enemy)
    -- ── 死亡分裂 (splitOnDeath): 产生子怪物 ──
    if enemy.splitOnDeath then
        local splitCfg = enemy.splitOnDeath
        local childTemplate = StageConfig.MONSTERS[splitCfg.childId]
        if childTemplate then
            local gs = GameState.stage
            local scaleMul = StageConfig.GetScaleMul(gs.chapter, gs.stage)
            local count = splitCfg.count or 2
            for i = 1, count do
                local angle = (i / count) * math.pi * 2
                local offsetX = math.cos(angle) * 25
                local offsetY = math.sin(angle) * 25
                local sx = math.max(30, math.min(bs.areaW - 30, enemy.x + offsetX))
                local sy = math.max(30, math.min(bs.areaH - 30, enemy.y + offsetY))
                local cHp = math.floor(childTemplate.hp * scaleMul)
                local cAtk = math.floor(childTemplate.atk * scaleMul)
                table.insert(bs.enemies, {
                    x = sx, y = sy,
                    hp = cHp, maxHp = cHp, atk = cAtk,
                    speed = childTemplate.speed, radius = childTemplate.radius or 11,
                    expDrop = math.floor(childTemplate.expDrop * scaleMul),
                    goldMin = math.floor(childTemplate.goldDrop[1] * math.sqrt(scaleMul)),
                    goldMax = math.floor(childTemplate.goldDrop[2] * math.sqrt(scaleMul)),
                    color = { childTemplate.color[1], childTemplate.color[2], childTemplate.color[3] },
                    image = childTemplate.image, isBoss = false, dead = false,
                    def = math.floor((childTemplate.def or 0) * scaleMul), atkTimer = 0,
                    atkCd = childTemplate.atkInterval or 2.0, atkRange = childTemplate.atkRange or 35,
                    name = childTemplate.name, knockbackVx = 0, knockbackVy = 0,
                    weight = childTemplate.weight or 1.0,
                    element = childTemplate.element or "physical",
                    antiHeal = childTemplate.antiHeal or false,
                    slowOnHit = childTemplate.slowOnHit or 0, slowDuration = childTemplate.slowDuration or 0,
                    attachedElement = nil, attachedElementTimer = 0,
                    defReduceRate = 0, defReduceTimer = 0,
                    elemWeakenRate = 0, elemWeakenTimer = 0,
                    reactionDot = nil,
                    templateId = splitCfg.childId,
                    defPierce = childTemplate.defPierce or 0,
                    packBonus = childTemplate.packBonus or 0, packThreshold = childTemplate.packThreshold or 0,
                    isRanged = childTemplate.isRanged or false, deathExplode = childTemplate.deathExplode,
                    hpRegenPct = childTemplate.hpRegen or 0, hpRegenInterval = childTemplate.hpRegenInterval or 0,
                    hpRegenTimer = 0, enraged = false,
                    resist = childTemplate.resist, lifesteal = childTemplate.lifesteal or 0,
                    healAura = childTemplate.healAura, healAuraTimer = 0,
                    firstStrikeMul = childTemplate.firstStrikeMul, firstStrikeDone = false,
                    igniteDot = nil,
                    splitOnDeath = childTemplate.splitOnDeath,  -- 子怪不再分裂(coral_shard无此字段)
                    corrosion = childTemplate.corrosion,
                    inkBlind = childTemplate.inkBlind,
                    venomStack = childTemplate.venomStack,
                    sporeCloud = childTemplate.sporeCloud,
                    burnStack = childTemplate.burnStack,
                    scorchOnHit = childTemplate.scorchOnHit,
                    burnAura = childTemplate.burnAura,
                    burnAuraTimer = childTemplate.burnAura and childTemplate.burnAura.interval or 0,
                })
                EnemyAnim.InitAnim(bs.enemies[#bs.enemies])
            end
            Particles.SpawnReactionText(bs.particles, enemy.x, enemy.y - 10, "分裂!", { 200, 100, 80 })
        end
    end

    -- ── 孢子云 (sporeCloud): 死亡释放孢子云降低玩家攻速 ──
    if enemy.sporeCloud then
        local sCfg = enemy.sporeCloud
        GameState.ApplySporeCloudDebuff(sCfg.atkSpeedReducePct, sCfg.duration)
        Particles.SpawnReactionText(bs.particles, enemy.x, enemy.y - 10, "孢子云!", { 160, 200, 80 })
    end

    if not enemy.deathExplode then return end
    local cfg = enemy.deathExplode
    local dmg = math.floor(enemy.atk * (cfg.dmgMul or 0.8))
    local radius = cfg.radius or 40
    local p = bs.playerBattle

    -- 检查玩家是否在爆炸范围内
    local dx = p.x - enemy.x
    local dy = p.y - enemy.y
    local dist = math.sqrt(dx * dx + dy * dy)

    -- 爆炸视觉
    Particles.SpawnReactionText(bs.particles, enemy.x, enemy.y - 10, "爆!", { 150, 200, 255 })
    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_NORMAL)

    -- 死亡爆炸视觉特效
    table.insert(bs.bossSkillEffects, {
        type = "deathExplode",
        element = cfg.element or "ice",
        x = enemy.x, y = enemy.y,
        radius = radius,
        life = 0.6, maxLife = 0.6,
    })

    if dist <= radius and not GameState.playerDead then
        local rawDmg = GameState.CalcElementDamage(dmg, cfg.element or "ice")
        local actualDmg, isDodged = GameState.DamagePlayer(rawDmg)
        if isDodged then
            Particles.SpawnDodgeText(bs.particles, p.x, p.y - 30)
        else
            local elemColor = Config.ELEMENTS.colors[cfg.element or "ice"]
            Particles.SpawnDmgText(bs.particles, p.x, p.y - 30, actualDmg, false, false, elemColor)
            GameState.ApplyElementAndReact(cfg.element or "ice", 0)
            bs.playerHitFlash = 0.3
        end
    end
end

-- ============================================================================
-- 敌人攻击玩家
-- ============================================================================

--- @param bs table BattleSystem 引用
--- @param enemy table 敌人
function EnemySystem.EnemyAttackPlayer(bs, enemy)
    if GameState.playerDead then return end
    -- 攻击动画 (前摇挤压弹出)
    EnemyAnim.OnAttack(enemy)

    -- 计算攻击力 (含狼群增伤)
    local rawDmg = enemy.atk
    if enemy._packActive then
        rawDmg = math.floor(rawDmg * (1 + (enemy.packBonus or 0)))
    end

    -- 首击倍率 (shadow_assassin)
    if enemy.firstStrikeMul and not enemy.firstStrikeDone then
        rawDmg = math.floor(rawDmg * enemy.firstStrikeMul)
        enemy.firstStrikeDone = true
    end

    -- 充能攻击 (chargeUp): 满层时增伤+可选AOE
    rawDmg = ApplyChargeUpAttack(bs, enemy, rawDmg)

    -- 恐慌后 ATK debuff (fiends)
    if enemy._panicAtkDebuff then
        rawDmg = math.floor(rawDmg * (1 - enemy._panicAtkDebuff))
    end

    -- 精英攻击修正 (领袖buff/猎杀/暴击)
    local EliteSys = require("battle.EliteSystem")
    rawDmg = EliteSys.ModifyAttack(bs, enemy, rawDmg)

    -- 精英穿甲 (额外无视DEF)
    local eliteArmorPierce = EliteSys.GetArmorPierce(enemy)

    -- v3.1: 怪物等级 (用于 DEF K 缩放)
    local monsterLevel = enemy.level

    -- defPierce: 无视部分DEF，直接对裸伤追加
    local totalPierce = (enemy.defPierce or 0) + eliteArmorPierce
    local pierceDmg = 0
    if totalPierce > 0 then
        -- 计算被减免的伤害量，然后追回 pierce 比例
        local defMul = GameState.GetDEFMul(monsterLevel)
        local normalDmg = math.max(1, math.floor(rawDmg * defMul))
        local fullDmg = rawDmg
        pierceDmg = math.floor((fullDmg - normalDmg) * math.min(1.0, totalPierce))
    end

    -- 元素伤害减免 (非物理走元素抗性)
    rawDmg = GameState.CalcElementDamage(rawDmg, enemy.element)
    -- 元素反应检测 (不同元素碰撞触发反应)
    local reaction, reactedDmg = GameState.ApplyElementAndReact(enemy.element, rawDmg)
    rawDmg = reactedDmg

    local actualDmg, isDodged = GameState.DamagePlayer(rawDmg, monsterLevel)

    local p = bs.playerBattle
    -- 闪避: 显示闪避飘字, 跳过后续伤害逻辑
    if isDodged then
        Particles.SpawnDodgeText(bs.particles, p.x, p.y - 30)
        return
    end

    -- 追加穿透伤害
    if pierceDmg > 0 then
        GameState.DamagePlayer(pierceDmg)
        actualDmg = actualDmg + pierceDmg
    end

    -- 受伤飘字 (元素颜色)
    local elemColor = Config.ELEMENTS.colors[enemy.element]
    Particles.SpawnDmgText(bs.particles, p.x, p.y - 30, actualDmg, false, false, elemColor)
    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_NORMAL * 0.6)
    bs.playerHitFlash = 0.3
    -- 元素反应特效 (防守方向: 敌人攻击玩家)
    if reaction then
        -- 反应名飘字
        Particles.SpawnReactionText(bs.particles, p.x, p.y - 55, reaction.name, { 255, 255, 100 })
        CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_NORMAL)
        -- 冻结/眩晕: 施加强减速
        if reaction.stunDuration then
            GameState.ApplySlowDebuff(0.95, reaction.stunDuration)
        end
        -- 减攻速 debuff
        if reaction.slowRate then
            GameState.ApplySlowDebuff(reaction.slowRate, reaction.slowDur or 2.0)
        end
        -- AOE 反弹伤害给附近敌人
        if reaction.aoeRadius then
            for _, e2 in ipairs(bs.enemies) do
                if not e2.dead then
                    local dx = e2.x - p.x
                    local dy = e2.y - p.y
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist <= reaction.aoeRadius then
                        local aoeDmg = math.floor(actualDmg * 0.5)
                        EnemySystem.ApplyDamage(e2, aoeDmg, bs)
                        Particles.SpawnDmgText(bs.particles, e2.x, e2.y - 20, aoeDmg, false, true, { 255, 140, 30 })
                        -- AOE减速
                        if reaction.aoeSlow then
                            e2.slowTimer = reaction.aoeSlowDur or 2.0
                            e2.slowFactor = 1.0 - reaction.aoeSlow
                        end
                    end
                end
            end
        end
    end
    -- 减疗 debuff (特定怪物)
    if enemy.antiHeal then
        GameState.ApplyAntiHealDebuff(Config.ANTI_HEAL.rate, Config.ANTI_HEAL.duration)
    end
    -- 减速 debuff (特定怪物)
    if enemy.slowOnHit and enemy.slowOnHit > 0 then
        GameState.ApplySlowDebuff(enemy.slowOnHit, enemy.slowDuration or 1.5)
    end

    -- 腐蚀 debuff (abyssal_crab): 叠加降低玩家DEF
    if enemy.corrosion then
        local cfg = enemy.corrosion
        GameState.ApplyCorrosionDebuff(cfg.defReducePct, cfg.stackMax, cfg.duration)
        Particles.SpawnReactionText(bs.particles, p.x, p.y - 45, "腐蚀!", { 40, 80, 120 })
    end
    -- 墨汁致盲 (ink_octopus): 降低玩家ATK
    if enemy.inkBlind then
        local cfg = enemy.inkBlind
        GameState.ApplyInkBlindDebuff(cfg.atkReducePct, cfg.duration)
        Particles.SpawnReactionText(bs.particles, p.x, p.y - 45, "致盲!", { 60, 20, 80 })
    end

    -- 敌人吸血 (cursed_knight)
    if enemy.lifesteal and enemy.lifesteal > 0 and actualDmg > 0 then
        -- 检测敌人身上的减疗debuff
        local healMul = 1.0
        if enemy._antiHealTimer and enemy._antiHealTimer > 0 then
            healMul = 1.0 - (enemy._antiHealRate or 0)
        end
        local heal = math.floor(actualDmg * enemy.lifesteal * healMul)
        if heal > 0 and enemy.hp < enemy.maxHp then
            enemy.hp = math.min(enemy.maxHp, enemy.hp + heal)
            Particles.SpawnDmgText(bs.particles, enemy.x, enemy.y - (enemy.radius or 16) - 10, heal, false, false, { 100, 255, 100 })
        end
    end

    -- 链弹 (chainLightning): 攻击后电弧弹射额外伤害
    ApplyChainLightning(bs, enemy)

    -- 沙暴 (sandStorm): 攻击命中降低玩家暴击率
    ApplySandStorm(enemy)

    -- 毒蛊叠加 (venomStack): 攻击命中叠加毒蛊层数
    ApplyVenomStack(enemy)

    -- 灼烧叠加 (burnStack): 攻击命中叠加灼烧层数 (第15章)
    ApplyBurnStack(enemy)

    -- 焚灼命中 (scorchOnHit): 攻击命中叠加焚灼层数 (第15章)
    ApplyScorchOnHit(enemy)

    -- 浸蚀叠加 (drenchStack): 攻击命中叠加浸蚀层数 (第16章)
    ApplyDrenchOnHit(enemy)

    -- 精英词缀攻击后效果 (吸血/冰封/缠绕/爆裂AOE/闪电链/减速)
    EliteSys.OnAttackHit(bs, enemy, actualDmg)
    -- 蛛蝎叠毒 (venomkin familyType)
    local FamilyMech = require("battle.FamilyMechanics")
    FamilyMech.OnVenomkinAttackHit(enemy)

    local BuffManager = require("battle.BuffManager")
    -- 极寒之心2件: 受冰/水伤回血
    BuffManager.TryPermafrostHeal(bs, enemy.element)
    -- 极寒之心6件: 寒冰化身反弹冰伤
    BuffManager.TryIceAvatarReflect(bs, enemy)
end

-- ============================================================================
-- 冰甲减伤: 敌人受到伤害时的钩子 (由外部调用)
-- ============================================================================

--- 计算冰甲减伤后的实际伤害
--- @param enemy table 敌人
--- @param dmg number 原始伤害
--- @return number 减伤后的伤害
function EnemySystem.ApplyDamageReduction(enemy, dmg)
    if enemy.iceArmorActive and enemy.iceArmor then
        dmg = math.floor(dmg * (1 - enemy.iceArmor.dmgReduce))
    end
    -- 模板系统护甲减伤 (DEF_armor)
    if enemy._templateArmorActive and enemy._templateArmorReduce then
        dmg = math.floor(dmg * (1 - enemy._templateArmorReduce))
    end
    -- 模板系统护盾减伤 (DEF_shield 存活时 Boss 减伤)
    if enemy._templateShieldActive and enemy._templateShieldReduce then
        dmg = math.floor(dmg * (1 - enemy._templateShieldReduce))
    end
    return dmg
end

-- ============================================================================
-- 统一扣血出口: 所有对敌人造成伤害都应经过此函数
-- ============================================================================

--- 对敌人施加伤害（统一出口）
--- 集中处理: 冻结伤害累计(碎冰)、Boss伤害统计、死亡判定
--- @param e table 敌人
--- @param dmg number 伤害值（已经过减伤计算）
--- @param bs table BattleSystem 引用
--- @return boolean killed 是否击杀
function EnemySystem.ApplyDamage(e, dmg, bs)
    if e.dead or dmg <= 0 then return false end

    -- 精英护盾吸收 (在扣血之前)
    local EliteSystem = require("battle.EliteSystem")
    dmg = EliteSystem.AbsorbShield(e, dmg)
    if dmg <= 0 then return false end

    -- 虚空 AOE 减伤 (标记由调用方设置 e._lastHitIsAOE)
    local FamilyMech = require("battle.FamilyMechanics")
    dmg = FamilyMech.ModifyIncomingDmg(e, dmg, e._lastHitIsAOE)

    e.hp = e.hp - dmg
    -- 碎冰: 冻结期间伤害累计
    if e.isFrozen then
        e._frozenDmgTaken = (e._frozenDmgTaken or 0) + dmg
    end
    CombatUtils.RecordBossDmg(dmg)

    -- 精英受击钩子 (荆棘等)
    EliteSystem.OnEnemyHit(bs, e, dmg)
    -- 虚空闪移触发
    FamilyMech.TryVoidbornBlink(bs, e)
    -- 受击动画 (闪白+后仰)
    EnemyAnim.OnHit(e, bs)

    if e.hp <= 0 and not e.dead then
        -- 不死词缀拦截
        if EliteSystem.CheckUndying(e) then
            return false  -- 阻止死亡
        end
        e.dead = true
        EnemyAnim.OnDeath(e)
        bs.OnEnemyKilled(e)
        return true
    end
    return false
end

-- ============================================================================
-- 充能 (chargeUp): 敌人受伤时叠充能层数 (由外部 CombatCore 调用)
-- ============================================================================

--- 敌人受到伤害后叠加充能层数
--- @param enemy table 敌人
function EnemySystem.OnEnemyTakeDamageChargeUp(enemy)
    if not enemy.chargeUp or enemy.dead then return end
    local cfg = enemy.chargeUp
    enemy.chargeUpStacks = (enemy.chargeUpStacks or 0) + 1
    if enemy.chargeUpStacks >= cfg.stackMax then
        enemy._chargeReady = true  -- 标记: 下次攻击为充能攻击
    end
end

-- ============================================================================
-- 充能攻击释放 (在 EnemyAttackPlayer 中调用)
-- ============================================================================

--- 充能攻击: 增伤 + 可选AOE
--- @param bs table BattleSystem
--- @param enemy table 敌人
--- @param baseDmg number 基础伤害
--- @return number 最终伤害
ApplyChargeUpAttack = function(bs, enemy, baseDmg)
    if not enemy._chargeReady then return baseDmg end
    local cfg = enemy.chargeUp
    local chargedDmg = math.floor(baseDmg * cfg.dmgMul)

    -- AOE 充能爆发
    if cfg.isAOE and cfg.aoeRadius then
        local p = bs.playerBattle
        -- 对范围内的玩家造成AOE伤害（这里主要是视觉效果 + 额外伤害文本）
        Particles.SpawnReactionText(bs.particles, enemy.x, enemy.y - (enemy.radius or 16) - 20, "充能爆发!", { 220, 180, 50 })
        CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_CRIT)
        -- AOE 视觉特效
        table.insert(bs.bossSkillEffects, {
            type = "deathExplode",
            element = "arcane",
            x = enemy.x, y = enemy.y,
            radius = cfg.aoeRadius,
            life = 0.5, maxLife = 0.5,
        })
    else
        Particles.SpawnReactionText(bs.particles, enemy.x, enemy.y - (enemy.radius or 16) - 20, "充能!", { 220, 180, 50 })
        CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_NORMAL)
    end

    -- 重置充能
    if cfg.resetOnTrigger then
        enemy.chargeUpStacks = 0
    end
    enemy._chargeReady = false

    return chargedDmg
end

-- ============================================================================
-- 链弹 (chainLightning): 攻击后电弧弹射
-- ============================================================================

--- 链弹: 攻击命中后搜索附近敌人造成弹射伤害（当前实现为对玩家额外伤害）
--- @param bs table BattleSystem
--- @param enemy table 敌人
ApplyChainLightning = function(bs, enemy)
    if not enemy.chainLightning or GameState.playerDead then return end
    local cfg = enemy.chainLightning
    local dmg = math.floor(enemy.atk * cfg.dmgMul)
    local p = bs.playerBattle

    -- 链弹视觉: 电弧从敌人弹射
    for i = 1, (cfg.bounces or 2) do
        local angle = math.random() * math.pi * 2
        local dist = math.random(20, cfg.range or 80)
        local tx = p.x + math.cos(angle) * dist * 0.3
        local ty = p.y + math.sin(angle) * dist * 0.3

        table.insert(bs.delayedActions, {
            timer = i * 0.15,
            callback = function()
                if GameState.playerDead then return end
                local rawDmg = GameState.CalcElementDamage(dmg, cfg.element or "arcane")
                local actualDmg, isDodged = GameState.DamagePlayer(rawDmg)
                if isDodged then
                    Particles.SpawnDodgeText(bs.particles, p.x, p.y - 20)
                    return
                end
                local elemColor = Config.ELEMENTS.colors[cfg.element or "arcane"]
                Particles.SpawnDmgText(bs.particles, p.x + math.random(-10, 10), p.y - 20, actualDmg, false, false, elemColor)
            end,
        })
    end
    Particles.SpawnReactionText(bs.particles, enemy.x, enemy.y - (enemy.radius or 16) - 20, "链弹!", { 180, 130, 255 })
end

-- ============================================================================
-- 沙暴 (sandStorm): 攻击命中时降低玩家暴击率
-- ============================================================================

--- 沙暴: 施加暴击率降低debuff
--- @param enemy table 敌人
ApplySandStorm = function(enemy)
    if not enemy.sandStorm or GameState.playerDead then return end
    local cfg = enemy.sandStorm
    GameState.ApplySandStormDebuff(cfg.critReducePct, cfg.duration)
end

-- ============================================================================
-- 毒蛊叠加 (venomStack): 攻击命中时叠加毒蛊层数
-- ============================================================================

--- 毒蛊叠加: 施加毒蛊debuff
--- @param enemy table 敌人
ApplyVenomStack = function(enemy)
    if not enemy.venomStack or GameState.playerDead then return end
    local cfg = enemy.venomStack
    GameState.ApplyVenomStackDebuff(cfg.dmgPctPerStack, cfg.stackMax, cfg.duration)
end

-- ============================================================================
-- 灼烧叠加 (burnStack): 攻击命中时叠加灼烧层数 (第15章)
-- ============================================================================

--- 灼烧叠加: 施加灼烧debuff (DoT + 攻速减)
--- @param enemy table 敌人
ApplyBurnStack = function(enemy)
    if not enemy.burnStack or GameState.playerDead then return end
    local cfg = enemy.burnStack
    GameState.ApplyBlazeDebuff(cfg.dmgPct, cfg.atkSpdReduce, cfg.maxStacks, cfg.duration, enemy.atk)
end

-- ============================================================================
-- 焚灼命中 (scorchOnHit): 攻击命中时叠加焚灼层数 (第15章)
-- ============================================================================

--- 焚灼命中: 施加焚灼debuff (受伤增幅)
--- @param enemy table 敌人
ApplyScorchOnHit = function(enemy)
    if not enemy.scorchOnHit or GameState.playerDead then return end
    local cfg = enemy.scorchOnHit
    GameState.ApplyScorchDebuff(cfg.dmgAmpPct, cfg.maxStacks, cfg.duration)
end

-- ============================================================================
-- 浸蚀叠加 (drenchStack): 攻击命中时叠加浸蚀层数 (第16章)
-- ============================================================================

--- 浸蚀命中: 施加浸蚀debuff (暴击降低+火抗降低)
--- @param enemy table 敌人
ApplyDrenchOnHit = function(enemy)
    if not enemy.drenchStack or GameState.playerDead then return end
    local cfg = enemy.drenchStack
    GameState.ApplyDrenchDebuff(cfg.perStack, cfg.maxStacks, cfg.duration)
end

-- ============================================================================
-- 灼热光环 (burnAura): 范围内自动叠加灼烧 (第15章)
-- ============================================================================

--- 灼热光环: 定时对范围内玩家叠加灼烧
--- @param bs table BattleSystem
--- @param enemy table 敌人
--- @param dt number 帧间隔
function EnemySystem.UpdateBurnAura(bs, enemy, dt)
    if not enemy.burnAura or GameState.playerDead then return end
    enemy.burnAuraTimer = (enemy.burnAuraTimer or 0) - dt
    if enemy.burnAuraTimer > 0 then return end
    enemy.burnAuraTimer = enemy.burnAura.interval or 1.0

    -- 检查玩家是否在光环范围内
    local px, py = GameState.playerX or 0, GameState.playerY or 0
    local dx, dy = px - enemy.x, py - enemy.y
    local dist = math.sqrt(dx * dx + dy * dy)
    local auraRadius = enemy.burnAura.radius or 50
    if dist <= auraRadius then
        GameState.ApplyBlazeDebuff(0.018, 0.03, 8, 5.0, enemy.atk)
    end
end

return EnemySystem
