-- ============================================================================
-- battle/buffs/T13Sets.lua - 第13章套装 Buff 逻辑
-- 包含: lava_conqueror (熔岩征服者), permafrost_heart (极寒之心)
-- ============================================================================

local Config      = require("Config")
local GameState   = require("GameState")

local M = {}

-- ============================================================================
-- 熔岩征服者 (lava_conqueror)
-- 2件: 火伤+30%,攻速+12%(被动statsMul), 攻击25%几率点燃(4%ATK/秒,5秒,叠3层)
-- 4件: 点燃满3层→熔岩爆发450%ATK火伤+清层+扩散1层(半径80,CD5秒)
-- 6件: 熔岩爆发后6秒「熔岩领主」:火伤+40%+25%溅射+暴击火焰冲击100%ATK(CD28秒)
-- ============================================================================

--- 熔岩征服者2件: 攻击命中时25%几率点燃目标 (由 CombatCore.HitEnemy 调用)
--- @param bs table BattleSystem
--- @param target table 敌人
function M.OnLavaConquerorHit(bs, target)
    local setCounts = GameState.GetEquippedSetCounts()
    if not setCounts["lava_conqueror"] or setCounts["lava_conqueror"] < 2 then return end
    if target.dead then return end

    local lc2 = Config.EQUIP_SET_MAP["lava_conqueror"].bonuses[2].buff
    if math.random() > (lc2.burnChance or 0.25) then return end

    -- 初始化点燃数据
    if not target._lavaBurn then
        target._lavaBurn = { stacks = 0, timer = 0 }
    end

    local burn = target._lavaBurn
    local maxStacks = lc2.burnMaxStacks or 3
    burn.stacks = math.min(maxStacks, burn.stacks + 1)
    burn.timer = lc2.burnDur or 5.0
    burn.dmgPerSec = math.floor(GameState.GetTotalAtk() * (lc2.burnDmgPct or 0.04))

    -- 4件: 满层触发熔岩爆发
    if setCounts["lava_conqueror"] >= 4 and burn.stacks >= maxStacks then
        M.TryLavaBurst(bs, target)
    end
end

--- 熔岩征服者4件: 熔岩爆发 (点燃满层触发)
--- @param bs table BattleSystem
--- @param target table 点燃满层的敌人
function M.TryLavaBurst(bs, target)
    local setCounts = GameState.GetEquippedSetCounts()
    if not setCounts["lava_conqueror"] or setCounts["lava_conqueror"] < 4 then return end

    local lc4 = Config.EQUIP_SET_MAP["lava_conqueror"].bonuses[4].buff
    local cd = GameState.setBuffCD["lava_conqueror_4"] or 0
    if cd > 0 then return end

    GameState.setBuffCD["lava_conqueror_4"] = lc4.cd or 5.0

    local Particles = require("battle.Particles")
    local CombatUtils = require("battle.CombatUtils")

    local totalAtk = GameState.GetTotalAtk()
    local burstDmg = math.floor(totalAtk * (lc4.burstDmgMul or 4.5))
    local spreadRadius = lc4.spreadRadius or 80

    -- 对目标造成爆发伤害
    if not target.dead then
        local dmg = burstDmg
        if target.resist and target.resist.fire then
            dmg = math.max(1, math.floor(dmg * (1 - target.resist.fire)))
        end
        target.hp = target.hp - dmg
        CombatUtils.RecordBossDmg(dmg)
        Particles.SpawnDmgText(bs.particles, target.x, target.y - (target.radius or 16) - 10,
            dmg, false, false, { 255, 100, 30 })
        -- 清除目标点燃层数
        if target._lavaBurn then
            target._lavaBurn.stacks = 0
            target._lavaBurn.timer = 0
        end
        if target.hp <= 0 then
            target.dead = true
            bs.OnEnemyKilled(target)
        end
    end

    -- 扩散: 范围内其他敌人获得1层点燃
    if lc4.spreadBurn then
        local lc2 = Config.EQUIP_SET_MAP["lava_conqueror"].bonuses[2].buff
        local spreadStacks = lc4.spreadStacks or 1
        for _, e in ipairs(bs.enemies) do
            if not e.dead and e ~= target then
                local dx, dy = e.x - target.x, e.y - target.y
                if math.sqrt(dx * dx + dy * dy) <= spreadRadius then
                    if not e._lavaBurn then
                        e._lavaBurn = { stacks = 0, timer = 0, dmgPerSec = 0 }
                    end
                    e._lavaBurn.stacks = math.min(lc2.burnMaxStacks or 3,
                        e._lavaBurn.stacks + spreadStacks)
                    e._lavaBurn.timer = lc2.burnDur or 5.0
                    e._lavaBurn.dmgPerSec = math.floor(GameState.GetTotalAtk() * (lc2.burnDmgPct or 0.04))
                end
            end
        end
    end

    -- 视觉效果
    Particles.SpawnReactionText(bs.particles, target.x, target.y - 40, "熔岩爆发!", { 255, 100, 30 })
    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_STORM)

    table.insert(bs.bossSkillEffects, {
        type = "deathExplode", element = "fire",
        x = target.x, y = target.y,
        radius = spreadRadius, life = 0.8, maxLife = 0.8,
    })

    -- 6件: 爆发后触发「熔岩领主」
    if setCounts["lava_conqueror"] >= 6 then
        M.TryLavaLord(bs)
    end
end

--- 熔岩征服者6件: 熔岩领主增强态
function M.TryLavaLord(bs)
    local setCounts = GameState.GetEquippedSetCounts()
    if not setCounts["lava_conqueror"] or setCounts["lava_conqueror"] < 6 then return end

    local lc6 = Config.EQUIP_SET_MAP["lava_conqueror"].bonuses[6].buff
    local cd = GameState.setBuffCD["lava_conqueror_6"] or 0
    if cd > 0 then return end

    GameState.setBuffCD["lava_conqueror_6"] = lc6.cd or 28.0
    GameState._lavaLordTimer = lc6.duration or 6.0
    GameState._lavaLordFireDmgBonus = lc6.fireDmgBonus or 0.40
    GameState._lavaLordSplashPct = lc6.splashPct or 0.25
    GameState._lavaLordCritFireDmgMul = lc6.critFireDmgMul or 1.0
    GameState._lavaLordCritFireRadius = lc6.critFireRadius or 60

    local Particles = require("battle.Particles")
    Particles.SpawnReactionText(bs.particles, bs.playerBattle.x, bs.playerBattle.y - 40,
        "熔岩领主!", { 255, 80, 0 })
end

--- 熔岩征服者6件: 获取火伤加成
function M.GetLavaLordFireDmgBonus()
    if GameState._lavaLordTimer and GameState._lavaLordTimer > 0 then
        return GameState._lavaLordFireDmgBonus or 0
    end
    return 0
end

--- 熔岩征服者6件: 获取溅射率 (普攻命中时额外伤害扩散)
function M.GetLavaLordSplashPct()
    if GameState._lavaLordTimer and GameState._lavaLordTimer > 0 then
        return GameState._lavaLordSplashPct or 0
    end
    return 0
end

--- 熔岩征服者6件: 暴击时火焰冲击 (由 CombatCore.HitEnemy 暴击时调用)
function M.OnLavaLordCritHit(bs, target)
    if not GameState._lavaLordTimer or GameState._lavaLordTimer <= 0 then return end
    if target.dead then return end

    local Particles = require("battle.Particles")
    local CombatUtils = require("battle.CombatUtils")

    local totalAtk = GameState.GetTotalAtk()
    local critFireDmg = math.floor(totalAtk * (GameState._lavaLordCritFireDmgMul or 1.0))
    local radius = GameState._lavaLordCritFireRadius or 60

    -- AOE 火焰冲击
    for _, e in ipairs(bs.enemies) do
        if not e.dead then
            local dx, dy = e.x - target.x, e.y - target.y
            if math.sqrt(dx * dx + dy * dy) <= radius then
                local dmg = critFireDmg
                if e.resist and e.resist.fire then
                    dmg = math.max(1, math.floor(dmg * (1 - e.resist.fire)))
                end
                e.hp = e.hp - dmg
                CombatUtils.RecordBossDmg(dmg)
                Particles.SpawnDmgText(bs.particles, e.x, e.y - (e.radius or 16) - 10,
                    dmg, false, false, { 255, 120, 30 })
                if e.hp <= 0 then
                    e.dead = true
                    bs.OnEnemyKilled(e)
                end
            end
        end
    end
end

--- 熔岩征服者6件: 溅射伤害 (普攻命中时对周围敌人造成25%伤害)
--- @param bs table BattleSystem
--- @param target table 被命中的敌人
--- @param dmg number 本次命中伤害
function M.OnLavaLordSplash(bs, target, dmg)
    if not GameState._lavaLordTimer or GameState._lavaLordTimer <= 0 then return end
    local splashPct = GameState._lavaLordSplashPct or 0
    if splashPct <= 0 then return end
    if target.dead then return end

    local Particles = require("battle.Particles")
    local CombatUtils = require("battle.CombatUtils")

    local splashDmg = math.max(1, math.floor(dmg * splashPct))
    local splashRadius = 50  -- 溅射半径

    for _, e in ipairs(bs.enemies) do
        if not e.dead and e ~= target then
            local dx, dy = e.x - target.x, e.y - target.y
            if math.sqrt(dx * dx + dy * dy) <= splashRadius then
                e.hp = e.hp - splashDmg
                CombatUtils.RecordBossDmg(splashDmg)
                Particles.SpawnDmgText(bs.particles, e.x, e.y - (e.radius or 16) - 10,
                    splashDmg, false, false, { 255, 140, 60 })
                if e.hp <= 0 then
                    e.dead = true
                    bs.OnEnemyKilled(e)
                end
            end
        end
    end
end

--- 熔岩征服者: 更新点燃DOT (每帧调用)
--- @param dt number 帧间隔
--- @param bs table BattleSystem
function M.UpdateLavaConquerorBurn(dt, bs)
    local Particles = require("battle.Particles")
    local CombatUtils = require("battle.CombatUtils")

    for _, e in ipairs(bs.enemies) do
        if not e.dead and e._lavaBurn and e._lavaBurn.stacks > 0 and e._lavaBurn.timer > 0 then
            local burn = e._lavaBurn
            burn.timer = burn.timer - dt

            -- DOT 伤害 (每秒 dmgPerSec × stacks)
            if not burn._tickAccum then burn._tickAccum = 0 end
            burn._tickAccum = burn._tickAccum + dt
            if burn._tickAccum >= 0.5 then  -- 每0.5秒跳一次
                local tickDmg = math.floor(burn.dmgPerSec * burn.stacks * burn._tickAccum)
                burn._tickAccum = 0
                if tickDmg > 0 then
                    if e.resist and e.resist.fire then
                        tickDmg = math.max(1, math.floor(tickDmg * (1 - e.resist.fire)))
                    end
                    e.hp = e.hp - tickDmg
                    CombatUtils.RecordBossDmg(tickDmg)
                    Particles.SpawnDmgText(bs.particles, e.x, e.y - (e.radius or 16) - 5,
                        tickDmg, false, false, { 255, 80, 20 })
                    if e.hp <= 0 then
                        e.dead = true
                        bs.OnEnemyKilled(e)
                    end
                end
            end

            -- 超时清除
            if burn.timer <= 0 then
                burn.stacks = 0
                burn.timer = 0
                burn.dmgPerSec = 0
                burn._tickAccum = 0
            end
        end
    end
end

--- 熔岩征服者: 每帧更新 (计时器 + CD + 点燃DOT)
function M.UpdateLavaConqueror(dt, bs)
    -- 熔岩领主计时器
    if GameState._lavaLordTimer and GameState._lavaLordTimer > 0 then
        GameState._lavaLordTimer = GameState._lavaLordTimer - dt
        if GameState._lavaLordTimer <= 0 then
            GameState._lavaLordTimer = 0
            GameState._lavaLordFireDmgBonus = 0
            GameState._lavaLordSplashPct = 0
            GameState._lavaLordCritFireDmgMul = 0
            GameState._lavaLordCritFireRadius = 0
        end
    end
    -- CD
    local cd4 = GameState.setBuffCD["lava_conqueror_4"] or 0
    if cd4 > 0 then GameState.setBuffCD["lava_conqueror_4"] = math.max(0, cd4 - dt) end
    local cd6 = GameState.setBuffCD["lava_conqueror_6"] or 0
    if cd6 > 0 then GameState.setBuffCD["lava_conqueror_6"] = math.max(0, cd6 - dt) end
    -- 点燃DOT
    M.UpdateLavaConquerorBurn(dt, bs)
end


-- ============================================================================
-- 极寒之心 (permafrost_heart)
-- 2件: 冰抗+40%,水抗+25%,HP+20%(被动statsMul/resist), 受冰/水伤回复2%HP
-- 4件: 受致命伤→极寒护盾(6秒无敌+回55%HP+冻结3秒+清减速),每关1次
-- 6件: 极寒护盾后12秒「寒冰化身」:减伤40%+回5%HP/秒+30%反弹冰伤150%ATK+免减速(CD32秒)
-- ============================================================================

--- 极寒之心2件: 受冰/水伤回复2%HP (由 EnemySystem.OnEnemyHitPlayer 调用)
--- @param bs table BattleSystem
--- @param attackerElement string|nil 攻击者元素
function M.TryPermafrostHeal(bs, attackerElement)
    local setCounts = GameState.GetEquippedSetCounts()
    if not setCounts["permafrost_heart"] or setCounts["permafrost_heart"] < 2 then return end
    if attackerElement ~= "ice" and attackerElement ~= "water" then return end

    local ph2 = Config.EQUIP_SET_MAP["permafrost_heart"].bonuses[2].buff
    local healAmt = math.floor(GameState.GetMaxHP() * (ph2.healPct or 0.02))
    if healAmt > 0 then
        GameState.HealPlayer(healAmt)
    end
end

--- 极寒之心4件: 致命保护 - 极寒护盾
--- @param bs table BattleSystem
--- @param incomingDmg number 即将造成的伤害
--- @return boolean 是否触发了保护
function M.CheckPermafrostFatalProtect(bs, incomingDmg)
    local setCounts = GameState.GetEquippedSetCounts()
    if not setCounts["permafrost_heart"] or setCounts["permafrost_heart"] < 4 then return false end

    local ph4 = Config.EQUIP_SET_MAP["permafrost_heart"].bonuses[4].buff
    if not ph4.fatalProtect then return false end
    if GameState._permafrostFatalUsed then return false end
    if GameState.playerHP - incomingDmg > 0 then return false end

    -- 触发极寒护盾
    GameState._permafrostFatalUsed = true
    GameState.playerHP = 1

    local Particles = require("battle.Particles")
    local CombatUtils = require("battle.CombatUtils")

    -- 回复55%HP
    local healAmt = math.floor(GameState.GetMaxHP() * (ph4.fatalHealPct or 0.55))
    if healAmt > 0 then
        GameState.HealPlayer(healAmt)
    end

    -- 无敌
    GameState._permafrostInvulTimer = ph4.fatalInvulDur or 6.0

    -- 清除减速
    if ph4.clearSlow then
        GameState._slowDebuffTimer = 0
        GameState._slowDebuffRate = 0
    end

    -- 冻结范围内敌人
    local freezeDur = ph4.freezeDur or 3.0
    local freezeRadius = ph4.freezeRadius or 100
    for _, e in ipairs(bs.enemies) do
        if not e.dead then
            local dx, dy = e.x - bs.playerBattle.x, e.y - bs.playerBattle.y
            if math.sqrt(dx * dx + dy * dy) <= freezeRadius then
                e._frozenSlowTimer = freezeDur
                e._frozenSlowRate = 1.0  -- 完全冻结
            end
        end
    end

    Particles.SpawnReactionText(bs.particles, bs.playerBattle.x, bs.playerBattle.y - 40,
        "极寒护盾!", { 100, 200, 240 })
    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_STORM)

    table.insert(bs.bossSkillEffects, {
        type = "deathExplode", element = "ice",
        x = bs.playerBattle.x, y = bs.playerBattle.y,
        radius = freezeRadius, life = 1.0, maxLife = 1.0,
    })

    -- 6件: 触发寒冰化身
    if setCounts["permafrost_heart"] >= 6 then
        M.TryIceAvatar(bs)
    end

    return true
end

--- 极寒之心6件: 寒冰化身增强态
function M.TryIceAvatar(bs)
    local setCounts = GameState.GetEquippedSetCounts()
    if not setCounts["permafrost_heart"] or setCounts["permafrost_heart"] < 6 then return end

    local ph6 = Config.EQUIP_SET_MAP["permafrost_heart"].bonuses[6].buff
    local cd = GameState.setBuffCD["permafrost_heart_6"] or 0
    if cd > 0 then return end

    GameState.setBuffCD["permafrost_heart_6"] = ph6.cd or 32.0
    GameState._iceAvatarTimer = ph6.duration or 12.0
    GameState._iceAvatarDmgReduce = ph6.dmgReduce or 0.40
    GameState._iceAvatarRegenPct = ph6.regenPctPerSec or 0.05
    GameState._iceAvatarReflectChance = ph6.reflectChance or 0.30
    GameState._iceAvatarReflectDmgMul = ph6.reflectDmgMul or 1.5
    GameState._iceAvatarSlowImmune = ph6.slowImmune or false

    local Particles = require("battle.Particles")
    Particles.SpawnReactionText(bs.particles, bs.playerBattle.x, bs.playerBattle.y - 40,
        "寒冰化身!", { 80, 180, 255 })
end

--- 极寒之心6件: 获取减伤率
function M.GetIceAvatarDmgReduce()
    if GameState._iceAvatarTimer and GameState._iceAvatarTimer > 0 then
        return GameState._iceAvatarDmgReduce or 0
    end
    return 0
end

--- 极寒之心6件: 是否免疫减速
function M.IsIceAvatarSlowImmune()
    if GameState._iceAvatarTimer and GameState._iceAvatarTimer > 0 then
        return GameState._iceAvatarSlowImmune or false
    end
    return false
end

--- 极寒之心6件: 受击反弹冰伤 (由 EnemySystem.OnEnemyHitPlayer 调用)
--- @param bs table BattleSystem
--- @param attacker table 攻击者敌人
function M.TryIceAvatarReflect(bs, attacker)
    if not GameState._iceAvatarTimer or GameState._iceAvatarTimer <= 0 then return end
    if not attacker or attacker.dead then return end
    if math.random() > (GameState._iceAvatarReflectChance or 0.30) then return end

    local Particles = require("battle.Particles")
    local CombatUtils = require("battle.CombatUtils")

    local totalAtk = GameState.GetTotalAtk()
    local reflectDmg = math.floor(totalAtk * (GameState._iceAvatarReflectDmgMul or 1.5))

    -- 冰抗减伤
    if attacker.resist and attacker.resist.ice then
        reflectDmg = math.max(1, math.floor(reflectDmg * (1 - attacker.resist.ice)))
    end

    attacker.hp = attacker.hp - reflectDmg
    CombatUtils.RecordBossDmg(reflectDmg)
    Particles.SpawnDmgText(bs.particles, attacker.x, attacker.y - (attacker.radius or 16) - 10,
        reflectDmg, false, false, { 100, 200, 240 })

    if attacker.hp <= 0 then
        attacker.dead = true
        bs.OnEnemyKilled(attacker)
    end
end

--- 极寒之心4件: 无敌状态检测 (由 state/Combat.lua TakeDamage 调用)
function M.IsPermafrostInvulnerable()
    return GameState._permafrostInvulTimer and GameState._permafrostInvulTimer > 0
end

--- 极寒之心: 每帧更新
function M.UpdatePermafrostHeart(dt)
    -- 无敌计时器
    if GameState._permafrostInvulTimer and GameState._permafrostInvulTimer > 0 then
        GameState._permafrostInvulTimer = GameState._permafrostInvulTimer - dt
        if GameState._permafrostInvulTimer <= 0 then
            GameState._permafrostInvulTimer = 0
        end
    end
    -- 寒冰化身
    if GameState._iceAvatarTimer and GameState._iceAvatarTimer > 0 then
        GameState._iceAvatarTimer = GameState._iceAvatarTimer - dt
        -- 每秒回复
        local healAmt = math.floor(GameState.GetMaxHP() * (GameState._iceAvatarRegenPct or 0.05) * dt)
        if healAmt > 0 then
            GameState.HealPlayer(healAmt)
        end
        -- 减速免疫: 持续清除减速
        if GameState._iceAvatarSlowImmune then
            GameState._slowDebuffTimer = 0
            GameState._slowDebuffRate = 0
        end
        if GameState._iceAvatarTimer <= 0 then
            GameState._iceAvatarTimer = 0
            GameState._iceAvatarDmgReduce = 0
            GameState._iceAvatarRegenPct = 0
            GameState._iceAvatarReflectChance = 0
            GameState._iceAvatarReflectDmgMul = 0
            GameState._iceAvatarSlowImmune = false
        end
    end
    -- CD
    local cd6 = GameState.setBuffCD["permafrost_heart_6"] or 0
    if cd6 > 0 then GameState.setBuffCD["permafrost_heart_6"] = math.max(0, cd6 - dt) end
end

return M
