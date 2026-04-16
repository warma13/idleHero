-- ============================================================================
-- battle/FamilyMechanics.lua - 10 家族战斗机制运行时 (v3.0)
-- ============================================================================
-- 职责:
--   1. Init/Reset      — 初始化/重置 familyState
--   2. Update          — 逐帧: 潮池/孢子云/领袖光环/群猎检测/恐慌AI/虚空闪移 等
--   3. OnEnemyDeath    — 死亡钩子: 分裂(swarm)/复活排队(undead)/碎裂(constructs)
--                         /献祭(cult)/孢子爆发(fungal)
--   4. OnEnemySpawned  — 生成钩子: 恶魔首领检测(fiends)
--   5. IsUntargetable  — 查询: 虚空相位中不可选中
--   6. ModifyIncomingDmg — 伤害修正: 虚空AOE减伤
--
-- 依赖: FamilyConfig(参数), EnemySystem(ApplyDamage), GameState, Particles
-- ============================================================================

local FamilyConfig = require("FamilyConfig")
local GameState    = require("GameState")
local EnemyAnim    = require("battle.EnemyAnim")

local FM = {}

-- ============================================================================
-- familyState: 每局战斗共享的家族机制状态
-- ============================================================================

---@class FamilyState
---@field tidePools table[]         活跃的潮池列表
---@field sporeClouds table[]       活跃的孢子云列表
---@field revivePending table[]     待复活的亡灵
---@field sacrificeBuffs table[]    活跃的献祭增益
---@field packHuntActive boolean    群猎激活
---@field leaderAlive table|nil     当前领袖引用
---@field panicTimer number         恐慌计时器
---@field panicPhase string|nil     恐慌阶段

---@type FamilyState|nil
local state = nil

function FM.Init()
    state = {
        tidePools     = {},
        sporeClouds   = {},
        revivePending = {},
        sacrificeBuffs = {},
        packHuntActive = false,
        leaderAlive   = nil,
        panicTimer    = 0,
        panicPhase    = nil,   -- nil | "panic" | "flee" | "debuff"
    }
end

function FM.Reset()
    state = nil
end

function FM.GetState()
    return state
end

-- ============================================================================
-- 内部工具
-- ============================================================================

local function dist2(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return dx * dx + dy * dy
end

local function countFamilyType(bs, fType, excludeDead)
    local n = 0
    for _, e in ipairs(bs.enemies) do
        if e.familyType == fType and (not excludeDead or not e.dead) then
            n = n + 1
        end
    end
    return n
end

-- ============================================================================
-- 2. Update (逐帧)
-- ============================================================================

---@param bs table BattleSystem
---@param dt number
function FM.Update(bs, dt)
    if not state then return end

    FM._updateTidePools(bs, dt)
    FM._updateSporeClouds(bs, dt)
    FM._updatePackHunt(bs, dt)
    FM._updateFiendsPanic(bs, dt)
    FM._updateVoidbornBlink(bs, dt)
    FM._updateUndeadRevive(bs, dt)
    FM._updateSacrificeBuffs(bs, dt)
    FM._updateConstructReassemble(bs, dt)
    FM._updateVenomStacking(bs, dt)
end

-- ── 潮池 (drowned) ──────────────────────────────────────────────────────

function FM._updateTidePools(bs, dt)
    local params = FamilyConfig.MECHANIC_PARAMS.drowned
    local p = bs.playerBattle
    if not p then return end

    -- 存活时间衰减
    for i = #state.tidePools, 1, -1 do
        local pool = state.tidePools[i]
        pool.life = pool.life - dt
        if pool.life <= 0 then
            table.remove(state.tidePools, i)
        else
            -- 玩家在池中: 减速 + DOT
            local d2 = (p.x - pool.x) ^ 2 + (p.y - pool.y) ^ 2
            if d2 <= pool.radius ^ 2 and not GameState.playerDead then
                GameState.ApplySlowDebuff(params.poolSlowPct, 0.5)
                pool._dotTimer = (pool._dotTimer or 0) - dt
                if pool._dotTimer <= 0 then
                    pool._dotTimer = 1.0
                    local dmg = math.floor(pool.dotDmg)
                    GameState.DamagePlayer(dmg)
                end
            end
            -- 海民在池中: 移速+/DEF+
            for _, e in ipairs(bs.enemies) do
                if not e.dead and e.familyType == "drowned" then
                    local ed2 = (e.x - pool.x) ^ 2 + (e.y - pool.y) ^ 2
                    if ed2 <= pool.radius ^ 2 then
                        e._inTidePool = true
                        e._tidePoolSpdBuff = params.poolAllySpd
                        e._tidePoolDefBuff = params.poolAllyDef
                    end
                end
            end
        end
    end

    -- 清除过期标记
    for _, e in ipairs(bs.enemies) do
        if e._inTidePool and e.familyType == "drowned" then
            -- 标记在池循环中设置, 下帧开始前清除
        end
    end
end

-- ── 孢子云 (fungal) ─────────────────────────────────────────────────────

function FM._updateSporeClouds(bs, dt)
    local params = FamilyConfig.MECHANIC_PARAMS.fungal
    local p = bs.playerBattle
    if not p then return end

    for i = #state.sporeClouds, 1, -1 do
        local cloud = state.sporeClouds[i]
        cloud.life = cloud.life - dt
        if cloud.life <= 0 then
            table.remove(state.sporeClouds, i)
        else
            local d2 = (p.x - cloud.x) ^ 2 + (p.y - cloud.y) ^ 2
            if d2 <= cloud.radius ^ 2 and not GameState.playerDead then
                -- DOT
                cloud._dotTimer = (cloud._dotTimer or 0) - dt
                if cloud._dotTimer <= 0 then
                    cloud._dotTimer = 1.0
                    local dmg = math.floor(cloud.dotDmg)
                    GameState.DamagePlayer(dmg)
                end
                -- 攻速降低 + 技能CD增加 (通过 debuff)
                GameState.ApplySlowDebuff(params.sporeAtkSpdDebuff, 0.5)
            end
        end
    end
end

-- ── 群猎 (beasts) ───────────────────────────────────────────────────────

function FM._updatePackHunt(bs, dt)
    local params = FamilyConfig.MECHANIC_PARAMS.beasts
    local count = countFamilyType(bs, "beasts", true)
    local active = count >= params.packThreshold

    for _, e in ipairs(bs.enemies) do
        if not e.dead and e.familyType == "beasts" then
            if active then
                e._packActive = true
                e._packAtkBuff = params.packAtkBuff
                e._packSpdBuff = params.packSpdBuff
            else
                -- 群猎解除 → 怯懦逃跑
                if e._packActive then
                    e._cowardTimer = params.cowardDuration
                end
                e._packActive = false
                e._packAtkBuff = nil
                e._packSpdBuff = nil
            end
        end
    end
    state.packHuntActive = active
end

-- ── 恶魔恐慌 (fiends) ──────────────────────────────────────────────────

function FM._updateFiendsPanic(bs, dt)
    local params = FamilyConfig.MECHANIC_PARAMS.fiends
    local phase = state.panicPhase

    -- 检测领袖是否存活
    local leader = nil
    for _, e in ipairs(bs.enemies) do
        if not e.dead and e.familyType == "fiends" and e._isFiendsLeader then
            leader = e
            break
        end
    end
    state.leaderAlive = leader

    -- 领袖存活: 给小弟 ATK/移速 buff
    if leader then
        for _, e in ipairs(bs.enemies) do
            if not e.dead and e.familyType == "fiends" and e ~= leader then
                e._leaderAtkBuff = params.leaderAtkBuff
                e._leaderSpdBuff = params.leaderSpdBuff
            end
        end
        return  -- 领袖活着, 不恐慌
    end

    -- 领袖死亡 → 触发恐慌链
    if not phase then
        state.panicPhase = "panic"
        state.panicTimer = params.panicDuration
        -- 所有 fiends 停顿
        for _, e in ipairs(bs.enemies) do
            if not e.dead and e.familyType == "fiends" then
                e._panicStunned = true
            end
        end
        return
    end

    state.panicTimer = state.panicTimer - dt

    if phase == "panic" and state.panicTimer <= 0 then
        state.panicPhase = "flee"
        state.panicTimer = params.fleeDuration
        for _, e in ipairs(bs.enemies) do
            if not e.dead and e.familyType == "fiends" then
                e._panicStunned = false
                e._fleeing = true
            end
        end
    elseif phase == "flee" and state.panicTimer <= 0 then
        state.panicPhase = "debuff"
        state.panicTimer = 999  -- 永久 debuff 直到死亡
        for _, e in ipairs(bs.enemies) do
            if not e.dead and e.familyType == "fiends" then
                e._fleeing = false
                e._panicAtkDebuff = params.postPanicAtkDebuff
            end
        end
    end
end

-- ── 虚空闪移 (voidborn) ────────────────────────────────────────────────

function FM._updateVoidbornBlink(bs, dt)
    local params = FamilyConfig.MECHANIC_PARAMS.voidborn
    for _, e in ipairs(bs.enemies) do
        if not e.dead and e.familyType == "voidborn" then
            -- 相位消失计时
            if e._phaseShifted then
                e._phaseTimer = (e._phaseTimer or 0) - dt
                if e._phaseTimer <= 0 then
                    e._phaseShifted = false
                    e._phaseTimer = nil
                end
            end
        end
    end
end

--- 受击闪移检测 (在受击后调用)
---@param bs table BattleSystem
---@param enemy table
function FM.TryVoidbornBlink(bs, enemy)
    if enemy.familyType ~= "voidborn" or enemy.dead then return end
    if enemy._phaseShifted then return end

    local params = FamilyConfig.MECHANIC_PARAMS.voidborn
    if math.random() > params.blinkChance then return end

    -- 闪移
    local angle = math.random() * math.pi * 2
    local dist = params.blinkDist[1] + math.random() * (params.blinkDist[2] - params.blinkDist[1])
    enemy.x = math.max(30, math.min(bs.areaW - 30, enemy.x + math.cos(angle) * dist))
    enemy.y = math.max(30, math.min(bs.areaH - 30, enemy.y + math.sin(angle) * dist))

    -- 短暂不可选中
    enemy._phaseShifted = true
    enemy._phaseTimer   = params.blinkInvisTime
end

-- ── 亡灵复活 (undead) ──────────────────────────────────────────────────

function FM._updateUndeadRevive(bs, dt)
    local params = FamilyConfig.MECHANIC_PARAMS.undead
    for i = #state.revivePending, 1, -1 do
        local entry = state.revivePending[i]
        entry.delay = entry.delay - dt
        if entry.delay <= 0 then
            table.remove(state.revivePending, i)
            local e = entry.enemy
            -- 检查是否还在 enemies 列表中且未被清理
            if e._pendingRevive and e.dead then
                e.dead = false
                e._pendingRevive = false
                e._dyingAnim = false
                if e.anim then e.anim.deathTimer = 0 end
                e.hp = math.floor(e.maxHp * params.reviveHpRatio)
                e._reviveCount = (e._reviveCount or 0) + 1
                e._reviveFlash = 0.5
            end
        end
    end
end

-- ── 献祭 buff 衰减 (cult) ──────────────────────────────────────────────

function FM._updateSacrificeBuffs(bs, dt)
    local params = FamilyConfig.MECHANIC_PARAMS.cult
    for i = #state.sacrificeBuffs, 1, -1 do
        local buff = state.sacrificeBuffs[i]
        buff.timer = buff.timer - dt
        if buff.timer <= 0 then
            local target = buff.target
            if target and not target.dead then
                target._sacrificeAtkBuff = nil
                target._sacrificeHpBuff  = nil
            end
            table.remove(state.sacrificeBuffs, i)
        end
    end

    -- 狂信检测
    for _, e in ipairs(bs.enemies) do
        if not e.dead and e.familyType == "cult" then
            if (e._sacrificeReceived or 0) >= params.fanaticThreshold and not e._fanatic then
                e._fanatic = true
                e.atk   = math.floor(e.atk * params.fanaticMul)
                e.maxHp = math.floor(e.maxHp * params.fanaticMul)
                e.hp    = e.maxHp
                e._fanaticFlash = 0.5
            end
        end
    end
end

-- ── 构装体重组 (constructs) ────────────────────────────────────────────

function FM._updateConstructReassemble(bs, dt)
    local params = FamilyConfig.MECHANIC_PARAMS.constructs
    for _, e in ipairs(bs.enemies) do
        if not e.dead and e._isFragment then
            e._reassembleTimer = (e._reassembleTimer or params.reassembleDelay) - dt
            if e._reassembleTimer <= 0 and not e._reassembling then
                -- 查找同源碎片
                local partner = nil
                for _, e2 in ipairs(bs.enemies) do
                    if e2 ~= e and not e2.dead and e2._isFragment
                       and e2._fragmentParentId == e._fragmentParentId then
                        partner = e2
                        break
                    end
                end
                if partner then
                    e._reassembling = true
                    e._reassembleCast = params.reassembleCast
                    e._reassemblePartner = partner
                end
            end

            -- 施法进度
            if e._reassembling then
                e._reassembleCast = e._reassembleCast - dt
                if e._reassembleCast <= 0 then
                    local partner = e._reassemblePartner
                    if partner and not partner.dead then
                        -- 重组: 杀死碎片, 复活原体
                        partner.dead = true
                        e.dead = true
                        -- 原体复活 (使用碎片之一的位置)
                        local parent = e._fragmentParent
                        if parent then
                            parent.dead = false
                            parent._dyingAnim = false
                            if parent.anim then parent.anim.deathTimer = 0 end
                            parent.hp = math.floor(parent.maxHp * params.reassembleHpRatio)
                            parent.x = e.x
                            parent.y = e.y
                            parent._isFragment = nil
                            parent._fragmentParentId = nil
                            parent._reassembleFlash = 0.5
                        end
                    end
                    e._reassembling = false
                    e._reassemblePartner = nil
                end
            end
        end
    end
end

-- ── 蛛蝎叠毒 (venomkin) ────────────────────────────────────────────────

function FM._updateVenomStacking(bs, dt)
    -- 毒 DOT 处理
    local params = FamilyConfig.MECHANIC_PARAMS.venomkin
    local p = bs.playerBattle
    if not p or GameState.playerDead then return end

    -- 毒层 DOT: 每秒造成 venomDotPct × 叠层 的伤害 (基于最高ATK的蛛蝎)
    local maxAtk = 0
    local totalStacks = GameState._venomStacks or 0
    if totalStacks > 0 then
        for _, e in ipairs(bs.enemies) do
            if not e.dead and e.familyType == "venomkin" then
                maxAtk = math.max(maxAtk, e.atk)
            end
        end
        if maxAtk > 0 then
            GameState._venomDotTimer = (GameState._venomDotTimer or 0) - dt
            if GameState._venomDotTimer <= 0 then
                GameState._venomDotTimer = 1.0
                local dmg = math.floor(maxAtk * params.venomDotPct * totalStacks)
                if dmg > 0 then
                    GameState.DamagePlayer(dmg)
                end
            end
        end
    end
end

-- ============================================================================
-- 3. OnEnemyDeath
-- ============================================================================

--- 家族机制死亡钩子 (在 BattleSystem.OnEnemyKilled 中调用)
---@param bs table BattleSystem
---@param enemy table
function FM.OnEnemyDeath(bs, enemy)
    if not state then return end
    local fType = enemy.familyType
    if not fType then return end

    -- ── swarm: 死亡分裂 ──
    if fType == "swarm" then
        FM._onSwarmDeath(bs, enemy)

    -- ── undead: 排队复活 ──
    elseif fType == "undead" then
        FM._onUndeadDeath(bs, enemy)

    -- ── constructs: 碎裂 ──
    elseif fType == "constructs" then
        FM._onConstructDeath(bs, enemy)

    -- ── cult: 献祭 ──
    elseif fType == "cult" then
        FM._onCultDeath(bs, enemy)

    -- ── fungal: 孢子爆发 ──
    elseif fType == "fungal" then
        FM._onFungalDeath(bs, enemy)

    -- ── drowned: 留潮池 ──
    elseif fType == "drowned" then
        FM._onDrownedDeath(bs, enemy)
    end
end

-- ── swarm 分裂 ──

function FM._onSwarmDeath(bs, enemy)
    local params = FamilyConfig.MECHANIC_PARAMS.swarm
    -- 已分裂过的不再裂
    if (enemy._splitGen or 0) >= params.maxSplitGen then return end
    if math.random() > params.splitChance then return end

    for i = 1, 2 do
        local angle = (i / 2) * math.pi * 2
        local ox = math.cos(angle) * 20
        local oy = math.sin(angle) * 20
        local child = {
            x = math.max(30, math.min(bs.areaW - 30, enemy.x + ox)),
            y = math.max(30, math.min(bs.areaH - 30, enemy.y + oy)),
            hp = math.floor(enemy.maxHp * params.splitHpRatio),
            maxHp = math.floor(enemy.maxHp * params.splitHpRatio),
            atk = math.floor(enemy.atk * params.splitAtkRatio),
            speed = enemy.speed * 1.1,
            radius = math.max(6, (enemy.radius or 12) * 0.7),
            def = math.floor((enemy.def or 0) * 0.5),
            atkTimer = 0, atkCd = enemy.atkCd,
            atkRange = enemy.atkRange or 35,
            element = enemy.element or "physical",
            color = enemy.color and { enemy.color[1], enemy.color[2], enemy.color[3] } or { 200, 100, 80 },
            name = enemy.name .. "碎", isBoss = false, dead = false,
            expDrop = math.floor((enemy.expDrop or 0) * 0.3),
            goldMin = 0, goldMax = 0,
            knockbackVx = 0, knockbackVy = 0,
            weight = 0.5,
            attachedElement = nil, attachedElementTimer = 0,
            defReduceRate = 0, defReduceTimer = 0,
            elemWeakenRate = 0, elemWeakenTimer = 0,
            familyType = "swarm", familyId = enemy.familyId,
            _splitGen = (enemy._splitGen or 0) + 1,
            _isSplitChild = true,
            -- 继承精英词缀
            eliteRank = enemy.eliteRank,
            eliteAffixes = enemy.eliteAffixes,
        }
        table.insert(bs.enemies, child)
        EnemyAnim.InitAnim(child)
    end
end

-- ── undead 复活排队 ──

function FM._onUndeadDeath(bs, enemy)
    local params = FamilyConfig.MECHANIC_PARAMS.undead
    if enemy._isSummon then return end  -- 召唤物不复活
    if (enemy._reviveCount or 0) >= params.maxRevives then return end

    -- 标记待复活, 阻止 CleanupDead 移除
    enemy._pendingRevive = true
    table.insert(state.revivePending, {
        enemy = enemy,
        delay = params.reviveDelay,
    })
end

-- ── constructs 碎裂 ──

function FM._onConstructDeath(bs, enemy)
    local params = FamilyConfig.MECHANIC_PARAMS.constructs
    if enemy._isFragment then return end  -- 碎片不再碎裂

    -- 生成碎片
    local parentId = tostring(enemy) -- 唯一标识
    for i = 1, params.fragmentCount do
        local angle = (i / params.fragmentCount) * math.pi * 2
        local ox = math.cos(angle) * 25
        local oy = math.sin(angle) * 25
        local frag = {
            x = math.max(30, math.min(bs.areaW - 30, enemy.x + ox)),
            y = math.max(30, math.min(bs.areaH - 30, enemy.y + oy)),
            hp = math.floor(enemy.maxHp * params.fragmentHpRatio),
            maxHp = math.floor(enemy.maxHp * params.fragmentHpRatio),
            atk = math.floor(enemy.atk * params.fragmentAtkRatio),
            speed = enemy.speed * 1.3,
            radius = math.max(6, (enemy.radius or 12) * 0.7),
            def = math.floor((enemy.def or 0) * 0.5),
            atkTimer = 0, atkCd = enemy.atkCd * 1.2,
            atkRange = enemy.atkRange or 35,
            element = enemy.element or "physical",
            color = enemy.color and { enemy.color[1], enemy.color[2], enemy.color[3] } or { 140, 140, 160 },
            name = enemy.name .. "碎片", isBoss = false, dead = false,
            expDrop = 0, goldMin = 0, goldMax = 0,
            knockbackVx = 0, knockbackVy = 0,
            weight = 0.8,
            attachedElement = nil, attachedElementTimer = 0,
            defReduceRate = 0, defReduceTimer = 0,
            elemWeakenRate = 0, elemWeakenTimer = 0,
            familyType = "constructs", familyId = enemy.familyId,
            _isFragment = true,
            _fragmentParentId = parentId,
            _fragmentParent = enemy,  -- 引用原体 (用于重组)
        }
        table.insert(bs.enemies, frag)
        EnemyAnim.InitAnim(frag)
    end

    -- 原体标记为碎裂态 (保留在列表中以备重组)
    enemy._pendingRevive = true  -- 阻止 CleanupDead
    enemy._fragmentParentId = parentId
end

-- ── cult 献祭 ──

function FM._onCultDeath(bs, enemy)
    local params = FamilyConfig.MECHANIC_PARAMS.cult
    if enemy._isSummon then return end

    -- 找最近的同族存活成员
    local nearest, nearDist2 = nil, math.huge
    for _, e in ipairs(bs.enemies) do
        if e ~= enemy and not e.dead and e.familyType == "cult" then
            local d = dist2(e, enemy)
            if d < nearDist2 then
                nearest = e
                nearDist2 = d
            end
        end
    end
    if not nearest then return end

    -- 献祭增益
    nearest.hp = math.min(nearest.maxHp,
        nearest.hp + math.floor(nearest.maxHp * params.sacrificeHpPct))
    local atkBuff = math.floor(nearest.atk * params.sacrificeAtkPct)
    nearest.atk = nearest.atk + atkBuff
    nearest._sacrificeAtkBuff = (nearest._sacrificeAtkBuff or 0) + atkBuff
    nearest._sacrificeHpBuff  = params.sacrificeHpPct
    nearest._sacrificeReceived = (nearest._sacrificeReceived or 0) + 1
    nearest._sacrificeFlash = 0.4

    table.insert(state.sacrificeBuffs, {
        target = nearest,
        timer  = params.sacrificeDuration,
    })
end

-- ── fungal 孢子爆发 ──

function FM._onFungalDeath(bs, enemy)
    local params = FamilyConfig.MECHANIC_PARAMS.fungal
    -- 死亡时释放孢子云
    table.insert(state.sporeClouds, {
        x = enemy.x, y = enemy.y,
        radius = params.burstRadius,
        life   = params.burstDuration,
        maxLife = params.burstDuration,
        dotDmg = math.floor(enemy.atk * params.sporeDotPct),
    })
end

-- ── drowned 潮池 ──

function FM._onDrownedDeath(bs, enemy)
    local params = FamilyConfig.MECHANIC_PARAMS.drowned
    table.insert(state.tidePools, {
        x = enemy.x, y = enemy.y,
        radius = params.poolRadius,
        life   = params.poolDuration,
        dotDmg = math.floor(enemy.atk * params.poolDotPct),
    })
end

-- ============================================================================
-- 4. OnEnemySpawned (生成钩子)
-- ============================================================================

--- 敌人生成后调用 (在 Spawner.SpawnFromQueue 末尾)
---@param bs table BattleSystem
---@param enemy table
function FM.OnEnemySpawned(bs, enemy)
    if not state then return end
    local fType = enemy.familyType
    if not fType then return end

    -- fiends: 检测是否为领袖 (第一个 fiends 或 isBoss)
    if fType == "fiends" then
        if enemy.isBoss or not state.leaderAlive then
            enemy._isFiendsLeader = true
            state.leaderAlive = enemy
        end
    end

    -- venomkin: 初始化毒层
    if fType == "venomkin" then
        enemy._venomPerHit = FamilyConfig.MECHANIC_PARAMS.venomkin.venomPerHit
    end
end

-- ============================================================================
-- 5. 查询接口
-- ============================================================================

--- 检查敌人是否不可选中 (虚空相位)
---@param enemy table
---@return boolean
function FM.IsUntargetable(enemy)
    return enemy._phaseShifted == true
end

--- 检查敌人是否在逃跑中 (群猎解散后怯懦/恐慌逃散)
---@param enemy table
---@return boolean
function FM.IsFleeing(enemy)
    return enemy._fleeing == true or (enemy._cowardTimer and enemy._cowardTimer > 0)
end

-- ============================================================================
-- 6. 伤害修正
-- ============================================================================

--- 虚空AOE减伤 (voidborn 被 AOE 命中时)
---@param enemy table
---@param dmg number
---@param isAOE boolean
---@return number modifiedDmg
function FM.ModifyIncomingDmg(enemy, dmg, isAOE)
    if not enemy.familyType then return dmg end

    -- voidborn: AOE 伤害减免
    if enemy.familyType == "voidborn" and isAOE then
        local params = FamilyConfig.MECHANIC_PARAMS.voidborn
        dmg = math.floor(dmg * (1 - params.aoeDmgReduction))
    end

    -- 恐慌后 ATK debuff (影响 fiends 受伤无关, 这里只做伤害修正占位)
    -- (fiends debuff 影响的是输出, 不是受伤, 所以不在这里)

    return dmg
end

--- 蛛蝎攻击命中玩家时叠毒 (由 EnemyAttackPlayer 调用)
---@param enemy table
function FM.OnVenomkinAttackHit(enemy)
    if enemy.familyType ~= "venomkin" then return end
    local params = FamilyConfig.MECHANIC_PARAMS.venomkin
    GameState._venomStacks = math.min(
        params.venomMax,
        (GameState._venomStacks or 0) + params.venomPerHit
    )
    GameState._venomDmgAmp = (GameState._venomStacks or 0) * params.venomDmgPct
end

-- ============================================================================
-- 7. Install
-- ============================================================================

function FM.Install(GS)
    GS.FamilyMechanics = FM
end

return FM
