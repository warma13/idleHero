local Combat = {}

function Combat.Install(GameState)
    local Config = require("Config")
    local AffixHelper = require("state.AffixHelper")
    local ShieldManager = require("state.ShieldManager")

    -- ========================================================================
    -- Player Health System
    -- ========================================================================

    --- 重置HP到满血 (关卡开始/死亡重试时调用)
    GameState.ResetHP = function()
        GameState.playerHP = GameState.GetMaxHP()
        GameState.playerDead = false
        GameState.lifeStealAccum = 0
        GameState.lifeStealTimer = 0
        GameState.ResetBuffs()  -- buff/debuff 状态统一由 BuffRuntime 重置
    end

    --- 玩家受伤 (先扣护盾再扣HP, 考虑DEF减免)
    --- @param rawDmg number 原始伤害
    --- @param monsterLevel number|nil 攻击者怪物等级 (v3.1, nil=自动推算)
    --- @return number actualDmg 实际伤害
    --- @return boolean isDodged 是否闪避
    GameState.DamagePlayer = function(rawDmg, monsterLevel)
        if GameState.playerDead then return 0, false end

        -- 极寒之心4件: 无敌状态
        local ok_bm, BuffManager = pcall(require, "battle.BuffManager")
        if ok_bm and BuffManager.IsPermafrostInvulnerable and BuffManager.IsPermafrostInvulnerable() then
            return 0, false
        end

        -- 焚灼debuff: 受伤增幅 (第15章)
        if GameState.scorchStacks > 0 and GameState.scorchDmgAmp > 0 and GameState.scorchTimer > 0 then
            rawDmg = math.floor(rawDmg * (1 + GameState.scorchStacks * GameState.scorchDmgAmp))
        end

        -- P1 闪避判定 (DEX 通用效果, 在 DEF 减免之前)
        local dodgeChance = GameState.GetDodgeChance()
        if dodgeChance > 0 and math.random() < dodgeChance then
            return 0, true
        end

        -- 引导打断: 被命中时尝试打断引导 (闪避的不算)
        local ok_ch, ChannelSystem = pcall(require, "battle.ChannelSystem")
        if ok_ch and ChannelSystem.TryInterrupt then
            ChannelSystem.TryInterrupt()
        end

        -- DEF减免 (v3.1: K 随怪物等级缩放)
        local dmg = math.max(1, math.floor(rawDmg * GameState.GetDEFMul(monsterLevel)))

        -- 套装减伤: 冰甲 + 熔铠 + 怨魂 (统一上限80%)
        if ok_bm and BuffManager.GetTotalSetDmgReduce then
            local setReduce = BuffManager.GetTotalSetDmgReduce()
            if setReduce > 0 then
                dmg = math.max(1, math.floor(dmg * (1 - setReduce)))
            end
        end

        -- 词缀: 绝境 (生命低于20%时减伤)
        local lastStandVal = AffixHelper.GetAffixValue("last_stand")
        if lastStandVal > 0 and GameState.playerHP < GameState.GetMaxHP() * 0.20 then
            dmg = math.max(1, math.floor(dmg * (1 - lastStandVal)))
        end

        -- 闪光传送: 30%伤害减免 (3秒)
        if (GameState._teleportDmgReduceTimer or 0) > 0 then
            dmg = math.max(1, math.floor(dmg * 0.70))
        end

        -- 铁壁要塞2件: 受击获得护盾
        if ok_bm and BuffManager.TryIronBastionShield then
            BuffManager.TryIronBastionShield(nil, dmg)
        end

        -- 先扣护盾
        local totalShield = ShieldManager.GetTotal()
        if totalShield > 0 then
            local absorbed, remaining = ShieldManager.Absorb(dmg)
            if remaining <= 0 then
                return dmg, false
            else
                -- 护盾被击穿
                if absorbed > 0 and ok_bm and BuffManager.OnIronBastionShieldBreak then
                    local BattleSystem = require("BattleSystem")
                    BuffManager.OnIronBastionShieldBreak(BattleSystem, absorbed)
                end
                dmg = remaining
            end
        end

        -- 致命保护检测 (HP 将降为0时触发)
        if GameState.playerHP - dmg <= 0 then
            if not ok_bm then
                ok_bm, BuffManager = pcall(require, "battle.BuffManager")
            end
            if ok_bm and BuffManager then
                -- 极寒之心4件: 致命保护
                if BuffManager.CheckPermafrostFatalProtect then
                    local permafrostProtected = BuffManager.CheckPermafrostFatalProtect(
                        require("BattleSystem"), dmg)
                    if permafrostProtected then
                        return dmg, false
                    end
                end
            end
        end

        -- 扣HP
        GameState.playerHP = GameState.playerHP - dmg
        if GameState.playerHP <= 0 then
            GameState.playerHP = 0
            GameState.playerDead = true
        end
        return dmg, false
    end

    --- 玩家治疗 (走统一治疗管线: base × HEAL% × (1 - antiHeal))
    --- @param baseHeal number 基础治疗量
    --- @return number 实际回血量
    GameState.HealPlayer = function(baseHeal)
        if GameState.playerDead then return 0 end
        local healMul = GameState.GetHealMul()
        local antiHeal = GameState.antiHealRate or 0
        local actual = math.floor(baseHeal * healMul * (1 - antiHeal))
        if actual <= 0 then return 0 end
        local maxHP = GameState.GetMaxHP()
        local before = GameState.playerHP
        GameState.playerHP = math.min(maxHP, GameState.playerHP + actual)
        return GameState.playerHP - before
    end

    --- 玩家吸血 (走统一治疗管线 + 每秒上限)
    --- @param baseDmg number 造成的伤害
    --- @param efficiency number 吸血效率系数
    --- @return number 实际回血量
    GameState.LifeStealHeal = function(baseDmg, efficiency)
        if GameState.playerDead then return 0 end
        local lsPct = GameState.GetLifeSteal()
        if lsPct <= 0 then return 0 end
        local rawHeal = baseDmg * lsPct * efficiency
        -- 每秒吸血上限
        local maxPerSec = GameState.GetMaxHP() * Config.LIFESTEAL.maxPctPerSec
        local remaining = maxPerSec - GameState.lifeStealAccum
        if remaining <= 0 then return 0 end
        rawHeal = math.min(rawHeal, remaining)
        local healed = GameState.HealPlayer(rawHeal)
        GameState.lifeStealAccum = GameState.lifeStealAccum + healed
        return healed
    end

    --- 每帧更新吸血计时器 (BattleSystem调用)
    GameState.UpdateLifeStealTimer = function(dt)
        GameState.lifeStealTimer = GameState.lifeStealTimer + dt
        if GameState.lifeStealTimer >= 1.0 then
            GameState.lifeStealTimer = GameState.lifeStealTimer - 1.0
            GameState.lifeStealAccum = 0
        end
    end

    --- 每秒回血 tick (BattleSystem调用)
    GameState.TickHPRegen = function(dt)
        if GameState.playerDead then return end
        local regen = GameState.GetHPRegen()
        if regen > 0 then
            GameState.HealPlayer(regen * dt)
        end
    end

    -- ========================================================================
    -- Player Mana System (D4 法力资源)
    -- ========================================================================

    --- 重置法力到满蓝 (关卡开始/死亡重试时调用)
    GameState.ResetMana = function()
        GameState.playerMana = GameState.GetMaxMana()
    end

    --- 每秒法力回复 tick (BattleSystem调用)
    GameState.TickManaRegen = function(dt)
        if GameState.playerDead then return end
        local maxMana = GameState.GetMaxMana()
        if GameState.playerMana >= maxMana then return end
        local regen = GameState.GetManaRegen()
        if regen > 0 then
            GameState.playerMana = math.min(maxMana, GameState.playerMana + regen * dt)
        end
    end

    --- 是否有足够法力
    --- @param cost number 法力消耗量
    --- @return boolean
    GameState.HasMana = function(cost)
        return GameState.playerMana >= cost
    end

    --- 消耗法力 (先检查再扣除)
    --- @param cost number 法力消耗量
    --- @return boolean 是否成功消耗
    GameState.SpendMana = function(cost)
        if GameState.playerMana >= cost then
            GameState.playerMana = GameState.playerMana - cost
            -- 微光寒冰甲: 每花费50法力减1秒CD
            if GameState.iceArmorActive and GameState._hasIceArmorShimmering then
                GameState.iceArmorManaSpent = (GameState.iceArmorManaSpent or 0) + cost
                local threshold = 50
                while GameState.iceArmorManaSpent >= threshold do
                    GameState.iceArmorManaSpent = GameState.iceArmorManaSpent - threshold
                    GameState._iceArmorCdrPending = (GameState._iceArmorCdrPending or 0) + 1.0
                end
            end
            return true
        end
        return false
    end

    --- 回复法力 (不超过上限)
    --- @param amount number 法力回复量
    GameState.AddMana = function(amount)
        local maxMana = GameState.GetMaxMana()
        GameState.playerMana = math.min(maxMana, GameState.playerMana + amount)
    end

    -- Debuff 施加/更新/护盾/OnKillShield 已迁移至 state/BuffRuntime.lua

    -- ========================================================================
    -- Element Resistance (v3.0 D4模型: 保留抗性, 移除反应)
    -- ========================================================================

    --- 获取指定元素的抗性 (0~1)
    --- @param element string 元素类型
    --- @return number 抗性值
    GameState.GetElementResist = function(element)
        if not element then return 0 end
        local base = Config.ELEMENTS.baseResist[element] or 0
        -- 装备抗性词条: fire → fireRes
        local statKey = element .. "Res"
        local fromEquip = GameState._equipSum(statKey)
        -- 套装抗性加成: bonus.resist = { ice = 0.25 }
        local fromSet = 0
        local counts = GameState.GetEquippedSetCounts()
        for setId, count in pairs(counts) do
            local setCfg = Config.EQUIP_SET_MAP[setId]
            if setCfg then
                for threshold, bonus in pairs(setCfg.bonuses) do
                    if count >= threshold and bonus.resist and bonus.resist[element] then
                        fromSet = fromSet + bonus.resist[element]
                    end
                end
            end
        end
        -- P1 全抗: INT 通用效果, 与单抗加算
        local allResist = GameState.GetAllResist()
        return base + fromEquip + fromSet + allResist
    end

    --- 计算元素伤害减免后的实际伤害
    --- v3.1: 接入世界层级抗性穿透
    --- @param rawDmg number 原始伤害
    --- @param element string|nil 元素类型
    --- @return number 实际伤害
    GameState.CalcElementDamage = function(rawDmg, element)
        if not element or element == "physical" then
            return rawDmg
        end
        local resist = GameState.GetElementResist(element)
        -- 世界层级穿透 (T1=0%, T2=5%, T3=10%, T4=15%)
        local worldTierId = 1
        if GameState.spireTrial and GameState.spireTrial.worldTier then
            worldTierId = GameState.spireTrial.worldTier
        end
        local DF = require("DefenseFormula")
        local effectiveResist = DF.CalcEffectiveResist(resist, worldTierId)
        return math.max(1, math.floor(rawDmg * DF.ResistMul(effectiveResist)))
    end

    --- STUB: 玩家元素附着+反应 (v3.0 已移除反应系统)
    GameState.ApplyElementAndReact = function(element, rawDmg, attachGrade)
        return nil, rawDmg
    end

    --- STUB: 敌人元素附着+反应 (v3.0 已移除反应系统)
    GameState.ApplyEnemyElementAndReact = function(enemy, element, rawDmg, attachGrade)
        return nil, rawDmg
    end

end

return Combat
