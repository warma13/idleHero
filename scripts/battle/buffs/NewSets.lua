-- ============================================================================
-- battle/buffs/NewSets.lua - 6套新套装 Buff 逻辑
-- 包含: swift_hunter, fission_force, shadow_hunter, iron_bastion,
--       dragon_fury, rune_weaver
-- ============================================================================

local Config      = require("Config")
local GameState   = require("GameState")

local M = {}

-- ============================================================================
-- 迅捷猎手 (swift_hunter)
-- 2件: 攻速+12%(被动statsMul处理), 普攻命中回复0.5%HP
-- 4件: 连续命中同一目标每次+3%(max 10层), 换目标清零
-- 6件: 叠满10层触发连击风暴: 3秒攻速翻倍+分裂弹+3 (CD20)
-- ============================================================================

--- 迅捷猎手2件: 普攻命中回血0.5%HP
function M.TrySwiftHunterOnHit(bs, target)
    local setCounts = GameState.GetEquippedSetCounts()
    if not setCounts["swift_hunter"] or setCounts["swift_hunter"] < 2 then return end
    local sh2 = Config.EQUIP_SET_MAP["swift_hunter"].bonuses[2].buff
    local healAmt = math.floor(GameState.GetMaxHP() * (sh2.healPct or 0.005))
    if healAmt > 0 then
        GameState.HealPlayer(healAmt)
    end
end

--- 迅捷猎手4件: 连续命中同目标叠层 (由 CombatCore.HitEnemy 调用)
--- @param bs table BattleSystem
--- @param target table 敌人
function M.OnSwiftHunterHit(bs, target)
    local setCounts = GameState.GetEquippedSetCounts()
    if not setCounts["swift_hunter"] or setCounts["swift_hunter"] < 4 then return end

    local sh4 = Config.EQUIP_SET_MAP["swift_hunter"].bonuses[4].buff
    local maxStacks = sh4.maxStacks or 10

    -- 判断是否同一目标
    if GameState._swiftHunterTarget ~= target then
        GameState._swiftHunterTarget = target
        GameState._swiftHunterStacks = 0
    end

    GameState._swiftHunterStacks = math.min(maxStacks, (GameState._swiftHunterStacks or 0) + 1)

    -- 满层触发6件
    if setCounts["swift_hunter"] >= 6 and GameState._swiftHunterStacks >= maxStacks then
        M.TrySwiftHunterStorm(bs)
    end
end

--- 迅捷猎手4件: 获取同目标叠层增伤
--- @param target table 敌人
--- @return number 增伤比例
function M.GetSwiftHunterBonus(target)
    local setCounts = GameState.GetEquippedSetCounts()
    if not setCounts["swift_hunter"] or setCounts["swift_hunter"] < 4 then return 0 end
    if GameState._swiftHunterTarget ~= target then return 0 end
    local sh4 = Config.EQUIP_SET_MAP["swift_hunter"].bonuses[4].buff
    local stacks = GameState._swiftHunterStacks or 0
    return stacks * (sh4.stackDmgPct or 0.03)
end

--- 迅捷猎手6件: 连击风暴 (3秒攻速翻倍 + 分裂+3)
function M.TrySwiftHunterStorm(bs)
    local setCounts = GameState.GetEquippedSetCounts()
    if not setCounts["swift_hunter"] or setCounts["swift_hunter"] < 6 then return end

    local sh6 = Config.EQUIP_SET_MAP["swift_hunter"].bonuses[6].buff
    local cd = GameState.setBuffCD["swift_hunter_6"] or 0
    if cd > 0 then return end

    GameState._swiftHunterStormTimer = sh6.duration or 3.0
    GameState._swiftHunterAtkSpdMul = sh6.atkSpeedMul or 2.0
    GameState._swiftHunterExtraSplit = sh6.extraSplit or 3
    GameState._swiftHunterStacks = 0  -- 清空层数
    GameState.setBuffCD["swift_hunter_6"] = sh6.cd or 20.0

    local Particles = require("battle.Particles")
    local CombatUtils = require("battle.CombatUtils")
    Particles.SpawnReactionText(bs.particles, bs.playerBattle.x, bs.playerBattle.y - 40, "连击风暴!", { 255, 200, 50 })
    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_CRIT)
end

--- 迅捷猎手: 获取攻速加成
function M.GetSwiftHunterAtkSpeedBonus()
    if GameState._swiftHunterStormTimer and GameState._swiftHunterStormTimer > 0 then
        return GameState._swiftHunterAtkSpdMul or 0
    end
    return 0
end

--- 迅捷猎手: 获取额外分裂弹数
function M.GetSwiftHunterExtraSplit()
    if GameState._swiftHunterStormTimer and GameState._swiftHunterStormTimer > 0 then
        return GameState._swiftHunterExtraSplit or 0
    end
    return 0
end

--- 迅捷猎手: 每帧更新
function M.UpdateSwiftHunter(dt)
    -- 风暴计时器
    if GameState._swiftHunterStormTimer and GameState._swiftHunterStormTimer > 0 then
        GameState._swiftHunterStormTimer = GameState._swiftHunterStormTimer - dt
        if GameState._swiftHunterStormTimer <= 0 then
            GameState._swiftHunterStormTimer = 0
            GameState._swiftHunterAtkSpdMul = 0
            GameState._swiftHunterExtraSplit = 0
        end
    end
    -- 6件CD
    local cd6 = GameState.setBuffCD["swift_hunter_6"] or 0
    if cd6 > 0 then GameState.setBuffCD["swift_hunter_6"] = math.max(0, cd6 - dt) end
end

-- ============================================================================
-- 裂变之力 (fission_force)
-- 2件: 普攻伤害+10%(被动stats), 每命中获1点裂变能量(上限50)
-- 4件: 能量满50释放裂变脉冲: 150%ATK AOE + 2秒减速30%
-- 6件: 脉冲改为250%ATK + 命中回血1%HP/敌 + 脉冲后5秒攻速+20%
-- ============================================================================

--- 裂变之力2件: 普攻命中获取能量
function M.OnFissionForceHit(bs, target)
    local setCounts = GameState.GetEquippedSetCounts()
    if not setCounts["fission_force"] or setCounts["fission_force"] < 2 then return end

    local ff2 = Config.EQUIP_SET_MAP["fission_force"].bonuses[2].buff
    local maxEnergy = ff2.maxEnergy or 50
    GameState._fissionEnergy = math.min(maxEnergy, (GameState._fissionEnergy or 0) + (ff2.energyPerHit or 1))

    -- 满能量触发脉冲
    if GameState._fissionEnergy >= maxEnergy then
        M.CastFissionPulse(bs)
    end
end

--- 裂变之力4/6件: 裂变脉冲
function M.CastFissionPulse(bs)
    local setCounts = GameState.GetEquippedSetCounts()
    local has6 = setCounts["fission_force"] and setCounts["fission_force"] >= 6

    -- 6件有独立CD
    if has6 then
        local cd = GameState.setBuffCD["fission_force_6"] or 0
        if cd > 0 then return end
    end

    -- 清空能量
    GameState._fissionEnergy = 0

    local Particles = require("battle.Particles")
    local CombatUtils = require("battle.CombatUtils")

    -- 选择4件或6件参数
    local pulseCfg
    if has6 then
        pulseCfg = Config.EQUIP_SET_MAP["fission_force"].bonuses[6].buff
    else
        pulseCfg = Config.EQUIP_SET_MAP["fission_force"].bonuses[4].buff
    end

    local totalAtk = GameState.GetTotalAtk()
    local pulseDmg = math.floor(totalAtk * (pulseCfg.pulseDmgMul or 1.5))
    local pulseRadius = pulseCfg.pulseRadius or 60
    local hitCount = 0

    for _, e in ipairs(bs.enemies) do
        if not e.dead then
            local dx, dy = e.x - bs.playerBattle.x, e.y - bs.playerBattle.y
            if math.sqrt(dx * dx + dy * dy) <= pulseRadius then
                local dmg = pulseDmg
                e.hp = e.hp - dmg
                CombatUtils.RecordBossDmg(dmg)
                Particles.SpawnDmgText(bs.particles, e.x, e.y - (e.radius or 16) - 10, dmg, false, false, { 80, 200, 255 })

                -- 减速
                e._frozenSlowTimer = pulseCfg.slowDur or 2.0
                e._frozenSlowRate = pulseCfg.slowRate or 0.30

                hitCount = hitCount + 1

                if e.hp <= 0 then
                    e.dead = true
                    bs.OnEnemyKilled(e)
                end
            end
        end
    end

    -- 6件: 命中回血 + 脉冲后攻速
    if has6 then
        local healPct = pulseCfg.healPerEnemyPct or 0.01
        if hitCount > 0 then
            local healAmt = math.floor(GameState.GetMaxHP() * healPct * hitCount)
            if healAmt > 0 then
                GameState.HealPlayer(healAmt)
            end
        end
        GameState._fissionAtkSpdTimer = pulseCfg.postPulseDur or 5.0
        GameState._fissionAtkSpdBonus = pulseCfg.postPulseAtkSpeed or 0.20
        GameState.setBuffCD["fission_force_6"] = pulseCfg.cd or 10.0
    end

    Particles.SpawnReactionText(bs.particles, bs.playerBattle.x, bs.playerBattle.y - 40, "裂变脉冲!", { 80, 200, 255 })
    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_STORM)

    table.insert(bs.bossSkillEffects, {
        type = "deathExplode", element = "arcane",
        x = bs.playerBattle.x, y = bs.playerBattle.y,
        radius = pulseRadius, life = 0.6, maxLife = 0.6,
    })
end

--- 裂变之力: 获取攻速加成 (6件脉冲后)
function M.GetFissionForceAtkSpeedBonus()
    if GameState._fissionAtkSpdTimer and GameState._fissionAtkSpdTimer > 0 then
        return GameState._fissionAtkSpdBonus or 0
    end
    return 0
end

--- 裂变之力: 每帧更新
function M.UpdateFissionForce(dt)
    if GameState._fissionAtkSpdTimer and GameState._fissionAtkSpdTimer > 0 then
        GameState._fissionAtkSpdTimer = GameState._fissionAtkSpdTimer - dt
        if GameState._fissionAtkSpdTimer <= 0 then
            GameState._fissionAtkSpdTimer = 0
            GameState._fissionAtkSpdBonus = 0
        end
    end
    local cd6 = GameState.setBuffCD["fission_force_6"] or 0
    if cd6 > 0 then GameState.setBuffCD["fission_force_6"] = math.max(0, cd6 - dt) end
end

-- ============================================================================
-- 暗影猎手 (shadow_hunter)
-- 2件: 暴击伤害+25%(被动statsMul), 暴击命中获1层暗影(上限30)
-- 4件: 暗影满30层自动释放暗影爆发: 200%ATK AOE + 吸血30%
-- 6件: 爆发后10秒暴击率+20% + 暴击回0.3%HP (CD15)
-- ============================================================================

--- 暗影猎手2件: 暴击命中叠暗影
function M.OnShadowHunterCrit(bs, target)
    local setCounts = GameState.GetEquippedSetCounts()
    if not setCounts["shadow_hunter"] or setCounts["shadow_hunter"] < 2 then return end

    local sh2 = Config.EQUIP_SET_MAP["shadow_hunter"].bonuses[2].buff
    local maxShadow = sh2.maxShadow or 30
    GameState._shadowStacks = math.min(maxShadow, (GameState._shadowStacks or 0) + (sh2.shadowPerCrit or 1))

    -- 满层触发4件
    if setCounts["shadow_hunter"] >= 4 and GameState._shadowStacks >= maxShadow then
        M.CastShadowBurst(bs)
    end
end

--- 暗影猎手4件: 暗影爆发
function M.CastShadowBurst(bs)
    local setCounts = GameState.GetEquippedSetCounts()
    local sh4 = Config.EQUIP_SET_MAP["shadow_hunter"].bonuses[4].buff
    GameState._shadowStacks = 0  -- 清空暗影

    local Particles = require("battle.Particles")
    local CombatUtils = require("battle.CombatUtils")

    local totalAtk = GameState.GetTotalAtk()
    local burstDmg = math.floor(totalAtk * (sh4.burstDmgMul or 2.0))
    local burstRadius = sh4.burstRadius or 70
    local totalDmgDealt = 0

    for _, e in ipairs(bs.enemies) do
        if not e.dead then
            local dx, dy = e.x - bs.playerBattle.x, e.y - bs.playerBattle.y
            if math.sqrt(dx * dx + dy * dy) <= burstRadius then
                e.hp = e.hp - burstDmg
                CombatUtils.RecordBossDmg(burstDmg)
                totalDmgDealt = totalDmgDealt + burstDmg
                Particles.SpawnDmgText(bs.particles, e.x, e.y - (e.radius or 16) - 10, burstDmg, false, false, { 80, 50, 120 })
                if e.hp <= 0 then
                    e.dead = true
                    bs.OnEnemyKilled(e)
                end
            end
        end
    end

    -- 吸血30%
    local lifestealPct = sh4.lifestealPct or 0.30
    local healAmt = math.floor(totalDmgDealt * lifestealPct)
    if healAmt > 0 then
        GameState.HealPlayer(healAmt)
    end

    -- 6件: 爆发后暴击BUFF
    if setCounts["shadow_hunter"] >= 6 then
        local sh6 = Config.EQUIP_SET_MAP["shadow_hunter"].bonuses[6].buff
        local cd = GameState.setBuffCD["shadow_hunter_6"] or 0
        if cd <= 0 then
            GameState._shadowPostBurstTimer = sh6.duration or 10.0
            GameState._shadowPostBurstCritBonus = sh6.critBonus or 0.20
            GameState._shadowPostBurstCritHealPct = sh6.critHealPct or 0.003
            GameState.setBuffCD["shadow_hunter_6"] = sh6.cd or 15.0
        end
    end

    Particles.SpawnReactionText(bs.particles, bs.playerBattle.x, bs.playerBattle.y - 40, "暗影爆发!", { 80, 50, 120 })
    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_STORM)

    table.insert(bs.bossSkillEffects, {
        type = "deathExplode", element = "arcane",
        x = bs.playerBattle.x, y = bs.playerBattle.y,
        radius = burstRadius, life = 0.8, maxLife = 0.8,
    })
end

--- 暗影猎手6件: 获取暴击率加成
function M.GetShadowHunterCritBonus()
    if GameState._shadowPostBurstTimer and GameState._shadowPostBurstTimer > 0 then
        return GameState._shadowPostBurstCritBonus or 0
    end
    return 0
end

--- 暗影猎手6件: 暴击回血 (由 HitEnemy 暴击时调用)
function M.OnShadowHunterCritHeal()
    if not GameState._shadowPostBurstTimer or GameState._shadowPostBurstTimer <= 0 then return end
    local healPct = GameState._shadowPostBurstCritHealPct or 0.003
    local healAmt = math.floor(GameState.GetMaxHP() * healPct)
    if healAmt > 0 then
        GameState.HealPlayer(healAmt)
    end
end

--- 暗影猎手: 每帧更新
function M.UpdateShadowHunter(dt)
    if GameState._shadowPostBurstTimer and GameState._shadowPostBurstTimer > 0 then
        GameState._shadowPostBurstTimer = GameState._shadowPostBurstTimer - dt
        if GameState._shadowPostBurstTimer <= 0 then
            GameState._shadowPostBurstTimer = 0
            GameState._shadowPostBurstCritBonus = 0
            GameState._shadowPostBurstCritHealPct = 0
        end
    end
    local cd6 = GameState.setBuffCD["shadow_hunter_6"] or 0
    if cd6 > 0 then GameState.setBuffCD["shadow_hunter_6"] = math.max(0, cd6 - dt) end
end

-- ============================================================================
-- 铁壁要塞 (iron_bastion)
-- 2件: DEF+10%(被动statsMul), 受击时获得等于伤害5%的护盾(max 30%HP)
-- 4件: 护盾超20%HP时, 溢出部分每1%转化为+2%ATK(max +20%)
-- 6件: 护盾被击碎时爆炸: 消耗护盾200%伤害 + 3秒50%减伤 (CD10)
-- ============================================================================

--- 铁壁要塞2件: 受击获得护盾 (由 OnPlayerTakeDamage 调用)
function M.TryIronBastionShield(bs, dmgTaken)
    local setCounts = GameState.GetEquippedSetCounts()
    if not setCounts["iron_bastion"] or setCounts["iron_bastion"] < 2 then return end

    local ib2 = Config.EQUIP_SET_MAP["iron_bastion"].bonuses[2].buff
    local shieldGain = math.floor(dmgTaken * (ib2.shieldPct or 0.05))
    local maxShield = math.floor(GameState.GetMaxHP() * (ib2.maxShieldPct or 0.30))
    local ShieldManager = require("state.ShieldManager")
    local currentShield = ShieldManager.GetTotal()

    if currentShield < maxShield and shieldGain > 0 then
        local actual = math.min(shieldGain, maxShield - currentShield)
        GameState.AddShield(actual)
    end
end

--- 铁壁要塞4件: 获取护盾溢出ATK加成
function M.GetIronBastionAtkBonus()
    local setCounts = GameState.GetEquippedSetCounts()
    if not setCounts["iron_bastion"] or setCounts["iron_bastion"] < 4 then return 0 end

    local ib4 = Config.EQUIP_SET_MAP["iron_bastion"].bonuses[4].buff
    local ShieldManager = require("state.ShieldManager")
    local currentShield = ShieldManager.GetTotal()
    local maxHP = GameState.GetMaxHP()
    local threshold = maxHP * (ib4.shieldThreshold or 0.20)

    if currentShield <= threshold then return 0 end

    local overflowPct = (currentShield - threshold) / maxHP  -- 溢出百分比
    local atkBonusPerPct = (ib4.overflowToAtk or 0.02) * 100  -- 每1%溢出→ATK加成
    local bonus = overflowPct * atkBonusPerPct
    return math.min(bonus, ib4.maxAtkBonus or 0.20)
end

--- 铁壁要塞6件: 护盾破碎爆炸 (由护盾系统在盾消耗完时调用)
function M.OnIronBastionShieldBreak(bs, consumedShield)
    local setCounts = GameState.GetEquippedSetCounts()
    if not setCounts["iron_bastion"] or setCounts["iron_bastion"] < 6 then return end

    local ib6 = Config.EQUIP_SET_MAP["iron_bastion"].bonuses[6].buff
    local cd = GameState.setBuffCD["iron_bastion_6"] or 0
    if cd > 0 then return end

    GameState.setBuffCD["iron_bastion_6"] = ib6.cd or 10.0

    local Particles = require("battle.Particles")
    local CombatUtils = require("battle.CombatUtils")

    local burstDmg = math.floor(consumedShield * (ib6.shieldBurstMul or 2.0))
    local burstRadius = ib6.burstRadius or 60

    for _, e in ipairs(bs.enemies) do
        if not e.dead then
            local dx, dy = e.x - bs.playerBattle.x, e.y - bs.playerBattle.y
            if math.sqrt(dx * dx + dy * dy) <= burstRadius then
                e.hp = e.hp - burstDmg
                CombatUtils.RecordBossDmg(burstDmg)
                Particles.SpawnDmgText(bs.particles, e.x, e.y - (e.radius or 16) - 10, burstDmg, false, false, { 140, 160, 180 })
                if e.hp <= 0 then
                    e.dead = true
                    bs.OnEnemyKilled(e)
                end
            end
        end
    end

    -- 减伤BUFF
    GameState._ironBastionDmgReduceTimer = ib6.dmgReduceDur or 3.0
    GameState._ironBastionDmgReducePct = ib6.dmgReducePct or 0.50

    Particles.SpawnReactionText(bs.particles, bs.playerBattle.x, bs.playerBattle.y - 40, "铁壁爆碎!", { 140, 160, 180 })
    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_STORM)

    table.insert(bs.bossSkillEffects, {
        type = "deathExplode", element = "fire",
        x = bs.playerBattle.x, y = bs.playerBattle.y,
        radius = burstRadius, life = 0.8, maxLife = 0.8,
    })
end

--- 铁壁要塞6件: 获取减伤率
function M.GetIronBastionDmgReduce()
    if GameState._ironBastionDmgReduceTimer and GameState._ironBastionDmgReduceTimer > 0 then
        return GameState._ironBastionDmgReducePct or 0
    end
    return 0
end

--- 铁壁要塞: 每帧更新
function M.UpdateIronBastion(dt)
    if GameState._ironBastionDmgReduceTimer and GameState._ironBastionDmgReduceTimer > 0 then
        GameState._ironBastionDmgReduceTimer = GameState._ironBastionDmgReduceTimer - dt
        if GameState._ironBastionDmgReduceTimer <= 0 then
            GameState._ironBastionDmgReduceTimer = 0
            GameState._ironBastionDmgReducePct = 0
        end
    end
    local cd6 = GameState.setBuffCD["iron_bastion_6"] or 0
    if cd6 > 0 then GameState.setBuffCD["iron_bastion_6"] = math.max(0, cd6 - dt) end
end

-- ============================================================================
-- 龙息之怒 (dragon_fury)
-- 2件: 普攻和技能伤害+15%(被动stats)
-- 4件: 普攻命中3次→下次技能+50%; 技能命中→3次普攻+30%(交替循环)
-- 6件: 交替3轮→龙息: 400%ATK全屏火伤+8秒龙威全伤害+20% (CD18)
-- ============================================================================

--- 龙息之怒4件: 普攻命中计数
function M.OnDragonFuryNormalHit(bs, target)
    local setCounts = GameState.GetEquippedSetCounts()
    if not setCounts["dragon_fury"] or setCounts["dragon_fury"] < 4 then return end

    local df4 = Config.EQUIP_SET_MAP["dragon_fury"].bonuses[4].buff

    -- 当前处于"等待普攻命中"阶段
    if GameState._dragonPhase ~= "skill" then
        -- 默认是普攻阶段
        if GameState._dragonPhase ~= "atk" then
            GameState._dragonPhase = "atk"
            GameState._dragonHitCount = 0
        end
        GameState._dragonHitCount = (GameState._dragonHitCount or 0) + 1
        local hitsNeeded = df4.atkHitsForSkill or 3
        if GameState._dragonHitCount >= hitsNeeded then
            -- 切换到技能增强阶段
            GameState._dragonPhase = "skill"
            GameState._dragonHitCount = 0
            GameState._dragonSkillBonus = df4.skillBonusToSkill or 0.50
        end
    else
        -- 已在技能阶段, 普攻命中消耗攻击增幅
        if GameState._dragonAtkBonusHits and GameState._dragonAtkBonusHits > 0 then
            GameState._dragonAtkBonusHits = GameState._dragonAtkBonusHits - 1
            if GameState._dragonAtkBonusHits <= 0 then
                GameState._dragonAtkBonus = 0
            end
        end
    end
end

--- 龙息之怒4件: 技能命中回调 (由 SkillCaster 技能命中调用)
function M.OnDragonFurySkillHit(bs)
    local setCounts = GameState.GetEquippedSetCounts()
    if not setCounts["dragon_fury"] or setCounts["dragon_fury"] < 4 then return end

    local df4 = Config.EQUIP_SET_MAP["dragon_fury"].bonuses[4].buff

    -- 只在技能增强阶段触发
    if GameState._dragonPhase == "skill" then
        -- 消耗技能增幅, 切回普攻阶段
        GameState._dragonSkillBonus = 0
        GameState._dragonPhase = "atk"
        GameState._dragonHitCount = 0
        -- 给予普攻增幅
        GameState._dragonAtkBonus = df4.skillBonusToAtk or 0.30
        GameState._dragonAtkBonusHits = df4.atkBonusHits or 3

        -- 完成一轮交替, 累计轮次
        GameState._dragonCycleCount = (GameState._dragonCycleCount or 0) + 1

        -- 6件: 满3轮触发龙息
        if setCounts["dragon_fury"] >= 6 then
            M.TryDragonBreath(bs)
        end
    end
end

--- 龙息之怒4件: 获取技能增伤 (下次技能+50%)
function M.GetDragonFurySkillBonus()
    return GameState._dragonSkillBonus or 0
end

--- 龙息之怒4件: 获取普攻增伤 (3次普攻+30%)
function M.GetDragonFuryAtkBonus()
    if GameState._dragonAtkBonusHits and GameState._dragonAtkBonusHits > 0 then
        return GameState._dragonAtkBonus or 0
    end
    return 0
end

--- 龙息之怒6件: 龙息
function M.TryDragonBreath(bs)
    local setCounts = GameState.GetEquippedSetCounts()
    if not setCounts["dragon_fury"] or setCounts["dragon_fury"] < 6 then return end

    local df6 = Config.EQUIP_SET_MAP["dragon_fury"].bonuses[6].buff
    local cd = GameState.setBuffCD["dragon_fury_6"] or 0
    if cd > 0 then return end

    local cyclesRequired = df6.cyclesRequired or 3
    if (GameState._dragonCycleCount or 0) < cyclesRequired then return end

    GameState._dragonCycleCount = 0
    GameState.setBuffCD["dragon_fury_6"] = df6.cd or 18.0

    local Particles = require("battle.Particles")
    local CombatUtils = require("battle.CombatUtils")

    local totalAtk = GameState.GetTotalAtk()
    local breathDmg = math.floor(totalAtk * (df6.breathDmgMul or 4.0))

    for _, e in ipairs(bs.enemies) do
        if not e.dead then
            local dmg = breathDmg
            -- 火元素抗性
            if e.resist and e.resist.fire then
                dmg = math.max(1, math.floor(dmg * (1 - e.resist.fire)))
            end
            e.hp = e.hp - dmg
            CombatUtils.RecordBossDmg(dmg)
            Particles.SpawnDmgText(bs.particles, e.x, e.y - (e.radius or 16) - 10, dmg, false, false, { 255, 80, 30 })
            if e.hp <= 0 then
                e.dead = true
                bs.OnEnemyKilled(e)
            end
        end
    end

    -- 龙威BUFF: 全伤害+20%
    GameState._dragonMightTimer = df6.allDmgDur or 8.0
    GameState._dragonMightBonus = df6.allDmgBonus or 0.20

    Particles.SpawnReactionText(bs.particles, bs.playerBattle.x, bs.playerBattle.y - 40, "龙息!", { 255, 80, 30 })
    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_STORM)

    table.insert(bs.bossSkillEffects, {
        type = "deathExplode", element = "fire",
        x = bs.playerBattle.x, y = bs.playerBattle.y,
        radius = 120, life = 1.0, maxLife = 1.0,
    })
end

--- 龙息之怒6件: 获取龙威全伤害加成
function M.GetDragonMightBonus()
    if GameState._dragonMightTimer and GameState._dragonMightTimer > 0 then
        return GameState._dragonMightBonus or 0
    end
    return 0
end

--- 龙息之怒: 每帧更新
function M.UpdateDragonFury(dt)
    if GameState._dragonMightTimer and GameState._dragonMightTimer > 0 then
        GameState._dragonMightTimer = GameState._dragonMightTimer - dt
        if GameState._dragonMightTimer <= 0 then
            GameState._dragonMightTimer = 0
            GameState._dragonMightBonus = 0
        end
    end
    local cd6 = GameState.setBuffCD["dragon_fury_6"] or 0
    if cd6 > 0 then GameState.setBuffCD["dragon_fury_6"] = math.max(0, cd6 - dt) end
end

-- ============================================================================
-- 符文编织 (rune_weaver)
-- 2件: 技能CD缩减+15%(被动statsMul), 每次释放技能获1层符文(上限5)
-- 4件: 符文满5层消耗: 所有技能CD-3秒 + 下次技能+80%
-- 6件: 消耗后6秒符文共鸣: 技能伤害+50%+技能回1%HP+CD流速翻倍 (CD18)
-- ============================================================================

--- 符文编织2件: 技能释放叠符文 (由 BattleSystem.CastSkill 调用)
function M.OnRuneWeaverSkillCast(bs)
    local setCounts = GameState.GetEquippedSetCounts()
    if not setCounts["rune_weaver"] or setCounts["rune_weaver"] < 2 then return end

    local rw2 = Config.EQUIP_SET_MAP["rune_weaver"].bonuses[2].buff
    local maxRunes = rw2.maxRunes or 5
    GameState._runeStacks = math.min(maxRunes, (GameState._runeStacks or 0) + (rw2.runePerCast or 1))

    -- 满层触发4件
    if setCounts["rune_weaver"] >= 4 and GameState._runeStacks >= maxRunes then
        M.ConsumeRunes(bs)
    end
end

--- 符文编织4件: 消耗符文
function M.ConsumeRunes(bs)
    GameState._runeStacks = 0

    local setCounts = GameState.GetEquippedSetCounts()
    local rw4 = Config.EQUIP_SET_MAP["rune_weaver"].bonuses[4].buff

    -- 随机一个技能CD减少
    if bs and bs.playerBattle and bs.playerBattle.skillTimers then
        local cdReduce = rw4.cdReduceRandom or rw4.cdReduceAll or 5.0
        if rw4.cdReduceRandom then
            -- 随机选一个技能
            local skillIds = {}
            for skillId, _ in pairs(bs.playerBattle.skillTimers) do
                table.insert(skillIds, skillId)
            end
            if #skillIds > 0 then
                local chosen = skillIds[math.random(1, #skillIds)]
                bs.playerBattle.skillTimers[chosen] = math.max(0, bs.playerBattle.skillTimers[chosen] - cdReduce)
            end
        else
            -- 兼容旧逻辑: 所有技能CD减少
            for skillId, timer in pairs(bs.playerBattle.skillTimers) do
                bs.playerBattle.skillTimers[skillId] = math.max(0, timer - cdReduce)
            end
        end
    end

    -- 下次技能伤害加成
    GameState._runeNextSkillBonus = rw4.nextSkillDmgBonus or 0.80

    -- 6件: 符文共鸣
    if setCounts["rune_weaver"] >= 6 then
        local rw6 = Config.EQUIP_SET_MAP["rune_weaver"].bonuses[6].buff
        local cd = GameState.setBuffCD["rune_weaver_6"] or 0
        if cd <= 0 then
            GameState._runeResonanceTimer = rw6.duration or 6.0
            GameState._runeResonanceSkillDmg = rw6.skillDmgBonus or 0.50
            GameState._runeResonanceHealPct = rw6.skillHealPct or 0.01
            GameState._runeResonanceCdMul = rw6.cdFlowMul or 2.0
            GameState.setBuffCD["rune_weaver_6"] = rw6.cd or 18.0

            local Particles = require("battle.Particles")
            Particles.SpawnReactionText(bs.particles, bs.playerBattle.x, bs.playerBattle.y - 40, "符文共鸣!", { 100, 150, 255 })
        end
    end
end

--- 符文编织4件: 获取下次技能增伤 (消耗后归零)
function M.ConsumeRuneNextSkillBonus()
    local bonus = GameState._runeNextSkillBonus or 0
    GameState._runeNextSkillBonus = 0
    return bonus
end

--- 符文编织6件: 获取技能伤害加成
function M.GetRuneResonanceSkillDmgBonus()
    if GameState._runeResonanceTimer and GameState._runeResonanceTimer > 0 then
        return GameState._runeResonanceSkillDmg or 0
    end
    return 0
end

--- 符文编织6件: 技能命中回血
function M.OnRuneResonanceSkillHit()
    if not GameState._runeResonanceTimer or GameState._runeResonanceTimer <= 0 then return end
    local healPct = GameState._runeResonanceHealPct or 0.01
    local healAmt = math.floor(GameState.GetMaxHP() * healPct)
    if healAmt > 0 then
        GameState.HealPlayer(healAmt)
    end
end

--- 符文编织6件: 获取CD流速倍率 (>1 表示加速)
function M.GetRuneResonanceCdMul()
    if GameState._runeResonanceTimer and GameState._runeResonanceTimer > 0 then
        return GameState._runeResonanceCdMul or 1.0
    end
    return 1.0
end

--- 符文编织: 每帧更新
function M.UpdateRuneWeaver(dt)
    if GameState._runeResonanceTimer and GameState._runeResonanceTimer > 0 then
        GameState._runeResonanceTimer = GameState._runeResonanceTimer - dt
        if GameState._runeResonanceTimer <= 0 then
            GameState._runeResonanceTimer = 0
            GameState._runeResonanceSkillDmg = 0
            GameState._runeResonanceHealPct = 0
            GameState._runeResonanceCdMul = 0
        end
    end
    local cd6 = GameState.setBuffCD["rune_weaver_6"] or 0
    if cd6 > 0 then GameState.setBuffCD["rune_weaver_6"] = math.max(0, cd6 - dt) end
end

return M
