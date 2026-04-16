-- ============================================================================
-- state/BuffRuntime.lua - Buff/Debuff 运行时状态与逻辑
-- 统一管理: debuff施加(9种) + 每帧tick + 正面buff计时(狂热/战意/狂暴)
--           + 护盾管理 + 药水buff系统
-- 通过 Install(GameState) 注入, 调用方式不变: GameState.ApplySlowDebuff(...)
-- ============================================================================

local BuffRuntime = {}

function BuffRuntime.Install(GameState)
    local Config = require("Config")
    local ShieldManager = require("state.ShieldManager")
    local CombatUtils = require("battle.CombatUtils")
    local BuffRegistry = require("state.BuffRegistry")
    local DebuffApplier = require("state.DebuffApplier")

    -- ========================================================================
    -- DebuffApplier: 注册 10 个 debuff 施加配置
    -- ========================================================================
    -- 覆盖型 (5)
    DebuffApplier.Register("slow", {
        ccImmune = true, mode = "override",
        valueField = "playerSlowRate", timerField = "playerSlowTimer",
    })
    DebuffApplier.Register("antiHeal", {
        ccImmune = false, mode = "override",
        valueField = "antiHealRate", timerField = "antiHealTimer",
    })
    DebuffApplier.Register("inkBlind", {
        ccImmune = true, mode = "override",
        valueField = "inkBlindRate", timerField = "inkBlindTimer",
    })
    DebuffApplier.Register("sandStorm", {
        ccImmune = false, mode = "override",
        valueField = "sandStormCritReduce", timerField = "sandStormTimer",
    })
    DebuffApplier.Register("sporeCloud", {
        ccImmune = true, mode = "override",
        valueField = "sporeCloudAtkSpdReduce", timerField = "sporeCloudTimer",
    })
    -- 叠层自增型 (3)
    DebuffApplier.Register("corrosion", {
        ccImmune = true, mode = "stack_inc",
        valueField = "corrosionDefReduce", timerField = "corrosionTimer",
        stackField = "corrosionStacks", maxStackField = "corrosionMaxStacks",
    })
    DebuffApplier.Register("venomStack", {
        ccImmune = false, mode = "stack_inc",
        valueField = "venomStackDmgPct", timerField = "venomStackTimer",
        stackField = "venomStackCount", maxStackField = "venomStackMaxStacks",
        minThreshold = 0.001,
    })
    DebuffApplier.Register("scorch", {
        ccImmune = false, mode = "stack_inc",
        valueField = "scorchDmgAmp", timerField = "scorchTimer",
        stackField = "scorchStacks", maxStackField = "scorchMaxStacks",
        minThreshold = 0.001,
    })
    -- 叠层加值型 (2)
    DebuffApplier.Register("drench", {
        ccImmune = false, mode = "stack_add",
        timerField = "drenchTimer",
        stackField = "drenchStacks", maxStackField = "drenchMaxStacks",
        extraFields = { critPerStack = "drenchCritReduce", fireResPerStack = "drenchFireResReduce" },
        thresholdParam = "critPerStack", minThreshold = 0.001,
    })
    DebuffApplier.Register("tidalCorrosion", {
        ccImmune = false, mode = "stack_add",
        timerField = "tidalCorrosionTimer",
        stackField = "tidalCorrosionStacks", maxStackField = "tidalCorrosionMaxStacks",
        extraFields = { dmgAmp = "tidalCorrosionDmgAmp" },
        thresholdParam = "dmgAmp", minThreshold = 0.001,
    })

    -- 注册护盾上限 = 最大生命值
    ShieldManager.SetMaxGetter(function()
        return GameState.GetMaxHP()
    end)

    -- ========================================================================
    -- BuffRegistry: 注册 19 个简单倒计时 buff（替代手动 if-block）
    -- ========================================================================
    BuffRegistry.Register({ id = "antiHeal", timerField = "antiHealTimer",
        resetFields = { antiHealRate = 0, antiHealTimer = 0 } })
    BuffRegistry.Register({ id = "slow", timerField = "playerSlowTimer",
        resetFields = { playerSlowRate = 0, playerSlowTimer = 0 } })
    BuffRegistry.Register({ id = "corrosion", timerField = "corrosionTimer",
        resetFields = { corrosionStacks = 0, corrosionDefReduce = 0, corrosionTimer = 0, corrosionMaxStacks = 0 } })
    BuffRegistry.Register({ id = "inkBlind", timerField = "inkBlindTimer",
        resetFields = { inkBlindRate = 0, inkBlindTimer = 0 } })
    BuffRegistry.Register({ id = "sandStorm", timerField = "sandStormTimer",
        resetFields = { sandStormCritReduce = 0, sandStormTimer = 0 } })
    BuffRegistry.Register({ id = "sporeCloud", timerField = "sporeCloudTimer",
        resetFields = { sporeCloudAtkSpdReduce = 0, sporeCloudTimer = 0 } })
    BuffRegistry.Register({ id = "scorch", timerField = "scorchTimer",
        resetFields = { scorchStacks = 0, scorchDmgAmp = 0, scorchTimer = 0, scorchMaxStacks = 0 } })
    BuffRegistry.Register({ id = "drench", timerField = "drenchTimer",
        resetFields = { drenchStacks = 0, drenchCritReduce = 0, drenchFireResReduce = 0, drenchTimer = 0, drenchMaxStacks = 0 } })
    BuffRegistry.Register({ id = "tidalCorrosion", timerField = "tidalCorrosionTimer",
        resetFields = { tidalCorrosionStacks = 0, tidalCorrosionDmgAmp = 0, tidalCorrosionTimer = 0, tidalCorrosionMaxStacks = 0 } })
    BuffRegistry.Register({ id = "attachedElement", timerField = "attachedElementTimer",
        resetFields = { attachedElement = nil, attachedElementTimer = 0 } })
    BuffRegistry.Register({ id = "flameShieldSpeed", timerField = "_flameShieldSpeedTimer",
        resetFields = { _flameShieldSpeedTimer = 0 } })
    BuffRegistry.Register({ id = "frostNovaSpeed", timerField = "_frostNovaSpeedTimer",
        resetFields = { _frostNovaSpeedTimer = 0 } })
    BuffRegistry.Register({ id = "arcaneStrikeAtkSpd", timerField = "_arcaneStrikeAtkSpdTimer",
        resetFields = { _arcaneStrikeAtkSpdTimer = 0 } })
    BuffRegistry.Register({ id = "teleportMystical", timerField = "_teleportMysticalTimer",
        resetFields = { _teleportMysticalTimer = 0 } })
    BuffRegistry.Register({ id = "teleportDmgReduce", timerField = "_teleportDmgReduceTimer",
        resetFields = { _teleportDmgReduceTimer = 0 } })
    BuffRegistry.Register({ id = "meteorSupreme", timerField = "_meteorSupremeTimer",
        resetFields = { _meteorSupremeTimer = 0 } })
    BuffRegistry.Register({ id = "thunderStormSupreme", timerField = "_thunderStormSupremeTimer",
        resetFields = { _thunderStormSupremeTimer = 0 } })
    BuffRegistry.Register({ id = "frozenOrbSpeed", timerField = "_frozenOrbSpeedTimer",
        resetFields = { _frozenOrbSpeedTimer = 0 } })
    BuffRegistry.Register({ id = "blizzard", timerField = "blizzardTimer",
        resetFields = { blizzardActive = false, blizzardTimer = 0 } })

    -- ========================================================================
    -- 状态初始化 / 重置
    -- ========================================================================

    --- 初始化所有 buff/debuff 状态字段 (GameState.Init 调用)
    GameState.InitBuffState = function()
        GameState.ResetBuffs()
        GameState.potionBuffs = {}
    end

    --- 重置所有战斗 buff/debuff (ResetHP 调用)
    GameState.ResetBuffs = function()
        ShieldManager.Reset()
        -- 批量重置 19 个已注册的简单 buff
        BuffRegistry.ResetAll(GameState)
        -- 以下为未注册的复杂 buff，需手动重置
        -- 毒蛊 (有 tickCD 周期伤害)
        GameState.venomStackCount = 0
        GameState.venomStackDmgPct = 0
        GameState.venomStackTimer = 0
        GameState.venomStackMaxStacks = 0
        GameState.venomStackTickCD = 0
        -- 灼烧 (有 tickCD 周期伤害)
        GameState.blazeStacks = 0
        GameState.blazeDmgPct = 0
        GameState.blazeAtkSpdReduce = 0
        GameState.blazeMaxStacks = 0
        GameState.blazeTimer = 0
        GameState.blazeTickCD = 0
        GameState.blazeBossAtk = 0
        -- 寒冰甲 (护盾 + 多标志)
        GameState.shieldTimer = 0
        GameState.iceArmorActive = false
        GameState.iceArmorFrostbiteTimer = 0
        GameState.iceArmorManaSpent = 0
        -- 火焰护盾 (护盾 + 条件爆炸) — timer 由 Registry 重置，这里清附加标志
        GameState._flameShieldMystical = false
        -- 深度冻结 (周期产蓝 + 冰爆)
        GameState.ccImmune = false
        GameState.ccImmuneTimer = 0
        GameState._deepFreezeActive = false
        GameState._deepFreezeBurstPct = 0
        GameState._deepFreezeRadius = 0
        GameState._deepFreezeBs = nil
    end

    -- ========================================================================
    -- 护盾管理
    -- ========================================================================

    --- 添加护盾 (走护盾管线: base × SHLD%, 不受 HEAL% 和 antiHeal 影响)
    --- @param baseShield number 基础护盾值
    --- @param sourceId? string 护盾来源标识，默认 "passive"
    --- @return number 实际获得护盾量
    GameState.AddShield = function(baseShield, sourceId)
        if GameState.playerDead then return 0 end
        local shldMul = GameState.GetShieldMul()
        local actual = math.floor(baseShield * shldMul)
        local maxShield = GameState.GetMaxHP() * 0.5  -- 护盾上限 = HP × 50%
        local before = ShieldManager.GetTotal()
        local room = math.max(0, maxShield - before)
        actual = math.min(actual, room)
        if actual > 0 then
            ShieldManager.Add(sourceId or "passive", actual)
        end
        return actual
    end

    --- 击杀触发护盾
    GameState.OnKillShield = function()
        if GameState.playerDead then return end
        local base = Config.SHIELD.onKillBase + GameState.player.level * Config.SHIELD.onKillPerLevel
        GameState.AddShield(base)
    end

    -- ========================================================================
    -- 深度冻结: CC 免疫激活 / 到期爆炸
    -- ========================================================================

    --- 激活深度冻结 (IceSkills 调用)
    --- @param duration number 免疫持续时间
    --- @param burstPct number 结束爆炸伤害% (小数)
    --- @param radius number AOE 半径
    --- @param bs table battleState 引用
    GameState.ActivateDeepFreeze = function(duration, burstPct, radius, bs)
        GameState.ccImmune = true
        GameState.ccImmuneTimer = duration
        GameState._deepFreezeActive = true
        GameState._deepFreezeBurstPct = burstPct
        GameState._deepFreezeRadius = radius
        GameState._deepFreezeBs = bs
    end

    -- ========================================================================
    -- Debuff 施加 (9种, 均经过韧性衰减)
    -- ========================================================================

    --- 施加减速 debuff
    GameState.ApplySlowDebuff = function(slowRate, duration)
        DebuffApplier.Apply("slow", GameState, { value = slowRate, duration = duration })
    end

    --- 施加减疗 debuff
    GameState.ApplyAntiHealDebuff = function(rate, duration)
        DebuffApplier.Apply("antiHeal", GameState, { value = rate, duration = duration })
    end

    --- 施加腐蚀 debuff (叠加制, 降低DEF)
    GameState.ApplyCorrosionDebuff = function(defReducePct, maxStacks, duration)
        DebuffApplier.Apply("corrosion", GameState, { value = defReducePct, maxStacks = maxStacks, duration = duration })
    end

    --- 施加墨汁致盲 debuff (降低ATK)
    GameState.ApplyInkBlindDebuff = function(atkReducePct, duration)
        DebuffApplier.Apply("inkBlind", GameState, { value = atkReducePct, duration = duration })
    end

    --- 施加沙暴 debuff (降低暴击率)
    GameState.ApplySandStormDebuff = function(critReducePct, duration)
        DebuffApplier.Apply("sandStorm", GameState, { value = critReducePct, duration = duration })
    end

    --- 施加毒蛊叠加 debuff (每层按%maxHP每秒持续伤害)
    GameState.ApplyVenomStackDebuff = function(dmgPctPerStack, maxStacks, duration)
        DebuffApplier.Apply("venomStack", GameState, { value = dmgPctPerStack, maxStacks = maxStacks, duration = duration })
    end

    --- 施加孢子云 debuff (降低攻速)
    GameState.ApplySporeCloudDebuff = function(atkSpeedReducePct, duration)
        DebuffApplier.Apply("sporeCloud", GameState, { value = atkSpeedReducePct, duration = duration })
    end

    --- 施加灼烧 debuff (叠加制, 每层DoT + 攻速降低) (第15章)
    --- 保留手动实现: 5参数 + bossAtk快照 + 双阈值判断
    GameState.ApplyBlazeDebuff = function(dmgPct, atkSpdReduce, maxStacks, duration, bossAtk)
        if GameState.playerDead then return end
        local resist = GameState.GetDebuffResist()
        local durFactor = Config.TENACITY.durFactor
        local actualDmgPct = dmgPct * (1 - resist)
        local actualSpdReduce = atkSpdReduce * (1 - resist)
        local actualDur = duration * (1 - resist * durFactor)
        if actualDmgPct < 0.001 and actualSpdReduce < 0.001 then return end
        GameState.blazeDmgPct = actualDmgPct
        GameState.blazeAtkSpdReduce = actualSpdReduce
        GameState.blazeMaxStacks = maxStacks
        GameState.blazeTimer = actualDur
        if bossAtk then
            GameState.blazeBossAtk = bossAtk
        end
        if GameState.blazeStacks < maxStacks then
            GameState.blazeStacks = GameState.blazeStacks + 1
        end
    end

    --- 施加焚灼 debuff (叠加制, 每层增加受到伤害%)
    GameState.ApplyScorchDebuff = function(dmgAmpPct, maxStacks, duration)
        DebuffApplier.Apply("scorch", GameState, { value = dmgAmpPct, maxStacks = maxStacks, duration = duration })
    end

    --- 施加浸蚀 debuff (叠加制, 每层: 暴击-2.5% + 火抗-4%)
    GameState.ApplyDrenchDebuff = function(stacksToAdd, maxStacks, duration)
        DebuffApplier.Apply("drench", GameState, {
            duration = duration, maxStacks = maxStacks, stacksToAdd = stacksToAdd,
            critPerStack = 0.025, fireResPerStack = 0.04,
        })
    end

    --- 施加潮蚀 debuff (叠加制, 每层: 水属性受伤+3.5%)
    GameState.ApplyTidalCorrosionDebuff = function(stacksToAdd, maxStacks, duration)
        DebuffApplier.Apply("tidalCorrosion", GameState, {
            duration = duration, maxStacks = maxStacks, stacksToAdd = stacksToAdd,
            dmgAmp = 0.035,
        })
    end

    -- ========================================================================
    -- Debuff 每帧 Tick
    -- ========================================================================

    --- 每帧更新 debuff 计时器
    GameState.UpdateDebuffs = function(dt, bs)
        -- BuffRegistry 统一处理 19 个简单倒计时 buff
        BuffRegistry.Update(dt, GameState, bs)

        -- ================================================================
        -- 以下为复杂 buff（含周期伤害/子系统交互），需手动处理
        -- ================================================================

        -- 毒蛊叠加 debuff
        if GameState.venomStackTimer > 0 and GameState.venomStackCount > 0 then
            GameState.venomStackTimer = GameState.venomStackTimer - dt
            if GameState.venomStackTimer <= 0 then
                GameState.venomStackCount = 0
                GameState.venomStackDmgPct = 0
                GameState.venomStackTimer = 0
                GameState.venomStackMaxStacks = 0
                GameState.venomStackTickCD = 0
            else
                GameState.venomStackTickCD = GameState.venomStackTickCD - dt
                if GameState.venomStackTickCD <= 0 then
                    GameState.venomStackTickCD = 1.0
                    local maxHP = GameState.GetMaxHP()
                    local venomDmg = math.floor(maxHP * GameState.venomStackDmgPct * GameState.venomStackCount)
                    if venomDmg > 0 then
                        GameState.DamagePlayer(venomDmg)
                    end
                end
            end
        end
        -- 灼烧 debuff (第15章)
        if GameState.blazeTimer > 0 and GameState.blazeStacks > 0 then
            GameState.blazeTimer = GameState.blazeTimer - dt
            if GameState.blazeTimer <= 0 then
                GameState.blazeStacks = 0
                GameState.blazeDmgPct = 0
                GameState.blazeAtkSpdReduce = 0
                GameState.blazeTimer = 0
                GameState.blazeMaxStacks = 0
                GameState.blazeTickCD = 0
                GameState.blazeBossAtk = 0
            else
                GameState.blazeTickCD = GameState.blazeTickCD - dt
                if GameState.blazeTickCD <= 0 then
                    GameState.blazeTickCD = 1.0
                    local blazeDmg = math.floor(GameState.blazeBossAtk * GameState.blazeDmgPct * GameState.blazeStacks)
                    if blazeDmg > 0 then
                        GameState.DamagePlayer(blazeDmg)
                    end
                end
            end
        end
        -- 寒冰甲屏障持续时间
        if GameState.shieldTimer > 0 then
            GameState.shieldTimer = GameState.shieldTimer - dt
            if GameState.shieldTimer <= 0 then
                GameState.shieldTimer = 0
                ShieldManager.Remove("ice_armor")
                GameState.iceArmorActive = false
                GameState.iceArmorFrostbiteTimer = 0
                GameState.iceArmorManaSpent = 0
            end
        end
        -- 火焰护盾持续时间
        if GameState.flameShieldTimer and GameState.flameShieldTimer > 0 then
            GameState.flameShieldTimer = GameState.flameShieldTimer - dt
            if GameState.flameShieldTimer <= 0 then
                GameState.flameShieldTimer = 0
                ShieldManager.Remove("flame_shield")
                -- 神秘火焰护盾: 结束时释放火焰爆炸
                if GameState._flameShieldMystical and bs then
                    local p = bs.playerBattle
                    if p then
                        local H = require("battle.skills.Helpers")
                        local CU = require("battle.CombatUtils")
                        for _, e in ipairs(bs.enemies) do
                            if not e.dead then
                                local dx, dy = e.x - p.x, e.y - p.y
                                if math.sqrt(dx * dx + dy * dy) <= 100 then
                                    H.HitEnemySkill(bs, e, 0.60, "fire", {}, p.x, p.y, CU.KNOCKBACK_SKILL)
                                end
                            end
                        end
                        table.insert(bs.skillEffects, {
                            type = "flame_shield_explode", x = p.x, y = p.y,
                            radius = 100, life = 0.4, maxLife = 0.4,
                        })
                    end
                end
                GameState._flameShieldMystical = false
            end
        end
        -- 深度冻结 CC 免疫计时
        if GameState.ccImmuneTimer > 0 then
            -- 至尊深度冻结: 每2秒生成10点法力
            if GameState._deepFreezeActive and GameState._deepFreezeSupreme then
                GameState._deepFreezeManaTick = (GameState._deepFreezeManaTick or 0) + dt
                if GameState._deepFreezeManaTick >= 2.0 then
                    GameState._deepFreezeManaTick = GameState._deepFreezeManaTick - 2.0
                    local maxMana = GameState.GetMaxMana()
                    GameState.playerMana = math.min(maxMana, GameState.playerMana + 10)
                end
            end
            GameState.ccImmuneTimer = GameState.ccImmuneTimer - dt
            if GameState.ccImmuneTimer <= 0 then
                GameState.ccImmune = false
                GameState.ccImmuneTimer = 0
                -- 深度冻结到期: 结束爆炸
                if GameState._deepFreezeActive then
                    GameState._deepFreezeActive = false
                    local dfBs = GameState._deepFreezeBs
                    local p = dfBs and dfBs.playerBattle
                    if dfBs and p then
                        local px, py = p.x, p.y
                        local burstPct = GameState._deepFreezeBurstPct
                        local radius = GameState._deepFreezeRadius
                        local totalAtk = GameState.GetTotalAtk()
                        local burstDmg = math.floor(totalAtk * burstPct)
                        local DamageFormula = require("battle.DamageFormula")
                        local H = require("battle.skills.Helpers")
                        local Particles = require("battle.Particles")
                        for _, e in ipairs(dfBs.enemies) do
                            if not e.dead then
                                local dx, dy = e.x - px, e.y - py
                                if math.sqrt(dx * dx + dy * dy) <= radius then
                                    local ctx = DamageFormula.BuildContext({
                                        target    = e,
                                        bs        = dfBs,
                                        baseDmg   = burstDmg,
                                        damageTag = "skill",
                                        element   = "ice",
                                    })
                                    local finalDmg = DamageFormula.Calculate(ctx)
                                    local EnemySys = require("battle.EnemySystem")
                                    finalDmg = EnemySys.ApplyDamageReduction(e, finalDmg)
                                    EnemySys.ApplyDamage(e, finalDmg, dfBs)
                                    GameState.LifeStealHeal(finalDmg, Config.LIFESTEAL.efficiency.fireZone)
                                    Particles.SpawnDmgText(dfBs.particles, e.x, e.y - 10, finalDmg, false, false, { 100, 200, 255 })
                                end
                            end
                        end
                        -- 爆炸视觉效果
                        CombatUtils.TriggerShake(dfBs, CombatUtils.SHAKE_BLAST)
                        CombatUtils.PlaySfx("frostImpact", 0.8)
                        table.insert(dfBs.skillEffects, {
                            type = "deep_freeze_burst",
                            x = px, y = py,
                            radius = radius,
                            life = 0.8, maxLife = 0.8,
                        })
                        -- 初级深度冻结: 结束时获得屏障
                        if H.HasEnhance("deep_freeze_prime") then
                            local shieldBase = GameState.GetMaxHP() * 0.50
                            GameState.AddShield(shieldBase, "deep_freeze")
                        end
                    end
                    GameState._deepFreezeBs = nil
                end
            end
        end
        -- 神秘寒冰甲: 周期性冻伤 (每1.5秒)
        if GameState.iceArmorActive and GameState._hasIceArmorMystical then
            GameState.iceArmorFrostbiteTimer = (GameState.iceArmorFrostbiteTimer or 0) + dt
            if GameState.iceArmorFrostbiteTimer >= 1.5 then
                GameState.iceArmorFrostbiteTimer = GameState.iceArmorFrostbiteTimer - 1.5
                -- 对近距离敌人施加冻伤 (实际施加在 BattleSystem tick 中处理)
                GameState._iceArmorFrostbitePending = true
            end
        end
    end

    -- ========================================================================
    -- 药水 Buff 系统
    -- ========================================================================

    --- 购买药水 (叠加时间)
    --- @param typeId string "exp"|"hp"|"atk"|"luck"
    --- @param sizeIdx number 1=小 2=中 3=大
    --- @return boolean success, string|nil error
    GameState.BuyPotion = function(typeId, sizeIdx)
        local sizeCfg = Config.POTION_SIZES[sizeIdx]
        if not sizeCfg then return false, "无效尺寸" end
        local baseCost = Config.POTION_BASE_COST[typeId]
        if not baseCost then return false, "无效类型" end

        local cost = math.floor(baseCost * sizeCfg.costMul)
        if not GameState.SpendGold(cost) then return false, "金币不足" end

        local baseValue = Config.POTION_VALUES[typeId] or 0
        local hpMul = Config.HP_POTION_MUL and Config.HP_POTION_MUL[sizeCfg.id]
        local value = baseValue * ((typeId == "hp" and hpMul) and hpMul or sizeCfg.valueMul)
        local duration = sizeCfg.duration

        local queue = GameState.potionBuffs[typeId]
        if not queue or type(queue) ~= "table" or queue.timer then
            if queue and queue.timer and queue.timer > 0 then
                queue = { { timer = queue.timer, value = queue.value or 0 } }
            else
                queue = {}
            end
            GameState.potionBuffs[typeId] = queue
        end

        local merged = false
        for _, entry in ipairs(queue) do
            if math.abs(entry.value - value) < 0.001 then
                entry.timer = entry.timer + duration
                merged = true
                break
            end
        end

        if not merged then
            table.insert(queue, { timer = duration, value = value })
        end

        table.sort(queue, function(a, b) return a.value > b.value end)

        return true, nil
    end

    --- 更新药水buff计时器 (每帧调用)
    GameState.UpdatePotionBuffs = function(dt)
        for typeId, queue in pairs(GameState.potionBuffs) do
            if type(queue) == "table" and queue.timer then
                if queue.timer > 0 then
                    queue = { { timer = queue.timer, value = queue.value or 0 } }
                else
                    queue = {}
                end
                GameState.potionBuffs[typeId] = queue
            end

            if #queue > 0 then
                local head = queue[1]
                head.timer = head.timer - dt
                if head.timer <= 0 then
                    table.remove(queue, 1)
                end
            end
        end
    end

    --- 获取药水buff效果值 (0 = 无buff)
    GameState.GetPotionBuff = function(typeId)
        local queue = GameState.potionBuffs[typeId]
        if type(queue) == "table" and not queue.timer and #queue > 0 then
            local head = queue[1]
            if head.timer > 0 then return head.value end
        elseif type(queue) == "table" and queue.timer and queue.timer > 0 then
            return queue.value
        end
        return 0
    end

    --- 获取药水剩余总时间
    GameState.GetPotionTimer = function(typeId)
        local queue = GameState.potionBuffs[typeId]
        if type(queue) == "table" and not queue.timer then
            local total = 0
            for _, entry in ipairs(queue) do
                total = total + math.max(0, entry.timer)
            end
            return total
        elseif type(queue) == "table" and queue.timer then
            return math.max(0, queue.timer)
        end
        return 0
    end

    --- 获取指定档位剩余时间
    --- @param typeId string
    --- @param value number 药水效果值
    --- @return number 该档位剩余秒数
    GameState.GetPotionTierTimer = function(typeId, value)
        local queue = GameState.potionBuffs[typeId]
        if type(queue) == "table" and not queue.timer then
            for _, entry in ipairs(queue) do
                if math.abs(entry.value - value) < 0.001 and entry.timer > 0 then
                    return entry.timer
                end
            end
        end
        return 0
    end

    --- 格式化剩余时间显示
    GameState.FormatPotionTimer = function(typeId)
        local secs = GameState.GetPotionTimer(typeId)
        if secs <= 0 then return "" end
        local h = math.floor(secs / 3600)
        local m = math.floor((secs % 3600) / 60)
        local s = math.floor(secs % 60)
        if h > 0 then
            return string.format("%d:%02d:%02d", h, m, s)
        else
            return string.format("%d:%02d", m, s)
        end
    end
    -- ========================================================================
    -- 条件修饰器注册 (buff/debuff, 有 conditionFn)
    -- ========================================================================

    local SM = require("state.StatModifiers")

    -- ---- ATK 修饰器 ----

    -- 铁壁要塞4件: 护盾溢出→ATK加成 (延迟加载BuffManager)
    SM.Register({
        id = "set_ironBastion_atk", stat = "atk", type = "pctPool",
        valueFn = function()
            local ok, BM = pcall(require, "battle.BuffManager")
            if ok and BM.GetIronBastionAtkBonus then
                return BM.GetIronBastionAtkBonus()
            end
            return 0
        end,
    })

    -- 墨汁致盲: -inkBlindRate% ATK
    SM.Register({
        id = "debuff_inkBlind", stat = "atk", type = "pctReduce",
        valueFn = function() return GameState.inkBlindRate or 0 end,
        conditionFn = function() return (GameState.inkBlindTimer or 0) > 0 end,
    })

    -- ---- AtkSpd2 修饰器 (第二类: 触发/临时攻速) ----

    -- 迅捷猎手6件: 连击风暴攻速 (延迟加载BuffManager)
    SM.Register({
        id = "set_swiftHunter_spd", stat = "atkSpd2", type = "flatAdd",
        valueFn = function()
            local ok, BM = pcall(require, "battle.BuffManager")
            if ok and BM.GetSwiftHunterAtkSpeedBonus then
                return BM.GetSwiftHunterAtkSpeedBonus()
            end
            return 0
        end,
    })

    -- 裂变之力6件: 脉冲后攻速 (延迟加载BuffManager)
    SM.Register({
        id = "set_fissionForce_spd", stat = "atkSpd2", type = "flatAdd",
        valueFn = function()
            local ok, BM = pcall(require, "battle.BuffManager")
            if ok and BM.GetFissionForceAtkSpeedBonus then
                return BM.GetFissionForceAtkSpeedBonus()
            end
            return 0
        end,
    })

    -- 减速debuff: 减少第二类攻速
    SM.Register({
        id = "debuff_slow", stat = "atkSpd2", type = "flatSub",
        valueFn = function() return GameState.playerSlowRate or 0 end,
        conditionFn = function() return (GameState.playerSlowTimer or 0) > 0 end,
    })

    -- 孢子云debuff: 减少第二类攻速
    SM.Register({
        id = "debuff_sporeCloud", stat = "atkSpd2", type = "flatSub",
        valueFn = function() return GameState.sporeCloudAtkSpdReduce or 0 end,
        conditionFn = function() return (GameState.sporeCloudTimer or 0) > 0 end,
    })

    -- 灼烧debuff: 叠层×每层攻速降低
    SM.Register({
        id = "debuff_blaze_spd", stat = "atkSpd2", type = "flatSub",
        valueFn = function()
            return (GameState.blazeStacks or 0) * (GameState.blazeAtkSpdReduce or 0)
        end,
        conditionFn = function()
            return (GameState.blazeTimer or 0) > 0 and (GameState.blazeStacks or 0) > 0
        end,
    })

    -- ---- Crit 修饰器 ----

    -- 沙暴debuff: 降低暴击率
    SM.Register({
        id = "debuff_sandStorm", stat = "crit", type = "flatSub",
        valueFn = function() return GameState.sandStormCritReduce or 0 end,
        conditionFn = function() return (GameState.sandStormTimer or 0) > 0 end,
    })

    -- 浸蚀debuff: 叠层×每层暴击降低 (第16章)
    SM.Register({
        id = "debuff_drench", stat = "crit", type = "flatSub",
        valueFn = function()
            return (GameState.drenchStacks or 0) * (GameState.drenchCritReduce or 0)
        end,
        conditionFn = function()
            return (GameState.drenchTimer or 0) > 0 and (GameState.drenchStacks or 0) > 0
        end,
    })
end

return BuffRuntime
