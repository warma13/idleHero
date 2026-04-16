-- ============================================================================
-- battle/skills/FireSkills.lua - 火系技能施放
-- fire_bolt, fireball, incinerate, flame_shield, hydra, firewall,
-- fire_storm, meteor
-- ============================================================================

local GameState      = require("GameState")
local CombatUtils    = require("battle.CombatUtils")
local H              = require("battle.skills.Helpers")
local ShieldManager  = require("state.ShieldManager")

local function Register(SkillCaster)

-- ============================================================================
-- 火焰弹 (fire_bolt) — 基础火系: 直击 + 内置燃烧DoT
-- 强化: 穿透燃烧中的敌人 | 闪烁: 生成法力 | 闪耀: +30%对燃烧敌人
-- ============================================================================
function SkillCaster._Cast_fire_bolt(bs, skillCfg, lv, p)
    local element = "fire"
    local range = 200 * GameState.GetRangeFactor()
    local dmgScale = skillCfg.effect(lv) / 100
    local burnPct = skillCfg.burnDmgPct and skillCfg.burnDmgPct(lv) or 0.04
    local burnDur = skillCfg.burnDuration or 6.0

    local hasPenetrate = H.HasEnhance("fire_bolt_enhanced")
    local hasManaGen   = H.HasEnhance("fire_bolt_flickering")
    local hasBurnBonus = H.HasEnhance("fire_bolt_glinting")
    local manaGenAmt   = hasManaGen and 2 or 0

    -- 穿透模式: 命中所有范围内目标 (优先最近的)
    -- 普通模式: 仅命中最近一个
    local targets = {}
    if hasPenetrate then
        for _, e in ipairs(bs.enemies) do
            if not e.dead then
                local dx, dy = e.x - p.x, e.y - p.y
                if math.sqrt(dx * dx + dy * dy) <= range then
                    targets[#targets + 1] = e
                end
            end
        end
    else
        local t = H.FindNearestEnemy(bs.enemies, p.x, p.y, range)
        if t then targets[1] = t end
    end

    if #targets > 0 then CombatUtils.PlaySfx("fireBolt", 0.5) end
    local lastTarget = nil
    for _, target in ipairs(targets) do
        local bonuses = {}
        if hasBurnBonus and target.burnTimer and target.burnTimer > 0 then
            bonuses.enhanced = 0.30
        end
        H.HitEnemySkill(bs, target, dmgScale, element, bonuses, p.x, p.y, CombatUtils.KNOCKBACK_SKILL)
        -- 内置燃烧 (始终施加)
        if not target.dead then
            H.ApplyBurn(target, burnPct / burnDur, burnDur)
        end
        -- 闪烁: 命中生成法力
        if hasManaGen then
            local maxMana = GameState.GetMaxMana()
            GameState.playerMana = math.min(maxMana, GameState.playerMana + manaGenAmt)
        end
        lastTarget = target
    end

    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_NORMAL)
    table.insert(bs.skillEffects, {
        type = "fire_bolt", x = p.x, y = p.y,
        targetX = lastTarget and lastTarget.x or p.x,
        targetY = lastTarget and lastTarget.y or p.y,
        radius = 20, life = 0.3, maxLife = 0.3,
    })
end

-- ============================================================================
-- 火球 (fireball) — AoE 爆炸
-- ============================================================================
-- ============================================================================
-- 火球 (fireball) — 经典AOE爆破, 燃烧联动
-- 基础: 对燃烧敌人+25%, 命中施加燃烧
-- 强化: 留下燃烧地面3秒 | 闪烁: 燃烧加伤→50%+击杀回蓝 | 闪耀: 暴击二次爆炸+范围+30%
-- ============================================================================
function SkillCaster._Cast_fireball(bs, skillCfg, lv, p)
    local element = "fire"
    local dmgScale = skillCfg.effect(lv) / 100

    local hasEnhanced  = H.HasEnhance("fireball_enhanced")
    local hasFlicker   = H.HasEnhance("fireball_flickering")
    local hasGlinting  = H.HasEnhance("fireball_glinting")

    -- 爆炸半径 (闪耀+30%)
    local radius = 80
    if hasGlinting then radius = radius * 1.3 end

    -- 燃烧敌人额外伤害: 基础25%, 闪烁升至50%
    local burnBonusPct = hasFlicker and 0.50 or (skillCfg.burnBonusPct or 0.25)

    -- 寻找最佳AOE落点
    local bestX, bestY = H.FindBestAoeCenter(bs.enemies, radius, p.x, p.y)
    local hitCount = 0
    local killedBurning = 0

    for _, e in ipairs(bs.enemies) do
        if not e.dead then
            local dx, dy = e.x - bestX, e.y - bestY
            if math.sqrt(dx * dx + dy * dy) <= radius then
                hitCount = hitCount + 1
                local xSources = {}
                -- 燃烧联动: 对燃烧中敌人增伤
                local wasBurning = e.burnTimer and e.burnTimer > 0
                if wasBurning then
                    xSources[#xSources + 1] = burnBonusPct
                end
                local hpBefore = e.hp
                H.HitEnemySkill(bs, e, dmgScale, element, {}, bestX, bestY, CombatUtils.KNOCKBACK_SKILL * 1.2, xSources)
                -- 施加燃烧
                if not e.dead then
                    local burnPct = skillCfg.burnApplyPct or 0.20
                    local burnDur = skillCfg.burnApplyDur or 3.0
                    H.ApplyBurn(e, burnPct, burnDur)
                end
                -- 闪烁: 击杀燃烧敌人回蓝
                if e.dead and wasBurning then
                    killedBurning = killedBurning + 1
                end
            end
        end
    end

    -- 闪烁: 击杀燃烧敌人回复法力
    if hasFlicker and killedBurning > 0 then
        GameState.AddMana(3 * killedBurning)
    end

    -- 闪耀: 暴击二次爆炸 (简化: 若本次命中≥1, 40%概率触发)
    if hasGlinting and hitCount > 0 then
        local critChance = GameState.GetCritChance and GameState.GetCritChance() or 0.15
        if math.random() < critChance then
            local secondaryScale = dmgScale * 0.40
            for _, e in ipairs(bs.enemies) do
                if not e.dead then
                    local dx, dy = e.x - bestX, e.y - bestY
                    if math.sqrt(dx * dx + dy * dy) <= radius then
                        H.HitEnemySkill(bs, e, secondaryScale, element, {}, bestX, bestY, 0)
                    end
                end
            end
            -- 二次爆炸特效
            table.insert(bs.skillEffects, {
                type = "fireball_secondary", x = bestX, y = bestY,
                radius = radius * 0.8, life = 0.3, maxLife = 0.3,
            })
        end
    end

    -- 强化: 燃烧地面
    if hasEnhanced then
        if not bs.fireZones then bs.fireZones = {} end
        table.insert(bs.fireZones, {
            x = bestX, y = bestY,
            radius = radius,
            duration = 3.0, maxDuration = 3.0,
            dmgPct = 0.15, tickRate = 0.5, tickCD = 0,
            element = "fire", source = "fireball_enhanced",
        })
    end

    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_BLAST)
    CombatUtils.PlaySfx("fireballCast", 0.7)
    -- 飞行弹道特效: 从玩家飞向爆炸中心
    table.insert(bs.skillEffects, {
        type = "fireball_cast",
        x = p.x, y = p.y,
        targetX = bestX, targetY = bestY,
        life = 0.25, maxLife = 0.25,
    })
    -- 爆炸特效 (落点)
    table.insert(bs.skillEffects, {
        type = "fireball", x = bestX, y = bestY,
        radius = radius, life = 0.5, maxLife = 0.5,
    })
end

-- ============================================================================
-- 焚烧 (incinerate) — 引导技能: 递增灼烧, 站桩高DPS
-- 4段引导(0.5s间隔), 倍率递增 1.0→1.25→1.5→2.0
-- 强化: 移速+20%不被打断 | 闪烁: 末段对燃烧+60%+回蓝 | 闪耀: 每段获屏障+结束AOE
-- ============================================================================

-- _Cast_incinerate: 启动引导 (由 CombatCore 调用, 通过 ChannelSystem 管理)
function SkillCaster._Cast_incinerate(bs, skillCfg, lv, p)
    local ChannelSystem = require("battle.ChannelSystem")
    -- 如果已在引导中, 不重复启动
    if ChannelSystem.IsChanneling() then return end

    local ok = ChannelSystem.Start(bs, skillCfg, lv)
    if not ok then
        -- ChannelSystem 启动失败 (无目标等), 跳过
        return
    end
end

-- 注册引导处理器 (模块加载时)
local ChannelSystem = require("battle.ChannelSystem")
ChannelSystem.Register("incinerate", {
    --- 引导开始: 初始化数据, 寻找目标
    ---@return table|nil data 技能数据 (nil=初始化失败)
    ---@return table|nil opts 选项覆盖
    onStart = function(bs, skillCfg, lv, p)
        local target = H.FindNearestEnemy(bs.enemies, p.x, p.y, 9999)
        if not target then return nil end

        local hasEnhanced = H.HasEnhance("incinerate_enhanced")

        -- 引导期间移速: 强化+20%(基于默认30%=0.3 → 0.5), 否则30%
        local moveMul = hasEnhanced and 0.5 or 0.3

        CombatUtils.PlaySfx("incinerate", 0.5)

        -- 添加引导开始视觉效果 (持续整个引导过程)
        local totalDuration = (skillCfg.channelTicks or 4) * (skillCfg.channelInterval or 0.5)
        table.insert(bs.skillEffects, {
            type = "incinerate_channel",
            life = totalDuration,
            maxLife = totalDuration,
            areaW = bs.areaW, areaH = bs.areaH,
        })

        return {
            -- 技能参数 (缓存, 避免每段重复计算)
            element = "fire",
            baseDmgScale = skillCfg.effect(lv) / 100,
            ramp = skillCfg.channelRamp or { 1.0, 1.25, 1.5, 2.0 },
            hasEnhanced = hasEnhanced,
            hasFlicker = H.HasEnhance("incinerate_flickering"),
            hasGlinting = H.HasEnhance("incinerate_glinting"),
            burnStackPct = skillCfg.burnStackPct or 0.10,
            burnStackDur = skillCfg.burnStackDur or 3.0,
            burnMaxStacks = skillCfg.burnMaxStacks or 4,
            totalTicks = skillCfg.channelTicks or 4,
        }, {
            target = target,
            canInterrupt = not hasEnhanced, -- 强化: 不可打断
            moveSpeedMul = moveMul,
        }
    end,

    --- 每段触发: 造成递增伤害 + 施加燃烧 + 增强效果
    ---@param cs ChannelState
    ---@param tick number 当前段数 (1-based)
    onTick = function(cs, tick)
        local d = cs.data
        local bs = cs.bs
        local p = bs.playerBattle
        local target = cs.target
        if not target or target.dead then return end

        local rampMul = d.ramp[tick] or d.ramp[#d.ramp]
        local tickDmg = d.baseDmgScale * rampMul
        local xSources = {}

        -- 闪烁: 第4段(最终段)对燃烧敌人+60%
        if d.hasFlicker and tick == d.totalTicks
            and target.burnTimer and target.burnTimer > 0 then
            xSources[#xSources + 1] = 0.60
        end

        H.HitEnemySkill(bs, target, tickDmg, d.element, {}, p.x, p.y, 0, xSources)

        -- 每段施加燃烧叠层
        if not target.dead then
            H.ApplyBurn(target, d.burnStackPct, d.burnStackDur, d.burnMaxStacks)
        end

        -- 闪烁: 每段回蓝
        if d.hasFlicker then
            GameState.AddMana(2)
        end

        -- 闪耀: 每段获得5%最大生命值屏障
        if d.hasGlinting and not target.dead then
            local maxHP = GameState.GetMaxHP()
            local shieldVal = math.floor(maxHP * 0.05)
            ShieldManager.Add("incinerate_shield", shieldVal)
        end

        -- 每段小震屏
        CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_NORMAL)

        -- 每段打击特效 (需要玩家+目标坐标供射线闪光)
        table.insert(bs.skillEffects, {
            type = "incinerate_tick",
            x = p.x, y = p.y,
            targetX = target.x, targetY = target.y,
            tick = tick, totalTicks = d.totalTicks,
            life = 0.3, maxLife = 0.3,
        })
    end,

    --- 引导结束
    ---@param cs ChannelState
    ---@param completed boolean 是否完成全部段数 (false=被打断)
    onEnd = function(cs, completed)
        local d = cs.data
        local bs = cs.bs
        local p = bs.playerBattle

        -- 闪耀: 只有完成引导才释放火焰爆炸
        if d.hasGlinting and completed then
            local explosionDmg = 0.80  -- 80%武器伤害
            for _, e in ipairs(bs.enemies) do
                if not e.dead then
                    H.HitEnemySkill(bs, e, explosionDmg, d.element, {},
                        p.x, p.y, CombatUtils.KNOCKBACK_SKILL)
                end
            end
            CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_BLAST)
            table.insert(bs.skillEffects, {
                type = "incinerate_explosion",
                life = 0.4, maxLife = 0.4,
                areaW = bs.areaW, areaH = bs.areaH,
            })
        elseif not completed then
            -- 被打断: 小震屏提示
            CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_NORMAL)
        end
    end,
})

-- ============================================================================
-- 火焰护盾 (flame_shield) — 屏障
-- ============================================================================
function SkillCaster._Cast_flame_shield(bs, skillCfg, lv, p)
    local shieldPct = skillCfg.effect(lv) / 100
    local duration = 6.0
    if H.HasEnhance("flame_shield_enhanced") then duration = duration + 2.0 end

    local maxHP = GameState.GetMaxHP()
    local shieldValue = math.floor(maxHP * shieldPct)

    ShieldManager.Add("flame_shield", shieldValue)
    GameState.flameShieldTimer = duration

    -- 神秘火焰护盾: 结束时释放火焰爆炸 (标记, BuffRuntime 消散时触发)
    GameState._flameShieldMystical = H.HasEnhance("flame_shield_mystical")
    -- 闪光火焰护盾: 激活时移动速度+25%
    if H.HasEnhance("flame_shield_shimmering") then
        GameState._flameShieldSpeedTimer = duration
    end

    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_SKILL)
    table.insert(bs.skillEffects, {
        type = "flame_shield", x = p.x, y = p.y,
        life = 0.5, maxLife = 0.5,
        radius = 60,
    })
end

-- ============================================================================
-- 九头蛇 (hydra) — 召唤物
-- ============================================================================
function SkillCaster._Cast_hydra(bs, skillCfg, lv, p)
    local duration = skillCfg.effect(lv)
    local dmgScale = skillCfg.summonDamage(lv) / 100
    local headCount = 3
    if H.HasEnhance("hydra_enhanced") then duration = duration + 2.0 end
    if H.HasEnhance("hydra_greater") then headCount = headCount + 1 end

    for i = 1, headCount do
        table.insert(GameState.spirits, {
            x = p.x + (i - 1) * 30 - (headCount - 1) * 15,
            y = p.y - 30,
            timer = duration,
            atkCD = 0,
            atkInterval = 1.0,
            dmgScale = dmgScale,
            atkRange = 200,
            element = "fire",
            orbitAngle = math.random() * math.pi * 2,
            source = "hydra",
            applyVulnerable = H.HasEnhance("hydra_destructive") and 2.0 or nil,
        })
    end

    CombatUtils.PlaySfx("hydra", 0.6)
    table.insert(bs.skillEffects, {
        type = "hydra_summon", x = p.x, y = p.y,
        life = 0.5, maxLife = 0.5,
    })
end

-- ============================================================================
-- 火墙 (firewall) — 火焰区域
-- ============================================================================
function SkillCaster._Cast_firewall(bs, skillCfg, lv, p)
    local dmgScale = skillCfg.effect(lv) / 100
    local duration = 6.0
    if H.HasEnhance("firewall_enhanced") then duration = duration + 2.0 end
    local radius = 70

    local bestX, bestY = H.FindBestAoeCenter(bs.enemies, radius, p.x, p.y)

    if H.HasEnhance("firewall_greater") then
        for _, e in ipairs(bs.enemies) do
            if not e.dead then
                local dx, dy = e.x - bestX, e.y - bestY
                if math.sqrt(dx * dx + dy * dy) <= radius then
                    CombatUtils.ApplyKnockback(e, bestX, bestY, CombatUtils.KNOCKBACK_SKILL * 1.5)
                end
            end
        end
    end

    table.insert(bs.fireZones, {
        x = bestX, y = bestY,
        radius = radius,
        duration = duration, maxDuration = duration,
        dmgPct = dmgScale, tickRate = 0.5, tickCD = 0,
        element = "fire", source = "firewall",
        bonusDmg = H.HasEnhance("firewall_destructive") and 0.15 or 0,
    })

    CombatUtils.PlaySfx("firewall", 0.6)
    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_SKILL)
    table.insert(bs.skillEffects, {
        type = "firewall", x = bestX, y = bestY,
        radius = radius, life = 0.5, maxLife = 0.5,
    })
end

-- ============================================================================
-- 烈焰风暴 (fire_storm) — 全屏火焰
-- ============================================================================
function SkillCaster._Cast_fire_storm(bs, skillCfg, lv, p)
    local element = "fire"
    local dmgScale = skillCfg.effect(lv) / 100
    local hasDestructive = H.HasEnhance("fire_storm_destructive")

    for _, e in ipairs(bs.enemies) do
        if not e.dead then
            local bonuses = {}
            if hasDestructive and e.burnTimer and e.burnTimer > 0 then
                bonuses.destructive = 0.25
            end
            H.HitEnemySkill(bs, e, dmgScale, element, bonuses, bs.areaW * 0.5, e.y, CombatUtils.KNOCKBACK_SKILL * 1.5)
        end
    end

    if H.HasEnhance("fire_storm_greater") then
        local zoneRadius = math.floor(math.min(bs.areaW, bs.areaH) * 0.4)
        -- 强化烈焰风暴: 范围+30%
        if H.HasEnhance("fire_storm_enhanced") then
            zoneRadius = math.floor(zoneRadius * 1.30)
        end
        table.insert(bs.fireZones, {
            x = bs.areaW * 0.5, y = bs.areaH * 0.5,
            radius = zoneRadius,
            duration = 3.0, maxDuration = 3.0,
            dmgPct = 0.25, tickRate = 0.5, tickCD = 0,
            element = "fire", source = "fire_storm_greater",
        })
    end

    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_STORM * 1.5)
    table.insert(bs.skillEffects, {
        type = "fire_storm",
        life = 1.0, maxLife = 1.0,
        areaW = bs.areaW, areaH = bs.areaH,
    })
end

-- ============================================================================
-- 陨石 (meteor) — 巨型火焰爆炸
-- ============================================================================
function SkillCaster._Cast_meteor(bs, skillCfg, lv, p)
    local element = "fire"
    local dmgScale = skillCfg.effect(lv) / 100
    local hasPrime = H.HasEnhance("meteor_prime")
    if hasPrime then dmgScale = dmgScale * 1.5 end

    for _, e in ipairs(bs.enemies) do
        if not e.dead then
            H.HitEnemySkill(bs, e, dmgScale, element, {}, bs.areaW * 0.5, bs.areaH * 0.5, CombatUtils.KNOCKBACK_SKILL * 2)
            if hasPrime and not e.dead then
                H.ApplyBurn(e, 0.08, 8.0)
            end
        end
    end

    -- 至尊陨石: 8秒内火焰伤害+20%[x]
    if H.HasEnhance("meteor_supreme") then
        GameState._meteorSupremeTimer = 8.0
    end

    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_STORM * 2)
    CombatUtils.PlaySfx("stormWarn", 0.8)
    table.insert(bs.skillEffects, {
        type = "meteor",
        life = 1.5, maxLife = 1.5,
        areaW = bs.areaW, areaH = bs.areaH,
    })
end

end -- Register

return { Register = Register }
