-- ============================================================================
-- battle/EliteSystem.lua - 精英/冠军系统 (v3.0)
-- ============================================================================
-- 职责:
--   1. RollElite     — 生成时掷骰决定精英/冠军
--   2. ApplyElite    — 属性倍率 + 词缀分配
--   3. UpdateAffixes — 逐帧词缀行为 (再生/护盾/燃烧/传送/狂热等)
--   4. OnEnemyHit    — 受击词缀 (荆棘/不死)
--   5. ModifyAttack  — 攻击词缀 (狂暴/穿甲/猎杀/吸血/冰封/缠绕/闪电链)
--   6. OnEliteDeath  — 死亡词缀 (爆裂)
--
-- 依赖: FamilyConfig (静态数据), EnemySystem (ApplyDamage), GameState, Particles
-- ============================================================================

local FamilyConfig = require("FamilyConfig")
local GameState    = require("GameState")

local EliteSystem = {}

-- ============================================================================
-- 内部工具
-- ============================================================================

local function hasAffix(enemy, affixId)
    if not enemy.eliteAffixes then return false end
    for _, id in ipairs(enemy.eliteAffixes) do
        if id == affixId then return true end
    end
    return false
end

local function getResonanceMul(enemy, affixId)
    if not enemy.familyType then return 1.0 end
    local _, mul = FamilyConfig.IsResonant(enemy.familyType, affixId)
    return mul
end

-- ============================================================================
-- 1. 精英掷骰: 生成时调用, 决定是否升级为精英/冠军
-- ============================================================================

--- 掷骰决定敌人是否成为精英/冠军, 并应用属性+词缀
--- Boss 不参与掷骰
---@param enemy table  刚创建的敌人对象 (需要已有 familyType)
---@param chapter number 当前章节
function EliteSystem.RollElite(enemy, chapter)
    if enemy.isBoss then return end
    if enemy.eliteRank then return end  -- 已由模板预设

    local eliteChance, champChance = FamilyConfig.GetEliteChance(chapter)
    local roll = math.random()

    if roll < champChance then
        enemy.eliteRank = "champion"
    elseif roll < champChance + eliteChance then
        enemy.eliteRank = "elite"
    else
        return  -- 普通怪
    end

    EliteSystem.ApplyElite(enemy)
end

-- ============================================================================
-- 2. 应用精英属性 + 词缀
-- ============================================================================

---@param enemy table
function EliteSystem.ApplyElite(enemy)
    local rank = enemy.eliteRank
    if not rank then return end

    local tier = FamilyConfig.ELITE_TIERS[rank]
    if not tier then return end

    -- 属性倍率
    enemy.maxHp = math.floor(enemy.maxHp * tier.hpMul)
    enemy.hp    = enemy.maxHp
    enemy.atk   = math.floor(enemy.atk * tier.atkMul)
    enemy.def   = math.floor((enemy.def or 0) + tier.defAdd)

    -- 体型
    enemy._eliteSizeMul = tier.sizeMul

    -- 暴击 (精英怪自身暴击)
    enemy._eliteCritRate = tier.critRate
    enemy._eliteCritMul  = tier.critMul

    -- 显示
    enemy._eliteLabel     = tier.label
    enemy._eliteNameColor = tier.nameColor

    -- 掷词缀
    EliteSystem.RollAffixes(enemy, tier)

    -- 词缀即时效果
    EliteSystem._applyPassiveAffixes(enemy)
end

-- ============================================================================
-- 3. 词缀掷骰
-- ============================================================================

---@param enemy table
---@param tier EliteTierDef
function EliteSystem.RollAffixes(enemy, tier)
    if enemy.eliteAffixes and #enemy.eliteAffixes > 0 then return end -- 模板预设

    local count = math.random(tier.affixMin, tier.affixMax)
    local pool  = {}
    for _, id in ipairs(FamilyConfig.ALL_AFFIX_IDS) do
        pool[#pool + 1] = id
    end

    -- Fisher-Yates 洗牌取前 count 个
    local picked = {}
    for i = 1, math.min(count, #pool) do
        local j = math.random(i, #pool)
        pool[i], pool[j] = pool[j], pool[i]
        picked[#picked + 1] = pool[i]
    end

    enemy.eliteAffixes = picked
end

-- ============================================================================
-- 4. 词缀被动效果 (生成时一次性应用)
-- ============================================================================

function EliteSystem._applyPassiveAffixes(enemy)
    if not enemy.eliteAffixes then return end

    for _, affixId in ipairs(enemy.eliteAffixes) do
        local rMul = getResonanceMul(enemy, affixId)

        if affixId == "berserker" then
            -- ATK+40%, 攻速+30% (共鸣: beasts 额外+20%攻速)
            enemy.atk = math.floor(enemy.atk * 1.4)
            local spdBonus = 0.30
            if rMul > 1.0 then spdBonus = spdBonus + 0.20 end
            enemy.atkCd = enemy.atkCd / (1 + spdBonus)

        elseif affixId == "iron_wall" then
            -- DEF+50%, 免疫击退和控制
            enemy.def = math.floor((enemy.def or 0) * 1.5)
            enemy._immuneKnockback = true
            enemy._immuneControl   = true

        elseif affixId == "blind" then
            -- 降低玩家暴击率30% (光环, 存在时生效)
            enemy._blindAura = true

        elseif affixId == "armor_pierce" then
            -- 无视30%防御 (攻击时使用)
            enemy._affixArmorPierce = 0.30 * rMul

        elseif affixId == "shield" then
            -- 护盾初始化
            local shieldPct = 0.20 * rMul  -- 共鸣: constructs 30%
            enemy._shieldMax     = math.floor(enemy.maxHp * shieldPct)
            enemy._shieldHp      = enemy._shieldMax
            enemy._shieldTimer   = 10.0
            enemy._shieldCooldown = 10.0

        elseif affixId == "frenzy" then
            -- 初始攻速记录
            enemy._baseAtkCd = enemy.atkCd
        end
    end
end

-- ============================================================================
-- 5. 逐帧词缀更新
-- ============================================================================

--- 每帧调用, 处理持续性词缀效果
---@param bs table BattleSystem
---@param enemy table
---@param dt number deltaTime
function EliteSystem.UpdateAffixes(bs, enemy, dt)
    if not enemy.eliteAffixes or enemy.dead then return end

    for _, affixId in ipairs(enemy.eliteAffixes) do
        local rMul = getResonanceMul(enemy, affixId)

        -- ── 再生: 每秒回 2% HP ──
        if affixId == "regen" then
            enemy._regenAccum = (enemy._regenAccum or 0) + dt
            if enemy._regenAccum >= 1.0 then
                enemy._regenAccum = enemy._regenAccum - 1.0
                local heal = math.floor(enemy.maxHp * 0.02 * rMul)
                enemy.hp = math.min(enemy.maxHp, enemy.hp + heal)
            end

        -- ── 护盾: 每 10 秒生成 20% HP 护盾 ──
        elseif affixId == "shield" then
            if enemy._shieldHp <= 0 then
                enemy._shieldTimer = (enemy._shieldTimer or 0) - dt
                if enemy._shieldTimer <= 0 then
                    local shieldPct = 0.20 * rMul
                    enemy._shieldMax   = math.floor(enemy.maxHp * shieldPct)
                    enemy._shieldHp    = enemy._shieldMax
                    enemy._shieldTimer = enemy._shieldCooldown
                end
            end

        -- ── 燃烧: 脚下留火焰区 DOT ──
        elseif affixId == "burning" then
            enemy._burnZoneTimer = (enemy._burnZoneTimer or 0) - dt
            if enemy._burnZoneTimer <= 0 then
                enemy._burnZoneTimer = 2.0  -- 每 2 秒刷新火区
                -- 在 bs.fireZones 中添加火焰区
                local dotPct = 0.03 * rMul
                table.insert(bs.fireZones, {
                    x = enemy.x, y = enemy.y,
                    radius = 30 * rMul,
                    life = 3.0,
                    maxLife = 3.0,
                    dmgPerSec = math.floor(enemy.atk * dotPct),
                    element = "fire",
                    source = "elite_burning",
                })
            end

        -- ── 传送: 定期闪现到玩家身边 ──
        elseif affixId == "teleport" then
            local cd = 6.0
            if rMul > 1.0 then cd = cd / rMul end  -- 共鸣: voidborn 间隔减半
            enemy._teleportTimer = (enemy._teleportTimer or cd) - dt
            if enemy._teleportTimer <= 0 then
                enemy._teleportTimer = cd
                local p = bs.playerBattle
                if p then
                    local angle = math.random() * math.pi * 2
                    local dist = 30 + math.random() * 20
                    enemy.x = math.max(30, math.min(bs.areaW - 30, p.x + math.cos(angle) * dist))
                    enemy.y = math.max(30, math.min(bs.areaH - 30, p.y + math.sin(angle) * dist))
                    -- 闪现特效标记
                    enemy._teleportFlash = 0.3
                end
            end
            if enemy._teleportFlash and enemy._teleportFlash > 0 then
                enemy._teleportFlash = enemy._teleportFlash - dt
            end

        -- ── 召唤: 定期召唤 2 只小怪 ──
        elseif affixId == "summoner" then
            enemy._summonTimer = (enemy._summonTimer or 8.0) - dt
            if enemy._summonTimer <= 0 then
                enemy._summonTimer = 12.0  -- 每 12 秒召唤
                local summonCount = 2
                for i = 1, summonCount do
                    local angle = (i / summonCount) * math.pi * 2
                    local sx = math.max(30, math.min(bs.areaW - 30, enemy.x + math.cos(angle) * 30))
                    local sy = math.max(30, math.min(bs.areaH - 30, enemy.y + math.sin(angle) * 30))
                    -- 召唤体: 精英 30% 属性的小怪
                    local minion = {
                        x = sx, y = sy,
                        hp = math.floor(enemy.maxHp * 0.15),
                        maxHp = math.floor(enemy.maxHp * 0.15),
                        atk = math.floor(enemy.atk * 0.20),
                        speed = enemy.speed * 1.2,
                        radius = math.max(8, (enemy.radius or 12) * 0.6),
                        def = 0, atkTimer = 0,
                        atkCd = enemy.atkCd * 1.2,
                        atkRange = enemy.atkRange or 35,
                        element = enemy.element or "physical",
                        color = enemy.color and { enemy.color[1], enemy.color[2], enemy.color[3] } or { 180, 100, 220 },
                        name = "召唤物", isBoss = false, dead = false,
                        expDrop = 0, goldMin = 0, goldMax = 0,
                        knockbackVx = 0, knockbackVy = 0,
                        weight = 0.5,
                        attachedElement = nil, attachedElementTimer = 0,
                        defReduceRate = 0, defReduceTimer = 0,
                        elemWeakenRate = 0, elemWeakenTimer = 0,
                        _isSummon = true,  -- 标记: 召唤物不计击杀/掉落
                        familyType = enemy.familyType,
                        familyId   = enemy.familyId,
                    }
                    table.insert(bs.enemies, minion)
                end
            end

        -- ── 狂热: 生命越低攻速越快 ──
        elseif affixId == "frenzy" then
            local hpRatio = enemy.hp / enemy.maxHp
            -- 线性加速: 100% HP → 0%加速, 0% HP → +100%加速
            local speedMul = 1.0 + (1.0 - hpRatio) * rMul
            enemy.atkCd = (enemy._baseAtkCd or enemy.atkCd) / speedMul

        -- ── 领袖: 光环 ATK+25% 给附近同伴 ──
        elseif affixId == "leader" then
            enemy._leaderAuraTimer = (enemy._leaderAuraTimer or 0) - dt
            if enemy._leaderAuraTimer <= 0 then
                enemy._leaderAuraTimer = 1.0  -- 每秒刷新
                local buffPct = 0.25 * rMul
                local auraRange = 80 * rMul
                for _, e2 in ipairs(bs.enemies) do
                    if e2 ~= enemy and not e2.dead then
                        local dx = e2.x - enemy.x
                        local dy = e2.y - enemy.y
                        if dx * dx + dy * dy <= auraRange * auraRange then
                            e2._leaderBuff     = buffPct
                            e2._leaderBuffTimer = 1.5  -- 持续 1.5 秒
                        end
                    end
                end
            end
        end
    end

    -- 领袖 buff 衰减 (所有敌人)
    if enemy._leaderBuffTimer then
        enemy._leaderBuffTimer = enemy._leaderBuffTimer - dt
        if enemy._leaderBuffTimer <= 0 then
            enemy._leaderBuff = nil
            enemy._leaderBuffTimer = nil
        end
    end

    -- 传送闪光衰减
    if enemy._teleportFlash and enemy._teleportFlash <= 0 then
        enemy._teleportFlash = nil
    end
end

-- ============================================================================
-- 6. 受击词缀处理
-- ============================================================================

--- 精英怪受击时调用 (在 ApplyDamage 之后)
---@param bs table BattleSystem
---@param enemy table
---@param dmg number 实际造成的伤害
function EliteSystem.OnEnemyHit(bs, enemy, dmg)
    if not enemy.eliteAffixes or enemy.dead then return end

    -- ── 荆棘: 反弹 15% 伤害 ──
    if hasAffix(enemy, "thorns") then
        local rMul = getResonanceMul(enemy, "thorns")
        local reflectDmg = math.floor(dmg * 0.15 * rMul)
        if reflectDmg > 0 and not GameState.playerDead then
            GameState.DamagePlayer(reflectDmg)
            -- 反弹飘字由视图层处理
        end
    end

    -- ── 护盾: 吸收伤害 ──
    -- (护盾吸收逻辑需要在 ApplyDamage 之前, 见 AbsorbShield)
end

--- 护盾吸收 (在 ApplyDamage 之前调用)
--- 返回剩余穿透伤害
---@param enemy table
---@param dmg number
---@return number remainDmg
function EliteSystem.AbsorbShield(enemy, dmg)
    if not enemy._shieldHp or enemy._shieldHp <= 0 then
        return dmg
    end
    if enemy._shieldHp >= dmg then
        enemy._shieldHp = enemy._shieldHp - dmg
        return 0
    else
        local remain = dmg - enemy._shieldHp
        enemy._shieldHp = 0
        return remain
    end
end

--- 不死词缀: 首次致命伤拦截
--- 在 hp <= 0 时调用, 返回 true 表示阻止死亡
---@param enemy table
---@return boolean saved
function EliteSystem.CheckUndying(enemy)
    if not hasAffix(enemy, "undying") then return false end
    if enemy._undyingUsed then return false end

    enemy._undyingUsed = true
    local rMul = getResonanceMul(enemy, "undying")
    local healPct = 0.30 * rMul  -- 共鸣: undead 50%
    enemy.hp = math.floor(enemy.maxHp * healPct)
    enemy.dead = false
    enemy._undyingFlash = 0.5  -- 视觉特效标记
    return true
end

-- ============================================================================
-- 7. 攻击修正
-- ============================================================================

--- 修正精英怪攻击伤害 (在 EnemyAttackPlayer 中调用)
---@param bs table BattleSystem
---@param enemy table
---@param rawDmg number 原始攻击力
---@return number modifiedDmg
function EliteSystem.ModifyAttack(bs, enemy, rawDmg)
    if not enemy.eliteAffixes then return rawDmg end
    local dmg = rawDmg

    -- 领袖光环 buff
    if enemy._leaderBuff then
        dmg = math.floor(dmg * (1 + enemy._leaderBuff))
    end

    -- 猎杀: 目标 < 30% HP 伤害+60%
    if hasAffix(enemy, "execute") then
        local playerHpRatio = (GameState.playerHP or 1) / (GameState.playerMaxHP or 1)
        if playerHpRatio < 0.30 then
            local rMul = getResonanceMul(enemy, "execute")
            dmg = math.floor(dmg * (1 + 0.60 * rMul))
        end
    end

    -- 精英暴击
    if enemy._eliteCritRate and enemy._eliteCritRate > 0 then
        if math.random() < enemy._eliteCritRate then
            dmg = math.floor(dmg * (enemy._eliteCritMul or 1.5))
            enemy._lastHitCrit = true
        end
    end

    return dmg
end

--- 攻击后效果 (吸血/冰封/缠绕/爆裂AOE/闪电链)
--- 在 EnemyAttackPlayer 命中后调用
---@param bs table BattleSystem
---@param enemy table
---@param actualDmg number 实际造成的伤害
function EliteSystem.OnAttackHit(bs, enemy, actualDmg)
    if not enemy.eliteAffixes or enemy.dead then return end

    local p = bs.playerBattle
    if not p then return end

    for _, affixId in ipairs(enemy.eliteAffixes) do
        local rMul = getResonanceMul(enemy, affixId)

        -- ── 吸血: 伤害 10% 回血 ──
        if affixId == "lifesteal" then
            local heal = math.floor(actualDmg * 0.10 * rMul)
            enemy.hp = math.min(enemy.maxHp, enemy.hp + heal)

        -- ── 冰封: 叠寒冷, 满层冻结 ──
        elseif affixId == "frozen" then
            GameState._eliteFrostStacks = (GameState._eliteFrostStacks or 0) + 1
            if GameState._eliteFrostStacks >= 5 then
                GameState._eliteFrostStacks = 0
                GameState.ApplySlowDebuff(0.95, 2.0 * rMul)  -- 冻结=极限减速
                -- 冻结期间受伤+25%
                GameState._frozenVulnTimer = 2.0 * rMul
                GameState._frozenVulnRate  = 0.25
            end

        -- ── 缠绕: 25% 概率定身 2 秒 ──
        elseif affixId == "entangle" then
            if math.random() < 0.25 then
                local dur = 2.0
                -- 共鸣: venomkin 期间叠 2 层蚀毒
                if rMul > 1.0 then
                    GameState._venomEntangleStacks = (GameState._venomEntangleStacks or 0) + 2
                end
                GameState.ApplySlowDebuff(1.0, dur)  -- 定身=100%减速
            end

        -- ── 减速: 降低移速 40% ──
        elseif affixId == "slow" then
            local slowPct = 0.40 * rMul  -- 共鸣: drowned 60%
            GameState.ApplySlowDebuff(slowPct, 2.0)

        -- ── 爆裂: 20% 概率范围爆炸 ──
        elseif affixId == "explosive" then
            if math.random() < 0.20 then
                local aoeRadius = 40 * rMul
                local aoeDmg = math.floor(actualDmg * 0.50)
                -- 对玩家造成额外 AOE 伤害
                if not GameState.playerDead then
                    GameState.DamagePlayer(aoeDmg)
                end
                -- 爆炸视觉标记
                table.insert(bs.bossSkillEffects, {
                    type = "eliteExplosion",
                    x = p.x, y = p.y,
                    radius = aoeRadius,
                    life = 0.4, maxLife = 0.4,
                })
            end

        -- ── 闪电链: 弹射 3 个目标 (对玩家多段伤害) ──
        elseif affixId == "chain_lightning" then
            local chainDmg = math.floor(actualDmg * 0.30 * rMul)
            local chains = 3
            for _ = 1, chains do
                if not GameState.playerDead then
                    GameState.DamagePlayer(chainDmg)
                end
            end
            -- 闪电视觉标记
            enemy._chainLightningFlash = 0.3
        end
    end
end

-- ============================================================================
-- 8. 死亡词缀
-- ============================================================================

--- 精英死亡时调用
---@param bs table BattleSystem
---@param enemy table
function EliteSystem.OnEliteDeath(bs, enemy)
    if not enemy.eliteAffixes then return end

    -- ── 爆裂: 死亡爆炸 ──
    if hasAffix(enemy, "explosive") then
        local rMul = getResonanceMul(enemy, "explosive")
        local radius = 50 * rMul
        local p = bs.playerBattle
        if p then
            local dx = p.x - enemy.x
            local dy = p.y - enemy.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist <= radius and not GameState.playerDead then
                local dmg = math.floor(enemy.atk * 0.80)
                GameState.DamagePlayer(dmg)
            end
            table.insert(bs.bossSkillEffects, {
                type = "eliteDeathExplosion",
                x = enemy.x, y = enemy.y,
                radius = radius,
                life = 0.6, maxLife = 0.6,
            })
        end
    end
end

-- ============================================================================
-- 9. 致盲光环查询 (PlayerAI/DamageFormula 调用)
-- ============================================================================

--- 检查玩家附近是否有致盲精英, 返回暴击率降低值
---@param bs table BattleSystem
---@return number critReduction 暴击率降低量 (0~0.30)
function EliteSystem.GetBlindReduction(bs)
    local reduction = 0
    for _, e in ipairs(bs.enemies) do
        if not e.dead and e._blindAura then
            reduction = math.max(reduction, 0.30)
            break  -- 不叠加
        end
    end
    return reduction
end

-- ============================================================================
-- 10. 穿甲查询 (EnemyAttackPlayer 中使用)
-- ============================================================================

--- 返回精英怪的穿甲率
---@param enemy table
---@return number piercePct 0~1
function EliteSystem.GetArmorPierce(enemy)
    return enemy._affixArmorPierce or 0
end

-- ============================================================================
-- 11. Install 注册到 GameState
-- ============================================================================

function EliteSystem.Install(GS)
    GS.EliteSystem = EliteSystem
end

return EliteSystem
