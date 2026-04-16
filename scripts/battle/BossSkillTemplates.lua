-- ============================================================================
-- battle/BossSkillTemplates.lua - Boss 技能模板系统
-- 三层架构: 模板层(行为) → 参数层(数值) → 特调层(元素/主题)
-- 新 Boss (有 phases 字段) 走此系统, 旧 Boss 不受影响
-- ============================================================================

local Config           = require("Config")
local GameState        = require("GameState")
local StageConfig      = require("StageConfig")
local Particles        = require("battle.Particles")
local CombatUtils      = require("battle.CombatUtils")
local ThreatSystem     = require("battle.ThreatSystem")
local MonsterFamilies  = require("MonsterFamilies")

local BossSkillTemplates = {}

-- ============================================================================
-- 模板注册表
-- ============================================================================

---@type table<string, { init: fun(bs, enemy, cfg), update: fun(dt, bs, enemy, cfg), onCast: fun(bs, enemy, cfg)?, onEnd: fun(bs, enemy, cfg)? }>
local templates = {}

--- 注册一个技能模板
function BossSkillTemplates.RegisterTemplate(id, handlers)
    templates[id] = handlers
end

-- ============================================================================
-- 公共工具函数 (消除模板间重复代码)
-- ============================================================================

--- 通用技能计时器: 倒计时 → 到期施放 → 重置
--- @param enemy table Boss 实体
--- @param skillIdx number 技能索引
--- @param dt number 帧间隔
--- @param cfg table 技能配置 (需含 interval)
--- @param defaultInterval number 默认间隔(秒)
--- @param castFn fun(bs, enemy, cfg) 施放函数
--- @param bs table BattleSystem
local function _timerUpdate(enemy, skillIdx, dt, cfg, defaultInterval, castFn, bs)
    if not enemy._skillTimers then return end
    enemy._skillTimers[skillIdx] = (enemy._skillTimers[skillIdx] or 0) - dt
    if enemy._skillTimers[skillIdx] <= 0 then
        enemy._skillTimers[skillIdx] = cfg.interval or defaultInterval
        castFn(bs, enemy, cfg)
    end
end

--- 对玩家造成元素伤害 + 伤害数字 + 元素附着 (一体化)
--- @param bs table BattleSystem
--- @param dmg number 基础伤害
--- @param elem string 元素类型
--- @param isCrit boolean 是否暴击显示
--- @param shake number|nil 震屏强度 (nil=不震)
--- @param randOffset boolean|nil 伤害数字 X 偏移随机化
local function _hitPlayer(bs, dmg, elem, isCrit, shake, randOffset)
    local p = bs.playerBattle
    if not p or GameState.playerDead then return 0 end
    local rawDmg = GameState.CalcElementDamage(dmg, elem)
    local actualDmg, isDodged = GameState.DamagePlayer(rawDmg)
    if isDodged then
        Particles.SpawnDodgeText(bs.particles, p.x, p.y - 25)
        return 0
    end
    local elemColor = Config.ELEMENTS.colors[elem] or { 255, 255, 255 }
    local ox = randOffset and math.random(-10, 10) or 0
    Particles.SpawnDmgText(bs.particles, p.x + ox, p.y - 25, actualDmg, isCrit or false, false, elemColor)
    GameState.ApplyElementAndReact(elem, 0)
    if shake then CombatUtils.TriggerShake(bs, shake) end
    return actualDmg
end

-- ============================================================================
-- Boss 初始化 (Spawner 生成 Boss 后调用)
-- ============================================================================

--- 初始化带 phases 的 Boss, 设置阶段状态和技能 timer
function BossSkillTemplates.InitBoss(bs, enemy)
    if not enemy.phases then return end

    enemy._phaseIdx = 1
    enemy._invincible = false
    enemy._templateArmorActive = false
    enemy._templateArmorReduce = 0
    enemy._templateShieldActive = false
    enemy._templateShieldReduce = 0

    -- 初始化当前阶段所有技能的 timer
    BossSkillTemplates._InitPhaseSkills(bs, enemy, enemy.phases[1])
end

--- 内部: 将 StageConfig 的 { template, params } 展平为模板可直接读取的 cfg
local function flattenSkillCfg(skill)
    local cfg = {}
    -- 先复制 params 子表（如果有）
    if skill.params then
        for k, v in pairs(skill.params) do
            cfg[k] = v
        end
    end
    -- 再复制顶层字段（不覆盖 params 中已有的同名字段，但 template/element 等元信息始终取顶层）
    for k, v in pairs(skill) do
        if k ~= "params" then
            cfg[k] = v
        end
    end
    -- 兼容: templateId 或 template 均可查找模板
    cfg.templateId = skill.templateId or skill.template

    -- ========== 语义映射: StageConfig 字段名 → 模板期望字段名 ==========

    -- ATK_breath: onHit 实际是区域每 tick 触发, 映射为 onTick
    if cfg.templateId == "ATK_breath" then
        if cfg.onHit and not cfg.onTick then
            cfg.onTick = cfg.onHit
        end
    end

    -- CTL_field: effect 是区域每 tick 触发, 映射为 onTick
    if cfg.templateId == "CTL_field" then
        if cfg.effect and not cfg.onTick then
            cfg.onTick = cfg.effect
        end
    end

    -- CTL_vortex: coreEffect 是核心区每 tick 触发, 映射为 onCoreTick
    if cfg.templateId == "CTL_vortex" then
        if cfg.coreEffect and not cfg.onCoreTick then
            cfg.onCoreTick = cfg.coreEffect
        end
    end

    -- ATK_detonate: interval=0 视为 "once" (单次释放)
    if cfg.templateId == "ATK_detonate" then
        if cfg.interval == 0 then
            cfg.interval = "once"
        end
    end

    -- DEF_shield: shield_reaction (下划线) → shieldReaction (驼峰)
    if cfg.templateId == "DEF_shield" then
        local sr = cfg.shield_reaction or cfg.shieldReaction
        if sr then
            cfg.shieldReaction = sr
            -- timeoutPenalty 可能嵌套在 shield_reaction 内部
            if sr.timeoutPenalty and not cfg.timeoutPenalty then
                cfg.timeoutPenalty = sr.timeoutPenalty
            end
        end
    end

    return cfg
end

--- 工具: 调用回调或应用效果描述表
--- StageConfig 的 onHit/onContact/onExplode 等可能是函数(旧式)或表(新式效果描述)
--- 函数: 直接调用; 表: 解析并应用对应 debuff/效果
--- @param handler any 回调函数或效果描述表
--- @param bs table BattleSystem
--- @param source table 效果来源(弹体/区域/可摧毁物)
local function invokeOrApplyEffect(handler, bs, source, ...)
    if not handler then return end
    if type(handler) == "function" then
        handler(bs, source, ...)
        return
    end
    if type(handler) ~= "table" then return end

    -- 以下处理效果描述表
    local p = bs.playerBattle
    if not p or GameState.playerDead then return end

    -- slow: 减速
    if handler.slow then
        GameState.ApplySlowDebuff(handler.slow, handler.slowDuration or 2.0)
    end

    -- freeze: 冻结 (强减速, 值为持续时间)
    if handler.freeze then
        GameState.ApplySlowDebuff(0.95, handler.freeze)
    end

    -- frostbite: 冻伤 (轻微减速)
    if handler.frostbite then
        GameState.ApplySlowDebuff(handler.frostbite, 1.5)
    end

    -- dmgMul + radius: AoE 爆炸 (如冰晶碎裂)
    if handler.dmgMul and handler.radius then
        local elem = handler.element or (source and source.element) or "ice"
        local baseDmg = 0
        if source and source._ownerBoss then
            baseDmg = source._ownerBoss.atk or 0
        end
        local dmg = math.floor(baseDmg * handler.dmgMul)
        if dmg > 0 then
            local dist = math.sqrt((p.x - (source.x or 0))^2 + (p.y - (source.y or 0))^2)
            if dist <= handler.radius then
                local rawDmg = GameState.CalcElementDamage(dmg, elem)
                local actualDmg, isDodged = GameState.DamagePlayer(rawDmg)
                if isDodged then
                    Particles.SpawnDodgeText(bs.particles, p.x, p.y - 25)
                else
                    local elemColor = Config.ELEMENTS.colors[elem] or { 255, 255, 255 }
                    Particles.SpawnDmgText(bs.particles, p.x, p.y - 25, actualDmg, true, false, elemColor)
                    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_NORMAL)
                end
            end
        end
    end
end

--- 内部: 初始化一个阶段的所有技能 timer
function BossSkillTemplates._InitPhaseSkills(bs, enemy, phase)
    if not phase or not phase.skills then return end
    enemy._skillTimers = {}
    enemy._skillStates = {}
    enemy._flatSkillCfgs = {}
    for i, skill in ipairs(phase.skills) do
        local cfg = flattenSkillCfg(skill)
        enemy._flatSkillCfgs[i] = cfg
        local tmpl = templates[cfg.templateId]
        if tmpl then
            enemy._skillTimers[i] = cfg.interval or 999
            enemy._skillStates[i] = {}
            if tmpl.init then
                tmpl.init(bs, enemy, cfg)
            end
        end
    end
end

-- ============================================================================
-- 主更新 (每帧, EnemySystem.UpdateEnemyAbilities 之后调用)
-- ============================================================================

function BossSkillTemplates.Update(dt, bs)
    if GameState.playerDead then return end
    local p = bs.playerBattle
    if not p then return end

    for _, e in ipairs(bs.enemies) do
        if not e.dead and e.phases then
            -- 自动初始化 (Spawner 生成后首次进入 Update)
            if not e._phaseIdx then
                BossSkillTemplates.InitBoss(bs, e)
            end

            -- 检查阶段转换
            BossSkillTemplates._CheckPhaseTransition(dt, bs, e)

            -- 更新当前阶段技能（使用展平后的 cfg）
            local phase = e.phases[e._phaseIdx]
            if phase and phase.skills and e._flatSkillCfgs then
                for i, skill in ipairs(phase.skills) do
                    local cfg = e._flatSkillCfgs[i]
                    if cfg then
                        local tmpl = templates[cfg.templateId]
                        if tmpl and tmpl.update then
                            tmpl.update(dt, bs, e, cfg, i)
                        end
                    end
                end
            end
        end
    end
end

-- ============================================================================
-- 阶段转换检查
-- ============================================================================

function BossSkillTemplates._CheckPhaseTransition(dt, bs, enemy)
    -- 正在转换演出中
    if bs.phaseTransition and bs.phaseTransition.enemy == enemy then
        bs.phaseTransition.timer = bs.phaseTransition.timer - dt
        if bs.phaseTransition.timer <= 0 then
            -- 演出结束: 切换到下一阶段
            local nextIdx = bs.phaseTransition.nextPhaseIdx
            enemy._phaseIdx = nextIdx
            enemy._invincible = false
            BossSkillTemplates._InitPhaseSkills(bs, enemy, enemy.phases[nextIdx])
            -- 清理旧阶段威胁
            ThreatSystem.RemoveBySource(bs, enemy._sourceId or tostring(enemy))
            bs.phaseTransition = nil
        end
        return  -- 演出期间不执行任何技能
    end

    -- 检查下一阶段的触发条件
    local curIdx = enemy._phaseIdx or 1
    local curPhase = enemy.phases[curIdx]
    local nextIdx = curIdx + 1
    local nextPhase = enemy.phases[nextIdx]
    if not nextPhase then return end  -- 没有下一阶段

    -- 兼容两种配置格式:
    -- 格式A (模板标准): nextPhase.trigger = { type = "hpBelow", value = 0.55 }
    -- 格式B (StageConfig): curPhase.transition = { hpThreshold = 0.55, ... } 或 nextPhase.hpThreshold
    local trigger = nextPhase.trigger
    local triggerHp = nil
    if trigger and trigger.type == "hpBelow" then
        triggerHp = trigger.value
    elseif curPhase and curPhase.transition and curPhase.transition.hpThreshold then
        triggerHp = curPhase.transition.hpThreshold
    elseif nextPhase.hpThreshold and nextPhase.hpThreshold < 1.0 then
        triggerHp = nextPhase.hpThreshold
    end
    if not triggerHp then return end

    local hpPct = enemy.hp / enemy.maxHp
    if hpPct <= triggerHp then
        -- 触发阶段转换: 优先从当前阶段的 transition 取演出参数
        local transition = (curPhase and curPhase.transition) or nextPhase.transition or {}
        local duration = transition.duration or 1.0
        local invincible = transition.invincible ~= false
        local text = transition.text or "阶段转换!"

        if invincible then
            enemy._invincible = true
        end

        bs.phaseTransition = {
            enemy = enemy,
            timer = duration,
            maxTimer = duration,
            nextPhaseIdx = nextIdx,
            text = text,
            invincible = invincible,
        }

        -- 视觉效果
        Particles.SpawnReactionText(bs.particles, enemy.x, enemy.y - (enemy.radius or 16) - 25, text, { 200, 220, 255 })
        CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_STORM)

        -- 清空当前 bossZones
        if bs.bossZones then
            for i = #bs.bossZones, 1, -1 do
                if bs.bossZones[i].sourceEnemy == enemy then
                    table.remove(bs.bossZones, i)
                end
            end
        end
        -- 清空该 Boss 的弹体
        if bs.bossProjectiles then
            for i = #bs.bossProjectiles, 1, -1 do
                if bs.bossProjectiles[i].sourceEnemy == enemy then
                    table.remove(bs.bossProjectiles, i)
                end
            end
        end
    end
end

-- ============================================================================
-- 弹体系统更新 (真实空间弹体, 有位置/速度/碰撞)
-- ============================================================================

function BossSkillTemplates.UpdateProjectiles(dt, bs)
    if not bs.bossProjectiles then return end
    local p = bs.playerBattle
    if not p then return end

    for i = #bs.bossProjectiles, 1, -1 do
        local proj = bs.bossProjectiles[i]
        -- 更新位置
        proj.x = proj.x + proj.vx * dt
        proj.y = proj.y + proj.vy * dt
        proj.age = (proj.age or 0) + dt

        -- 出界检测
        local margin = 50
        if proj.x < -margin or proj.x > bs.areaW + margin
        or proj.y < -margin or proj.y > bs.areaH + margin then
            -- 移除弹体和威胁
            if proj.threatRef then
                ThreatSystem.RemoveBySource(bs, proj.threatId)
            end
            table.remove(bs.bossProjectiles, i)
        else
            -- 碰撞检测: 圆-圆
            local playerR = 12
            if ThreatSystem.CircleCircle(proj.x, proj.y, proj.radius, p.x, p.y, playerR) then
                -- 命中玩家
                local elem = proj.element or "physical"
                local rawDmg = GameState.CalcElementDamage(proj.dmg, elem)
                local actualDmg, isDodged = GameState.DamagePlayer(rawDmg)
                if isDodged then
                    Particles.SpawnDodgeText(bs.particles, p.x, p.y - 25)
                else
                    local elemColor = Config.ELEMENTS.colors[elem] or { 255, 255, 255 }
                    Particles.SpawnDmgText(bs.particles, p.x + math.random(-10, 10), p.y - 25, actualDmg, false, false, elemColor)
                end

                -- onHit 特调回调 (函数或效果描述表)
                if proj.onHit then
                    invokeOrApplyEffect(proj.onHit, bs, proj)
                end

                -- 元素附着
                GameState.ApplyElementAndReact(elem, 0)

                -- 移除弹体
                if proj.threatRef then
                    ThreatSystem.RemoveBySource(bs, proj.threatId)
                end
                table.remove(bs.bossProjectiles, i)
            else
                -- 更新威胁位置
                if proj.threatRef then
                    proj.threatRef.x = proj.x
                    proj.threatRef.y = proj.y
                end
            end
        end
    end
end

-- (UpdateZones 定义在下方 ATK_pulse 之后, 含 pulse 特殊处理)

-- ============================================================================
-- 可摧毁物更新 (crystal/shield/detonate 等)
-- ============================================================================

function BossSkillTemplates.UpdateDestroyables(dt, bs)
    -- 可摧毁物作为 bs.enemies 中的特殊实体, 大部分行为由 EnemyAI/CombatCore 管理
    -- 这里只处理模板特有逻辑 (回血/超时/引爆)
    for _, e in ipairs(bs.enemies) do
        if not e.dead and e.isBossDestroyable then
            if e.destroyableType == "crystal" then
                -- 冰晶: 每秒回复 Boss HP
                e._healTimer = (e._healTimer or 0) + dt
                if e._healTimer >= 1.0 then
                    e._healTimer = e._healTimer - 1.0
                    local boss = e._ownerBoss
                    if boss and not boss.dead then
                        -- 检测减疗 debuff
                        local healMul = 1.0
                        if boss._antiHealTimer and boss._antiHealTimer > 0 then
                            healMul = 1.0 - (boss._antiHealRate or 0)
                        end
                        local heal = math.floor(boss.maxHp * (e._healPct or 0.01) * healMul)
                        if heal > 0 and boss.hp < boss.maxHp then
                            boss.hp = math.min(boss.maxHp, boss.hp + heal)
                            Particles.SpawnDmgText(bs.particles, boss.x, boss.y - (boss.radius or 16) - 10, heal, false, false, { 120, 200, 255 })
                        end
                    end
                end

            elseif e.destroyableType == "detonate" then
                -- 限时引爆: 倒计时
                e._detonateTimer = (e._detonateTimer or e._detonateMaxTimer or 8) - dt
                if e._detonateTimer <= 0 then
                    -- 超时爆炸
                    BossSkillTemplates._TriggerDetonate(bs, e)
                    e.dead = true
                end

            elseif e.destroyableType == "shield" then
                -- 反应护盾: 持续时间检测
                e._shieldTimer = (e._shieldTimer or e._shieldMaxTimer or 10) - dt
                if e._shieldTimer <= 0 then
                    -- 超时: 触发超时惩罚
                    BossSkillTemplates._TriggerShieldTimeout(bs, e)
                    e.dead = true
                end
            end
        end
    end
end

--- 限时引爆超时爆炸
function BossSkillTemplates._TriggerDetonate(bs, detonateObj)
    local p = bs.playerBattle
    if not p then return end
    local boss = detonateObj._ownerBoss

    -- 全场爆炸伤害
    local dmg = detonateObj._detonateDmg or 0
    local elem = detonateObj._detonateElement or "ice"
    local rawDmg = GameState.CalcElementDamage(dmg, elem)
    local actualDmg, isDodged = GameState.DamagePlayer(rawDmg)
    if isDodged then
        Particles.SpawnDodgeText(bs.particles, p.x, p.y - 30)
        return
    end
    local elemColor = Config.ELEMENTS.colors[elem] or { 255, 255, 255 }
    Particles.SpawnDmgText(bs.particles, p.x, p.y - 30, actualDmg, true, false, elemColor)
    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_STORM)

    -- Boss 回血
    if boss and not boss.dead and detonateObj._bossHealPct then
        local heal = math.floor(boss.maxHp * detonateObj._bossHealPct)
        boss.hp = math.min(boss.maxHp, boss.hp + heal)
        Particles.SpawnDmgText(bs.particles, boss.x, boss.y - (boss.radius or 16) - 10, heal, false, false, { 120, 200, 255 })
    end

    -- 特调回调 (函数或效果描述表)
    if detonateObj._onExplode then
        invokeOrApplyEffect(detonateObj._onExplode, bs, detonateObj)
    end

    Particles.SpawnReactionText(bs.particles, detonateObj.x, detonateObj.y - 15, "引爆!", { 255, 100, 100 })
end

--- 反应护盾超时惩罚
function BossSkillTemplates._TriggerShieldTimeout(bs, shieldObj)
    local boss = shieldObj._ownerBoss
    local penalty = shieldObj._timeoutPenalty
    if not penalty or not boss or boss.dead then
        -- 无惩罚, 恢复 Boss 状态
        if boss then
            boss._templateShieldActive = false
            boss._templateShieldReduce = 0
        end
        return
    end

    if penalty.type == "bossHeal" then
        local heal = math.floor(boss.maxHp * (penalty.healPct or 0.10))
        boss.hp = math.min(boss.maxHp, boss.hp + heal)
        Particles.SpawnDmgText(bs.particles, boss.x, boss.y - (boss.radius or 16) - 10, heal, false, false, { 120, 200, 255 })
        Particles.SpawnReactionText(bs.particles, boss.x, boss.y - (boss.radius or 16) - 30, "护盾回血!", { 120, 200, 255 })
    elseif penalty.type == "bossBuff" then
        boss._atkBuffMul = (boss._atkBuffMul or 1.0) + (penalty.atkBonus or 0.2)
        boss._atkBuffTimer = penalty.duration or 8.0
        Particles.SpawnReactionText(bs.particles, boss.x, boss.y - (boss.radius or 16) - 30, "暴怒!", { 255, 100, 80 })
    elseif penalty.type == "explode" then
        local p = bs.playerBattle
        if p then
            local dmg = math.floor(boss.atk * (penalty.dmgMul or 2.0))
            local rawDmg = GameState.CalcElementDamage(dmg, boss.element or "ice")
            local actualDmg, isDodged = GameState.DamagePlayer(rawDmg)
            if isDodged then
                Particles.SpawnDodgeText(bs.particles, p.x, p.y - 30)
            else
                Particles.SpawnDmgText(bs.particles, p.x, p.y - 30, actualDmg, true, false, { 200, 220, 255 })
                CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_STORM)
            end
        end
    elseif penalty.type == "respawn" then
        -- 重新生成护盾 (标记, 在 DEF_shield update 中处理)
        boss._shieldRespawn = true
    end

    boss._templateShieldActive = false
    boss._templateShieldReduce = 0
end

-- ============================================================================
-- 阶段转换更新
-- ============================================================================

function BossSkillTemplates.UpdatePhaseTransition(dt, bs)
    -- 阶段转换逻辑已在 _CheckPhaseTransition 中处理
    -- 此函数保留用于未来的转换特效更新
end

-- ============================================================================
-- 可摧毁物受伤处理 (CombatCore 调用)
-- ============================================================================

--- 处理对可摧毁物的伤害 (不走正常 DamageFormula)
--- @param bs table BattleSystem
--- @param target table 可摧毁物敌人
--- @param dmg number 原始伤害
--- @param ctx table 伤害上下文 (含 element 等)
--- @return number 实际伤害
function BossSkillTemplates.DamageDestroyable(bs, target, dmg, ctx)
    if target.destroyableType == "shield" then
        return BossSkillTemplates._DamageShield(bs, target, dmg, ctx)
    end

    -- crystal / detonate: 正常扣血
    target.hp = target.hp - dmg

    if target.hp <= 0 then
        target.dead = true
        -- crystal 被摧毁回调
        if target.destroyableType == "crystal" and target._onDestroy then
            invokeOrApplyEffect(target._onDestroy, bs, target)
        end
        -- detonate 被摧毁 = 安全拆除
        if target.destroyableType == "detonate" then
            Particles.SpawnReactionText(bs.particles, target.x, target.y - 15, "拆除!", { 100, 255, 100 })
            -- 移除相关威胁
            ThreatSystem.RemoveBySource(bs, target._threatId)
        end

        -- 清除 Boss 的减伤状态 (如果是护盾)
        local boss = target._ownerBoss
        if boss then
            if target.destroyableType == "crystal" then
                -- 冰晶摧毁不影响 Boss 减伤
            end
        end
    end

    return dmg
end

--- 处理反应护盾受伤 (含弱点/惩罚逻辑)
function BossSkillTemplates._DamageShield(bs, shield, dmg, ctx)
    local reaction = shield._shieldReaction
    if not reaction then
        -- 无反应配置, 正常扣血
        shield.hp = shield.hp - dmg
        if shield.hp <= 0 then
            shield.dead = true
            BossSkillTemplates._OnShieldDestroyed(bs, shield)
        end
        return dmg
    end

    local hitElement = ctx.element or "weapon"
    -- 武器元素映射: "weapon" 使用玩家当前武器元素
    if hitElement == "weapon" then
        hitElement = GameState.GetWeaponElement() or "physical"
    end

    local p = bs.playerBattle
    local actualDmg = dmg

    -- 检查弱点
    if hitElement == reaction.weakElement then
        -- 弱点命中: 倍率加成
        actualDmg = math.floor(dmg * (reaction.weakMultiplier or 2.0))
        Particles.SpawnReactionText(bs.particles, shield.x, shield.y - 15, "弱点!", { 255, 200, 50 })
    else
        -- 非弱点: 先应用基础减免
        actualDmg = math.floor(dmg * (1 - (shield._baseResist or 0.5)))

        -- 检查特定元素惩罚
        local wrongEffects = reaction.wrongHitEffects
        if wrongEffects and wrongEffects[hitElement] then
            local eff = wrongEffects[hitElement]

            -- 护盾回血
            if eff.shieldHeal and eff.shieldHeal > 0 then
                local heal = math.floor(shield.maxHp * eff.shieldHeal)
                shield.hp = math.min(shield.maxHp, shield.hp + heal)
                Particles.SpawnDmgText(bs.particles, shield.x, shield.y - 10, heal, false, false, { 120, 200, 255 })
            end

            -- Boss 回血
            if eff.bossHeal and eff.bossHeal > 0 and shield._ownerBoss then
                local boss = shield._ownerBoss
                local heal = math.floor(boss.maxHp * eff.bossHeal)
                boss.hp = math.min(boss.maxHp, boss.hp + heal)
                Particles.SpawnDmgText(bs.particles, boss.x, boss.y - (boss.radius or 16) - 10, heal, false, false, { 120, 200, 255 })
            end

            -- 反弹伤害
            if eff.reflect and eff.reflect > 0 and p then
                local reflectDmg = math.floor(dmg * eff.reflect)
                local actualReflect, isDodged = GameState.DamagePlayer(reflectDmg)
                if isDodged then
                    Particles.SpawnDodgeText(bs.particles, p.x, p.y - 25)
                else
                    Particles.SpawnDmgText(bs.particles, p.x, p.y - 25, actualReflect, false, false, { 200, 200, 255 })
                    Particles.SpawnReactionText(bs.particles, shield.x, shield.y - 20, "反弹!", { 200, 200, 255 })
                end
            end

            -- 降低攻速
            if eff.atkSpeedReduce and eff.atkSpeedReduce > 0 then
                GameState.ApplyAtkSpeedDebuff(eff.atkSpeedReduce, eff.duration or 3.0)
            end

            -- 伤害系数调整
            if eff.dmgFactor then
                actualDmg = math.floor(actualDmg * eff.dmgFactor)
            end

            -- 自伤 DoT
            if eff.dotOnSelf and eff.dotOnSelf > 0 and p then
                local dotDmg = math.floor(GameState.GetMaxHP() * eff.dotOnSelf)
                -- 简单实现: 3s, 每秒tick
                for t = 1, 3 do
                    table.insert(bs.delayedActions, {
                        timer = t,
                        callback = function()
                            if not GameState.playerDead then
                                local actualDot, isDodged = GameState.DamagePlayer(dotDmg)
                                if isDodged then
                                    Particles.SpawnDodgeText(bs.particles, p.x, p.y - 25)
                                else
                                    Particles.SpawnDmgText(bs.particles, p.x, p.y - 25, actualDot, false, false, { 160, 100, 255 })
                                end
                            end
                        end,
                    })
                end
            end
        end
    end

    -- 扣血
    shield.hp = shield.hp - actualDmg
    if shield.hp <= 0 then
        shield.dead = true
        BossSkillTemplates._OnShieldDestroyed(bs, shield)
    end

    return actualDmg
end

--- 护盾被摧毁
function BossSkillTemplates._OnShieldDestroyed(bs, shield)
    local boss = shield._ownerBoss
    if boss then
        boss._templateShieldActive = false
        boss._templateShieldReduce = 0
    end
    Particles.SpawnReactionText(bs.particles, shield.x, shield.y - 15, "护盾破碎!", { 255, 200, 100 })
    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_CRIT)
    -- 移除威胁
    ThreatSystem.RemoveBySource(bs, shield._threatId)
end

-- ============================================================================
-- 工具: 生成可摧毁物实体 (插入 bs.enemies)
-- ============================================================================

--- 创建可摧毁物并插入 bs.enemies
--- @return table 可摧毁物实体
function BossSkillTemplates.SpawnDestroyable(bs, boss, dtype, x, y, hp, radius, extra)
    local obj = {
        x = x, y = y,
        hp = hp, maxHp = hp,
        atk = 0,
        speed = 0, radius = radius or 16,
        expDrop = 0, goldMin = 0, goldMax = 0,
        color = extra and extra.color or { 140, 200, 255 },
        isBoss = false, dead = false,
        def = 0, atkTimer = 0, atkCd = 999,
        atkRange = 0,
        name = extra and extra.name or dtype,
        knockbackVx = 0, knockbackVy = 0,
        weight = 999,  -- 不可击退
        element = boss.element or "ice",
        isBossDestroyable = true,
        destroyableType = dtype,
        _ownerBoss = boss,
        -- 必须有这些字段防止其他系统 nil 错误
        attachedElement = nil, attachedElementTimer = 0,
        defReduceRate = 0, defReduceTimer = 0,
        elemWeakenRate = 0, elemWeakenTimer = 0,
        reactionDot = nil,
        enraged = false,
        resist = boss.resist,
    }
    -- 合并额外字段
    if extra then
        for k, v in pairs(extra) do
            if obj[k] == nil then
                obj[k] = v
            end
        end
    end

    table.insert(bs.enemies, obj)
    return obj
end

-- ============================================================================
-- ATK_barrage 模板 — 真实空间弹幕
-- ============================================================================

BossSkillTemplates.RegisterTemplate("ATK_barrage", {
    --- 初始化
    init = function(bs, enemy, cfg)
        -- timer 在 _InitPhaseSkills 中已设置
    end,

    update = function(dt, bs, enemy, cfg, skillIdx)
        _timerUpdate(enemy, skillIdx, dt, cfg, 6, BossSkillTemplates._CastBarrage, bs)
    end,
})

--- ATK_barrage 施放: 向玩家方向扇形发射弹体
function BossSkillTemplates._CastBarrage(bs, enemy, cfg)
    if GameState.playerDead then return end
    local p = bs.playerBattle
    if not p then return end

    local count = cfg.count or 12
    local spread = math.rad(cfg.spread or 120)  -- 转换为弧度
    local dmgMul = cfg.dmgMul or 0.8
    local speed = cfg.speed or 200
    local dmg = math.floor(enemy.atk * dmgMul)
    local elem = cfg.element or enemy.element or "ice"

    -- 计算朝向玩家的角度
    local dx, dy = p.x - enemy.x, p.y - enemy.y
    local baseAngle = math.atan(dy, dx)

    Particles.SpawnReactionText(bs.particles, enemy.x, enemy.y - (enemy.radius or 16) - 20, "弹幕!", { 140, 200, 255 })
    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_NORMAL)

    local sourceId = tostring(enemy) .. "_barrage_" .. tostring(bs.time)

    for i = 1, count do
        -- 扇形内均匀分布
        local angleOffset = 0
        if count > 1 then
            angleOffset = (i - 1) / (count - 1) * spread - spread / 2
        end
        local angle = baseAngle + angleOffset

        local vx = math.cos(angle) * speed
        local vy = math.sin(angle) * speed

        local threatId = sourceId .. "_" .. i
        local threat = {
            type = "dangerZone",
            x = enemy.x,
            y = enemy.y,
            radius = cfg.projRadius or 12,
            damage = dmg,
            duration = 5.0,  -- 足够飞出屏幕
            priority = 0.4,
            sourceId = threatId,
        }
        ThreatSystem.Register(bs, threat)

        table.insert(bs.bossProjectiles, {
            x = enemy.x,
            y = enemy.y,
            vx = vx,
            vy = vy,
            radius = cfg.projRadius or 8,
            dmg = dmg,
            element = elem,
            sourceEnemy = enemy,
            age = 0,
            threatRef = threat,
            threatId = threatId,
            onHit = cfg.onHit,  -- 特调回调
        })
    end
end

-- ============================================================================
-- ATK_breath 模板 — 扇形持续伤害区域
-- ============================================================================

BossSkillTemplates.RegisterTemplate("ATK_breath", {
    init = function(bs, enemy, cfg) end,

    update = function(dt, bs, enemy, cfg, skillIdx)
        _timerUpdate(enemy, skillIdx, dt, cfg, 8, BossSkillTemplates._CastBreath, bs)
    end,
})

function BossSkillTemplates._CastBreath(bs, enemy, cfg)
    if GameState.playerDead then return end
    local p = bs.playerBattle
    if not p then return end

    local angle = math.rad(cfg.angle or 60)
    local range = cfg.range or 150
    local dmgMul = cfg.dmgMul or 0.5
    local tickRate = cfg.tickRate or 0.3
    local duration = cfg.duration or 1.5
    local elem = cfg.element or enemy.element or "ice"
    local dmg = math.floor(enemy.atk * dmgMul)

    -- 计算朝向玩家的角度
    local dx, dy = p.x - enemy.x, p.y - enemy.y
    local dirAngle = math.atan(dy, dx)

    local threatId = tostring(enemy) .. "_breath_" .. tostring(bs.time)

    local threat = {
        type = "dangerZone",
        x = enemy.x,
        y = enemy.y,
        radius = range,
        damage = dmg,
        duration = duration,
        priority = 0.7,
        sourceId = threatId,
        shape = "sector",
        shapeData = { dirAngle = dirAngle, halfAngle = angle / 2, range = range },
    }
    ThreatSystem.Register(bs, threat)

    table.insert(bs.bossZones, {
        shape = "sector",
        x = enemy.x,
        y = enemy.y,
        dirAngle = dirAngle,
        halfAngle = angle / 2,
        radius = range,
        dmg = dmg,
        element = elem,
        tickRate = tickRate,
        tickTimer = 0,
        duration = duration,
        maxDuration = duration,
        sourceEnemy = enemy,
        followEnemy = false,  -- 吐息方向固定
        threatRef = threat,
        threatId = threatId,
        onTick = cfg.onTick,
        onEnd = cfg.onEnd,
        age = 0,
        zoneType = "breath",
    })

    Particles.SpawnReactionText(bs.particles, enemy.x, enemy.y - (enemy.radius or 16) - 20, "吐息!", { 140, 180, 255 })
    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_STORM)
end

-- ============================================================================
-- ATK_spikes 模板 — 地刺 (预警+延迟触发+残留)
-- ============================================================================

BossSkillTemplates.RegisterTemplate("ATK_spikes", {
    init = function(bs, enemy, cfg) end,

    update = function(dt, bs, enemy, cfg, skillIdx)
        _timerUpdate(enemy, skillIdx, dt, cfg, 8, BossSkillTemplates._CastSpikes, bs)
    end,
})

function BossSkillTemplates._CastSpikes(bs, enemy, cfg)
    if GameState.playerDead then return end
    local p = bs.playerBattle
    if not p then return end

    local count = cfg.count or 3
    local radius = cfg.radius or 35
    local delay = cfg.delay or 1.2
    local dmgMul = cfg.dmgMul or 1.2
    local lingerTime = cfg.lingerTime or 0
    local elem = cfg.element or enemy.element or "ice"
    local dmg = math.floor(enemy.atk * dmgMul)

    Particles.SpawnReactionText(bs.particles, enemy.x, enemy.y - (enemy.radius or 16) - 20, "地刺!", { 180, 200, 255 })

    for i = 1, count do
        -- 在玩家周围随机位置生成
        local sx = p.x + math.random(-60, 60)
        local sy = p.y + math.random(-60, 60)
        sx = math.max(radius, math.min(bs.areaW - radius, sx))
        sy = math.max(radius, math.min(bs.areaH - radius, sy))

        local threatId = tostring(enemy) .. "_spike_" .. tostring(bs.time) .. "_" .. i

        -- 预警阶段: 注册 dangerZone 威胁
        local threat = {
            type = "dangerZone",
            x = sx,
            y = sy,
            radius = radius,
            damage = dmg,
            duration = delay + 0.5,
            priority = 0.7,
            sourceId = threatId,
        }
        ThreatSystem.Register(bs, threat)

        -- 添加预警区域 (仅视觉, 不造成伤害)
        table.insert(bs.bossZones, {
            shape = "circle",
            x = sx,
            y = sy,
            radius = radius,
            dmg = 0,  -- 预警阶段不伤害
            element = elem,
            tickRate = 999,
            tickTimer = 999,
            duration = delay,
            maxDuration = delay,
            sourceEnemy = enemy,
            followEnemy = false,
            threatRef = threat,
            threatId = threatId,
            age = 0,
            zoneType = "spike_warning",
            isWarning = true,
        })

        -- 延迟触发伤害
        table.insert(bs.delayedActions, {
            timer = delay,
            callback = function()
                if GameState.playerDead then return end
                -- 检测玩家是否在范围内
                local playerDist = ThreatSystem.Dist(p.x, p.y, sx, sy)
                if playerDist <= radius then
                    _hitPlayer(bs, dmg, elem, true, CombatUtils.SHAKE_CRIT, true)

                    -- onHit 特调 (函数或效果描述表)
                    if cfg.onHit then invokeOrApplyEffect(cfg.onHit, bs, cfg) end
                end

                -- 残留障碍
                if lingerTime > 0 then
                    local lingerThreatId = threatId .. "_linger"
                    local lingerThreat = {
                        type = "dangerZone",
                        x = sx,
                        y = sy,
                        radius = radius * 0.8,
                        damage = 0,  -- 残留主要是障碍, 低伤或特调伤害
                        duration = lingerTime,
                        priority = 0.3,
                        sourceId = lingerThreatId,
                    }
                    ThreatSystem.Register(bs, lingerThreat)

                    table.insert(bs.bossZones, {
                        shape = "circle",
                        x = sx,
                        y = sy,
                        radius = radius * 0.8,
                        dmg = 0,
                        element = elem,
                        tickRate = 0.5,
                        tickTimer = 0,
                        duration = lingerTime,
                        maxDuration = lingerTime,
                        sourceEnemy = enemy,
                        followEnemy = false,
                        threatRef = lingerThreat,
                        threatId = lingerThreatId,
                        age = 0,
                        zoneType = "spike_linger",
                        onTick = cfg.lingerOnTick or cfg.lingerEffect,  -- 特调: 残留接触效果(函数或效果描述表)
                    })
                end
            end,
        })
    end
end

-- ============================================================================
-- ATK_pulse 模板 — 扩散脉冲环
-- ============================================================================

BossSkillTemplates.RegisterTemplate("ATK_pulse", {
    init = function(bs, enemy, cfg) end,

    update = function(dt, bs, enemy, cfg, skillIdx)
        _timerUpdate(enemy, skillIdx, dt, cfg, 10, BossSkillTemplates._CastPulse, bs)
    end,
})

function BossSkillTemplates._CastPulse(bs, enemy, cfg)
    if GameState.playerDead then return end
    local p = bs.playerBattle
    if not p then return end

    local speed = cfg.speed or 80
    local width = cfg.width or 20
    local maxRadius = cfg.maxRadius or 200
    local dmgMul = cfg.dmgMul or 0.8
    local elem = cfg.element or enemy.element or "ice"
    local dmg = math.floor(enemy.atk * dmgMul)
    local duration = maxRadius / speed  -- 扩散到最大半径的时间

    local threatId = tostring(enemy) .. "_pulse_" .. tostring(bs.time)

    local threat = {
        type = "expandingRing",
        x = enemy.x,
        y = enemy.y,
        radius = maxRadius,
        damage = dmg,
        duration = duration,
        priority = 0.6,
        sourceId = threatId,
        shape = "ring",
        shapeData = { speed = speed, width = width, maxRadius = maxRadius },
    }
    ThreatSystem.Register(bs, threat)

    -- 脉冲环作为特殊区域
    table.insert(bs.bossZones, {
        shape = "ring",
        x = enemy.x,
        y = enemy.y,
        innerR = 0,
        outerR = width,
        currentRadius = 0,
        expandSpeed = speed,
        ringWidth = width,
        maxRadius = maxRadius,
        dmg = dmg,
        element = elem,
        tickRate = 0.1,
        tickTimer = 0,
        duration = duration,
        maxDuration = duration,
        sourceEnemy = enemy,
        followEnemy = false,
        threatRef = threat,
        threatId = threatId,
        age = 0,
        zoneType = "pulse",
        _hitPlayer = false,  -- 只命中一次
        hitEffect = cfg.hitEffect,
        hitDuration = cfg.hitDuration or 0.5,
        onHit = cfg.onHit,
    })

    Particles.SpawnReactionText(bs.particles, enemy.x, enemy.y - (enemy.radius or 16) - 20, "脉冲!", { 160, 180, 255 })
    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_SKILL)
end

-- ============================================================================
-- 区域系统更新 (含 pulse 脉冲环特殊处理)
-- ============================================================================

function BossSkillTemplates.UpdateZones(dt, bs)
    if not bs.bossZones then return end
    local p = bs.playerBattle
    if not p then return end

    for i = #bs.bossZones, 1, -1 do
        local zone = bs.bossZones[i]
        zone.age = (zone.age or 0) + dt
        zone.duration = zone.duration - dt

        if zone.duration <= 0 then
            ThreatSystem.RemoveBySource(bs, zone.threatId)
            if zone.onEnd then zone.onEnd(bs, zone) end
            table.remove(bs.bossZones, i)
        elseif zone.zoneType == "pulse" then
            -- 脉冲环: 扩散
            zone.currentRadius = (zone.currentRadius or 0) + zone.expandSpeed * dt
            zone.innerR = math.max(0, zone.currentRadius - zone.ringWidth)
            zone.outerR = zone.currentRadius

            -- 碰撞检测 (只命中一次)
            if not zone._hitPlayer then
                if ThreatSystem.PointInRing(p.x, p.y, zone.x, zone.y, zone.innerR, zone.outerR) then
                    zone._hitPlayer = true
                    _hitPlayer(bs, zone.dmg, zone.element, true, CombatUtils.SHAKE_NORMAL)

                    -- hitEffect
                    if zone.hitEffect == "stun" then
                        GameState.ApplySlowDebuff(0.95, zone.hitDuration or 0.5)
                    elseif zone.hitEffect == "slow" then
                        GameState.ApplySlowDebuff(0.5, zone.hitDuration or 1.0)
                    elseif zone.hitEffect == "knockback" then
                        -- 击退: 远离 Boss
                        local kdx, kdy = p.x - zone.x, p.y - zone.y
                        local kdist = math.sqrt(kdx * kdx + kdy * kdy)
                        if kdist > 1 then
                            p.x = p.x + (kdx / kdist) * 40
                            p.y = p.y + (kdy / kdist) * 40
                            p.x = math.max(20, math.min(bs.areaW - 20, p.x))
                            p.y = math.max(20, math.min(bs.areaH - 20, p.y))
                        end
                    end

                    if zone.onHit then invokeOrApplyEffect(zone.onHit, bs, zone) end
                end
            end

        elseif zone.zoneType == "spike_warning" then
            -- 预警区域: 仅视觉, 不伤害

        else
            -- 通用区域: tick 伤害
            zone.tickTimer = (zone.tickTimer or 0) - dt
            if zone.tickTimer <= 0 then
                zone.tickTimer = zone.tickRate

                local inZone = false
                if zone.shape == "circle" then
                    local distSq = ThreatSystem.DistSq(p.x, p.y, zone.x, zone.y)
                    inZone = distSq <= zone.radius * zone.radius
                elseif zone.shape == "sector" then
                    inZone = ThreatSystem.PointInSector(p.x, p.y, zone.x, zone.y, zone.dirAngle, zone.halfAngle, zone.radius)
                elseif zone.shape == "rect" then
                    inZone = ThreatSystem.PointInRect(p.x, p.y, zone.rx, zone.ry, zone.rw, zone.rh)
                end

                if inZone then
                    _hitPlayer(bs, zone.dmg, zone.element, false, nil, true)

                    if zone.onTick then invokeOrApplyEffect(zone.onTick, bs, zone) end
                end
            end

            -- 跟随 Boss
            if zone.followEnemy and zone.sourceEnemy and not zone.sourceEnemy.dead then
                zone.x = zone.sourceEnemy.x
                zone.y = zone.sourceEnemy.y
                if zone.threatRef then
                    zone.threatRef.x = zone.x
                    zone.threatRef.y = zone.y
                end
            end
        end
    end
end

-- ============================================================================
-- DEF_armor 模板 — 护甲
-- ============================================================================

BossSkillTemplates.RegisterTemplate("DEF_armor", {
    init = function(bs, enemy, cfg)
        enemy._templateArmorCdTimer = 0
    end,

    update = function(dt, bs, enemy, cfg, skillIdx)
        -- CD 倒计时
        if enemy._templateArmorCdTimer and enemy._templateArmorCdTimer > 0 then
            enemy._templateArmorCdTimer = enemy._templateArmorCdTimer - dt
        end

        -- 激活中倒计时
        if enemy._templateArmorActive then
            enemy._templateArmorTimer = (enemy._templateArmorTimer or 0) - dt
            if enemy._templateArmorTimer <= 0 then
                enemy._templateArmorActive = false
                enemy._templateArmorReduce = 0
                enemy._templateArmorCdTimer = cfg.cd or 13
            end
        else
            -- 检测触发条件
            local hpPct = enemy.hp / enemy.maxHp
            if hpPct <= (cfg.hpThreshold or 0.5) and (enemy._templateArmorCdTimer or 0) <= 0 then
                enemy._templateArmorActive = true
                enemy._templateArmorReduce = cfg.dmgReduce or 0.65
                enemy._templateArmorTimer = cfg.duration or 5
                Particles.SpawnReactionText(bs.particles, enemy.x, enemy.y - (enemy.radius or 16) - 20, "护甲!", { 120, 200, 255 })
                -- 视觉特效
                table.insert(bs.bossSkillEffects, {
                    type = "iceArmor",
                    element = cfg.element or enemy.element or "ice",
                    enemyRef = enemy,
                    life = cfg.duration or 5, maxLife = cfg.duration or 5,
                })
            end
        end
    end,
})

-- ============================================================================
-- DEF_regen 模板 — 回血
-- ============================================================================

BossSkillTemplates.RegisterTemplate("DEF_regen", {
    init = function(bs, enemy, cfg) end,

    update = function(dt, bs, enemy, cfg, skillIdx)
        local hpPct = enemy.hp / enemy.maxHp
        if hpPct <= (cfg.hpThreshold or 0.3) then
            enemy._regenTimer = (enemy._regenTimer or 0) + dt
            if enemy._regenTimer >= 1.0 then
                enemy._regenTimer = enemy._regenTimer - 1.0
                -- 检测减疗 debuff
                local healMul = 1.0
                if enemy._antiHealTimer and enemy._antiHealTimer > 0 then
                    healMul = 1.0 - (enemy._antiHealRate or 0)
                end
                local heal = math.floor(enemy.maxHp * (cfg.regenPct or 0.03) * healMul)
                if heal > 0 and enemy.hp < enemy.maxHp then
                    enemy.hp = math.min(enemy.maxHp, enemy.hp + heal)
                    Particles.SpawnDmgText(bs.particles, enemy.x, enemy.y - (enemy.radius or 16) - 10, heal, false, false, { 120, 200, 255 })
                end
            end
        end
    end,
})

-- ============================================================================
-- DEF_crystal 模板 — 回血晶体
-- ============================================================================

BossSkillTemplates.RegisterTemplate("DEF_crystal", {
    init = function(bs, enemy, cfg)
        enemy._crystalSpawnTimer = cfg.spawnInterval or 12
    end,

    update = function(dt, bs, enemy, cfg, skillIdx)
        enemy._crystalSpawnTimer = (enemy._crystalSpawnTimer or 0) - dt
        if enemy._crystalSpawnTimer <= 0 then
            enemy._crystalSpawnTimer = cfg.spawnInterval or 12
            BossSkillTemplates._SpawnCrystals(bs, enemy, cfg)
        end
    end,
})

function BossSkillTemplates._SpawnCrystals(bs, enemy, cfg)
    local count = cfg.count or 2
    local hpPct = cfg.hpPct or 0.02
    local healPct = cfg.healPct or 0.015
    local spawnRadius = cfg.spawnRadius or 80
    local elem = cfg.element or enemy.element or "ice"

    for i = 1, count do
        local angle = (i / count) * math.pi * 2 + math.random() * 0.5
        local cx = enemy.x + math.cos(angle) * spawnRadius
        local cy = enemy.y + math.sin(angle) * spawnRadius
        cx = math.max(20, math.min(bs.areaW - 20, cx))
        cy = math.max(20, math.min(bs.areaH - 20, cy))

        local crystalHp = math.floor(enemy.maxHp * hpPct)
        local threatId = tostring(enemy) .. "_crystal_" .. tostring(bs.time) .. "_" .. i

        local crystal = BossSkillTemplates.SpawnDestroyable(bs, enemy, "crystal", cx, cy, crystalHp, 14, {
            name = "冰晶",
            color = { 120, 200, 255 },
            _healPct = healPct,
            _threatId = threatId,
            _onDestroy = cfg.onDestroy,
        })

        -- 注册威胁
        ThreatSystem.Register(bs, {
            type = "priorityTarget",
            x = cx,
            y = cy,
            radius = 14,
            damage = 0,
            duration = 9999,
            priority = cfg.priority or 0.6,
            sourceId = threatId,
        })
    end

    Particles.SpawnReactionText(bs.particles, enemy.x, enemy.y - (enemy.radius or 16) - 20, "冰晶生成!", { 120, 200, 255 })
end

-- ============================================================================
-- DEF_shield 模板 — 反应护盾
-- ============================================================================

BossSkillTemplates.RegisterTemplate("DEF_shield", {
    init = function(bs, enemy, cfg)
        enemy._shieldCdTimer = 0
        enemy._shieldRespawn = false
    end,

    update = function(dt, bs, enemy, cfg, skillIdx)
        -- CD 倒计时
        if enemy._shieldCdTimer and enemy._shieldCdTimer > 0 then
            enemy._shieldCdTimer = enemy._shieldCdTimer - dt
        end

        -- respawn 标记
        if enemy._shieldRespawn then
            enemy._shieldRespawn = false
            BossSkillTemplates._SpawnShield(bs, enemy, cfg)
            return
        end

        -- 检测触发条件 (无活跃护盾且CD就绪)
        if not enemy._templateShieldActive then
            local hpPct = enemy.hp / enemy.maxHp
            if hpPct <= (cfg.hpThreshold or 0.5) and (enemy._shieldCdTimer or 0) <= 0 then
                BossSkillTemplates._SpawnShield(bs, enemy, cfg)
            end
        end
    end,
})

function BossSkillTemplates._SpawnShield(bs, enemy, cfg)
    local hpPct = cfg.hpPct or 0.03
    local shieldHp = math.floor(enemy.maxHp * hpPct)
    local elem = cfg.element or enemy.element or "ice"
    local threatId = tostring(enemy) .. "_shield_" .. tostring(bs.time)

    enemy._templateShieldActive = true
    enemy._templateShieldReduce = cfg.bossDmgReduce or 0.80
    enemy._shieldCdTimer = cfg.cd or 18

    local shield = BossSkillTemplates.SpawnDestroyable(bs, enemy, "shield", enemy.x, enemy.y + 30, shieldHp, 20, {
        name = "反应护盾",
        color = { 100, 180, 255 },
        _baseResist = cfg.baseResist or 0.50,
        _shieldReaction = cfg.shieldReaction,
        _timeoutPenalty = cfg.timeoutPenalty,
        _shieldTimer = cfg.duration or 10,
        _shieldMaxTimer = cfg.duration or 10,
        _threatId = threatId,
    })

    -- 注册威胁
    ThreatSystem.Register(bs, {
        type = "priorityTarget",
        x = shield.x,
        y = shield.y,
        radius = 20,
        damage = 0,
        duration = cfg.duration or 10,
        priority = 0.8,
        sourceId = threatId,
    })

    Particles.SpawnReactionText(bs.particles, enemy.x, enemy.y - (enemy.radius or 16) - 20, "反应护盾!", { 100, 180, 255 })
    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_SKILL)
end

-- ============================================================================
-- CTL_field 模板 — 领域 (以Boss为中心的持续区域)
-- ============================================================================

BossSkillTemplates.RegisterTemplate("CTL_field", {
    init = function(bs, enemy, cfg)
        enemy._fieldCdTimer = 0
    end,

    update = function(dt, bs, enemy, cfg, skillIdx)
        if enemy._fieldCdTimer and enemy._fieldCdTimer > 0 then
            enemy._fieldCdTimer = enemy._fieldCdTimer - dt
        end

        -- 无活跃领域时检测触发
        if not enemy._fieldActive then
            local hpPct = enemy.hp / enemy.maxHp
            if hpPct <= (cfg.hpThreshold or 1.0) and (enemy._fieldCdTimer or 0) <= 0 then
                enemy._fieldActive = true
                BossSkillTemplates._CastField(bs, enemy, cfg)
            end
        end
    end,
})

function BossSkillTemplates._CastField(bs, enemy, cfg)
    local radius = cfg.radius or 120
    local dmgMul = cfg.dmgMul or 0.30
    local tickRate = cfg.tickRate or 0.5
    local duration = cfg.duration or 8
    local elem = cfg.element or enemy.element or "ice"
    local dmg = math.floor(enemy.atk * dmgMul)

    local threatId = tostring(enemy) .. "_field_" .. tostring(bs.time)

    ThreatSystem.Register(bs, {
        type = "dangerZone",
        x = enemy.x,
        y = enemy.y,
        radius = radius,
        damage = dmg,
        duration = duration,
        priority = 0.5,
        sourceId = threatId,
    })

    table.insert(bs.bossZones, {
        shape = "circle",
        x = enemy.x,
        y = enemy.y,
        radius = radius,
        dmg = dmg,
        element = elem,
        tickRate = tickRate,
        tickTimer = 0,
        duration = duration,
        maxDuration = duration,
        sourceEnemy = enemy,
        followEnemy = true,  -- 跟随 Boss
        threatRef = nil,
        threatId = threatId,
        age = 0,
        zoneType = "field",
        onTick = cfg.onTick,
        onEnd = function(bs2, zone)
            enemy._fieldActive = false
            enemy._fieldCdTimer = cfg.cd or 14
        end,
    })

    Particles.SpawnReactionText(bs.particles, enemy.x, enemy.y - (enemy.radius or 16) - 20, "领域!", { 100, 160, 255 })
    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_SKILL)
end

-- ============================================================================
-- CTL_barrier 模板 — 障壁
-- ============================================================================

BossSkillTemplates.RegisterTemplate("CTL_barrier", {
    init = function(bs, enemy, cfg) end,

    update = function(dt, bs, enemy, cfg, skillIdx)
        _timerUpdate(enemy, skillIdx, dt, cfg, 14, BossSkillTemplates._CastBarrier, bs)
    end,
})

function BossSkillTemplates._CastBarrier(bs, enemy, cfg)
    if GameState.playerDead then return end
    local p = bs.playerBattle
    if not p then return end

    local count = cfg.count or 2
    local duration = cfg.duration or 6
    local contactDmgMul = cfg.contactDmgMul or 0.3
    local elem = cfg.element or enemy.element or "ice"
    local contactDmg = math.floor(enemy.atk * contactDmgMul)

    for i = 1, count do
        -- 在玩家与Boss之间或边缘生成墙壁
        local wallW, wallH = 60, 12
        local wx, wy
        if i % 2 == 1 then
            -- 水平墙
            wx = p.x + math.random(-80, 80)
            wy = p.y + math.random(30, 60) * (math.random() < 0.5 and 1 or -1)
        else
            -- 垂直墙
            wallW, wallH = 12, 60
            wx = p.x + math.random(30, 60) * (math.random() < 0.5 and 1 or -1)
            wy = p.y + math.random(-80, 80)
        end
        wx = math.max(0, math.min(bs.areaW - wallW, wx))
        wy = math.max(0, math.min(bs.areaH - wallH, wy))

        local threatId = tostring(enemy) .. "_barrier_" .. tostring(bs.time) .. "_" .. i

        ThreatSystem.Register(bs, {
            type = "dangerZone",
            x = wx + wallW / 2,
            y = wy + wallH / 2,
            radius = math.max(wallW, wallH) / 2,
            damage = contactDmg,
            duration = duration,
            priority = 0.5,
            sourceId = threatId,
            shape = "rect",
            shapeData = { rx = wx, ry = wy, rw = wallW, rh = wallH },
        })

        table.insert(bs.bossZones, {
            shape = "rect",
            rx = wx, ry = wy, rw = wallW, rh = wallH,
            x = wx + wallW / 2,
            y = wy + wallH / 2,
            radius = math.max(wallW, wallH) / 2,
            dmg = contactDmg,
            element = elem,
            tickRate = 0.3,
            tickTimer = 0,
            duration = duration,
            maxDuration = duration,
            sourceEnemy = enemy,
            followEnemy = false,
            threatId = threatId,
            age = 0,
            zoneType = "barrier",
            onTick = cfg.onContact,
        })
    end

    Particles.SpawnReactionText(bs.particles, enemy.x, enemy.y - (enemy.radius or 16) - 20, "障壁!", { 140, 180, 255 })
end

-- ============================================================================
-- CTL_vortex 模板 — 漩涡 (牵引)
-- ============================================================================

BossSkillTemplates.RegisterTemplate("CTL_vortex", {
    init = function(bs, enemy, cfg) end,

    update = function(dt, bs, enemy, cfg, skillIdx)
        _timerUpdate(enemy, skillIdx, dt, cfg, 12, BossSkillTemplates._CastVortex, bs)
    end,
})

function BossSkillTemplates._CastVortex(bs, enemy, cfg)
    if GameState.playerDead then return end
    local p = bs.playerBattle
    if not p then return end

    local radius = cfg.radius or 100
    local pullSpeed = cfg.pullSpeed or 30
    local coreDmgMul = cfg.coreDmgMul or 0.6
    local coreRadius = cfg.coreRadius or 30
    local duration = cfg.duration or 4
    local elem = cfg.element or enemy.element or "ice"
    local coreDmg = math.floor(enemy.atk * coreDmgMul)

    -- 漩涡位置: Boss 附近偏向玩家
    local dx, dy = p.x - enemy.x, p.y - enemy.y
    local dist = math.sqrt(dx * dx + dy * dy)
    local vx, vy = enemy.x, enemy.y
    if dist > 1 then
        vx = enemy.x + (dx / dist) * math.min(dist * 0.4, 60)
        vy = enemy.y + (dy / dist) * math.min(dist * 0.4, 60)
    end

    local threatId = tostring(enemy) .. "_vortex_" .. tostring(bs.time)

    ThreatSystem.Register(bs, {
        type = "pull",
        x = vx,
        y = vy,
        radius = radius,
        damage = coreDmg,
        duration = duration,
        priority = 0.7,
        sourceId = threatId,
        shape = "circle",
        shapeData = { pullSpeed = pullSpeed, coreRadius = coreRadius },
    })

    table.insert(bs.bossZones, {
        shape = "circle",
        x = vx,
        y = vy,
        radius = radius,
        dmg = coreDmg,
        element = elem,
        tickRate = 0.3,
        tickTimer = 0,
        duration = duration,
        maxDuration = duration,
        sourceEnemy = enemy,
        followEnemy = false,
        threatId = threatId,
        age = 0,
        zoneType = "vortex",
        pullSpeed = pullSpeed,
        coreRadius = coreRadius,
        onTick = function(bs2, player, zone)
            -- 核心区域额外伤害在通用 tick 中已处理
            -- 特调回调
            if cfg.onCoreTick then invokeOrApplyEffect(cfg.onCoreTick, bs2, zone) end
        end,
    })

    Particles.SpawnReactionText(bs.particles, vx, vy - 20, "漩涡!", { 140, 140, 255 })
    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_SKILL)
end

-- ============================================================================
-- CTL_decay 模板 — 持续衰减
-- ============================================================================

BossSkillTemplates.RegisterTemplate("CTL_decay", {
    init = function(bs, enemy, cfg)
        enemy._decayActivated = false
        enemy._decayAccum = 0
    end,

    update = function(dt, bs, enemy, cfg, skillIdx)
        local hpPct = enemy.hp / enemy.maxHp
        if hpPct <= (cfg.hpThreshold or 0.5) then
            enemy._decayActivated = true
        end

        if enemy._decayActivated then
            local stat = cfg.stat or "moveSpeed"
            local reducePerSec = cfg.reducePerSec or 0.02
            local maxReduce = cfg.maxReduce or 0.30

            enemy._decayAccum = math.min(maxReduce, (enemy._decayAccum or 0) + reducePerSec * dt)

            -- 应用到 GameState
            if stat == "moveSpeed" then
                GameState._bossDecayMoveSpeed = enemy._decayAccum
            elseif stat == "atkSpeed" then
                GameState._bossDecayAtkSpeed = enemy._decayAccum
            elseif stat == "atk" then
                GameState._bossDecayAtk = enemy._decayAccum
            elseif stat == "def" then
                GameState._bossDecayDef = enemy._decayAccum
            end
        end
    end,
})

--- CTL_decay 被 Boss 技能命中时的额外叠加 (外部调用)
function BossSkillTemplates.ApplyDecayBonusOnHit(enemy)
    if not enemy._decayActivated then return end
    for _, phase in ipairs(enemy.phases or {}) do
        if phase.skills then
            for _, skill in ipairs(phase.skills) do
                local tid = skill.templateId or skill.template
                if tid == "CTL_decay" then
                    local p = skill.params or skill
                    local bonusOnHit = p.bonusOnHit or skill.bonusOnHit
                    if bonusOnHit then
                        local maxReduce = p.maxReduce or skill.maxReduce or 0.30
                        enemy._decayAccum = math.min(maxReduce, (enemy._decayAccum or 0) + bonusOnHit)
                    end
                end
            end
        end
    end
end

-- ============================================================================
-- SUM_minion 模板 — 召唤小怪 (复用旧 summon 逻辑)
-- ============================================================================

BossSkillTemplates.RegisterTemplate("SUM_minion", {
    init = function(bs, enemy, cfg) end,

    update = function(dt, bs, enemy, cfg, skillIdx)
        _timerUpdate(enemy, skillIdx, dt, cfg, 10, BossSkillTemplates._SummonMinions, bs)
    end,
})

function BossSkillTemplates._SummonMinions(bs, enemy, cfg)
    local gs = GameState.stage
    local scaleMul = StageConfig.GetScaleMul(gs.chapter, gs.stage)

    -- 优先用 Boss 同家族的 swarm 成员，fallback 到 cfg.monsterId
    local sTemplate = nil
    local templateId = cfg.monsterId
    if enemy.familyId then
        local familyDef = MonsterFamilies.Get(enemy.familyId)
        if familyDef and familyDef.members and familyDef.members.swarm then
            sTemplate = MonsterFamilies.Resolve(enemy.familyId, "swarm", gs.chapter, nil, nil)
            templateId = enemy.familyId .. "_swarm"
        end
    end
    if not sTemplate then
        sTemplate = StageConfig.MONSTERS[cfg.monsterId]
    end
    if not sTemplate then return end

    for _ = 1, (cfg.count or 3) do
        local sHp = math.floor(sTemplate.hp * scaleMul)
        local sAtk = math.floor(sTemplate.atk * scaleMul)
        local sx = enemy.x + math.random(-50, 50)
        local sy = enemy.y + math.random(-50, 50)
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
            attachedElement = nil, attachedElementTimer = 0,
            defReduceRate = 0, defReduceTimer = 0,
            elemWeakenRate = 0, elemWeakenTimer = 0,
            reactionDot = nil,
            templateId = templateId,
            enraged = false,
            resist = sTemplate.resist,
            _isSummon = true,
        })
    end
    Particles.SpawnReactionText(bs.particles, enemy.x, enemy.y - (enemy.radius or 16) - 20, "召唤!", { 180, 140, 255 })
end

-- ============================================================================
-- SUM_guard 模板 — 嘲讽守卫
-- ============================================================================

BossSkillTemplates.RegisterTemplate("SUM_guard", {
    init = function(bs, enemy, cfg) end,

    update = function(dt, bs, enemy, cfg, skillIdx)
        _timerUpdate(enemy, skillIdx, dt, cfg, 15, BossSkillTemplates._SpawnGuards, bs)
    end,
})

function BossSkillTemplates._SpawnGuards(bs, enemy, cfg)
    local count = cfg.count or 2
    local hpPct = cfg.hpPct or 0.01
    local atkMul = cfg.atkMul or 0.4
    local tauntWeight = cfg.tauntWeight or 0.6

    for i = 1, count do
        local angle = (i / count) * math.pi * 2 + math.random() * 0.5
        local gx = enemy.x + math.cos(angle) * 60
        local gy = enemy.y + math.sin(angle) * 60
        gx = math.max(20, math.min(bs.areaW - 20, gx))
        gy = math.max(20, math.min(bs.areaH - 20, gy))

        local guardHp = math.floor(enemy.maxHp * hpPct)
        local guardAtk = math.floor(enemy.atk * atkMul)
        local threatId = tostring(enemy) .. "_guard_" .. tostring(bs.time) .. "_" .. i

        table.insert(bs.enemies, {
            x = gx, y = gy,
            hp = guardHp, maxHp = guardHp, atk = guardAtk,
            speed = 20, radius = 14,
            expDrop = 0, goldMin = 0, goldMax = 0,
            color = { 100, 160, 255 },
            isBoss = false, dead = false,
            def = math.floor(enemy.def * 0.5), atkTimer = 0,
            atkCd = 2.5, atkRange = 35,
            name = "嘲讽守卫",
            knockbackVx = 0, knockbackVy = 0,
            weight = 2.0,
            element = enemy.element or "ice",
            attachedElement = nil, attachedElementTimer = 0,
            defReduceRate = 0, defReduceTimer = 0,
            elemWeakenRate = 0, elemWeakenTimer = 0,
            reactionDot = nil,
            enraged = false,
            resist = enemy.resist,
            _isTauntGuard = true,
            _tauntWeight = tauntWeight,
            _tauntThreatId = threatId,
        })

        ThreatSystem.Register(bs, {
            type = "taunt",
            x = gx,
            y = gy,
            radius = 200,
            damage = 0,
            duration = 9999,
            priority = tauntWeight,
            sourceId = threatId,
        })
    end
    Particles.SpawnReactionText(bs.particles, enemy.x, enemy.y - (enemy.radius or 16) - 20, "守卫!", { 100, 160, 255 })
end

-- ============================================================================
-- ATK_detonate 模板 — 限时引爆
-- ============================================================================

BossSkillTemplates.RegisterTemplate("ATK_detonate", {
    init = function(bs, enemy, cfg)
        enemy._detonateUsed = false
    end,

    update = function(dt, bs, enemy, cfg, skillIdx)
        -- once 模式: 只触发一次
        if cfg.interval == "once" then
            if enemy._detonateUsed then return end
        else
            if not enemy._skillTimers then return end
            enemy._skillTimers[skillIdx] = (enemy._skillTimers[skillIdx] or 0) - dt
            if enemy._skillTimers[skillIdx] > 0 then return end
            enemy._skillTimers[skillIdx] = cfg.interval or 25
        end

        BossSkillTemplates._CastDetonate(bs, enemy, cfg)
        enemy._detonateUsed = true
    end,
})

function BossSkillTemplates._CastDetonate(bs, enemy, cfg)
    if GameState.playerDead then return end

    local count = cfg.count or 4
    local hpPct = cfg.hpPct or 0.008
    local timer = cfg.timer or 8
    local dmgMul = cfg.dmgMul or 2.0
    local bossHealPct = cfg.bossHealPct or 0.10
    local elem = cfg.element or enemy.element or "ice"
    local dmg = math.floor(enemy.atk * dmgMul)

    for i = 1, count do
        local angle = (i / count) * math.pi * 2 + math.random() * 0.3
        local dist = 60 + math.random(0, 40)
        local dx = enemy.x + math.cos(angle) * dist
        local dy = enemy.y + math.sin(angle) * dist
        dx = math.max(20, math.min(bs.areaW - 20, dx))
        dy = math.max(20, math.min(bs.areaH - 20, dy))

        local objHp = math.floor(enemy.maxHp * hpPct)
        local threatId = tostring(enemy) .. "_detonate_" .. tostring(bs.time) .. "_" .. i

        BossSkillTemplates.SpawnDestroyable(bs, enemy, "detonate", dx, dy, objHp, 12, {
            name = "引爆物",
            color = { 255, 100, 100 },
            _detonateTimer = timer,
            _detonateMaxTimer = timer,
            _detonateDmg = dmg,
            _detonateElement = elem,
            _bossHealPct = bossHealPct,
            _onExplode = cfg.onExplode,
            _threatId = threatId,
        })

        ThreatSystem.Register(bs, {
            type = "priorityTarget",
            x = dx,
            y = dy,
            radius = 12,
            damage = dmg,
            duration = timer + 1,
            priority = 0.95,
            sourceId = threatId,
        })
    end

    Particles.SpawnReactionText(bs.particles, enemy.x, enemy.y - (enemy.radius or 16) - 25, "限时引爆!", { 255, 100, 100 })
    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_STORM)
end

-- ============================================================================
-- 漩涡牵引力更新 (在 BattleSystem.Update 中每帧调用)
-- ============================================================================

function BossSkillTemplates.UpdateVortexPull(dt, bs)
    if not bs.bossZones then return end
    local p = bs.playerBattle
    if not p or GameState.playerDead then return end

    for _, zone in ipairs(bs.bossZones) do
        if zone.zoneType == "vortex" and zone.duration > 0 then
            local dx, dy = zone.x - p.x, zone.y - p.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < zone.radius and dist > 1 then
                -- 牵引力: 越近越强
                local pullStrength = zone.pullSpeed * (1 - dist / zone.radius) * dt
                p.x = p.x + (dx / dist) * pullStrength
                p.y = p.y + (dy / dist) * pullStrength
                p.x = math.max(20, math.min(bs.areaW - 20, p.x))
                p.y = math.max(20, math.min(bs.areaH - 20, p.y))
            end
        end
    end
end

-- ============================================================================
-- 清理: Boss 死亡时清除相关数据
-- ============================================================================

function BossSkillTemplates.OnBossDied(bs, enemy)
    if not enemy.phases then return end

    -- 清除所有威胁
    ThreatSystem.RemoveBySource(bs, tostring(enemy))

    -- 清除弹体
    if bs.bossProjectiles then
        for i = #bs.bossProjectiles, 1, -1 do
            if bs.bossProjectiles[i].sourceEnemy == enemy then
                table.remove(bs.bossProjectiles, i)
            end
        end
    end

    -- 清除区域
    if bs.bossZones then
        for i = #bs.bossZones, 1, -1 do
            if bs.bossZones[i].sourceEnemy == enemy then
                table.remove(bs.bossZones, i)
            end
        end
    end

    -- 清除可摧毁物
    for _, e in ipairs(bs.enemies) do
        if e.isBossDestroyable and e._ownerBoss == enemy then
            e.dead = true
        end
    end

    -- 清除 Decay 状态
    GameState._bossDecayMoveSpeed = 0
    GameState._bossDecayAtkSpeed = 0
    GameState._bossDecayAtk = 0
    GameState._bossDecayDef = 0

    -- 清除阶段转换
    if bs.phaseTransition and bs.phaseTransition.enemy == enemy then
        bs.phaseTransition = nil
    end
end

return BossSkillTemplates
